ARG BASE_IMAGE
FROM ${BASE_IMAGE}

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /app
COPY pyproject.toml uv.lock ./

ARG CACHE_BUST
# Cache only the sdist dir: after `uv cache prune --ci` that's the only thing the
# uv cache retains (the ~3.7GB tensorrt artifact under sdists-v9). Keeping the
# rest of /root/.cache/uv (archive-v0, wheels) on the local rootfs lets uv
# hardlink into the venv (same filesystem) instead of a cross-fs full copy, and
# keeps the bulk off the registry-backed FUSE cache mount.
RUN --mount=type=cache,target=/root/.cache/uv/sdists-v9 \
    echo "$CACHE_BUST" >/dev/null && \
    uv sync --frozen --no-progress --compile-bytecode && \
    uv cache prune --ci
ENV PATH=/app/.venv/bin:$PATH
