#!/usr/bin/env bash

set -euo pipefail

HOST="products.impact.com"
BASE_DIR="$HOME/git/misc/commerce-engine"
DATA_DIR="$BASE_DIR/data/onp"
ARCHIVE_DIR="$DATA_DIR/archive"
LISP_DIR="$BASE_DIR/common-lisp"
LISP_FILE="$LISP_DIR/onp-database.lisp"

CONVERTER_SCRIPT="$LISP_DIR/convert-ir-to-csv.lisp"

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

echo "Checking ONP catalogs..."

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
# sync_catalog : format-tag local-dir local-basename result-file -> writes
#                1 or 0 to result-file
###############################################################################
# Handles one <catalog> entry end to end: reads its <lastUpdated> and
# <location> straight from the XML tree via xmllint (no pattern-matching
# text, which is what made the original sed version fragile the moment
# there was more than one <catalog> block -- there are two here).
# Compares against the local file's mtime, downloads + archives if the
# remote copy is newer, and reports back whether it did.

sync_catalog() {
    local format_tag="$1"
    local local_dir="$2"
    local local_basename="$3"    # e.g. Updated-ONP-Catalog_IR.txt.gz
    local result_file="$4"

    local local_gz="$local_dir/$local_basename"

    local remote_timestamp
    remote_timestamp="$(xmllint --xpath \
        "string(//catalog[format='${format_tag}']/lastUpdated)" \
        "$INFO_XML")"

    local remote_location
    remote_location="$(xmllint --xpath \
        "string(//catalog[format='${format_tag}']/location)" \
        "$INFO_XML")"

    if [[ -z "$remote_timestamp" || -z "$remote_location" ]]; then
        echo "ERROR: Could not read metadata for format '$format_tag'."
        echo "0" > "$result_file"
        return
    fi

    echo "[$format_tag] remote: $remote_timestamp"

    local need_update=1
    if [[ -f "$local_gz" ]]; then
        local local_time remote_time
        local_time=$(stat -c %Y "$local_gz")
        remote_time=$(date -d "$remote_timestamp" +%s)
        echo "[$format_tag] local:  $(date -d "@$local_time" '+%Y-%m-%d %H:%M:%S %Z')"
        if (( remote_time > local_time )); then
            echo "[$format_tag] remote is newer -- updating."
        else
            echo "[$format_tag] already up to date."
            need_update=0
        fi
    else
        echo "[$format_tag] no local catalog found -- downloading."
    fi

    if (( need_update == 0 )); then
        echo "0" > "$result_file"
        return
    fi

    local remote_dir remote_filename tmp_download
    remote_dir="$(dirname "$remote_location")"
    remote_filename="$(basename "$remote_location")"
    tmp_download="$TMP_DIR/$local_basename"

    ftp -iv "$HOST" >"$TMP_DIR/ftp-download-${format_tag// /_}.log" <<EOF
cd $remote_dir
get $remote_filename $tmp_download
bye
EOF

    if [[ ! -s "$tmp_download" ]]; then
        echo "ERROR: [$format_tag] download failed."
        cat "$TMP_DIR/ftp-download-${format_tag// /_}.log"
        exit 1
    fi

    mkdir -p "$ARCHIVE_DIR"
    if [[ -f "$local_gz" ]]; then
        local archive_name
        archive_name="$ARCHIVE_DIR/$(date -r "$local_gz" '+%Y%m%d-%H%M%S')-$local_basename"
        echo "[$format_tag] archiving old catalog -> $archive_name"
        mv "$local_gz" "$archive_name"
    fi

    mv "$tmp_download" "$local_gz"
    echo "[$format_tag] installed: $local_gz"

    # -k keeps the .gz alongside the extracted file -- the .gz's mtime
    # is what next run's staleness check reads, so deleting it would
    # make every future run think there's no local catalog at all.
    gunzip -k -f "$local_gz"
    echo "[$format_tag] extracted: ${local_gz%.gz}"

    echo "1" > "$result_file"
}

###############################################################################
# Sync both formats -- Google is kept current for human reference only;
# IR is what the Lisp loader actually reads, tracked separately below.
###############################################################################

GOOGLE_RESULT="$TMP_DIR/google-updated"
IR_RESULT="$TMP_DIR/ir-updated"

sync_catalog "GOOGLE TXT" \
    "$DATA_DIR/google-format" \
    "Updated-ONP-Catalog_GOOGLE_TXT.txt.gz" \
    "$GOOGLE_RESULT"

sync_catalog "IR" \
    "$DATA_DIR/impact-format" \
    "Updated-ONP-Catalog_IR.txt.gz" \
    "$IR_RESULT"

IR_UPDATED="$(cat "$IR_RESULT")"

if [[ "$IR_UPDATED" != "1" ]]; then
    echo "IR catalog unchanged -- nothing for the database to pick up."
    exit 0
fi

###############################################################################
# Convert IR .txt -> .csv, then rebuild the database
###############################################################################
# Only runs when IR specifically changed -- no point reconverting or
# rebuilding off a Google-only update the Lisp side never reads.

IR_TXT="$DATA_DIR/impact-format/Updated-ONP-Catalog_IR.txt"
IR_CSV="$DATA_DIR/impact-format/Updated-ONP-Catalog_IR.csv"

echo "Converting IR catalog to CSV..."
sbcl --script "$CONVERTER_SCRIPT" "$IR_TXT" "$IR_CSV"

if [[ ! -s "$IR_CSV" ]]; then
    echo "ERROR: CSV conversion produced no output at $IR_CSV"
    exit 1
fi

echo "Rebuilding database..."
cd "$LISP_DIR"
sbcl --non-interactive \
     --load "$LISP_FILE" \
     --eval '(load-products-to-db *products*)'

echo "ONP catalog update complete."
