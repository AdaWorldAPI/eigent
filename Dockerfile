# Eigent Server - Railway Deployment
# Based on official server/Dockerfile, optimized for Railway

FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

WORKDIR /app

# Env setup
ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy
ENV PYTHONUNBUFFERED=1

# Install system deps
RUN apt-get update && apt-get install -y \
    gcc \
    python3-dev \
    curl \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Copy dependency files first (better layer caching)
COPY server/pyproject.toml server/uv.lock ./

# Install Python dependencies
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --no-install-project --no-dev

# Copy server code
COPY server/ /app

# Copy utils from parent (required by main.py)
COPY utils /app/utils

# Final sync
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --no-dev

# Compile i18n
RUN uv run pybabel extract -F babel.cfg -o messages.pot . 2>/dev/null || true && \
    uv run pybabel init -i messages.pot -d lang -l zh_CN 2>/dev/null || true && \
    uv run pybabel compile -d lang -l zh_CN 2>/dev/null || true

# Ensure public dir exists
RUN mkdir -p /app/app/public

# Add venv to PATH
ENV PATH="/app/.venv/bin:$PATH"

# Railway provides PORT env var
EXPOSE ${PORT:-5678}

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:${PORT:-5678}/health || exit 1

# Startup script for Railway (handles migration + start)
COPY <<'STARTUP' /app/railway-start.sh
#!/bin/sh
set -e

echo "=== Eigent Server Starting on Railway ==="
echo "DATABASE_URL configured: ${DATABASE_URL:+yes}"

# Run migrations if DB is configured
if [ -n "$DATABASE_URL" ]; then
    echo "Running database migrations..."
    uv run alembic upgrade head || echo "Migration warning (may be first run)"
fi

# Start the server
echo "Starting Eigent API server on port ${PORT:-5678}..."
exec uv run uvicorn main:api --host 0.0.0.0 --port ${PORT:-5678}
STARTUP

RUN chmod +x /app/railway-start.sh

CMD ["/app/railway-start.sh"]
