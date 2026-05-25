#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import tempfile
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


BLUEPRINT_COLUMNS = [
    "id",
    "name",
    "version",
    "game_id",
    "category_id",
    "expansion_id",
    "image_url",
    "card_market_ids",
    "tcg_player_ids",
    "editable_properties",
    "blueprint",
    "expansion",
]


def database_url(env: dict[str, str]) -> str:
    for key in ("MARKETPLACE_DATABASE_URL", "SUPABASE_DB_URL", "DATABASE_URL", "POSTGRES_URL"):
        value = env.get(key, "").strip()
        if value:
            return value
    raise SystemExit("Missing MARKETPLACE_DATABASE_URL, SUPABASE_DB_URL, DATABASE_URL, or POSTGRES_URL for upload.")


def jsonb(value) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def tsv(value) -> str:
    if value is None:
        return "\\N"
    return str(value).replace("\\", "\\\\").replace("\t", "\\t").replace("\n", "\\n")


def blueprint_values(record: dict) -> list[object]:
    blueprint = record["blueprint"]
    return [
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
        jsonb(record.get("expansion")),
    ]


def upsert_sql(copy_path: Path) -> str:
    column_sql = ",\n  ".join(BLUEPRINT_COLUMNS)
    update_sql = ",\n  ".join(
        f"{column} = excluded.{column}"
        for column in BLUEPRINT_COLUMNS
        if column != "id"
    )
    return f"""
create temp table cardtrader_pokemon_blueprints_import (
  id bigint,
  name text,
  version text,
  game_id integer,
  category_id integer,
  expansion_id integer,
  image_url text,
  card_market_ids jsonb,
  tcg_player_ids jsonb,
  editable_properties jsonb,
  blueprint jsonb,
  expansion jsonb
) on commit drop;

\\copy cardtrader_pokemon_blueprints_import (
  {column_sql}
) from '{copy_path}' with (format text, delimiter E'\\t', null '\\N');

insert into public.cardtrader_pokemon_blueprints (
  {column_sql}
)
select
  {column_sql}
from cardtrader_pokemon_blueprints_import
on conflict (id) do update set
  {update_sql},
  imported_at = now();
"""


def main() -> int:
    parser = argparse.ArgumentParser(description="Load CardTrader Pokemon blueprints JSONL into Postgres/Supabase.")
    parser.add_argument("--env", default=".env.local")
    parser.add_argument("--input", default="data/cardtrader/pokemon-blueprints.jsonl")
    parser.add_argument("--schema", action="store_true", help="Apply the Oracle marketplace schema before importing.")
    parser.add_argument("--schema-command", default="node scripts/oracle-marketplace-migrate.js schema")
    args = parser.parse_args()

    env = {**read_env(Path(args.env)), **os.environ}
    db_url = database_url(env)
    input_path = Path(args.input)

    copy_file = tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".copy.tsv", delete=False)
    copy_path = Path(copy_file.name)
    try:
        with copy_file:
            for line in input_path.open(encoding="utf-8"):
                row = json.loads(line)
                copy_file.write("\t".join(tsv(value) for value in blueprint_values(row)))
                copy_file.write("\n")

        if args.schema:
            subprocess.run(args.schema_command, shell=True, check=True)
        subprocess.run(["psql", db_url, "-v", "ON_ERROR_STOP=1", "-c", upsert_sql(copy_path)], check=True)
    finally:
        copy_path.unlink(missing_ok=True)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
