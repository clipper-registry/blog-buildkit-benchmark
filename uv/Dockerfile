ARG BASE_IMAGE
FROM ${BASE_IMAGE}

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /app
COPY pyproject.toml uv.lock ./

ARG CACHE_BUST
# No cache mount: the only thing it persisted was the ~3.7GB tensorrt sdist
# artifact, and pulling that from the registry-backed cache mount (~72s) is slower
# than uv re-pulling it from NVIDIA's CDN (~21s) -- the cache was a slower copy of
# upstream. Keeping uv's cache on the rootfs also lets the install hardlink into
# the venv (same fs) instead of a cross-filesystem copy. rm -rf afterwards keeps
# the cache out of the exported layer.
RUN echo "$CACHE_BUST" >/dev/null && \
    uv sync --frozen --no-progress --compile-bytecode && \
    rm -rf /root/.cache/uv
ENV PATH=/app/.venv/bin:$PATH
