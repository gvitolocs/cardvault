#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
from pathlib import Path


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


def database_url(env: dict[str, str]) -> str:
    for key in ("SUPABASE_DB_URL", "DATABASE_URL", "POSTGRES_URL"):
        value = env.get(key, "").strip()
        if value:
            return value
    raise SystemExit("Missing SUPABASE_DB_URL, DATABASE_URL, or POSTGRES_URL for upload.")


def jsonb(value) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def main() -> int:
    parser = argparse.ArgumentParser(description="Load CardTrader Pokemon blueprints JSONL into Postgres/Supabase.")
    parser.add_argument("--env", default=".env.local")
    parser.add_argument("--input", default="data/cardtrader/pokemon-blueprints.jsonl")
    parser.add_argument("--migration", default="supabase/migrations/20260517184500_cardtrader_pokemon_blueprints.sql")
    args = parser.parse_args()

    env = {**read_env(Path(args.env)), **os.environ}
    db_url = database_url(env)
    input_path = Path(args.input)
    migration_path = Path(args.migration)

    copy_path = input_path.with_suffix(".copy.tsv")
    with copy_path.open("w", encoding="utf-8") as temp:
        for line in input_path.open(encoding="utf-8"):
            row = json.loads(line)
            blueprint = row["blueprint"]
            values = [
                blueprint.get("id"),
                blueprint.get("name"),
                blueprint.get("version"),
                blueprint.get("game_id"),
                blueprint.get("category_id"),
                blueprint.get("expansion_id"),
                blueprint.get("image_url"),
                jsonb(blueprint.get("card_market_ids")),
                jsonb(blueprint.get("tcg_player_ids")),
                jsonb(blueprint.get("editable_properties") or []),
                jsonb(blueprint),
                jsonb(row.get("expansion")),
            ]
            temp.write("\t".join("\\N" if value is None else str(value).replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n") for value in values))
            temp.write("\n")

    copy_sql = f"""
\\copy public.cardtrader_pokemon_blueprints (
  id,
  name,
  version,
  game_id,
  category_id,
  expansion_id,
  image_url,
  card_market_ids,
  tcg_player_ids,
  editable_properties,
  blueprint,
  expansion
) from '{copy_path}' with (format text, delimiter E'\\t', null '\\N');
"""

    try:
        subprocess.run(["psql", db_url, "-v", "ON_ERROR_STOP=1", "-f", str(migration_path)], check=True)
        subprocess.run(["psql", db_url, "-v", "ON_ERROR_STOP=1", "-c", copy_sql], check=True)
    finally:
        copy_path.unlink(missing_ok=True)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
