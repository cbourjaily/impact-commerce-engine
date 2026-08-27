#!/usr/bin/env bash
#
# Downloads and loads every retailer's catalog. Run manually or from
# a timer -- see RUNBOOK.txt in the repo root for that setup.
#
# TO ADD A GENERIC RETAILER (no custom parsing needed -- most
# retailers): add ONE line to the GENERIC_RETAILERS array below.
#   1. Find its advertiserId: after this script has run once,
#      xmllint --xpath "//catalog[format='IR']/name" \
#        data/catalogs_info_file.xml
#      lists every IR catalog on the account -- match yours by
#      <location>, then read its <advertiserId> sibling. Don't use
#      <name> -- it's not guaranteed unique (two retailers on this
#      account already share the literal name "Imported Shopify
#      Catalog").
#   2. Add "advertiserId|Display Name|dir-name|load-fn" to
#      GENERIC_RETAILERS.
#   3. Add the matching retailer to common-lisp/retailers/catalogs.lisp
#      (one defparameter + one defun, see that file's own top comment).
# That's the whole cost -- no directory needs to exist beforehand,
# no other part of this script needs to change.
#
# TO ADD A RETAILER THAT NEEDS CUSTOM PARSING (like ONP's quantity
# extraction): it needs its own dedicated wrapper file, following
# common-lisp/retailers/onp/onp-db.lisp as the template, and its own
# sync_catalog call(s) down near ONP's, rather than an entry in
# GENERIC_RETAILERS.

set -euo pipefail

HOST="products.impact.com"

# Self-locating rather than a hardcoded absolute path -- a fixed
# "$HOME/git/misc/thuida/..." path only ever works on the ONE machine
# it was written for. This resolves relative to wherever the SCRIPT
# ITSELF actually lives on disk: BASH_SOURCE is this file's own path
# regardless of what directory you were in when you ran it or how you
# invoked it (bash shell/update-onp.sh, ./update-onp.sh from inside
# shell/, an absolute path from a systemd unit -- all work correctly
# the same way), dirname gets the shell/ directory containing it, and
# /.. goes up one level to commerce-engine/. This is exactly the
# problem that broke deployment onto a fresh machine: cloned into
# ~/thuida instead of ~/git/misc/thuida, and the old hardcoded path
# pointed at a directory that simply didn't exist there.
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_ROOT="$BASE_DIR/data"
ONP_DATA_DIR="$DATA_ROOT/onp"
ARCHIVE_ROOT="$DATA_ROOT/archive"    # one subdir per retailer, not nested inside each retailer's own dir
LISP_DIR="$BASE_DIR/common-lisp"
ONP_LISP_FILE="$LISP_DIR/retailers/onp/onp-db.lisp"
CONVERTER_SCRIPT="$LISP_DIR/utilities/convert-ir-to-csv.lisp"
CATALOGS_LISP="$LISP_DIR/retailers/catalogs.lisp"    # generic retailers -- see bottom of file


TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

###############################################################################
# Preflight -- fail loudly now rather than mysteriously later, especially
# since this will eventually run unattended from a timer with no one
# watching the output live.
###############################################################################

for cmd in ftp xmllint sbcl gunzip; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: required command '$cmd' not found on PATH."
        [[ "$cmd" == "xmllint" ]] && echo "  Install with: sudo apt install libxml2-utils"
        exit 1
    fi
done

echo "Checking catalogs..."

###############################################################################
# Download catalog metadata
###############################################################################

ftp -iv "$HOST" >"$TMP_DIR/ftp-info.log" <<EOF
get catalogs_info_file.xml $TMP_DIR/catalogs_info_file.xml
bye
EOF

if [[ ! -f "$TMP_DIR/catalogs_info_file.xml" ]]; then
    echo "ERROR: Failed to download catalogs_info_file.xml"
    cat "$TMP_DIR/ftp-info.log"
    exit 1
fi

INFO_XML="$TMP_DIR/catalogs_info_file.xml"

###############################################################################
# Keep a persistent, always-current copy of catalogs_info_file.xml at
# data/, and archive the previous one -- same archive-then-replace
# pattern sync_catalog uses for the catalog files themselves. Without
# this, the only copy of this metadata ever existed in $TMP_DIR, which
# cleanup() deletes on exit -- there was never anywhere to look back
# at what an old run actually saw.
###############################################################################

INFO_XML_CURRENT="$DATA_ROOT/catalogs_info_file.xml"
INFO_XML_ARCHIVE_DIR="$ARCHIVE_ROOT/catalogs_info"

