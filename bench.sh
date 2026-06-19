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
# (e.g. "s2 s3 s4" to skip the s1 baseline).
run() {
  local id="$2"
  case " ${SCENARIOS:-s1 s1-dance s2 s3 s4} " in
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
# s1       = upstream buildkit, cold baseline.
# s1-dance = upstream buildkit warmed by buildkit-cache-dance -- the dance
#            (inject/extract of the RUN cache mounts via actions/cache) runs in
#            the CI workflow around this; here it's just the same upstream build.
#            The fair "what upstream CAN do" comparison vs clipper's cache-mount.
# s2-s4    = clipper (s3/s4 use clipper's registry-backed cache-mount).
run ./run-scenario.sh s1       bench-s1       nvidia/cuda:12.9.0-devel-ubuntu24.04 docker.io/clipperregistry/cuda-llamacpp-bench:s1       image   docker.io/clipperregistry/cuda-llamacpp-bench-cache
run ./run-scenario.sh s1-dance bench-s1-dance nvidia/cuda:12.9.0-devel-ubuntu24.04 docker.io/clipperregistry/cuda-llamacpp-bench:s1-dance image   docker.io/clipperregistry/cuda-llamacpp-bench-cache
run ./run-scenario.sh s2 bench-s2 "$cuda"                               clipper.dev/clipper/cuda-llamacpp-bench:s2       clipper clipper.dev/clipper/cuda-llamacpp-bench-cache
run ./run-scenario.sh s3 bench-s3 "$cuda"                               clipper.dev/clipper/cuda-llamacpp-bench:s3       clipper clipper.dev/clipper/cuda-llamacpp-bench-cache --mount
run ./run-scenario.sh s4 bench-s4 "$cuda"                               clipper.dev/clipper/cuda-llamacpp-bench:s4       clipper clipper.dev/clipper/cuda-llamacpp-bench-cache --mount

echo
echo "=== RESULTS ==="
grep '^RESULT' results.txt || echo "(no results)"
exit "$rc_any"
