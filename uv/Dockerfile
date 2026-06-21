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
    uv cache prune --ci && \
    # Guard: the mount target is uv's sdist cache dir, whose version can bump
    # (sdists-v9 -> v10). If uv stops using sdists-v9 the mount silently caches
    # nothing, so fail loud: sdists-v9 must hold the sdist, and no other
    # sdists-v* dir may be populated.
    test -d /root/.cache/uv/sdists-v9/pypi || \
      { echo "FATAL: /root/.cache/uv/sdists-v9/pypi absent after sync -- uv sdist cache dir changed; update the --mount target"; exit 1; } && \
    for d in /root/.cache/uv/sdists-v*/; do \
      [ "$d" = /root/.cache/uv/sdists-v9/ ] && continue; \
      if [ -n "$(ls -A "$d" 2>/dev/null)" ]; then \
        echo "FATAL: uv populated $d, not the mounted sdists-v9; update the --mount target"; exit 1; \
      fi; \
    done
ENV PATH=/app/.venv/bin:$PATH