mkdir -p "$INFO_XML_ARCHIVE_DIR"
if [[ -f "$INFO_XML_CURRENT" ]]; then
    archive_name="$INFO_XML_ARCHIVE_DIR/$(date -r "$INFO_XML_CURRENT" '+%Y%m%d-%H%M%S')-catalogs_info_file.xml"
    echo "Archiving previous catalogs_info_file.xml -> $archive_name"
    mv "$INFO_XML_CURRENT" "$archive_name"
fi

cp "$INFO_XML" "$INFO_XML_CURRENT"
echo "Installed current catalog metadata: $INFO_XML_CURRENT"

###############################################################################
# sync_catalog : format-tag advertiser-id display-label local-dir local-basename archive-dir result-file -> writes
#                1 or 0 to result-file
###############################################################################
# Handles one <catalog> entry end to end: reads its <lastUpdated> and
# <location> straight from the XML tree via xmllint. Matches on
# advertiserId, not <name> -- <name> is presentation text and is NOT
# guaranteed unique (SinoCrafted and Terra both show up as "Imported
# Shopify Catalog" in this account's metadata). advertiserId is the
# actual unique-per-merchant-program identifier. display_label is
# separate, purely for readable log output. archive_dir is passed in
# explicitly by the caller rather than read from a single global --
# each retailer gets its own archive subdirectory, not a shared one.

sync_catalog() {
    local format_tag="$1"
    local advertiser_id="$2"
    local display_label="$3"
    local local_dir="$4"
    local local_basename="$5"    # e.g. Updated-ONP-Catalog_IR.txt.gz
    local archive_dir="$6"
    local result_file="$7"

    local local_gz="$local_dir/$local_basename"
    local local_txt="${local_gz%.gz}"

    local remote_timestamp
    remote_timestamp="$(xmllint --xpath \
        "string(//catalog[format='${format_tag}' and advertiserId='${advertiser_id}']/lastUpdated)" \
        "$INFO_XML")"

    local remote_location
    remote_location="$(xmllint --xpath \
        "string(//catalog[format='${format_tag}' and advertiserId='${advertiser_id}']/location)" \
        "$INFO_XML")"

    if [[ -z "$remote_timestamp" || -z "$remote_location" ]]; then
        echo "ERROR: Could not read metadata for '$display_label' ($format_tag, advertiserId=$advertiser_id)."
        echo "0" > "$result_file"
        return
    fi

    echo "[$display_label] remote: $remote_timestamp"

    local need_update=1
    if [[ -f "$local_gz" ]]; then
        local local_time remote_time
        local_time=$(stat -c %Y "$local_gz")
        remote_time=$(date -d "$remote_timestamp" +%s)
        echo "[$display_label] local:  $(date -d "@$local_time" '+%Y-%m-%d %H:%M:%S %Z')"
        if (( remote_time > local_time )); then
            echo "[$display_label] remote is newer -- updating."
        else
            echo "[$display_label] already up to date."
            need_update=0
        fi
    else
        echo "[$display_label] no local catalog found -- downloading."
    fi

    if (( need_update == 0 )); then
        echo "0" > "$result_file"
        return
    fi

    local remote_dir remote_filename tmp_download
    remote_dir="$(dirname "$remote_location")"
    remote_filename="$(basename "$remote_location")"
    tmp_download="$TMP_DIR/$local_basename"

    ftp -iv "$HOST" >"$TMP_DIR/ftp-download-${display_label// /_}.log" <<EOF
cd $remote_dir
get $remote_filename $tmp_download
bye
EOF

    if [[ ! -s "$tmp_download" ]]; then
        echo "ERROR: [$display_label] download failed."
        cat "$TMP_DIR/ftp-download-${display_label// /_}.log"
        exit 1
    fi

    mkdir -p "$local_dir"
    mkdir -p "$archive_dir"
    if [[ -f "$local_txt" ]]; then
        local archive_name
        archive_name="$archive_dir/$(date -r "$local_txt" '+%Y%m%d-%H%M%S')-$(basename "$local_txt")"
        echo "[$display_label] archiving old catalog -> $archive_name"
        mv "$local_txt" "$archive_name"
    fi

    mv "$tmp_download" "$local_gz"
    echo "[$display_label] installed: $local_gz"

    # -k keeps the .gz alongside the extracted file -- the .gz's mtime
    # is what next run's staleness check reads, so deleting it would
    # make every future run think there's no local catalog at all.
    gunzip -k -f "$local_gz"
    echo "[$display_label] extracted: ${local_gz%.gz}"

    echo "1" > "$result_file"
}

