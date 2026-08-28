"""Meilisearch name lookup for TrainingAI OCR rerank (marketplace card_id == blueprint_id)."""

from __future__ import annotations

import os
import re
from typing import Any

import requests

COLLECTOR_NUMBER_RE = re.compile(
    r"^\s*([a-z]{0,3}\d{1,4})\s*/\s*([a-z]{0,3}\d{1,4})\s*$",
    re.IGNORECASE,
)

# Footer / rule-box words that must never drive Meili or name rerank.
MEILI_NAME_BLOCKLIST = frozenset(
    {
        "ans",
        "are",
        "pal",
        "ret",
        "cam",
        "dat",
        "ef",
        "ene",
        "enn",
        "on",
        "bee",
        "ak",
        "as",
        "at",
        "to",
        "of",
        "or",
        "an",
        "the",
        "and",
        "for",
        "you",
        "your",
        "when",
        "acute",
        "arrears",
        "knocued",
        "knocked",
        "weakness",
        "resistance",
        "illus",
        "pokemon",
        "prize",
        "cards",
        "opponent",
        "active",
        "deck",
        "energy",
        "attack",
        "damage",
        "rule",
        "rules",
        "during",
        "turn",
        "this",
        "that",
        "from",
        "into",
        "then",
        "may",
        "once",
        "each",
        "all",
        "any",
        "basic",
        "search",
        "shuffle",
        "hand",
        "spot",
        "knock",
        "out",
        "takes",
        "take",
        "premnoe",
        "erence",
        "irotot",
        "surgtbeer",
        "teer",
        "senee",
        "keeys",
        "knocaed",
        "gaa",
        "gat",
        "wo",
        "pt",
    }
)

MEILI_HOST = os.environ.get("MEILI_HOST", os.environ.get("MEILISEARCH_HOST", "")).rstrip("/")
MEILI_API_KEY = os.environ.get("MEILI_API_KEY", os.environ.get("MEILISEARCH_API_KEY", ""))
MEILI_MARKETPLACE_INDEX = os.environ.get("MEILI_MARKETPLACE_INDEX", "marketplace_cards")
MEILI_SEARCH_LANGUAGE = os.environ.get("TRAININGAI_MEILI_SEARCH_LANGUAGE", "en").strip() or "en"
MEILI_TIMEOUT_SECONDS = float(os.environ.get("TRAININGAI_MEILI_TIMEOUT_SECONDS", "0.8"))
MEILI_SEARCH_LIMIT = int(os.environ.get("TRAININGAI_MEILI_SEARCH_LIMIT", "32"))
MEILI_INJECT_CLIP_BASE = float(os.environ.get("TRAININGAI_MEILI_INJECT_CLIP_BASE", "0.58"))


def meili_configured() -> bool:
    return bool(MEILI_HOST)


def plausible_name_token(token: str) -> bool:
    text = str(token).strip().lower()
    if not (3 <= len(text) <= 9) or not text.isalpha():
        return False
    if text in MEILI_NAME_BLOCKLIST:
        return False
    vowels = sum(1 for char in text if char in "aeiouy")
    if vowels < 1:
        return False
    if len(text) >= 8 and vowels / len(text) < 0.28:
        return False
    return True


def ocr_collector_fraction(ocr: dict[str, Any]) -> str:
    """Collector number from the bottom strip only (e.g. 236/193)."""
    for number in ocr.get("collectorNumbers") or []:
        match = COLLECTOR_NUMBER_RE.match(str(number).strip())
        if match:
            return f"{match.group(1).lower()}/{match.group(2).lower()}"
    return ""


def ocr_meili_name_terms(ocr: dict[str, Any]) -> list[str]:
    """Pokémon name tokens from the name-bar strip only (max two)."""
    candidates: list[str] = []
    for token in ocr.get("nameTokens") or []:
        text = str(token).strip().lower()
        if not plausible_name_token(text):
            continue
        if text.startswith("pao") and len(text) > 3:
            normalized = "pao"
        else:
            normalized = text
        if normalized not in candidates:
            candidates.append(normalized)
    if not candidates:
        return []

    pao = next((token for token in candidates if token == "pao"), None)
    rest = sorted(
        [token for token in candidates if token != "pao"],
        key=len,
        reverse=True,
    )
    picked: list[str] = []
    for token in rest:
        if len(picked) >= (1 if pao else 2):
            break
        picked.append(token)
    if pao:
        picked.append("pao")
    return picked[:2]


