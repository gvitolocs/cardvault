import base64
import json
import os
from pathlib import Path
from typing import Any

import faiss
import gradio as gr
import numpy as np
import open_clip
import requests
import torch
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from PIL import Image
from pydantic import BaseModel


DATA_DIR = Path(os.environ.get("TRAININGAI_DATA_DIR", "data"))
ASSET_BASE_URL = os.environ.get(
    "TRAININGAI_ASSET_BASE_URL",
    "https://raw.githubusercontent.com/SabatinoRaffaella/PokemonCardRecognizer/main/main_app",
).rstrip("/")
IMAGE_BASE_URL = os.environ.get("TRAININGAI_IMAGE_BASE_URL", ASSET_BASE_URL).rstrip("/")
MAX_UPLOAD_BYTES = int(os.environ.get("TRAININGAI_MAX_UPLOAD_BYTES", str(8 * 1024 * 1024)))
MODEL_NAME = os.environ.get("TRAININGAI_MODEL_NAME", "ViT-B-32")
PRETRAINED = os.environ.get("TRAININGAI_PRETRAINED", "laion2b_s34b_b79k")

ASSETS = {
    "pokemon.index": "pokemon.index",
    "metadata.json": "metadata.json",
    "card_paths.json": "card_paths.json",
}

app = FastAPI(title="Pokoin TrainingAI Card Classifier")
_state: dict[str, Any] = {}


class Base64ClassifyRequest(BaseModel):
    imageBase64: str | None = None
    image_base64: str | None = None
    image: str | None = None
    topK: int | None = None
    top_k: int | None = None


def asset_url(name: str) -> str:
    return f"{ASSET_BASE_URL}/{name}"


def ensure_assets() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    for filename, remote_name in ASSETS.items():
        target = DATA_DIR / filename
        if target.exists() and target.stat().st_size > 0:
            continue
        response = requests.get(asset_url(remote_name), timeout=120)
        response.raise_for_status()
        target.write_bytes(response.content)


def load_metadata(index_size: int) -> list[dict[str, Any]]:
    metadata_path = DATA_DIR / "metadata.json"
    if metadata_path.exists():
        raw_metadata = json.loads(metadata_path.read_text())
        if isinstance(raw_metadata, list) and len(raw_metadata) >= index_size:
            return [
                entry if isinstance(entry, dict) else {"original_path": str(entry)}
                for entry in raw_metadata[:index_size]
            ]

    card_paths_path = DATA_DIR / "card_paths.json"
    if card_paths_path.exists():
        raw_paths = json.loads(card_paths_path.read_text())
        if isinstance(raw_paths, list):
            return [{"original_path": str(path)} for path in raw_paths[:index_size]]

    return [{"original_path": ""} for _ in range(index_size)]


def model_state() -> dict[str, Any]:
    if _state:
        return _state

    ensure_assets()
    device = "cuda" if torch.cuda.is_available() else "cpu"
    model, _, preprocess = open_clip.create_model_and_transforms(
        MODEL_NAME,
        pretrained=PRETRAINED,
    )
    model = model.to(device)
    model.eval()

    index = faiss.read_index(str(DATA_DIR / "pokemon.index"))
    metadata = load_metadata(index.ntotal)

    _state.update(
        {
            "device": device,
            "model": model,
            "preprocess": preprocess,
            "index": index,
            "metadata": metadata,
        }
    )
    return _state


def clean_top_k(value: int | str | None) -> int:
    try:
        parsed = int(value or 3)
    except (TypeError, ValueError):
        parsed = 3
    return max(1, min(parsed, 10))


def image_url_for_path(path: str) -> str:
    clean_path = path.strip().lstrip("/")
    if not clean_path:
        return ""
    return f"{IMAGE_BASE_URL}/{clean_path}"


def metadata_result(rank: int, score: float, entry: dict[str, Any]) -> dict[str, Any]:
    original_path = str(entry.get("original_path") or entry.get("path") or "")
    image_url = str(entry.get("url") or entry.get("imageUrl") or image_url_for_path(original_path))
    return {
        "rank": rank,
        "score": float(score),
        "cardPath": original_path,
        "imageUrl": image_url,
        "augmentation": entry.get("augmentation", ""),
        "ocrName": entry.get("ocr_name", entry.get("ocrName", [])),
        "ocrBottom": entry.get("ocr_bottom", entry.get("ocrBottom", [])),
        "metadata": entry,
    }


