FROM python:3.11-slim AS builder

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM python:3.11-slim

# procps provides pgrep for the HEALTHCHECK
RUN apt-get update \
    && apt-get install -y --no-install-recommends procps \
    && rm -rf /var/lib/apt/lists/*

# Non-root user — improves security when running on K8s/VM
RUN useradd -m -r -u 1001 tgbot

WORKDIR /app

# Copy installed packages from the builder stage
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --chown=tgbot:tgbot main.py .
COPY --chown=tgbot:tgbot scripts/ ./scripts/

# Create the data dir as root, then chown and drop privileges
RUN mkdir -p /app/data && chown -R tgbot:tgbot /app

USER tgbot
ENV HOME=/app

# OCI image annotations — static labels; CI injects dynamic ones (version, revision, created)
LABEL org.opencontainers.image.title="MentionMate" \
      org.opencontainers.image.description="Telegram mention alert daemon — never miss when your team @mentions you" \
      org.opencontainers.image.source="https://github.com/hoangp47/mentionmate" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.authors="hoangp47"

# Verify the Python entry process is alive. The hardening phase will replace this with an HTTP /healthz check.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD pgrep -f 'python.*main.py' > /dev/null || exit 1

CMD ["python", "main.py"]
