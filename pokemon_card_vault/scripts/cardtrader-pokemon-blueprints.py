#!/usr/bin/env python3
import argparse
import json
import os
import sys
import time
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


API_BASE = "https://api.cardtrader.com/api/v2"


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


def cardtrader_get(path: str, token: str, params: dict[str, object] | None = None):
    query = f"?{urlencode(params)}" if params else ""
    request = Request(
        f"{API_BASE}{path}{query}",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "User-Agent": "pokoin-cardtrader-import/1.0",
        },
    )
    for attempt in range(1, 6):
        try:
            with urlopen(request, timeout=60) as response:
                return json.loads(response.read().decode("utf-8"))
        except HTTPError as error:
            if error.code == 429 and attempt < 6:
                time.sleep(2 * attempt)
                continue
            body = error.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"CardTrader {path} failed: HTTP {error.code}: {body}") from error


def as_list(payload):
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict) and isinstance(payload.get("array"), list):
        return payload["array"]
    raise RuntimeError(f"Unexpected CardTrader response shape: {type(payload).__name__}")


def find_pokemon_game(games: list[dict]) -> dict:
    for game in games:
        haystack = f"{game.get('name', '')} {game.get('display_name', '')}".lower()
        if "pokemon" in haystack or "pokémon" in haystack:
            return game
    raise RuntimeError("Could not find Pokemon game in CardTrader /games response.")


def download(output_dir: Path, token: str, sleep_seconds: float) -> dict:
    output_dir.mkdir(parents=True, exist_ok=True)

    games = as_list(cardtrader_get("/games", token))
    pokemon = find_pokemon_game(games)
    game_id = pokemon["id"]

    categories = [
        category
        for category in as_list(cardtrader_get("/categories", token, {"game_id": game_id}))
        if category.get("game_id") == game_id
    ]
    expansions = [
        expansion
        for expansion in as_list(cardtrader_get("/expansions", token))
        if expansion.get("game_id") == game_id
    ]

    (output_dir / "games.json").write_text(json.dumps(games, ensure_ascii=False, indent=2))
    (output_dir / "pokemon-game.json").write_text(json.dumps(pokemon, ensure_ascii=False, indent=2))
    (output_dir / "pokemon-categories.json").write_text(json.dumps(categories, ensure_ascii=False, indent=2))
    (output_dir / "pokemon-expansions.json").write_text(json.dumps(expansions, ensure_ascii=False, indent=2))

    blueprint_path = output_dir / "pokemon-blueprints.jsonl"
    error_path = output_dir / "pokemon-blueprint-errors.jsonl"
    total = 0
    failed = 0
    seen_ids: set[int] = set()
    started_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    with blueprint_path.open("w") as blueprint_file, error_path.open("w") as error_file:
        for index, expansion in enumerate(expansions, start=1):
            expansion_id = expansion["id"]
            try:
                blueprints = as_list(cardtrader_get("/blueprints/export", token, {"expansion_id": expansion_id}))
            except Exception as error:
                failed += 1
                error_file.write(json.dumps({"expansion": expansion, "error": str(error)}, ensure_ascii=False) + "\n")
                print(f"[{index}/{len(expansions)}] expansion {expansion_id}: failed: {error}", file=sys.stderr)
                continue

            count = 0
            for blueprint in blueprints:
                blueprint_id = blueprint.get("id")
                if isinstance(blueprint_id, int) and blueprint_id in seen_ids:
                    continue
                if isinstance(blueprint_id, int):
                    seen_ids.add(blueprint_id)
                row = {
                    "blueprint": blueprint,
                    "expansion": expansion,
                    "game": pokemon,
                }
                blueprint_file.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")
                count += 1
            total += count
            print(f"[{index}/{len(expansions)}] expansion {expansion_id}: {count} blueprints")
            if sleep_seconds > 0:
                time.sleep(sleep_seconds)

    manifest = {
        "source": "cardtrader",
        "apiBase": API_BASE,
        "downloadedAt": started_at,
        "game": pokemon,
        "categoryCount": len(categories),
        "expansionCount": len(expansions),
        "blueprintCount": total,
        "failedExpansionCount": failed,
        "files": {
            "blueprints": str(blueprint_path),
            "errors": str(error_path),
        },
    }
    (output_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description="Download CardTrader Pokemon blueprints.")
    parser.add_argument("--env", default=".env.local", help="Path to local env file.")
    parser.add_argument("--output-dir", default="data/cardtrader", help="Output directory.")
    parser.add_argument("--sleep", type=float, default=0.08, help="Seconds to sleep between expansion requests.")
    args = parser.parse_args()

    env = {**read_env(Path(args.env)), **os.environ}
    token = env.get("CARDTRADER_AUTH_TOKEN", "").strip()
    if not token:
        raise SystemExit("CARDTRADER_AUTH_TOKEN is missing.")

    manifest = download(Path(args.output_dir), token, args.sleep)
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
