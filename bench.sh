#!/usr/bin/env bash
# Run all benchmark scenarios. Continue past a failing scenario so the rest
# still run and report; exit non-zero at the end if any scenario failed.
#
# Each scenario runs under a hard timeout (GIVEUP): healthy scenarios finish in
# ~1-2.5min, so one still running well past that is hung -- kill it so the run
# completes and still reports the others.
: >results.txt

arch="$(dpkg --print-architecture)"
cuda="clipper.dev/clipper/cuda:12.9.0-devel-ubuntu24.04-${arch}"
export CACHE_SUFFIX="-${arch}"

GIVEUP=600    # hard cap per scenario

rc_any=0

# run <./run-scenario.sh> <id> <builder> ... : run a scenario in the background
# under a hard-timeout watchdog. Skips the scenario if it's not in $SCENARIOS (a
# space-separated allowlist; defaults to all), letting a run target a subset
# (e.g. "clipper-registry-cache clipper-cache-mount clipper-lazy-fuse" to skip the upstream baselines).
run() {
  local id="$2"
  case " ${SCENARIOS:-upstream-baseline upstream-cachedance clipper-registry-cache clipper-cache-mount clipper-lazy-fuse} " in
    *" $id "*) ;;
    *) echo "skipping $id (not in SCENARIOS='${SCENARIOS}')"; return ;;
  esac
  "$@" &
  local bpid=$! start=$SECONDS
  while kill -0 "$bpid" 2>/dev/null; do
    sleep 15
    if [ "$((SECONDS - start))" -ge "$GIVEUP" ]; then
      echo "  $id exceeded ${GIVEUP}s -> killing"
      kill "$bpid" 2>/dev/null
      break
    fi
  done
  wait "$bpid" 2>/dev/null || rc_any=1
}

# One builder per scenario (see setup.sh) so each runs cold -- no scenario
# reuses another's pulled/extracted layers.
#
# upstream-baseline      = upstream buildkit, cold baseline.
# upstream-cachedance    = upstream buildkit warmed by buildkit-cache-dance -- the
#            dance (inject/extract of the RUN cache mounts via actions/cache) runs
#            in the CI workflow around this; here it's just the same upstream build.
#            The fair "what upstream CAN do" comparison vs clipper's cache-mount.
# clipper-*               = clipper (registry-cache, then cache-mount, then lazy-fuse).
run ./run-scenario.sh upstream-baseline   bench-upstream-baseline   nvidia/cuda:12.9.0-devel-ubuntu24.04 docker.io/clipperregistry/cuda-llamacpp-bench:upstream-baseline   image   docker.io/clipperregistry/cuda-llamacpp-bench-cache
run ./run-scenario.sh upstream-cachedance bench-upstream-cachedance nvidia/cuda:12.9.0-devel-ubuntu24.04 docker.io/clipperregistry/cuda-llamacpp-bench:upstream-cachedance image   docker.io/clipperregistry/cuda-llamacpp-bench-cache
run ./run-scenario.sh clipper-registry-cache bench-clipper-registry-cache "$cuda"                         clipper.dev/clipper/cuda-llamacpp-bench:clipper-registry-cache clipper clipper.dev/clipper/cuda-llamacpp-bench-cache
run ./run-scenario.sh clipper-cache-mount    bench-clipper-cache-mount    "$cuda"                         clipper.dev/clipper/cuda-llamacpp-bench:clipper-cache-mount    clipper clipper.dev/clipper/cuda-llamacpp-bench-cache --mount
run ./run-scenario.sh clipper-lazy-fuse      bench-clipper-lazy-fuse      "$cuda"                         clipper.dev/clipper/cuda-llamacpp-bench:clipper-lazy-fuse      clipper clipper.dev/clipper/cuda-llamacpp-bench-cache --mount

echo
echo "=== RESULTS ==="
grep '^RESULT' results.txt || echo "(no results)"
exit "$rc_any"