def ocr_meili_search_query(ocr: dict[str, Any]) -> str:
    """
    Meili query = name-bar Pokémon name + collector fraction only.
    Never uses full-card tokens or rule-box OCR garbage.
    """
    name_terms = ocr_meili_name_terms(ocr)
    fraction = ocr_collector_fraction(ocr)
    if not name_terms and not fraction:
        return ""
    parts = list(name_terms)
    if fraction:
        parts.append(fraction)
    return " ".join(parts).strip()


def meili_marketplace_blueprint_hits(query: str, limit: int | None = None) -> list[dict[str, Any]]:
    if not meili_configured() or not query:
        return []
    search_limit = limit if limit is not None else MEILI_SEARCH_LIMIT
    headers = {"Content-Type": "application/json"}
    if MEILI_API_KEY:
        headers["Authorization"] = f"Bearer {MEILI_API_KEY}"
    body = {
        "q": query,
        "limit": max(1, min(search_limit, 100)),
        "filter": f'language = "{MEILI_SEARCH_LANGUAGE}"',
        "attributesToRetrieve": ["card_id", "name"],
        "showRankingScore": True,
    }
    try:
        response = requests.post(
            f"{MEILI_HOST}/indexes/{MEILI_MARKETPLACE_INDEX}/search",
            headers=headers,
            json=body,
            timeout=MEILI_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        payload = response.json()
    except Exception:
        return []

    hits: list[dict[str, Any]] = []
    for index, hit in enumerate(payload.get("hits") or []):
        blueprint_id = str(hit.get("card_id") or "").strip()
        if not blueprint_id:
            continue
        hits.append(
            {
                "blueprintId": blueprint_id,
                "name": str(hit.get("name") or ""),
                "meiliScore": float(hit.get("_rankingScore") or 0.0),
                "meiliPosition": index + 1,
            }
        )
    return hits


def build_blueprint_index(metadata: list[dict[str, Any]], blueprint_id_from_entry) -> dict[str, list[int]]:
    index: dict[str, list[int]] = {}
    for idx, entry in enumerate(metadata):
        blueprint_id = blueprint_id_from_entry(entry)
        if blueprint_id:
            index.setdefault(blueprint_id, []).append(idx)
    return index


def inject_meili_candidates(
    *,
    metadata: list[dict[str, Any]],
    blueprint_index: dict[str, list[int]],
    ocr: dict[str, Any],
    seen_paths: set[str],
    candidates: list[dict[str, Any]],
    metadata_result,
    rerank_bonus,
    blueprint_id_from_entry,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    name_terms = ocr_meili_name_terms(ocr)
    fraction = ocr_collector_fraction(ocr)
    query = ocr_meili_search_query(ocr)
    meili_meta: dict[str, Any] = {
        "enabled": meili_configured(),
        "query": query,
        "nameTerms": name_terms,
        "collectorFraction": fraction,
        "hits": [],
        "injected": 0,
    }
    if not meili_configured():
        meili_meta["skippedReason"] = "not_configured"
        return candidates, meili_meta
    if not query:
        meili_meta["skippedReason"] = "no_name_or_collector_signal"
        return candidates, meili_meta

    hits = meili_marketplace_blueprint_hits(query)
    meili_meta["hits"] = [
        {
            "blueprintId": hit["blueprintId"],
            "name": hit["name"],
            "meiliScore": hit["meiliScore"],
        }
        for hit in hits[:12]
    ]

    for hit in hits:
        blueprint_id = hit["blueprintId"]
        for idx in blueprint_index.get(blueprint_id, []):
            if idx < 0 or idx >= len(metadata):
                continue
            entry = metadata[idx]
            original_path = str(entry.get("original_path") or entry.get("path") or "")
            dedupe_key = original_path or f"idx:{idx}"
            if dedupe_key in seen_paths:
                continue
            seen_paths.add(dedupe_key)
            inject_clip = MEILI_INJECT_CLIP_BASE + float(hit["meiliScore"]) * 0.08
            bonus, rerank = rerank_bonus(entry, ocr)
            result = metadata_result(0, float(inject_clip + bonus), entry)
            result["clipScore"] = float(inject_clip)
            result["rerankBonus"] = float(bonus)
            result["rerank"] = rerank
            result["candidateSource"] = "meili"
            result["meiliScore"] = float(hit["meiliScore"])
            result["meiliPosition"] = int(hit["meiliPosition"])
            candidates.append(result)
            meili_meta["injected"] += 1

    return candidates, meili_meta
