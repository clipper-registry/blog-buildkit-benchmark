# clipper-buildkit-benchmarks

Wall-clock comparisons of stock buildkit vs the clipper buildkit fork, building
llama.cpp on a CUDA base image with ccache.

## Scenarios

| scenario                 | engine                                | base FROM                  | push to     | cache mount                       |
|--------------------------|---------------------------------------|----------------------------|-------------|-----------------------------------|
| `upstream-baseline`      | stock upstream buildkit               | `nvidia/cuda` (dockerhub)  | dockerhub   | no                                |
| `upstream-cachedance`    | stock upstream + buildkit-cache-dance | `nvidia/cuda` (dockerhub)  | dockerhub   | via cache-dance (`actions/cache`) |
| `clipper-registry-cache` | clipper, eager apply                  | `clipper.dev/clipper/cuda` | clipper.dev | no                                |
| `clipper-cache-mount`    | clipper, eager apply                  | `clipper.dev/clipper/cuda` | clipper.dev | yes (registry-backed)             |
| `clipper-lazy-fuse`      | clipper, lazy FUSE snapshotter        | `clipper.dev/clipper/cuda` | clipper.dev | yes (registry-backed)             |

`upstream-cachedance` is the fair "what upstream can do" comparison for cache
mounts: upstream cannot restore a RUN cache mount from a registry the way
clipper's cache-mount does, so it warms the mount out of band with
buildkit-cache-dance + `actions/cache`. That restore/save runs in separate CI
steps and is added back in the summary.

## Running locally

```sh
./setup.sh    # one-time: create one buildx builder per scenario
./bench.sh    # run every scenario; results land in results.txt
```

Each scenario runs on its own builder so it starts cold (no scenario reuses
another's pulled/extracted layers), and `--build-arg CACHE_BUST` keeps the
compile layer cold every run. Run a subset with `SCENARIOS`:

```sh
SCENARIOS="clipper-cache-mount clipper-lazy-fuse" ./bench.sh
```

## Results

`results.txt` gets two lines per scenario:

```
RESULT label=clipper-lazy-fuse exit=0 seconds=46
PHASE  label=clipper-lazy-fuse pull=1.2 build=33.0 export=11.8
```

`parse-phases.sh` splits each scenario's real total into three phases that sum
to it:

- **pull**: getting the base image ready (resolve + cache-manifest import +
  layer download/extract). Ends when the last pull vertex completes.
- **export**: exporting the image and pushing the registry cache.
- **build**: the remainder (stage RUN steps). For `clipper-lazy-fuse` this
  includes the on-demand layer fetches that happen during exec, which is why its
  `pull` is near zero and the fetch cost surfaces in `build`.

## CI

`.github/workflows/benchmark.yml` builds the clipper buildkit image, then runs
each scenario on its own runner (matrix, in parallel, all cold) and writes
distinct registry tags (`cuda-llamacpp-bench:<scenario>`,
`cuda-llamacpp-bench-cache:<scenario>-<arch>`) so parallel runs do not collide.
A final `summarize` job collects every scenario's `RESULT`/`PHASE` into one
table. Trigger it manually (`workflow_dispatch`) to choose a `buildkit_image` or
a subset of `scenarios`.

Timings on GitHub-hosted runners are noisy (shared VMs); use them for
trend/regression, not absolutes.
