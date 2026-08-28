import base64
import difflib
import json
import os
import re
from pathlib import Path
from typing import Any

import faiss
import open_clip
import requests
import torch
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from PIL import Image, ImageEnhance, ImageFilter, ImageOps
from pydantic import BaseModel

from meili_rerank import (
    build_blueprint_index,
    inject_meili_candidates,
    meili_configured,
    ocr_meili_search_query,
)


DATA_DIR = Path(os.environ.get("TRAININGAI_DATA_DIR", "/opt/trainingai-card-classifier/data"))
ASSET_BASE_URL = os.environ.get(
    "TRAININGAI_ASSET_BASE_URL",
    "https://raw.githubusercontent.com/SabatinoRaffaella/PokemonCardRecognizer/main/main_app",
).rstrip("/")
IMAGE_BASE_URL = os.environ.get("TRAININGAI_IMAGE_BASE_URL", ASSET_BASE_URL).rstrip("/")
MAX_UPLOAD_BYTES = int(os.environ.get("TRAININGAI_MAX_UPLOAD_BYTES", str(8 * 1024 * 1024)))
MODEL_NAME = os.environ.get("TRAININGAI_MODEL_NAME", "ViT-B-32")
PRETRAINED = os.environ.get("TRAININGAI_PRETRAINED", "laion2b_s34b_b79k")
RERANK_POOL_MULTIPLIER = int(os.environ.get("TRAININGAI_RERANK_POOL_MULTIPLIER", "8"))
RERANK_MIN_POOL = int(os.environ.get("TRAININGAI_RERANK_MIN_POOL", "50"))
RERANK_NAME_BAR_POOL = int(os.environ.get("TRAININGAI_RERANK_NAME_BAR_POOL", "400"))
ENABLE_OCR_RERANK = os.environ.get("TRAININGAI_ENABLE_OCR_RERANK", "1") != "0"
ENABLE_MEILI_RERANK = os.environ.get("TRAININGAI_ENABLE_MEILI_RERANK", "1") != "0"
OCR_TIMEOUT_SECONDS = float(os.environ.get("TRAININGAI_OCR_TIMEOUT_SECONDS", "2.5"))
MANIFEST_FILENAME = "best-blueprint-images.json"
MANIFEST_URL = os.environ.get(
    "TRAININGAI_MANIFEST_URL",
    "https://trainingai.pokoin.com/blueprints/best-images.json",
).strip()

ENRICHMENT_FIELDS = (
    "name",
    "set_name",
    "version",
    "collector_number",
    "rarity",
    "url",
    "object_key",
    "original_path",
    "source",
    "blueprint_id",
)

ASSETS = {
    "pokemon.index": "pokemon.index",
    "metadata.json": "metadata.json",
    "card_paths.json": "card_paths.json",
}

app = FastAPI(title="Pokoin TrainingAI Oracle Card Classifier")
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


def normalize_lookup_key(value: Any) -> str:
    return str(value or "").strip().lstrip("/")


def is_generic_lookup_basename(value: str) -> bool:
    return value.lower() in {
        "preview.png",
        "preview.jpg",
        "preview.jpeg",
        "preview.webp",
        "image.png",
        "image.jpg",
        "image.jpeg",
        "image.webp",
        "card.png",
        "card.jpg",
        "card.jpeg",
        "card.webp",
        "default.png",
        "default.jpg",
        "default.jpeg",
        "default.webp",
        "fallback.png",
        "fallback.jpg",
        "fallback.jpeg",
        "fallback.webp",
    }


def path_lookup_keys(value: Any) -> set[str]:
    text = normalize_lookup_key(value)
    if not text:
        return set()
    if "fallbacks/card_uploader/" in text.lower():
        return set()
    basename = Path(text).name
    keys = {text}
    if not is_generic_lookup_basename(basename):
        keys.add(basename)
    if text.startswith("content/"):
        keys.add(f"/{text}")
    return {key for key in keys if key}


