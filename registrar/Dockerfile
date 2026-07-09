FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY pyproject.toml ./
COPY src/ ./src/
RUN pip install --no-cache-dir .

# Also needs the docker CLI's client library only (docker SDK, already a
# dependency) — no docker-in-docker binary required, only socket access.
EXPOSE 8000
CMD ["uvicorn", "registrar.app:app", "--host", "0.0.0.0", "--port", "8000"]
