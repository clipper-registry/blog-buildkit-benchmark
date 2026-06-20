ARG BASE_IMAGE
FROM ${BASE_IMAGE}

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# uv manages its own Python, so no system python needed. copy mode: uv can't
# hardlink across the cache mount. Pin 3.12 so torch's cp312 wheels resolve.
ENV UV_CACHE_DIR=/root/.cache/uv \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_PYTHON=3.12
WORKDIR /app
COPY pyproject.toml uv.lock ./

ARG CACHE_BUST
RUN --mount=type=cache,target=/root/.cache/uv \
    echo "$CACHE_BUST" >/dev/null && \
    uv sync --frozen --no-progress --compile-bytecode
ENV PATH=/opt/venv/bin:$PATH
