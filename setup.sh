#!/usr/bin/env bash
# Create the three buildx builders used by bench.sh. Idempotent.
set -euo pipefail

# Upstream buildkit image used for the baseline. Pinned so the comparison is
# stable. Bump occasionally.
UPSTREAM_IMAGE="${UPSTREAM_IMAGE:-moby/buildkit:v0.30.0}"

# Local fork image (clipper-aware). Built from clipper-registry/buildkit.
# `docker buildx bake image` produces moby/buildkit:local.
CLIPPER_IMAGE="${CLIPPER_IMAGE:-moby/buildkit:local}"

create_or_replace() {
    local name="$1"
    local image="$2"
    local flags="$3"
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

# Scenario 1: stock upstream buildkit, no clipper anything.
create_or_replace "bench-regular" "$UPSTREAM_IMAGE" \
    "--allow-insecure-entitlement=network.host"

# Scenarios 2-3: clipper-aware, eager applier (default snapshotter path).
create_or_replace "bench-clipper-eager" "$CLIPPER_IMAGE" \
    "--allow-insecure-entitlement=network.host"

# Scenario 4: clipper-aware, lazy FUSE snapshotter.
create_or_replace "bench-clipper-lazy" "$CLIPPER_IMAGE" \
    "--oci-worker-snapshotter=clipper-lazy --allow-insecure-entitlement=network.host"
