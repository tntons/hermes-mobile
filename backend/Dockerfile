FROM python:3.11-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install uv via the official standalone installer (no pip needed).
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:${PATH}"

COPY pyproject.toml ./
COPY hermes_bridge ./hermes_bridge
COPY tests ./tests

RUN uv sync --frozen --no-dev || uv sync
RUN uv run --no-project python -c "import hermes_bridge.main; print('import ok')"

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8080/__bridge/health || exit 1

CMD ["uv", "run", "uvicorn", "hermes_bridge.main:app", \
     "--host", "0.0.0.0", "--port", "8080", \
     "--log-level", "info"]
