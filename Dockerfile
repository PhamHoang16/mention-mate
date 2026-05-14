FROM python:3.11-slim as builder

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM python:3.11-slim

# Tạo non-root user để tăng tính bảo mật khi chạy trên K8s/VM
RUN useradd -m -r -u 1001 tgbot
USER tgbot

WORKDIR /app

# Copy thư viện đã cài từ builder
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --chown=tgbot:tgbot main.py .

# Thư mục chứa session file
RUN mkdir -p /app/data
ENV HOME=/app

CMD ["python", "main.py"]