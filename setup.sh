#!/usr/bin/env bash
# Create one buildx builder PER SCENARIO. Scenarios must NOT share a builder:
# a shared builder lets a later scenario reuse an earlier one's already-pulled
# and extracted layers (s3 was silently warmed by s2 on the shared eager
# builder, so s3 never paid the cold pull -- making the eager-vs-lazy comparison
# meaningless). Separate builders => every scenario runs cold. Idempotent.
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

# --debug: buildkitd logs at debug level so containerd's docker resolver prints
# its HTTP requests (the --cache-to push path goes through that resolver, not the
# clipper registry client, so it's otherwise uninstrumented). Verbose, but this
# is a diagnostic run hunting the intermittent cache-export stall.
EAGER_FLAGS="--debug"
LAZY_FLAGS="--debug --oci-worker-snapshotter=clipper-lazy"

# Create only the builder(s) needed. With no argument (or "all") create all four
# -- this is the local path: `./setup.sh && ./bench.sh` runs every scenario
# sequentially on one machine. Pass a scenario id (s1..s4) to create just that
# one, which is what the CI workflow does (one scenario per runner).
want="${1:-all}"

# s1: stock upstream buildkit, no clipper anything.
case "$want" in s1|all) create_or_replace "bench-s1" "$UPSTREAM_IMAGE" "$EAGER_FLAGS" ;; esac

# s1-dance: same stock upstream buildkit as s1; the difference is purely that CI
# warms its RUN cache mounts with buildkit-cache-dance (the upstream way to
# persist a cache mount, since upstream can't restore one from a registry).
case "$want" in s1-dance|all) create_or_replace "bench-s1-dance" "$UPSTREAM_IMAGE" "$EAGER_FLAGS" ;; esac

# s2 + s3: clipper-aware, eager applier (default snapshotter). Separate builders
# so s3 pulls+extracts the base cold instead of reusing s2's already-extracted one.
case "$want" in s2|all) create_or_replace "bench-s2" "$CLIPPER_IMAGE" "$EAGER_FLAGS" ;; esac
case "$want" in s3|all) create_or_replace "bench-s3" "$CLIPPER_IMAGE" "$EAGER_FLAGS" ;; esac

# s4: clipper-aware, lazy FUSE snapshotter.
case "$want" in s4|all) create_or_replace "bench-s4" "$CLIPPER_IMAGE" "$LAZY_FLAGS" ;; esac
