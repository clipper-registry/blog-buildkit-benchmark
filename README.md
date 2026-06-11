# clipper-buildkit-benchmarks

Wall-clock comparisons of stock buildkit vs clipper buildkit, building
llama.cpp on a CUDA base image with ccache.

| #  | Builder              | FROM                       | Push to                 | mode=cache-mount |
|----|----------------------|----------------------------|-------------------------|------------------|
| 1  | stock upstream       | `nvidia/cuda` (dockerhub)  | dockerhub               | no               |
| 2  | clipper, eager apply | `clipper.dev/clipper/cuda` | clipper.dev             | no               |
| 3  | clipper, eager apply | same                       | same                    | yes              |
| 4  | clipper, lazy FUSE   | same                       | same                    | yes              |

```sh
./setup.sh    # one-time: create the three buildx builders
./bench.sh    # run the matrix; results land in results.txt
```

Run `./bench.sh` twice to get cold then warm timings — only scenarios 3 and 4
transport the ccache mount across runs, so they're the only ones that should
collapse on the second pass.
