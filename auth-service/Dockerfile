# syntax=docker/dockerfile:1

FROM python:3.12-slim

# PYTHONUNBUFFERED: print logs immediately instead of buffering them.
# Without it `kubectl logs` / `docker logs` shows nothing until the buffer
# fills up -> you debug blind.
# PYTHONDONTWRITEBYTECODE: no .pyc files inside the image.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# ---- Layer 1: dependencies -------------------------------------------
# requirements.txt changes rarely, app code changes often -> separate layers.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ---- Layer 2: application code ---------------------------------------
# Create a non-root user BEFORE copying, then give it ownership.
RUN useradd --create-home --uid 10001 appuser
COPY --chown=appuser:appuser . .

USER appuser

EXPOSE 5000

CMD ["python", "app.py"]
