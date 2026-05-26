# Pokoin TrainingAI Oracle API

This service runs Pokemon card inference on a small Oracle VM using artifacts
generated elsewhere, preferably in Colab:

- `pokemon.index`
- `metadata.json`
- `card_paths.json`

The API shape matches the Hugging Face Space fallback, so
`trainingai.pokoin.com` can point `TRAININGAI_CLASSIFIER_URL` to either backend.

## Local run

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
uvicorn app:app --host 0.0.0.0 --port 7860
```

## Docker run on Oracle

```bash
docker build -t pokoin-trainingai-card-classifier .
docker run -d \
  --name pokoin-trainingai-card-classifier \
  --restart unless-stopped \
  --env-file /opt/trainingai-card-classifier/.env \
  -p 127.0.0.1:17860:7860 \
  -v /opt/trainingai-card-classifier/data:/opt/trainingai-card-classifier/data \
  pokoin-trainingai-card-classifier
```

## Environment

```text
TRAININGAI_DATA_DIR=/opt/trainingai-card-classifier/data
TRAININGAI_ASSET_BASE_URL=https://raw.githubusercontent.com/SabatinoRaffaella/PokemonCardRecognizer/main/main_app
TRAININGAI_IMAGE_BASE_URL=https://raw.githubusercontent.com/SabatinoRaffaella/PokemonCardRecognizer/main/main_app
TRAININGAI_MAX_UPLOAD_BYTES=8388608
TRAININGAI_MODEL_NAME=ViT-B-32
TRAININGAI_PRETRAINED=laion2b_s34b_b79k
```

If the three artifact files already exist in `TRAININGAI_DATA_DIR`, the service
uses the local copies and does not download them on startup.

## API

`GET /health` is intentionally lightweight for keep-alive pings.
Use `GET /ready` when you want to force-load OpenCLIP and the FAISS index.

```bash
curl -X POST "http://127.0.0.1:17860/classify" \
  -F "image=@card.jpg" \
  -F "top_k=3"
```

```bash
curl -X POST "http://127.0.0.1:17860/classify/base64" \
  -H "Content-Type: application/json" \
  -d '{"imageBase64":"<base64>","topK":3}'
```
