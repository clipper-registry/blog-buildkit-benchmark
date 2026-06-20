ARG BASE_IMAGE
FROM ${BASE_IMAGE}

RUN apt-get update && apt-get install -y --no-install-recommends python3
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /app
COPY pyproject.toml uv.lock ./

# only-system: use the base's python3 (3.12) rather than downloading a managed
# interpreter, so the uv cache mount holds only wheels.
ARG CACHE_BUST
RUN --mount=type=cache,target=/root/.cache/uv \
    echo "$CACHE_BUST" >/dev/null && \
    uv sync --frozen --python-preference only-system --no-progress --compile-bytecode
ENV PATH=/app/.venv/bin:$PATH
