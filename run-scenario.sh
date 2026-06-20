#!/usr/bin/env bash
# Run one timed docker buildx build, append wall-clock to results.txt.
#
# Usage:
#   ./run-scenario.sh <id> <builder> <base> <target> <output> <cache-repo> [--mount]
#
# Builds these cache flags from <cache-repo> + <id>:
#   --cache-to   type=registry,ref=<cache-repo>:<id>,mode=max
#   --cache-from type=registry,ref=<cache-repo>:<id>
# If --mount is passed, also adds:
#   --cache-to   type=registry,ref=<cache-repo>:<id>-mounts,mode=cache-mount
#   --cache-from type=registry,ref=<cache-repo>:<id>-mounts,mode=cache-mount
#
# Also passes --build-arg CACHE_BUST=<nanoseconds> so the Dockerfile's compile
# step has a different source content per invocation.
set -euo pipefail

id="$1"
builder="$2"
base="$3"
target="$4"
output="$5"
cache_repo="$6"
dockerfile="$7"
mount_flag="${8:-}"

# The build context is the Dockerfile's own directory (each workload is
# self-contained: e.g. uv/ carries pyproject.toml).
context="$(dirname "$dockerfile")"

# Runtime base for the final stage: the devel base with -devel- -> -runtime-.
runtime_base="${base/-devel-/-runtime-}"

# Capture this scenario's full stdout+stderr to a per-scenario log while still
# streaming live to the terminal. The redirect is applied to the script's own
# file descriptors via exec, so the build command below stays bare (no pipe or
# redirect attached to it) and its real exit code is preserved. Without this,
# buildx's failure output went only to the terminal and was lost; only the
# RESULT line landed in results.txt.
log="${id}-build.log"
: >"$log"
exec > >(tee -a "$log") 2>&1

# Optional CACHE_SUFFIX lets callers point at a fresh (cold) cache key without
# touching the existing tags, e.g. CACHE_SUFFIX=-t1700000000.
key="${id}${CACHE_SUFFIX:-}"
cache=(
    --cache-to   "type=registry,ref=${cache_repo}:${key},mode=max"
    --cache-from "type=registry,ref=${cache_repo}:${key}"
)
if [ "$mount_flag" = "--mount" ]; then
    cache+=(
        --cache-to   "type=registry,ref=${cache_repo}:${key}-mounts,mode=cache-mount"
        --cache-from "type=registry,ref=${cache_repo}:${key}-mounts,mode=cache-mount"
    )
fi

printf '\n=== %s ===\n' "$id" | tee -a results.txt

# Prune the builder cache so the timed build reflects only what cache-from can
# pull back from the registry, not whatever was left in the builder by a prior
# invocation. This only matters locally, where `./setup.sh && ./bench.sh` runs
# every scenario sequentially against persistent builders.
#
# Skip it entirely in GitHub Actions: each scenario runs on its own fresh runner
# with a freshly-created builder (nothing to prune), and a `prune -af` would wipe
# any cache restored just before the build -- notably upstream-cachedance's RUN cache mounts,
# which buildkit-cache-dance injects locally (upstream can't restore one from a
# registry). CACHE_BUST keeps the compile layer cold regardless.
if [ -z "${GITHUB_ACTIONS:-}" ]; then
    docker buildx prune -af --builder "$builder" >/dev/null
fi

start=$SECONDS
if docker buildx build --builder "$builder" \
        --file "$dockerfile" \
        --build-arg "BASE_IMAGE=${base}" \
        --build-arg "RUNTIME_BASE=${runtime_base}" \
        --build-arg "CACHE_BUST=$(date +%s%N)" \
        --output "type=${output},name=${target},push=true" \
        "${cache[@]}" \
        .; then
    rc=0
else
    rc=$?
fi
elapsed=$((SECONDS - start))
printf 'RESULT label=%q exit=%d seconds=%d\n' "$id" "$rc" "$elapsed" | tee -a results.txt

# Split this scenario's real total into pull/build/export phases for the summary.
printf 'PHASE label=%q %s\n' "$id" "$(./parse-phases.sh "$log" "$elapsed")" | tee -a results.txt

exit "$rc"
