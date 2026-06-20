#!/usr/bin/env bash
# Create one buildx builder PER SCENARIO. Scenarios must NOT share a builder:
# a shared builder lets a later scenario reuse an earlier one's already-pulled
# and extracted layers (clipper-cache-mount was silently warmed by
# clipper-baseline on the shared eager builder, so it never paid the cold
# pull -- making the eager-vs-lazy comparison meaningless). Separate builders =>
# every scenario runs cold. Idempotent.
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
# sequentially on one machine. Pass a scenario id (e.g. clipper-lazy-fuse) to
# create just that one, which is what the CI workflow does (one scenario per runner).
want="${1:-all}"

# upstream-baseline: stock upstream buildkit, no clipper anything.
case "$want" in upstream-baseline|all) create_or_replace "bench-upstream-baseline" "$UPSTREAM_IMAGE" "$EAGER_FLAGS" ;; esac

# upstream-cachedance: same stock upstream buildkit as upstream-baseline; the
# difference is purely that CI warms its RUN cache mounts with buildkit-cache-dance
# (the upstream way to persist a cache mount, since upstream can't restore one from
# a registry).
case "$want" in upstream-cachedance|all) create_or_replace "bench-upstream-cachedance" "$UPSTREAM_IMAGE" "$EAGER_FLAGS" ;; esac

# clipper-baseline + clipper-cache-mount: clipper-aware, eager applier
# (default snapshotter). Separate builders so clipper-cache-mount pulls+extracts
# the base cold instead of reusing clipper-baseline's already-extracted one.
case "$want" in clipper-baseline|all) create_or_replace "bench-clipper-baseline" "$CLIPPER_IMAGE" "$EAGER_FLAGS" ;; esac
case "$want" in clipper-cache-mount|all) create_or_replace "bench-clipper-cache-mount" "$CLIPPER_IMAGE" "$EAGER_FLAGS" ;; esac

# clipper-lazy-fuse: clipper-aware, lazy FUSE snapshotter.
case "$want" in clipper-lazy-fuse|all) create_or_replace "bench-clipper-lazy-fuse" "$CLIPPER_IMAGE" "$LAZY_FLAGS" ;; esac
