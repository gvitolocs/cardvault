FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=7860 \
    TRAININGAI_DATA_DIR=/opt/trainingai-card-classifier/data

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends git libgomp1 tesseract-ocr \
  && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY app.py meili_rerank.py ./
COPY best-blueprint-images.json .

VOLUME ["/opt/trainingai-card-classifier/data"]
EXPOSE 7860

CMD ["sh", "-c", "uvicorn app:app --host 0.0.0.0 --port ${PORT:-7860}"]
