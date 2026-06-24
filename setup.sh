#!/usr/bin/env bash
# Create one buildx builder per cell (<workload>-<scenario>) so each runs cold --
# no cell reuses another's pulled/extracted layers. Idempotent.
#
# Usage: setup.sh                 # all cells (local: ./setup.sh && ./bench.sh)
#        setup.sh <wl>-<scenario> # just that cell (CI: one cell per runner)
set -euo pipefail

# Upstream buildkit image for the baseline. Pinned for a stable comparison.
UPSTREAM_IMAGE="${UPSTREAM_IMAGE:-moby/buildkit:v0.31.0}"
# Clipper fork image (`docker buildx bake image` -> moby/buildkit:local).
CLIPPER_IMAGE="${CLIPPER_IMAGE:-moby/buildkit:local}"

# --debug surfaces the docker resolver's HTTP requests (the cache-to push path).
EAGER_FLAGS="--debug"
LAZY_FLAGS="--debug --oci-worker-snapshotter=clipper-lazy"

WORKLOADS="${WORKLOADS:-llamacpp uv}"
SCENARIOS="${SCENARIOS:-upstream-baseline upstream-cachedance clipper-baseline clipper-cache-mount clipper-lazy-fuse}"

create_or_replace() {
    local name="$1" image="$2" flags="$3"
    if docker buildx inspect "$name" >/dev/null 2>&1; then
        docker buildx rm "$name" >/dev/null
    fi
    docker buildx create \
        --name "$name" \
        --driver docker-container \
        --driver-opt "image=$image" \
        --buildkitd-flags "$flags" \
        >/dev/null
    docker buildx inspect "$name" --bootstrap >/dev/null
    echo "builder $name ready (image=$image, flags='$flags')"
}

# create_cell <wl>-<scenario>: pick engine/snapshotter from the scenario half.
create_cell() {
    local cell="$1" scenario="${1#*-}" image flags
    case "$scenario" in
        upstream-*)        image="$UPSTREAM_IMAGE"; flags="$EAGER_FLAGS" ;;
        clipper-lazy-fuse) image="$CLIPPER_IMAGE";  flags="$LAZY_FLAGS" ;;
        clipper-*)         image="$CLIPPER_IMAGE";  flags="$EAGER_FLAGS" ;;
        *) echo "unknown scenario in cell: $cell" >&2; return 1 ;;
    esac
    create_or_replace "bench-${cell}" "$image" "$flags"
}

want="${1:-all}"
if [ "$want" = all ]; then
    for wl in $WORKLOADS; do for sc in $SCENARIOS; do create_cell "${wl}-${sc}"; done; done
else
    create_cell "$want"
fi
