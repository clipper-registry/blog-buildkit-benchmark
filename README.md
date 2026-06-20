# clipper-buildkit-benchmarks

Wall-clock comparisons of stock buildkit vs the clipper buildkit fork, across two
workloads on a CUDA base, run for every **workload × scenario** cell.

## Workloads

| workload   | Dockerfile      | what it does                                          | RUN cache mount        | base    |
|------------|-----------------|------------------------------------------------------|------------------------|---------|
| `llamacpp` | `Dockerfile`    | compile llama.cpp with ccache (CPU-bound)            | ccache (many small)    | devel   |
| `uv`       | `Dockerfile.uv` | `uv sync` ML deps incl. torch (download/IO-bound)    | uv cache (few huge)    | runtime |

They stress opposite ends of cache-mount transfer: `llamacpp`'s ccache is many
small files; `uv`'s cache is a few multi-GB wheels. `llamacpp` is multi-stage
(devel base compiles, runtime base takes the binary); `uv` is single-stage on
the runtime base (uv manages its own Python, so nothing to discard).

## Scenarios

Each scenario applies to both workloads.

| scenario              | engine                                | base FROM                  | push to     | cache mount                       |
|-----------------------|---------------------------------------|----------------------------|-------------|-----------------------------------|
| `upstream-baseline`   | stock upstream buildkit               | `nvidia/cuda` (dockerhub)  | dockerhub   | no                                |
| `upstream-cachedance` | stock upstream + buildkit-cache-dance | `nvidia/cuda` (dockerhub)  | dockerhub   | via cache-dance (`actions/cache`) |
| `clipper-baseline`    | clipper, eager apply                  | `clipper.dev/clipper/cuda` | clipper.dev | no                                |
| `clipper-cache-mount` | clipper, eager apply                  | `clipper.dev/clipper/cuda` | clipper.dev | yes (registry-backed)             |
| `clipper-lazy-fuse`   | clipper, lazy FUSE snapshotter        | `clipper.dev/clipper/cuda` | clipper.dev | yes (registry-backed)             |

`upstream-cachedance` is the fair "what upstream can do" comparison for cache
mounts: upstream can't restore a RUN cache mount from a registry the way clipper
does, so it warms the mount out of band with buildkit-cache-dance + `actions/cache`.
That restore/save runs in separate CI steps and is shown in the dance columns.

## Running locally

```sh
./setup.sh    # create one buildx builder per cell
./bench.sh    # run every cell; results land in results.txt
```

Each cell runs on its own builder so it starts cold, and `--build-arg CACHE_BUST`
keeps the work layer cold every run. Subset with `WORKLOADS` / `SCENARIOS` (or
`CELLS` for exact cells):

```sh
WORKLOADS=uv SCENARIOS="clipper-cache-mount clipper-lazy-fuse" ./bench.sh
```

## Results

`results.txt` gets two lines per cell (`label` is `<workload>-<scenario>`):

```
RESULT label=llamacpp-clipper-lazy-fuse exit=0 seconds=46
PHASE  label=llamacpp-clipper-lazy-fuse pull=1.2 build=33.0 export=11.8
```

`parse-phases.sh` splits each cell's real total into three phases that sum to it:

- **pull**: getting the base image ready (resolve + cache-manifest import + layer
  download/extract). Ends when the last pull vertex completes.
- **export**: exporting the image and pushing the registry cache.
- **build**: the remainder (stage RUN steps). For `clipper-lazy-fuse` this
  includes the on-demand layer fetches during exec, which is why its `pull` is
  near zero and the fetch cost surfaces in `build`.

## CI

`.github/workflows/benchmark.yml` builds the clipper buildkit image, then runs
each cell on its own runner (matrix, parallel, cold), writing distinct tags
(`cuda-bench:<cell>`, `cuda-bench-cache:<cell>-<arch>`). A final `summarize` job
collects every cell's `RESULT`/`PHASE` into one table grouped by workload, then
engine, then total. Trigger it manually (`workflow_dispatch`) to choose a
`buildkit_image` or a subset of `workloads`/`scenarios`.

Timings on GitHub-hosted runners are noisy (shared VMs); use them for
trend/regression, not absolutes.
