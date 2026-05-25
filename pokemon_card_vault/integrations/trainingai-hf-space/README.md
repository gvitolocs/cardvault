# Pokoin TrainingAI Hugging Face Space

This Space runs the Pokemon Card Recognizer classifier behind the Pokoin API.
It loads OpenCLIP, the FAISS index, and metadata from
`SabatinoRaffaella/PokemonCardRecognizer` by default.

## Space setup

Create a Hugging Face Space with:

- SDK: Docker
- Hardware: CPU Basic for the free tier

Copy this directory into the Space repository.

## Optional variables

```text
TRAININGAI_ASSET_BASE_URL=https://raw.githubusercontent.com/SabatinoRaffaella/PokemonCardRecognizer/main/main_app
TRAININGAI_IMAGE_BASE_URL=https://raw.githubusercontent.com/SabatinoRaffaella/PokemonCardRecognizer/main/main_app
TRAININGAI_DATA_DIR=data
TRAININGAI_MAX_UPLOAD_BYTES=8388608
TRAININGAI_MODEL_NAME=ViT-B-32
TRAININGAI_PRETRAINED=laion2b_s34b_b79k
```

## API

```bash
curl -X POST "https://<user>-<space>.hf.space/classify" \
  -F "image=@card.jpg" \
  -F "top_k=3"
```

```bash
curl -X POST "https://<user>-<space>.hf.space/classify/base64" \
  -H "Content-Type: application/json" \
  -d '{"imageBase64":"<base64>","topK":3}'
```

The root path `/` serves a small Gradio test UI.
