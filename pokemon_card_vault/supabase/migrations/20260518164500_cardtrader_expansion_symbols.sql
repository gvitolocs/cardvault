create table if not exists public.cardtrader_pokemon_expansions (
  expansion_id integer primary key,
  game_id integer not null default 5,
  code text,
  name text not null,
  normalized_name text generated always as (
    lower(regexp_replace(name, '[^a-zA-Z0-9]+', ' ', 'g'))
  ) stored,
  source_asset_code text,
  symbol_image_url text,
  symbol_object_key text,
  symbol_imported_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists cardtrader_pokemon_expansions_code_idx
  on public.cardtrader_pokemon_expansions (code);

create index if not exists cardtrader_pokemon_expansions_name_idx
  on public.cardtrader_pokemon_expansions using gin (
    to_tsvector('simple', coalesce(name, ''))
  );

create or replace function public.touch_cardtrader_pokemon_expansions_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists touch_cardtrader_pokemon_expansions_updated_at
  on public.cardtrader_pokemon_expansions;

create trigger touch_cardtrader_pokemon_expansions_updated_at
before update on public.cardtrader_pokemon_expansions
for each row
execute function public.touch_cardtrader_pokemon_expansions_updated_at();