###############################################################################
# CUSTOM RETAILERS -- retailers needing dedicated per-retailer parsing
# (quantity-extraction heuristics, etc.), each with its own wrapper
# file, rather than an entry in GENERIC_RETAILERS further down.
# Currently just ONP. A second custom retailer gets its own
# subsection here, following ONP's shape -- its own variables, its
# own sync_catalog calls, its own if-block. Never touch ONP's
# variables to add one; copy the pattern instead.
###############################################################################

# -----------------------------------------------------------------------
# ONP
# -----------------------------------------------------------------------
# Google is kept current for human reference only; IR is what
# onp-db.lisp actually reads. If ONP's IR catalog hasn't changed,
# only ONP's own CSV/database steps are skipped below -- the script
# keeps going into the generic retailers afterward regardless. This
# used to be a full `exit 0`, which meant an unchanged ONP catalog
# silently prevented every OTHER retailer from ever being checked --
# exactly the kind of ONP-centrism that doesn't scale.

ONP_GOOGLE_RESULT="$TMP_DIR/onp-google-updated"
ONP_IR_RESULT="$TMP_DIR/onp-ir-updated"

sync_catalog "GOOGLE TXT" "6955634" "ONP" \
    "$ONP_DATA_DIR/google-format" \
    "Updated-ONP-Catalog_GOOGLE_TXT.txt.gz" \
    "$ARCHIVE_ROOT/onp" \
    "$ONP_GOOGLE_RESULT"

sync_catalog "IR" "6955634" "ONP" \
    "$ONP_DATA_DIR/impact-format" \
    "Updated-ONP-Catalog_IR.txt.gz" \
    "$ARCHIVE_ROOT/onp" \
    "$ONP_IR_RESULT"

ONP_IR_UPDATED="$(cat "$ONP_IR_RESULT")"

if [[ "$ONP_IR_UPDATED" == "1" ]]; then
    ONP_IR_TXT="$ONP_DATA_DIR/impact-format/Updated-ONP-Catalog_IR.txt"
    ONP_IR_CSV="$ONP_DATA_DIR/impact-format/Updated-ONP-Catalog_IR.csv"

    # Human-readable CSV -- convenience only, NOT required by the
    # database rebuild below, which reads the raw .txt directly. A
    # failure here is a warning, not a hard stop.
    echo "[ONP] producing human-readable CSV..."
    if sbcl --script "$CONVERTER_SCRIPT" "$ONP_IR_TXT" "$ONP_IR_CSV"; then
        echo "[ONP] CSV written: $ONP_IR_CSV"
    else
        echo "[ONP] WARNING: CSV conversion failed -- continuing with database rebuild anyway."
    fi

    echo "[ONP] rebuilding database..."
    cd "$LISP_DIR"
    sbcl --non-interactive \
         --load "$ONP_LISP_FILE" \
         --eval '(load-products-to-db *products*)'

    echo "[ONP] catalog update complete."
else
    echo "[ONP] IR catalog unchanged -- nothing for the database to pick up."
fi

###############################################################################
# GENERIC RETAILERS -- no custom parsing needed. See the top of this
# file for how to add one.
###############################################################################

GENERIC_RETAILERS=(
    # advertiserId|display-label|local dir under data/|sbcl function to call
    # advertiserId is the real, verified-unique identifier from
    # catalogs_info_file.xml -- NOT <name>, which SinoCrafted and Terra
    # both share ("Imported Shopify Catalog") and would collide on.
    "7479390|SinoCrafted|sinocrafted|load-sinocrafted"
    "7452908|Terra|terra|load-terra"
)

for entry in "${GENERIC_RETAILERS[@]}"; do
    IFS='|' read -r advertiser_id display_label dir_name load_fn <<< "$entry"

    RESULT_FILE="$TMP_DIR/${dir_name}-updated"

    sync_catalog "IR" "$advertiser_id" "$display_label" \
        "$DATA_ROOT/$dir_name/impact-format" \
        "Updated-${dir_name}_IR.txt.gz" \
        "$ARCHIVE_ROOT/$dir_name" \
        "$RESULT_FILE"

    if [[ "$(cat "$RESULT_FILE")" != "1" ]]; then
        echo "[$display_label] unchanged -- skipping database load."
        continue
    fi

    echo "[$display_label] loading into database..."
    cd "$LISP_DIR"
    sbcl --non-interactive \
         --load "$CATALOGS_LISP" \
         --eval "($load_fn)"
done

echo "All catalog updates complete."
exit 0
