#!/usr/bin/env bash
#
# Downloads and loads every retailer's catalog. Run manually or from
# a timer -- see RUNBOOK.txt in the repo root for that setup.
#
# Generic engine -- no retailer is hardcoded into this script's own
# logic. GENERIC_RETAILERS below currently holds exactly one sample
# entry (Example Retailer), kept specifically so this can be run and
# tested end to end without needing a full catalog set populated
# first. A real project built on this engine adds its own retailers
# here.
#
# TO ADD A GENERIC RETAILER (no custom parsing needed -- most
# retailers): add ONE line to the GENERIC_RETAILERS array below.
#   1. Find its advertiserId: after this script has run once,
#      xmllint --xpath "//catalog[format='IR']/name" \
#        data/catalogs_info_file.xml
#      lists every IR catalog on the account -- match yours by
#      <location>, then read its <advertiserId> sibling. Don't use
#      <name> -- it's not guaranteed unique (an account can have
#      more than one retailer sharing the literal name "Imported
#      Shopify Catalog").
#   2. Add "advertiserId|Display Name|dir-name|load-fn" to
#      GENERIC_RETAILERS.
#   3. Add the matching retailer to common-lisp/retailers/catalogs.lisp
#      (one defparameter + one defun, see that file's own top comment
#      and its Example Retailer entry for the pattern to copy).
# That's the whole cost -- no directory needs to exist beforehand,
# no other part of this script needs to change.
#
# TO ADD A RETAILER THAT NEEDS CUSTOM PARSING (quantity extraction,
# non-standard fields, etc): it needs its own dedicated wrapper file
# (its own product-building logic, its own sync_catalog call(s) in
# its own section here, separate from GENERIC_RETAILERS) rather than
# an entry in that array. No concrete example currently lives in
# this stripped-down engine to copy directly -- follow the general
# shape (own file, own variables, own sync_catalog calls, own
# if-block) rather than a specific template.
#
# Every Lisp invocation below goes through `ros run`, not plain
# `sbcl` -- confirmed necessary the hard way, deploying to a fresh
# machine. A traditional SBCL install auto-loads Quicklisp via
# ~/.sbclrc; a Roswell-managed SBCL (what app.lisp itself requires)
# does not expose a plain `sbcl` with that same auto-load behavior --
# calling bare `sbcl --load` on this kind of setup fails with
# "Package QL does not exist" the moment anything tries to
# ql:quickload. `ros run` is the confirmed-working equivalent.
#
# SKIP_ARCHIVE=1 bash shell/update-onp.sh disables archiving for
# that run -- an old catalog file is simply replaced instead of
# moved into data/archive/. Off by default, so the normal path (a
# daily timer, in particular) keeps archiving exactly as originally
# designed; this is an opt-in switch for situations like heavy local
# exploration/rebuild cycles, where re-running this repeatedly would
# otherwise keep accumulating archived snapshots of every
# intermediate catalog version nobody needs.

set -euo pipefail

HOST="products.impact.com"
SKIP_ARCHIVE="${SKIP_ARCHIVE:-0}"

# Self-locating rather than a hardcoded absolute path -- a fixed
# path only ever works on the ONE machine it was written for. Two
# separate base directories, not one: data/ and database/ are
# siblings of commerce-engine/ at the repo root, not nested inside
# it. COMMERCE_ENGINE_DIR (one level up from this script's own
# location in shell/) finds common-lisp/; REPO_ROOT (one level
# further up again) finds data/. The exact depth here is confirmed
# against common-lisp/retailers/catalogs.lisp's own Example Retailer
# entry, which resolves "../../../data/..." relative to retailers/
# -- three levels up to the repo root, consistent with two levels up
# from shell/ (shell/ and retailers/ sit at different nesting depths
# under commerce-engine/, but both correctly resolve to the same
# root from their own respective locations).
COMMERCE_ENGINE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$COMMERCE_ENGINE_DIR/.." && pwd)"
DATA_ROOT="$REPO_ROOT/data"
ARCHIVE_ROOT="$DATA_ROOT/archive"    # one subdir per retailer, not nested inside each retailer's own dir
LISP_DIR="$COMMERCE_ENGINE_DIR/common-lisp"
CATALOGS_LISP="$LISP_DIR/retailers/catalogs.lisp"    # generic retailers -- see bottom of file


TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

###############################################################################
# Preflight -- fail loudly now rather than mysteriously later, especially
# since this will eventually run unattended from a timer with no one
# watching the output live.
###############################################################################

for cmd in ftp xmllint ros gunzip; do
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

# Only archive+replace when the content actually changed -- this
# file, unlike a per-retailer catalog, carries no "last updated"
# timestamp of its own to compare against, so a direct content diff
# (cmp) is the right check here rather than the timestamp comparison
# sync_catalog uses elsewhere. Without this check, every single run
# archived a fresh copy unconditionally, even back-to-back runs
# seconds apart with nothing actually different on Impact's end --
# confirmed directly: two runs, two new archived files, real
# duplicate accumulation for zero reason.
if [[ -f "$INFO_XML_CURRENT" ]] && cmp -s "$INFO_XML" "$INFO_XML_CURRENT"; then
    echo "catalogs_info_file.xml unchanged -- not archiving."
else
    mkdir -p "$INFO_XML_ARCHIVE_DIR"
    if [[ -f "$INFO_XML_CURRENT" ]]; then
        if [[ "$SKIP_ARCHIVE" == "1" ]]; then
            echo "Replacing previous catalogs_info_file.xml (SKIP_ARCHIVE set, not archiving)"
        else
            archive_name="$INFO_XML_ARCHIVE_DIR/$(date -r "$INFO_XML_CURRENT" '+%Y%m%d-%H%M%S')-catalogs_info_file.xml"
            echo "Archiving previous catalogs_info_file.xml -> $archive_name"
            mv "$INFO_XML_CURRENT" "$archive_name"
        fi
    fi
    cp "$INFO_XML" "$INFO_XML_CURRENT"
    echo "Installed current catalog metadata: $INFO_XML_CURRENT"
fi

###############################################################################
# sync_catalog : format-tag advertiser-id display-label local-dir local-basename archive-dir result-file -> writes
#                1 or 0 to result-file
###############################################################################
# Handles one <catalog> entry end to end: reads its <lastUpdated> and
# <location> straight from the XML tree via xmllint. Matches on
# advertiserId, not <name> -- <name> is presentation text and is NOT
# guaranteed unique. advertiserId is the actual unique-per-merchant-
# program identifier. display_label is separate, purely for readable
# log output. archive_dir is passed in explicitly by the caller
# rather than read from a single global -- each retailer gets its
# own archive subdirectory, not a shared one.

sync_catalog() {
    local format_tag="$1"
    local advertiser_id="$2"
    local display_label="$3"
    local local_dir="$4"
    local local_basename="$5"
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
        if [[ "$SKIP_ARCHIVE" == "1" ]]; then
            echo "[$display_label] replacing old catalog (SKIP_ARCHIVE set, not archiving)"
        else
            local archive_name
            archive_name="$archive_dir/$(date -r "$local_txt" '+%Y%m%d-%H%M%S')-$(basename "$local_txt")"
            echo "[$display_label] archiving old catalog -> $archive_name"
            mv "$local_txt" "$archive_name"
        fi
    fi

    mv "$tmp_download" "$local_gz"
    echo "[$display_label] installed: $local_gz"

    # -k keeps the .gz alongside the extracted file -- the .gz's mtime
    # is what next run's staleness check reads, so deleting it would
    # make every future run think there's no local catalog at all.
    # -f overwrites the OLD .txt directly if one is still sitting
    # there (SKIP_ARCHIVE case, where the old one was never moved
    # aside) -- this is what actually replaces it, not a separate
    # delete step.
    gunzip -k -f "$local_gz"
    echo "[$display_label] extracted: ${local_gz%.gz}"

    echo "1" > "$result_file"
}

###############################################################################
# GENERIC RETAILERS -- no custom parsing needed. See the top of this
# file for how to add one. Currently just one sample entry (Skin
# Kins Co), kept specifically so this generic engine can be run and
# tested end to end without a full catalog set populated first.
###############################################################################

GENERIC_RETAILERS=(
    # advertiserId|display-label|local dir under data/|sbcl function to call
    "000000|Example Retailer|example-retailer|load-example-retailer"
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
    ros run \
         --load "$CATALOGS_LISP" \
         --eval "($load_fn)" \
         --quit
done

echo "All catalog updates complete."
exit 0
