ARG BASE_IMAGE
FROM ${BASE_IMAGE}

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential cmake git ccache ca-certificates

# Fetch the pinned commit as a tarball rather than a git ADD: avoids the git
# source fetching (and logging) every remote tag, and the "Not a valid object
# name" failure when buildkit's git source can't retrieve a bare commit SHA.
ADD https://github.com/ggml-org/llama.cpp/archive/0827b2c1da299805288abbd556d869318f2b121e.tar.gz /src.tar.gz
RUN mkdir -p /src && tar -xzf /src.tar.gz -C /src --strip-components=1 && rm /src.tar.gz
WORKDIR /src

# CACHE_BUST is injected per-invocation by run-scenario.sh. Appending it to
# src/llama.cpp before compiling means: (a) the RUN command differs each
# invocation so layer cache misses and the compile re-runs, and (b) the one
# changed TU misses ccache while every other TU hits, exercising the
# cache-mount transfer realistically.
ARG CACHE_BUST
RUN --mount=type=cache,target=/root/.cache/ccache \
    echo "// bench-mutation ${CACHE_BUST}" >> src/llama.cpp && \
    cmake -B build \
        -DCMAKE_C_COMPILER_LAUNCHER=ccache \
        -DCMAKE_CXX_COMPILER_LAUNCHER=ccache && \
    cmake --build build -j"$(nproc)" --target llama-cli