def leading_blueprint_id(value: Any) -> str:
    for key in path_lookup_keys(value):
        match = re.match(r"^(\d+)(?:[_-]|$)", Path(key).name)
        if match:
            return match.group(1)
    return ""


def manifest_candidates() -> list[Path]:
    candidates: list[Path] = []
    env_path = os.environ.get("TRAININGAI_MANIFEST_PATH")
    if env_path:
        candidates.append(Path(env_path))
    app_path = Path(__file__).resolve()
    candidates.extend(
        [
            DATA_DIR / MANIFEST_FILENAME,
            app_path.with_name(MANIFEST_FILENAME),
        ]
    )
    if len(app_path.parents) > 2:
        candidates.append(app_path.parents[2] / "data" / "trainingai" / MANIFEST_FILENAME)
    return candidates


def read_manifest_payload() -> dict[str, Any]:
    for path in manifest_candidates():
        if path.exists() and path.stat().st_size > 0:
            return json.loads(path.read_text())
    if MANIFEST_URL:
        response = requests.get(MANIFEST_URL, timeout=120)
        response.raise_for_status()
        return response.json()
    return {}


def add_manifest_entry(lookup: dict[str, dict[str, dict[str, Any]]], entry: dict[str, Any]) -> None:
    blueprint_id = str(entry.get("blueprint_id") or "").strip()
    if blueprint_id:
        lookup["blueprint_id"][blueprint_id] = entry

    for field in ("object_key", "original_path", "path", "url", "image_url", "cdn_image_url", "cardtrader_image_url"):
        for key in path_lookup_keys(entry.get(field)):
            lookup["path"][key] = entry


def load_manifest_lookup() -> dict[str, dict[str, dict[str, Any]]]:
    lookup: dict[str, dict[str, dict[str, Any]]] = {"blueprint_id": {}, "path": {}}
    try:
        payload = read_manifest_payload()
    except Exception:
        return lookup

    objects = payload.get("objects") if isinstance(payload, dict) else payload
    if not isinstance(objects, list):
        return lookup

    for item in objects:
        if isinstance(item, dict):
            add_manifest_entry(lookup, item)
    return lookup


def blueprint_id_from_entry(entry: dict[str, Any]) -> str:
    for field in ("blueprint_id", "blueprintId"):
        value = str(entry.get(field) or "").strip()
        if value:
            return value

    for field in ("object_key", "original_path", "path", "url", "image_url", "cdn_image_url", "cardtrader_image_url"):
        value = leading_blueprint_id(entry.get(field))
        if value:
            return value
    return ""


def manifest_match(entry: dict[str, Any], lookup: dict[str, dict[str, dict[str, Any]]]) -> dict[str, Any] | None:
    blueprint_id = blueprint_id_from_entry(entry)
    if blueprint_id:
        match = lookup["blueprint_id"].get(blueprint_id)
        if match:
            return match

    for field in ("object_key", "original_path", "path", "url", "image_url", "cdn_image_url", "cardtrader_image_url"):
        for key in path_lookup_keys(entry.get(field)):
            match = lookup["path"].get(key)
            if match:
                return match
    return None


def is_missing(value: Any) -> bool:
    return value is None or value == ""


def enrich_metadata_entry(entry: dict[str, Any], lookup: dict[str, dict[str, dict[str, Any]]]) -> dict[str, Any]:
    enriched = dict(entry)
    match = manifest_match(enriched, lookup)
    if not match:
        return enriched

    for field in ENRICHMENT_FIELDS:
        value = match.get(field)
        if field == "collector_number" and is_missing(value):
            value = match.get("version")
        if not is_missing(value) and is_missing(enriched.get(field)):
            enriched[field] = value

    if is_missing(enriched.get("collector_number")) and not is_missing(enriched.get("version")):
        enriched["collector_number"] = enriched["version"]
    return enriched


