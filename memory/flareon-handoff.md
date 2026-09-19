# Flareon handoff (Pokoin / CardVault)

- Focus: public web is moving to **React/Next.js**. New page APIs are live on `api.pokoin.com` after deploy: card-page, search-page, expansion-page, home `recentCardIds`.
- Current Cursor work: catalog JPEG sanitizer. Gold leftover deskew now skips dark matte and fits all four sides (Charizard 713832 was 0° while the face sat −1.70°). Local preview remaining −0.06°. Still needs Giuseppe check then `?v=ct3`. Do not full-catalog rewrite.
- Local CDN mirror: `/home/nez/Projects/pokoin/PokoinTest/index/cdn_images` (exact leftover R2 keys). Catalog jobs must write the same key there; do not scan by downloading cdn.pokoin.com.
- Mac Cursor stop-hook that shut the machine down was **removed** (2026-08-30 morning).
- Flutter web on pokoin.com was redeployed with full-size detail art; homepage New cards start at Mega Lucario ex. Homepage API is still ~30s.
- Flutter web on pokoin.com stays laggy (no Hero, stretched preview JPEGs). Do not patch CanvasKit further; React should use `heroImageUrl` / `gridImageUrl` (full JPEG, never `/previews/`).
- Docs: `pokemon_card_vault/docs/react-page-apis.md` and `GET /api/__contract`.
- Catalog: Mega Evolution / Phantasmal Flames / Inferno X / Mega Brave / Mega Symphonia / MEGA Dream ex **singles are on cdn.pokoin.com** (2026-08-30 digest, 776 faces). Older sets still have ~24k CardTrader image URLs.
- Local image copy: nezopt `/home/nez/Projects/pokoin/PokoinTest/index/cdn_images` (full leftover-key mirror). Dated digest `/home/nez/pokoincdn/cdn_images_digest/2026-08-30` is the Aug 30 Mega-set snapshot only.
- Public image URLs use our id; leftover R2 keys stay `ct_id_`; Worker maps.
- Do not run full `refresh_marketplace_cards_from_blueprints()` on live Postgres.
- Infra (2026-09-18): public api.pokoin.com / cdn.pokoin.com / Meili / Valkey are on **pi-home** (Raspberry Pi). **Not peer3.** Oracle pokoin-marketplace is the CardTrader dump / Postgres **writer** only. Pi Postgres is a streaming replica — do not write dumps there. PokoinPoS seed on peer1 only.
