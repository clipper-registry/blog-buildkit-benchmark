#!/usr/bin/env bash
# Run all benchmark scenarios. Continue past a failing scenario so the rest
# still run and report; exit non-zero at the end if any scenario failed.
#
# Each scenario runs under a stall watchdog: healthy scenarios finish in
# ~1-2.5min, so if one is still running at STALL/CONFIRM it is hung. We snapshot
# buildkitd's goroutines (pprof, non-destructive) twice -- the same goroutine
# parked at the same spot across both snapshots is a real block, not slowness --
# then kill it so the run completes and uploads the dumps. (The export stall and
# the exec wedge both surface here; the dump distinguishes them.)
: >results.txt

arch="$(dpkg --print-architecture)"
cuda="clipper.dev/clipper/cuda:12.9.0-runtime-ubuntu24.04-${arch}"
export CACHE_SUFFIX="-${arch}"

OUTDIR=hang-dumps
mkdir -p "$OUTDIR"
STALL=300     # snapshot 1: well past any healthy scenario (max ~150s)
CONFIRM=420   # snapshot 2 still running => confirmed hang
GIVEUP=600    # hard cap per scenario

rc_any=0

dump() { # $1=container $2=outfile
  docker exec "$1" wget -qO- "http://localhost:6060/debug/pprof/goroutine?debug=2" >"$2" 2>/dev/null || true
  echo "    hang-dump -> $(wc -l <"$2" 2>/dev/null || echo 0) lines  $2"
}

# run <./run-scenario.sh> <id> <builder> ... : run a scenario in the background
# with the stall watchdog. Skips the scenario if it's not in $SCENARIOS (a
# space-separated allowlist; defaults to all). Lets the hang-hunt skip s1
# (upstream baseline, irrelevant to the clipper paths) while the normal
# push-triggered benchmark still runs all four.
run() {
  local id="$2" builder="$3"
  case " ${SCENARIOS:-s1 s2 s3 s4} " in
    *" $id "*) ;;
    *) echo "skipping $id (not in SCENARIOS='${SCENARIOS}')"; return ;;
  esac
  local ctr="buildx_buildkit_${builder}0"
  "$@" &
  local bpid=$! start=$SECONDS s1=0 s2=0 el
  while kill -0 "$bpid" 2>/dev/null; do
    sleep 15
    el=$((SECONDS - start))
    if [ "$s1" = 0 ] && [ "$el" -ge "$STALL" ]; then
      echo "  $id still running at ${el}s -> goroutine snapshot 1 ($ctr)"
      dump "$ctr" "$OUTDIR/${id}-snap1.txt"
      s1=1
    elif [ "$s1" = 1 ] && [ "$s2" = 0 ] && [ "$el" -ge "$CONFIRM" ]; then
      echo "  $id STILL running at ${el}s -> snapshot 2 *** CONFIRMED HANG ***"
      dump "$ctr" "$OUTDIR/${id}-snap2.txt"
      docker logs "$ctr" >"$OUTDIR/${id}-daemon.log" 2>&1 || true
      s2=1
      kill "$bpid" 2>/dev/null
      break
    fi
    if [ "$el" -ge "$GIVEUP" ]; then
      echo "  $id exceeded ${GIVEUP}s -> killing"
      kill "$bpid" 2>/dev/null
      break
    fi
  done
  wait "$bpid" 2>/dev/null || rc_any=1
}

# One builder per scenario (see setup.sh) so each runs cold -- no scenario
# reuses another's pulled/extracted layers.
run ./run-scenario.sh s1 bench-s1 nvidia/cuda:12.9.0-runtime-ubuntu24.04 docker.io/clipperregistry/cuda-bench:s1 image   docker.io/clipperregistry/cuda-bench-cache
run ./run-scenario.sh s2 bench-s2 "$cuda"                                 clipper.dev/clipper/cuda-bench:s2       clipper clipper.dev/clipper/cuda-bench-cache
run ./run-scenario.sh s3 bench-s3 "$cuda"                                 clipper.dev/clipper/cuda-bench:s3       clipper clipper.dev/clipper/cuda-bench-cache --mount
run ./run-scenario.sh s4 bench-s4 "$cuda"                                 clipper.dev/clipper/cuda-bench:s4       clipper clipper.dev/clipper/cuda-bench-cache --mount

echo
echo "=== RESULTS ==="
grep '^RESULT' results.txt || echo "(no results)"
exit "$rc_any"
