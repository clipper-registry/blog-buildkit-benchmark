ARG BASE_IMAGE
FROM ${BASE_IMAGE}

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential cmake git ccache ca-certificates

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
ARG CACHE_BUST
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64/stubs/
RUN --mount=type=cache,target=/root/.cache/ccache \
    echo "// bench-mutation ${CACHE_BUST}" >> src/llama.cpp && \
    cmake -B build \
        -DGGML_CUDA=ON \
        -DCMAKE_CUDA_COMPILER_LAUNCHER=ccache \
        -DCMAKE_C_COMPILER_LAUNCHER=ccache \
        -DCMAKE_CXX_COMPILER_LAUNCHER=ccache && \
    cmake --build build -j"$(nproc)" --target llama-cli
