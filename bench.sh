#!/usr/bin/env bash
# Run benchmark cells (workload x scenario). Continue past a failing cell so the
# rest still run and report; exit non-zero at the end if any failed. Each cell
# runs under a hard timeout (GIVEUP) so a hung one doesn't block the rest.
: >results.txt

arch="$(dpkg --print-architecture)"
export CACHE_SUFFIX="-${arch}"

GIVEUP=900
rc_any=0

WORKLOADS="${WORKLOADS:-llamacpp uv}"
SCENARIOS="${SCENARIOS:-upstream-baseline upstream-cachedance clipper-baseline clipper-cache-mount clipper-lazy-fuse}"
# CELLS optionally restricts to specific "<workload>-<scenario>" cells; CI sets
# it to the one cell for the current matrix runner. Default: every cell.
CELLS="${CELLS:-}"

# workload -> cuda image variant (devel compiles llama.cpp; uv only installs
# prebuilt wheels, so it needs only the runtime base). Each workload's Dockerfile
# (and any context files) lives in its own directory: <workload>/Dockerfile.
wl_variant() { case "$1" in llamacpp) echo devel ;; uv) echo runtime ;; esac; }

# run <label> <cmd...>: run a cell in the background under a hard-timeout watchdog.
run() {
  local label="$1"; shift
  "$@" &
  local bpid=$! start=$SECONDS
  while kill -0 "$bpid" 2>/dev/null; do
    sleep 15
    if [ "$((SECONDS - start))" -ge "$GIVEUP" ]; then
      echo "  $label exceeded ${GIVEUP}s -> killing"
      kill "$bpid" 2>/dev/null
      break
    fi
  done
  wait "$bpid" 2>/dev/null || rc_any=1
}

# One builder per cell (see setup.sh) so each runs cold. The scenario half picks
# the engine: upstream-* = stock buildkit on dockerhub bases; clipper-* = the
# clipper fork on clipper.dev bases (cache-mount/lazy-fuse add the registry-backed
# RUN cache mount). upstream-cachedance is upstream warmed by buildkit-cache-dance
# in the CI workflow around this build.
for wl in $WORKLOADS; do
  df="${wl}/Dockerfile"
  variant="$(wl_variant "$wl")"
  for sc in $SCENARIOS; do
    cell="${wl}-${sc}"
    if [ -n "$CELLS" ]; then
      case " $CELLS " in *" $cell "*) ;; *) continue ;; esac
    fi
    case "$sc" in
      upstream-*)
        base="nvidia/cuda:12.9.0-${variant}-ubuntu24.04"
        repo="docker.io/clipperregistry/cuda-bench"
        output=image ;;
      clipper-*)
        base="clipper.dev/clipper/cuda:12.9.0-${variant}-ubuntu24.04-${arch}"
        repo="clipper.dev/clipper/cuda-bench"
        output=clipper ;;
    esac
    case "$sc" in *cache-mount|*lazy-fuse) mount=--mount ;; *) mount= ;; esac
    run "$cell" ./run-scenario.sh \
      "$cell" "bench-${cell}" "$base" "${repo}:${cell}" "$output" "${repo}-cache" "$df" $mount
  done
done

echo
echo "=== RESULTS ==="
grep '^RESULT' results.txt || echo "(no results)"
exit "$rc_any"
