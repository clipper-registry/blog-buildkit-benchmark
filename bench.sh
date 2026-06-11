#!/usr/bin/env bash
# Run all benchmark scenarios. Continue past a failing scenario so the rest
# still run and report; exit non-zero at the end if any scenario failed.
: >results.txt

# The clipper.dev CUDA base is tagged per arch; pick the one matching this host,
# and key the build cache by arch too so amd64/arm64 runs don't share a cache.
arch="$(dpkg --print-architecture)"
cuda="clipper.dev/clipper/cuda:12.9.0-runtime-ubuntu24.04-${arch}"
export CACHE_SUFFIX="-${arch}"

rc_any=0
run() { "$@" || rc_any=1; }

run ./run-scenario.sh s1 bench-regular       nvidia/cuda:12.9.0-runtime-ubuntu24.04 docker.io/clipperregistry/cuda-bench:s1 image   docker.io/clipperregistry/cuda-bench-cache
run ./run-scenario.sh s2 bench-clipper-eager "$cuda"                                 clipper.dev/clipper/cuda-bench:s2       clipper clipper.dev/clipper/cuda-bench-cache
run ./run-scenario.sh s3 bench-clipper-eager "$cuda"                                 clipper.dev/clipper/cuda-bench:s3       clipper clipper.dev/clipper/cuda-bench-cache --mount
run ./run-scenario.sh s4 bench-clipper-lazy  "$cuda"                                 clipper.dev/clipper/cuda-bench:s4       clipper clipper.dev/clipper/cuda-bench-cache --mount

echo
echo "=== RESULTS ==="
grep '^RESULT' results.txt || echo "(no results)"
exit "$rc_any"
