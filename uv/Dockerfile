ARG BASE_IMAGE
FROM ${BASE_IMAGE}

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# copy mode: across the cache mount uv can't hardlink into the venv. Pin 3.12 so
# torch's cp312 wheels resolve (uv otherwise grabs the newest, which has none).
ENV UV_LINK_MODE=copy \
    UV_PYTHON=3.12
WORKDIR /app
COPY pyproject.toml uv.lock ./

ARG CACHE_BUST
RUN --mount=type=cache,target=/root/.cache/uv \
    echo "$CACHE_BUST" >/dev/null && \
    uv sync --frozen --no-progress --compile-bytecode
ENV PATH=/app/.venv/bin:$PATH
