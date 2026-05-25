alter table public.cardtrader_pokemon_expansions
  add column if not exists logo_image_url text,
  add column if not exists logo_object_key text,
  add column if not exists logo_imported_at timestamptz;
