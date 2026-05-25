import importlib.util
from pathlib import Path


SCRIPT_PATH = Path(__file__).with_name("load-cardtrader-blueprints-to-postgres.py")
SPEC = importlib.util.spec_from_file_location("loader", SCRIPT_PATH)
loader = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(loader)


def test_database_url_prefers_oracle_marketplace_url():
    assert loader.database_url(
        {
            "MARKETPLACE_DATABASE_URL": "postgres://oracle",
            "SUPABASE_DB_URL": "postgres://supabase",
        }
    ) == "postgres://oracle"


def test_upsert_sql_merges_by_blueprint_id_without_truncate():
    sql = loader.upsert_sql(Path("/tmp/cardtrader.copy.tsv"))

    assert "insert into public.cardtrader_pokemon_blueprints" in sql
    assert "on conflict (id) do update set" in sql
    assert "imported_at = now()" in sql
    assert "truncate" not in sql.lower()
    assert "cdn_image_url" not in sql
    assert "preview_image_url" not in sql
    assert "homepage_image_url" not in sql


def test_blueprint_values_preserve_raw_json_fields():
    values = loader.blueprint_values(
        {
            "blueprint": {
                "id": 123,
                "name": "Darkrai",
                "version": "Holo",
                "game_id": 5,
                "category_id": 1,
                "expansion_id": 9,
                "image_url": "https://example.test/card.png",
                "card_market_ids": [10],
                "tcg_player_ids": [20],
                "editable_properties": [{"name": "Number", "value": "1/2"}],
            },
            "expansion": {"id": 9, "name": "Test Set"},
        }
    )

    assert values[:7] == [
        123,
        "Darkrai",
        "Holo",
        5,
        1,
        9,
        "https://example.test/card.png",
    ]
    assert values[7] == "[10]"
    assert values[8] == "[20]"
    assert '"Number"' in values[9]
    assert '"Darkrai"' in values[10]
    assert '"Test Set"' in values[11]
