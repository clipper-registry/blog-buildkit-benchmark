ARG BASE_IMAGE
ARG RUNTIME_BASE

FROM ${BASE_IMAGE} AS build

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential cmake git ca-certificates curl xz-utils

ARG CCACHE_VERSION=4.13.6
ARG TARGETARCH
RUN --mount=type=tmpfs,target=/tmp \
    case "$TARGETARCH" in \
        amd64) cc_arch=x86_64 ;; \
        arm64) cc_arch=aarch64 ;; \
        *) echo "unsupported TARGETARCH=$TARGETARCH for ccache install" >&2; exit 1 ;; \
    esac && \
    pkg="ccache-${CCACHE_VERSION}-linux-${cc_arch}-musl-static" && \
    curl -fsSL "https://github.com/ccache/ccache/releases/download/v${CCACHE_VERSION}/${pkg}.tar.xz" -o /tmp/ccache.tar.xz && \
    tar -xJf /tmp/ccache.tar.xz -C /usr/local/bin --strip-components=1 --no-same-owner "${pkg}/ccache" && \
    ccache --version

ADD https://github.com/ggml-org/llama.cpp.git#0827b2c1da299805288abbd556d869318f2b121e /src
WORKDIR /src

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
    cmake --build build -j"$(nproc)" --target llama-cli

RUN mkdir -p /opt/llama/bin /opt/llama/lib && \
    cp build/bin/llama-cli /opt/llama/bin/ && \
    find build -name '*.so*' -type f -exec cp -t /opt/llama/lib/ {} +

FROM ${RUNTIME_BASE}
COPY --from=build /opt/llama /usr/local
