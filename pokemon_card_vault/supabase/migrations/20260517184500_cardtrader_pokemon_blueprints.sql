create table if not exists public.cardtrader_pokemon_blueprints (
  id bigint primary key,
  name text not null,
  version text,
  game_id integer not null,
  category_id integer,
  expansion_id integer,
  image_url text,
  cardtrader_image_url text,
  cdn_image_url text,
  cdn_object_key text,
  card_market_ids jsonb,
  tcg_player_ids jsonb,
  editable_properties jsonb not null default '[]'::jsonb,
  blueprint jsonb not null,
  expansion jsonb,
  imported_at timestamptz not null default now()
);

create index if not exists cardtrader_pokemon_blueprints_name_idx
  on public.cardtrader_pokemon_blueprints using gin (to_tsvector('simple', coalesce(name, '')));

create index if not exists cardtrader_pokemon_blueprints_expansion_id_idx
  on public.cardtrader_pokemon_blueprints (expansion_id);

create index if not exists cardtrader_pokemon_blueprints_category_id_idx
  on public.cardtrader_pokemon_blueprints (category_id);