def enrich_metadata(metadata: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    lookup = load_manifest_lookup()
    enriched = [enrich_metadata_entry(entry, lookup) for entry in metadata]
    return enriched, {
        "manifestBlueprints": len(lookup["blueprint_id"]),
        "manifestPaths": len(lookup["path"]),
    }


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
    metadata, enrichment = enrich_metadata(load_metadata(index.ntotal))

    _state.update(
        {
            "device": device,
            "model": model,
            "preprocess": preprocess,
            "index": index,
            "metadata": metadata,
            "metadataEnrichment": enrichment,
            "blueprintIndex": build_blueprint_index(metadata, blueprint_id_from_entry),
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


def normalize_text(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", value.lower()).strip()


def normalize_name_token(token: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", token.lower())


def normalized_name_forms(text: str) -> set[str]:
    normalized_text = normalize_text(text)
    base_tokens = [token for token in normalized_text.split() if token]
    forms = {normalize_name_token(token) for token in base_tokens}
    forms.discard("")
    joined = "".join(base_tokens)
    if joined:
        forms.add(joined)
    return forms


def card_name_from_entry(entry: dict[str, Any]) -> str:
    name = str(entry.get("name") or "")
    if name:
        return name
    original_path = str(entry.get("original_path") or entry.get("path") or "")
    stem = Path(original_path).stem
    without_blueprint = re.sub(r"^\d+[_-]", "", stem)
    return re.split(r"-(?:rare|holo|ultra|full|promo|pre|reverse|\d)", without_blueprint, maxsplit=1)[0].replace("-", " ")


def candidate_numbers(entry: dict[str, Any]) -> set[str]:
    values = [
        entry.get("collector_number"),
        entry.get("collectorNumber"),
        entry.get("version"),
        entry.get("original_path"),
        entry.get("path"),
        entry.get("object_key"),
    ]
    numbers: set[str] = set()
    for value in values:
        text = str(value or "").lower()
        for left, right in re.findall(r"\b([a-z]{0,3}\d{1,4})\s*/\s*([a-z]{0,3}\d{1,4})\b", text):
            numbers.add(f"{left}/{right}")
        for token in re.findall(r"\b(?:sm|xy|sv)?\d{1,4}\b", text):
            numbers.add(token)
    return numbers


def name_bar_crop(image: Image.Image) -> Image.Image:
    """Name strip (5–22% height) where the Pokémon name is printed."""
    width, height = image.size
    horizontal_margin = max(0, int(width * 0.05))
    left = horizontal_margin
    right = max(left + 1, width - horizontal_margin)
    top = max(0, int(height * 0.05))
    bottom = min(height, max(top + 1, int(height * 0.22)))
    return image.crop((left, top, right, bottom))


def collector_bar_crop(image: Image.Image) -> Image.Image:
    """Bottom-left strip (78–100% height, left ~55%) where collector number is printed."""
    width, height = image.size
    horizontal_margin = max(0, int(width * 0.05))
    left = horizontal_margin
    right = max(left + 1, int(width * 0.55))
    top = max(0, int(height * 0.78))
    bottom = height
    return image.crop((left, top, right, bottom))


def extract_collector_numbers(text: str) -> set[str]:
    numbers: set[str] = set()
    lower = text.lower()
    for left, right in re.findall(r"\b([a-z]{0,3}\d{1,4})\s*/\s*([a-z]{0,3}\d{1,4})\b", lower):
        numbers.add(f"{left}/{right}")
    return numbers


def ocr_fraction_numbers_for_rerank(ocr: dict[str, Any]) -> set[str]:
    """Only full collector fractions (e.g. 236/193) — ignore isolated OCR digits like 2 or 4."""
    fractions: set[str] = set()
    for value in (ocr.get("collectorNumbers") or []) + (ocr.get("numbers") or []):
        text = str(value).strip().lower()
        if "/" in text:
            fractions.add(text)
    return fractions


def ocr_bar_high_contrast_darkest_only(crop: Image.Image) -> Image.Image:
    """High-contrast pipeline, then keep only darkest pixels (black text on white)."""
    import numpy as np

    gray = crop.convert("L")
    local_contrast = ImageOps.autocontrast(gray, cutoff=2)
    enlarged = local_contrast.resize(
        (max(1, local_contrast.width * 4), max(1, local_contrast.height * 4)),
        Image.Resampling.LANCZOS,
    )
    sharpened = ImageEnhance.Sharpness(enlarged).enhance(2.6)
    strong = ImageEnhance.Contrast(sharpened).enhance(3.0)
    denoised = strong.filter(ImageFilter.MedianFilter(size=3))
    arr = np.array(denoised, dtype=np.uint8)
    darkest_cutoff = int(np.percentile(arr, 12))
    darkest_cutoff = min(darkest_cutoff, 88)
    binary = np.where(arr <= darkest_cutoff, 0, 255).astype(np.uint8)
    return Image.fromarray(binary, mode="L")


def query_ocr(image: Image.Image) -> dict[str, Any]:
    if not ENABLE_OCR_RERANK:
        return {
            "enabled": False,
            "available": False,
            "text": "",
            "tokens": [],
            "numbers": [],
            "nameTokens": [],
            "collectorNumbers": [],
        }
    try:
        import pytesseract
    except Exception:
        return {
            "enabled": True,
            "available": False,
            "text": "",
            "tokens": [],
            "numbers": [],
            "nameTokens": [],
            "collectorNumbers": [],
        }

    name_tokens: set[str] = set()
    name_merged_tokens: set[str] = set()
    collector_numbers: set[str] = set()
    name_text_parts: list[str] = []
    collector_text_parts: list[str] = []

    name_charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-' "
    name_config_primary = f"--oem 1 --psm 6 -c tessedit_char_whitelist=\"{name_charset}\""
    name_config_fallback = f"--oem 1 --psm 7 -c tessedit_char_whitelist=\"{name_charset}\""
    name_variant = ocr_bar_high_contrast_darkest_only(name_bar_crop(image))
    for config in (name_config_primary, name_config_fallback):
        try:
            extracted = pytesseract.image_to_string(
                name_variant,
                config=config,
                timeout=OCR_TIMEOUT_SECONDS,
            )
        except RuntimeError:
            extracted = ""
        if not extracted:
            continue
        name_text_parts.append(extracted)
        for token in normalize_text(extracted).split():
            if 3 <= len(token) <= 9 and not token.isdigit():
                name_tokens.add(token)
        name_merged_tokens |= normalized_name_forms(extracted)

    number_charset = "0123456789/ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz "
    number_config_primary = f"--oem 1 --psm 6 -c tessedit_char_whitelist=\"{number_charset}\""
    number_config_fallback = f"--oem 1 --psm 7 -c tessedit_char_whitelist=\"{number_charset}\""
    collector_variant = ocr_bar_high_contrast_darkest_only(collector_bar_crop(image))
    for config in (number_config_primary, number_config_fallback):
        try:
            extracted = pytesseract.image_to_string(
                collector_variant,
                config=config,
                timeout=OCR_TIMEOUT_SECONDS,
            )
        except RuntimeError:
            extracted = ""
        if not extracted:
            continue
        collector_text_parts.append(extracted)
        collector_numbers |= extract_collector_numbers(extracted)

    text = "\n".join(name_text_parts + collector_text_parts)
    numbers = sorted(collector_numbers)
    tokens = sorted(name_tokens)
    return {
        "enabled": True,
        "available": True,
        "text": text.strip(),
        "tokens": tokens,
        "numbers": numbers,
        "nameTokens": sorted(name_tokens),
        "nameMergedTokens": sorted(name_merged_tokens),
        "collectorNumbers": sorted(collector_numbers),
    }


def ocr_token_matches_name_token(name_token: str, observed: str) -> bool:
    if len(name_token) < 3 or name_token.isdigit():
        return False
    if name_token == observed:
        return True
    if observed.startswith(name_token) or name_token in observed:
        return True
    return difflib.SequenceMatcher(None, name_token, observed).ratio() >= 0.66


def rerank_bonus(entry: dict[str, Any], ocr: dict[str, Any]) -> tuple[float, dict[str, Any]]:
    if not ocr.get("available"):
        return 0.0, {"name": 0.0, "number": 0.0}

    name_tokens_ocr = set(ocr.get("nameTokens") or [])
    name_merged_tokens = set(ocr.get("nameMergedTokens") or [])
    numbers = ocr_fraction_numbers_for_rerank(ocr)
    candidate_name = card_name_from_entry(entry)
    name_tokens = set(normalize_text(candidate_name).split())
    meaningful_name_tokens = {token for token in name_tokens if len(token) >= 3 and not token.isdigit()}
    meaningful_name_merged = {normalize_name_token(token) for token in meaningful_name_tokens if normalize_name_token(token)}
    matched_name_tokens = meaningful_name_tokens & name_tokens_ocr
    matched_name_bar_tokens = meaningful_name_tokens & name_tokens_ocr
    matched_name_merged_tokens = meaningful_name_merged & name_merged_tokens
    observed_name_tokens = {
        token for token in name_tokens_ocr if len(token) >= 3 and not token.isdigit()
    }
    fuzzy_name_matches = {
        token
        for token in meaningful_name_tokens
        if any(ocr_token_matches_name_token(token, observed) for observed in observed_name_tokens)
    }
    matched_name_bar_tokens |= fuzzy_name_matches & meaningful_name_tokens
    full_name_merged = normalize_name_token(candidate_name)
    merged_exact = bool(full_name_merged and full_name_merged in name_merged_tokens)

    name_bonus = 0.0
    if meaningful_name_tokens:
        coverage = len(matched_name_tokens) / len(meaningful_name_tokens)
        name_bar_coverage = len(matched_name_bar_tokens) / len(meaningful_name_tokens)
        merged_coverage = len(matched_name_merged_tokens) / len(meaningful_name_merged) if meaningful_name_merged else 0.0
        if merged_exact:
            name_bonus = 0.34
        elif merged_coverage >= 1.0:
            name_bonus = 0.28
        elif name_bar_coverage >= 0.5:
            name_bonus = min(0.24, 0.10 + name_bar_coverage * 0.14)
        elif len(fuzzy_name_matches) == len(meaningful_name_tokens):
            name_bonus = max(name_bonus, 0.2)
        elif coverage >= 0.5:
            name_bonus = min(0.16, 0.04 + coverage * 0.12)

    entry_numbers = candidate_numbers(entry)
    number_bonus = 0.0
    if numbers and entry_numbers:
        if numbers & entry_numbers:
            number_bonus = 0.18
        elif any(number.split("/", 1)[0] in entry_numbers for number in numbers if "/" in number):
            number_bonus = 0.06

    return name_bonus + number_bonus, {
        "name": round(name_bonus, 6),
        "number": round(number_bonus, 6),
        "matchedNameTokens": sorted(matched_name_tokens),
        "matchedNameBarTokens": sorted(matched_name_bar_tokens),
        "matchedNameMergedTokens": sorted(matched_name_merged_tokens),
        "matchedNameFuzzyTokens": sorted(fuzzy_name_matches),
        "nameMergedExact": merged_exact,
        "candidateNumbers": sorted(entry_numbers),
    }


def classify_pil(image: Image.Image, top_k: int = 3) -> dict[str, Any]:
    state = model_state()
    image = image.convert("RGB")
    ocr = query_ocr(image)
    tensor = state["preprocess"](image).unsqueeze(0).to(state["device"])

    with torch.no_grad():
        features = state["model"].encode_image(tensor)

    features = features / features.norm(dim=-1, keepdim=True)
    query = features.cpu().numpy().astype("float32")
    pool_size = min(max(top_k * RERANK_POOL_MULTIPLIER, RERANK_MIN_POOL, top_k), state["index"].ntotal)
    if ocr.get("available") and ocr_meili_search_query(ocr):
        pool_size = min(max(pool_size, RERANK_NAME_BAR_POOL), state["index"].ntotal)
    distances, indices = state["index"].search(query, k=pool_size)

    seen_paths: set[str] = set()
    candidates: list[dict[str, Any]] = []
    for score, idx in zip(distances[0], indices[0]):
        if idx < 0 or idx >= len(state["metadata"]):
            continue
        entry = state["metadata"][int(idx)]
        original_path = str(entry.get("original_path") or entry.get("path") or "")
        dedupe_key = original_path or f"idx:{idx}"
        if dedupe_key in seen_paths:
            continue
        seen_paths.add(dedupe_key)
        bonus, rerank = rerank_bonus(entry, ocr)
        result = metadata_result(0, float(score + bonus), entry)
        result["clipScore"] = float(score)
        result["rerankBonus"] = float(bonus)
        result["rerank"] = rerank
        result["candidateSource"] = "clip"
        candidates.append(result)

    meili_meta: dict[str, Any] = {
        "enabled": meili_configured(),
        "query": "",
        "hits": [],
        "injected": 0,
        "skippedReason": "disabled",
    }
    if ENABLE_MEILI_RERANK and ocr.get("available"):
        candidates, meili_meta = inject_meili_candidates(
            metadata=state["metadata"],
            blueprint_index=state.get("blueprintIndex") or {},
            ocr=ocr,
            seen_paths=seen_paths,
            candidates=candidates,
            metadata_result=metadata_result,
            rerank_bonus=rerank_bonus,
            blueprint_id_from_entry=blueprint_id_from_entry,
        )

    candidates.sort(key=lambda result: result["score"], reverse=True)
    results = candidates[:top_k]
    for rank, result in enumerate(results, start=1):
        result["rank"] = rank

    return {
        "ok": True,
        "service": "pokoin-trainingai-oracle-card-classifier",
        "model": MODEL_NAME,
        "pretrained": PRETRAINED,
        "device": state["device"],
        "indexVectors": int(state["index"].ntotal),
        "metadataEnrichment": state.get("metadataEnrichment", {}),
        "queryOcr": {
            "enabled": ocr.get("enabled", False),
            "available": ocr.get("available", False),
            "numbers": ocr.get("numbers", []),
            "collectorNumbers": ocr.get("collectorNumbers", []),
            "tokens": ocr.get("tokens", [])[:30],
            "meili": meili_meta,
        },
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
        "service": "pokoin-trainingai-oracle-card-classifier",
        "model": MODEL_NAME,
        "pretrained": PRETRAINED,
        "loaded": bool(_state),
        "assets": {
            filename: (DATA_DIR / filename).exists()
            for filename in ASSETS
        },
        "manifest": {
            "local": any(path.exists() and path.stat().st_size > 0 for path in manifest_candidates()),
            "loaded": bool(_state.get("metadataEnrichment", {}).get("manifestBlueprints")) if _state else False,
        },
        "meili": {
            "enabled": ENABLE_MEILI_RERANK,
            "configured": meili_configured(),
        },
    }


@app.get("/ready")
def ready() -> dict[str, Any]:
    state = model_state()
    return {
        "ok": True,
        "service": "pokoin-trainingai-oracle-card-classifier",
        "model": MODEL_NAME,
        "pretrained": PRETRAINED,
        "device": state["device"],
        "indexVectors": int(state["index"].ntotal),
        "metadataEnrichment": state.get("metadataEnrichment", {}),
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
