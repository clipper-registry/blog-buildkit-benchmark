#!/usr/bin/env bash
# Split a scenario's real wall-clock total into pull / build / export phases.
#
#   pull   = getting the base image ready: resolve + cache-manifest import +
#            layer download/extract. Heuristic: pulling ends when the last
#            pull vertex completes, i.e. the max cumulative completion offset
#            among pull vertices (they all start at ~build start, so a vertex's
#            "DONE <secs>s" is ~its offset from the start of the build).
#   export = exporting the image + pushing the registry cache: the elapsed of
#            the export/push vertices (which run at the end).
#   build  = the remainder (total - pull - export): the stage RUN steps, plus
#            for the lazy snapshotter the on-demand fetches folded into exec.
#
# Phases are a partition of the REAL total (passed in), so they sum to it.
#
# Layer download/extract is attributed by buildkit to the first stage step that
# needs the rootfs (often a WORKDIR), not to the FROM vertex, so a vertex counts
# as pull whenever it emits extract/download sublines -- not by name alone.
#
# Usage: parse-phases.sh <build.log> [total_seconds]
#        -> "pull=<s> build=<s> export=<s>"
set -euo pipefail

log="${1:-}"
total="${2:-0}"
if [ -z "$log" ] || [ ! -f "$log" ]; then
    echo "pull=0 build=0 export=0"
    exit 0
fi

awk -v total="$total" '
{
    if ($0 !~ /^#[0-9]+ /) next
    n = substr($1, 2) + 0
    rest = substr($0, length($1) + 2)
    seen[n] = 1

    # Cumulative completion time for the vertex (last one wins).
    if (rest ~ /^DONE [0-9.]+s$/) {
        s = rest; sub(/^DONE /, "", s); sub(/s$/, "", s)
        dur[n] = s + 0
        next
    }
    if (rest ~ /^CACHED/) { if (!(n in dur)) dur[n] = 0; next }

    # Download progress ("sha256:... 0B / 28B") or "extracting ..." => this
    # vertex is doing pull work, whatever its name says.
    if (rest ~ /^extracting / || rest ~ /^sha256:/) { pull_v[n] = 1; next }

    # Other status-only sublines: do not treat as the vertex name.
    if (rest ~ /^resolve / || rest ~ /^DONE/ || rest ~ /^sending / || \
        rest ~ /^pushing / || rest ~ /[0-9.]+s done$/ || rest ~ /^\.\.\./ || \
        rest ~ /^naming /  || rest ~ /^transferring /) next

    if (!(n in name)) name[n] = rest
}
END {
    pull = 0; xp = 0; bsum = 0
    for (n in seen) {
        nm = (n in name) ? name[n] : ""
        d  = (n in dur)  ? dur[n]  : 0
        if (nm ~ /exporting / || nm ~ /pushing/) {
            if (d > xp) xp = d                         # export elapsed (max)
        } else if ((n in pull_v) || nm ~ /FROM / || nm ~ /importing cache manifest/) {
            if (d > pull) pull = d                     # pull ends at last pull vertex
        } else if (nm ~ /\[stage-/) {
            bsum += d                                  # fallback build estimate
        }
    }
    if (total + 0 > 0) {
        build = total - pull - xp                      # remainder of the real total
        if (build < 0) build = 0
    } else {
        build = bsum
    }
    printf "pull=%.1f build=%.1f export=%.1f\n", pull, build, xp
}
' "$log"
