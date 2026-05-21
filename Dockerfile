# syntax=docker/dockerfile:1.7
# MentionMate — Telegram mention alert daemon
# Image optimization goals (in order): size, then security.

# --- Stage 1: builder ------------------------------------------------------
# python:3.11-alpine (musllinux) — digest-pinned for reproducibility.
# Refresh digest when bumping Python patch versions or on CVE bulletins.
FROM python:3.11-alpine@sha256:8b5bfdb1fd2d78aa94e21c4d61be52487693f54be7f1021647751ff365795703 AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_COMPILE=1

# Build deps only in this stage (gcc/musl-dev/etc are NOT copied to runtime).
# Required because some pinned wheels (yarl, multidict, aiohttp, frozenlist)
# may not publish musllinux wheels for every (version, arch) combo; we fall back
# to source builds.
RUN apk add --no-cache --virtual .build-deps \
        gcc \
        musl-dev \
        libffi-dev \
        openssl-dev \
        python3-dev

WORKDIR /src
COPY pyproject.toml ./
COPY src/ ./src/

# Install our package + deps into an isolated prefix that we will COPY whole.
RUN pip install --prefix=/install .

# Aggressively trim the install tree. We do NOT ship pip/setuptools/wheel in runtime.
RUN find /install -type d \( -name '__pycache__' -o -name 'tests' -o -name 'test' \) -prune -exec rm -rf {} + \
 && find /install -type d -name '*.dist-info' -prune -exec rm -rf {} + \
 && find /install -type f \( -name '*.pyi' -o -name '*.pyc' -o -name '*.pyo' \) -delete \
 && rm -rf /install/lib/python3.11/site-packages/pip \
           /install/lib/python3.11/site-packages/setuptools \
           /install/lib/python3.11/site-packages/wheel \
           /install/lib/python3.11/site-packages/pkg_resources \
           /install/bin/pip* \
           /install/bin/wheel*

# --- Stage 2: runtime ------------------------------------------------------
FROM python:3.11-alpine@sha256:8b5bfdb1fd2d78aa94e21c4d61be52487693f54be7f1021647751ff365795703

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    HOME=/app

# Non-root user — improves security when running on K8s/VM.
# Same step also strips pip/setuptools/wheel that ship in the base image.
RUN adduser -D -u 1001 tgbot \
 && mkdir -p /app/data \
 && chown -R tgbot:tgbot /app \
 && rm -rf /usr/local/lib/python3.11/site-packages/pip \
           /usr/local/lib/python3.11/site-packages/pip-*.dist-info \
           /usr/local/lib/python3.11/site-packages/setuptools \
           /usr/local/lib/python3.11/site-packages/setuptools-*.dist-info \
           /usr/local/lib/python3.11/site-packages/wheel \
           /usr/local/lib/python3.11/site-packages/wheel-*.dist-info \
           /usr/local/lib/python3.11/site-packages/_distutils_hack \
           /usr/local/lib/python3.11/site-packages/distutils-precedence.pth \
           /usr/local/lib/python3.11/site-packages/pkg_resources \
           /usr/local/bin/pip* \
           /usr/local/bin/wheel* \
           /usr/local/bin/idle* \
           /usr/local/bin/2to3* \
           /usr/local/bin/pydoc*

# Copy the pre-installed, pre-stripped tree.
COPY --from=builder /install /usr/local

WORKDIR /app
USER tgbot

# OCI image annotations — static labels; CI injects dynamic ones (version, revision, created)
LABEL org.opencontainers.image.title="MentionMate" \
      org.opencontainers.image.description="Telegram mention alert daemon — never miss when your team @mentions you" \
      org.opencontainers.image.source="https://github.com/PhamHoang16/mention-mate" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.authors="hoangp47"

# Liveness probe — PID 1 alive == container alive. No extra binary needed.
# Hardening phase will replace this with an HTTP /healthz check.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import os,sys; sys.exit(0 if os.path.exists('/proc/1/status') else 1)" || exit 1

CMD ["python", "-m", "mention_mate"]
