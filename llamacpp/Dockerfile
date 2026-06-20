ARG BASE_IMAGE
ARG RUNTIME_BASE

# Build stage (devel base): the timed compile; the ccache mount lives here.
FROM ${BASE_IMAGE} AS build

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential cmake git ca-certificates curl xz-utils

# Ubuntu 24.04 ships ccache 4.9.1; install a current ccache (>=4.11 for NVCC
# --compile handling) from upstream's fully-static musl binary instead. Select
# the arch from BuildKit's TARGETARCH (set from the build's target platform) --
# NOT `uname -m`, which is unreliable under QEMU/binfmt cross-builds.
ARG CCACHE_VERSION=4.13.6
ARG TARGETARCH
RUN case "$TARGETARCH" in \
        amd64) cc_arch=x86_64 ;; \
        arm64) cc_arch=aarch64 ;; \
        *) echo "unsupported TARGETARCH=$TARGETARCH for ccache install" >&2; exit 1 ;; \
    esac && \
    pkg="ccache-${CCACHE_VERSION}-linux-${cc_arch}-musl-static" && \
    curl -fsSL "https://github.com/ccache/ccache/releases/download/v${CCACHE_VERSION}/${pkg}.tar.xz" -o /tmp/ccache.tar.xz && \
    tar -xf /tmp/ccache.tar.xz -C /tmp && \
    install -m0755 "/tmp/${pkg}/ccache" /usr/local/bin/ccache && \
    rm -rf /tmp/ccache.tar.xz "/tmp/${pkg}" && \
    ccache --version

ADD https://github.com/ggml-org/llama.cpp.git#0827b2c1da299805288abbd556d869318f2b121e /src
WORKDIR /src

# CACHE_BUST is injected per-invocation by run-scenario.sh. Appending it to
# src/llama.cpp before compiling means: (a) the RUN command differs each
# invocation so layer cache misses and the compile re-runs, and (b) the one
# changed TU misses ccache while every other TU hits, exercising the
# cache-mount transfer realistically.
#
# Builds llama.cpp's CUDA backend (-DGGML_CUDA=ON); BASE_IMAGE must be a CUDA
# -devel image (provides nvcc + cuBLAS dev headers).
#
# Per-build ccache diagnostics, both written OUTSIDE the cache dir (in /tmp, so
# they're fresh each build and aren't carried in the exported cache-mount):
#   CCACHE_STATSLOG -> per-invocation stats, summarized by `--show-log-stats`,
#     giving THIS build's hit/miss counts (vs `--show-stats`, which reports the
#     cache's cumulative lifetime counters from the mount and is misleading here).
#   CCACHE_LOGFILE  -> per-compilation trace, parsed below to list which TUs
#     missed this build.
# In-cache stats are left enabled (CCACHE_NOSTATS would also disable ccache's
# automatic size-based cleanup, letting the 5 GiB cache-mount grow unbounded).
ARG CACHE_BUST
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64/stubs/
RUN ln -s /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1
RUN --mount=type=cache,target=/root/.cache/ccache \
    export CCACHE_LOGFILE=/tmp/ccache.log CCACHE_STATSLOG=/tmp/ccache.statslog && \
    echo "// bench-mutation ${CACHE_BUST}" >> src/llama.cpp && \
    cmake -B build \
        -DGGML_CUDA=ON \
        -DCMAKE_CUDA_COMPILER_LAUNCHER=ccache \
        -DCMAKE_C_COMPILER_LAUNCHER=ccache \
        -DCMAKE_CXX_COMPILER_LAUNCHER=ccache && \
    cmake --build build -j"$(nproc)" --target llama-cli && \
    { ccache --version; \
      echo "=== ccache stats (this build) ==="; ccache --show-log-stats; \
      echo "=== missed translation units this build ==="; \
      awk '{p=$2} /Command line:/{sub(/^.*Command line: /,"");cmd[p]=$0} /Result:.*miss/{print cmd[p]}' /tmp/ccache.log 2>/dev/null | sort | uniq -c | sort -rn; \
      rm -f /tmp/ccache.log /tmp/ccache.statslog; } || true

# cmake --install installs all of examples/ + tests/, but only llama-cli is
# built, so copy just it and its build-tree shared libs into the prefix.
RUN mkdir -p /opt/llama/bin /opt/llama/lib && \
    cp build/bin/llama-cli /opt/llama/bin/ && \
    for lib in $(ldd build/bin/llama-cli | awk '/=> \//{print $3}'); do \
        case "$lib" in /src/build/*) cp "$lib" /opt/llama/lib/ ;; esac; \
    done

# Runtime stage (runtime base): just the installed artifacts.
FROM ${RUNTIME_BASE}
COPY --from=build /opt/llama /usr/local
