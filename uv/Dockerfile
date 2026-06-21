ARG BASE_IMAGE
FROM ${BASE_IMAGE}

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /app
COPY pyproject.toml uv.lock ./

ARG CACHE_BUST
# Persist only uv's sdist bucket (the ~3.7GB tensorrt artifact) without putting
# the rest of the cache on the FUSE mount. uv renames built wheels from
# builds-v0 -> sdists-v9, which must be on ONE filesystem, so mount both on a
# single cache mount and symlink them into uv's cache. archive-v0 (the
# unpacked-wheel store uv installs from) stays on the local rootfs, so the
# install hardlinks into the venv (same fs) instead of a cross-filesystem copy.
RUN --mount=type=cache,target=/uvcache \
    mkdir -p /uvcache/builds-v0 /uvcache/sdists-v9 /root/.cache/uv && \
    ln -sfn /uvcache/builds-v0 /root/.cache/uv/builds-v0 && \
    ln -sfn /uvcache/sdists-v9 /root/.cache/uv/sdists-v9 && \
    echo "$CACHE_BUST" >/dev/null && \
    uv sync --frozen --no-progress --compile-bytecode && \
    uv cache prune --ci && \
    # Guard against uv bumping its cache bucket versions (builds-v0/sdists-v9):
    # a different bucket would be a REAL dir on the rootfs (not our symlink) and
    # the mount would cache nothing -- fail loud with the layout.
    for b in /root/.cache/uv/sdists-v* /root/.cache/uv/builds-v*; do \
      if [ -e "$b" ] && [ ! -L "$b" ]; then \
        echo "FATAL: $b is a real dir -- uv bumped its cache bucket; update the symlinks"; \
        ls -al /root/.cache/uv/ 2>&1; exit 1; \
      fi; \
    done && \
    { [ -n "$(find /uvcache/sdists-v9 -type f -size +100M 2>/dev/null)" ] || \
      { echo "FATAL: no large artifact cached in /uvcache/sdists-v9 after sync:"; ls -alR /uvcache 2>&1; exit 1; }; }
ENV PATH=/app/.venv/bin:$PATH
