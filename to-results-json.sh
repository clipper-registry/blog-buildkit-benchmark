#!/usr/bin/env bash
# Aggregate per-cell JSON objects (one object per file, written by
# run-scenario.sh) into a single JSON array on stdout, for rendering stats later.
#
# Usage: to-results-json.sh <cell.json>...   # e.g. ./to-results-json.sh *.json
#        to-results-json.sh artifacts/*/*.json > results.json
#
# No jq dependency: each input is already a complete JSON object, so we just
# wrap them in an array with separating commas.
set -euo pipefail

printf '['
sep=''
for f in "$@"; do
    [ -f "$f" ] || continue
    printf '%s' "$sep"
    cat "$f"
    sep=','
done
printf ']\n'
