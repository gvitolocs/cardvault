-- Authoritative artwork identity for theme validity. artwork_identity is
-- the sha256 of the canonical leftover JPEG bytes (objects/ copy when
-- present, else the sampled file), written by sample-leftover-art-shade.py
-- alongside the shade. marketplace_leftover_visual_themes.artwork_identity
-- (084) must equal it for a persisted theme to be served; the shade itself
-- is source metadata and never the correctness key, because two artworks
-- can quantize to the same shade and an artwork can change without moving
-- its quantized shade.

set statement_timeout = 0;

alter table public.marketplace_leftover_art_shades
  add column if not exists artwork_identity text;

alter table public.marketplace_leftover_art_shades
  add constraint marketplace_leftover_art_shades_identity
    check (artwork_identity ~ '^[0-9a-f]{64}$')
    not valid;
