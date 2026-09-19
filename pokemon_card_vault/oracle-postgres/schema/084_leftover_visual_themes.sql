-- Card visual theme v1: semantic OKLCH surfaces derived from the leftover
-- illustration shade (marketplace_leftover_art_shades). One row per leftover
-- ct_id. artwork_identity is the sha256 of the canonical leftover JPEG
-- (085) and is the validity key: marketplace-card-page serves the row only
-- while it equals the current identity, so a replaced artwork always
-- re-derives. artwork_shade is kept as source metadata, never as proof of
-- freshness.

set statement_timeout = 0;

create table if not exists public.marketplace_leftover_visual_themes (
  ct_id bigint primary key,
  version text not null,
  artwork_shade text not null,
  artwork_identity text,
  hue real not null,
  chroma real not null,
  background text not null,
  surface text not null,
  surface_raised text not null,
  hero text not null,
  hero_border text not null,
  border text not null,
  tint text not null,
  derived_at timestamptz not null default now(),
  constraint marketplace_leftover_visual_themes_version
    check (version ~ '^v[0-9]+$'),
  constraint marketplace_leftover_visual_themes_shade
    check (artwork_shade ~ '^#[0-9a-f]{6}$'),
  constraint marketplace_leftover_visual_themes_hexes check (
    background ~ '^#[0-9a-f]{6}$'
    and surface ~ '^#[0-9a-f]{6}$'
    and surface_raised ~ '^#[0-9a-f]{6}$'
    and hero ~ '^#[0-9a-f]{6}$'
    and hero_border ~ '^#[0-9a-f]{6}$'
    and border ~ '^#[0-9a-f]{6}$'
    and tint ~ '^#[0-9a-f]{6}$'
  )
);
