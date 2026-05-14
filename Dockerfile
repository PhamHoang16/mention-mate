FROM python:3.11-slim as builder

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM python:3.11-slim

# Tạo non-root user để tăng tính bảo mật khi chạy trên K8s/VM
RUN useradd -m -r -u 1001 tgbot

WORKDIR /app

# Copy thư viện đã cài từ builder
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --chown=tgbot:tgbot main.py .

# Tạo thư mục data (còn đang là root) rồi mới chown và switch user
RUN mkdir -p /app/data && chown -R tgbot:tgbot /app

USER tgbot
ENV HOME=/app

CMD ["python", "main.py"]