def classify_pil(image: Image.Image, top_k: int = 3) -> dict[str, Any]:
    state = model_state()
    image = image.convert("RGB")
    tensor = state["preprocess"](image).unsqueeze(0).to(state["device"])

    with torch.no_grad():
        features = state["model"].encode_image(tensor)

    features = features / features.norm(dim=-1, keepdim=True)
    query = features.cpu().numpy().astype("float32")
    distances, indices = state["index"].search(query, k=min(max(top_k * 4, top_k), state["index"].ntotal))

    seen_paths: set[str] = set()
    results: list[dict[str, Any]] = []
    for score, idx in zip(distances[0], indices[0]):
        if idx < 0 or idx >= len(state["metadata"]):
            continue
        entry = state["metadata"][int(idx)]
        original_path = str(entry.get("original_path") or entry.get("path") or "")
        dedupe_key = original_path or f"idx:{idx}"
        if dedupe_key in seen_paths:
            continue
        seen_paths.add(dedupe_key)
        results.append(metadata_result(len(results) + 1, float(score), entry))
        if len(results) >= top_k:
            break

    return {
        "ok": True,
        "model": MODEL_NAME,
        "pretrained": PRETRAINED,
        "device": state["device"],
        "indexVectors": int(state["index"].ntotal),
        "results": results,
    }


async def upload_to_image(upload: UploadFile) -> Image.Image:
    payload = await upload.read()
    if not payload or len(payload) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=400, detail=f"Image must be between 1 byte and {MAX_UPLOAD_BYTES} bytes.")
    try:
        from io import BytesIO

        return Image.open(BytesIO(payload))
    except Exception as error:
        raise HTTPException(status_code=400, detail="Uploaded file is not a readable image.") from error


def base64_to_image(value: str) -> Image.Image:
    raw = value.split(",", 1)[1] if "," in value and value.lower().startswith("data:image/") else value
    try:
        payload = base64.b64decode(raw, validate=True)
    except Exception as error:
        raise HTTPException(status_code=400, detail="imageBase64 is not valid base64.") from error
    if not payload or len(payload) > MAX_UPLOAD_BYTES:
        raise HTTPException(status_code=400, detail=f"Image must be between 1 byte and {MAX_UPLOAD_BYTES} bytes.")
    try:
        from io import BytesIO

        return Image.open(BytesIO(payload))
    except Exception as error:
        raise HTTPException(status_code=400, detail="Decoded image is not readable.") from error


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "ok": True,
        "service": "pokoin-trainingai-card-classifier",
        "model": MODEL_NAME,
        "pretrained": PRETRAINED,
        "loaded": bool(_state),
        "assets": {
            filename: (DATA_DIR / filename).exists()
            for filename in ASSETS
        },
    }


@app.get("/ready")
def ready() -> dict[str, Any]:
    state = model_state()
    return {
        "ok": True,
        "service": "pokoin-trainingai-card-classifier",
        "model": MODEL_NAME,
        "pretrained": PRETRAINED,
        "device": state["device"],
        "indexVectors": int(state["index"].ntotal),
    }


@app.post("/classify")
async def classify_upload(
    image: UploadFile = File(...),
    top_k: int = Form(3),
) -> dict[str, Any]:
    return classify_pil(await upload_to_image(image), clean_top_k(top_k))


@app.post("/classify/base64")
async def classify_base64(payload: Base64ClassifyRequest) -> dict[str, Any]:
    image_base64 = payload.imageBase64 or payload.image_base64 or payload.image or ""
    if not image_base64:
        raise HTTPException(status_code=400, detail="imageBase64 is required.")
    return classify_pil(base64_to_image(image_base64), clean_top_k(payload.top_k or payload.topK))


def gradio_predict(image: Image.Image, top_k: int) -> dict[str, Any]:
    if image is None:
        return {"ok": False, "error": "Upload an image first."}
    return classify_pil(image, clean_top_k(top_k))


demo = gr.Interface(
    fn=gradio_predict,
    inputs=[
        gr.Image(type="pil", label="Card image"),
        gr.Slider(1, 10, value=3, step=1, label="Top K"),
    ],
    outputs=gr.JSON(label="Classification"),
    title="Pokoin TrainingAI Card Classifier",
    description="Upload a Pokemon card image and receive the closest CardVault matches.",
)

app = gr.mount_gradio_app(app, demo, path="/")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app:app",
        host="0.0.0.0",
        port=int(os.environ.get("PORT", "7860")),
    )
