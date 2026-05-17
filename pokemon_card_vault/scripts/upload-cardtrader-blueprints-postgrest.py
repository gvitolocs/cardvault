#!/usr/bin/env python3
import argparse
import json
import os
import time
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def read_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for line in path.read_text().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, raw = stripped.split("=", 1)
        key = key.strip().removeprefix("export ").strip()
        values[key] = raw.strip().strip('"').strip("'")
    return values


def row_from_blueprint(record: dict) -> dict:
    blueprint = record["blueprint"]
    return {
        "id": blueprint.get("id"),
        "name": blueprint.get("name"),
        "version": blueprint.get("version"),
        "game_id": blueprint.get("game_id"),
        "category_id": blueprint.get("category_id"),
        "expansion_id": blueprint.get("expansion_id"),
        "image_url": blueprint.get("image_url"),
        "card_market_ids": blueprint.get("card_market_ids"),
        "tcg_player_ids": blueprint.get("tcg_player_ids"),
        "editable_properties": blueprint.get("editable_properties") or [],
        "blueprint": blueprint,
        "expansion": record.get("expansion"),
    }


def post_batch(url: str, service_key: str, rows: list[dict]) -> None:
    body = json.dumps(rows, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    request = Request(
        f"{url.rstrip('/')}/rest/v1/cardtrader_pokemon_blueprints?on_conflict=id",
        data=body,
        method="POST",
        headers={
            "apikey": service_key,
            "Authorization": f"Bearer {service_key}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates",
        },
    )
    for attempt in range(1, 6):
        try:
            with urlopen(request, timeout=120) as response:
                response.read()
                return
        except HTTPError as error:
            body_text = error.read().decode("utf-8", errors="replace")
            if error.code in (429, 500, 502, 503, 504) and attempt < 6:
                time.sleep(2 * attempt)
                continue
            raise RuntimeError(f"PostgREST upload failed: HTTP {error.code}: {body_text}") from error


def main() -> int:
    parser = argparse.ArgumentParser(description="Upload CardTrader Pokemon blueprints to Supabase PostgREST.")
    parser.add_argument("--env", default=".env.local")
    parser.add_argument("--input", default="data/cardtrader/pokemon-blueprints.jsonl")
    parser.add_argument("--batch-size", type=int, default=250)
    args = parser.parse_args()

    env = {**read_env(Path(args.env)), **os.environ}
    url = env.get("SUPABASE_URL", "").strip()
    service_key = env.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not url or not service_key:
        raise SystemExit("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY.")

    total = 0
    batch: list[dict] = []
    for line in Path(args.input).open(encoding="utf-8"):
        batch.append(row_from_blueprint(json.loads(line)))
        if len(batch) >= args.batch_size:
            post_batch(url, service_key, batch)
            total += len(batch)
            print(f"uploaded {total}")
            batch.clear()
    if batch:
        post_batch(url, service_key, batch)
        total += len(batch)
        print(f"uploaded {total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
