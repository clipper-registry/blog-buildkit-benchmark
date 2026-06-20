ARG BASE_IMAGE
ARG RUNTIME_BASE

# Build stage: install the ML deps into a venv; the uv cache mount lives here.
FROM ${BASE_IMAGE} AS build
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update && \
    apt-get install -y --no-install-recommends python3 ca-certificates
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# copy: uv hardlinks cache->venv by default, which fails across the cache mount.
ENV UV_CACHE_DIR=/root/.cache/uv \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_PYTHON=python3
WORKDIR /app
COPY pyproject.toml ./

ARG CACHE_BUST
RUN --mount=type=cache,target=/root/.cache/uv \
    echo "$CACHE_BUST" >/dev/null && \
    uv sync --no-progress --compile-bytecode

# Runtime stage: just the venv.
FROM ${RUNTIME_BASE}
COPY --from=build /opt/venv /opt/venv
ENV PATH=/opt/venv/bin:$PATH
