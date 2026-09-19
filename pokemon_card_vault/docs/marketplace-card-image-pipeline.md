# Marketplace card image pipeline (2026-08-30)

## Symptom

Card detail pages such as
`https://pokoin.com/marketplace/en/cards/598052/card-dachsbun-ex-full-art-160-142-stellar-crown`
showed a **solid dark rectangle** instead of art. Title, set, and number still
rendered. Homepage rows had the same empty frames during the same window.

## What is not broken

- R2 / `cdn.pokoin.com` objects exist. Dachsbun **ct_id `299026`**:
  `https://cdn.pokoin.com/299026_dachsbun-ex-full-art-160-142-stellar-crown.jpg`
  returns `200 image/jpeg`. Preview
  `https://cdn.pokoin.com/previews/299026_dachsbun-ex.jpg` also `200`.
- Public id **`598052` = `299026 * 2`**. The leftover object key is `299026_…`.
  The Worker maps `598052_…` to that leftover key.
- There is no `.webp` for this card; the catalog stores `.jpg`.
- Flutter paints `cardPalette.imageFrameColor` (`#FF243E68` for Dachsbun) until
  `CachedNetworkImage` gets a URL. That frame looks black. A true 404 uses the
  yellow `Icons.style` error widget.

## Pipeline (happy path)

1. Route `cardId` is **our id** (`marketplace_cards.card_id`, CardTrader × 2).
2. `GET /api/marketplace-card-versions?cardId=598052&limit=1` returns
   `image_url` / `cdn_image_url` rewritten to the **our id** filename.
3. Flutter `rewriteCdnPrefixToOurId` rewrites leftover `{ct_id}_` → `{ourId}_`
   if a cached URL still has the scrape prefix.
4. Browser loads `https://pokoin.com/card-images/{ourId}_…`. The Worker tries
   that key, then the leftover `{ct_id}_` object. CORS `*`.

Catalog source of truth on pokoin-marketplace (storage; API rewrites the prefix):

```
marketplace_search_candidates.card_id = 598052
marketplace_search_candidates.ct_id   = 299026
image_url = https://cdn.pokoin.com/299026_dachsbun-ex-full-art-160-142-stellar-crown.jpg
```

Public clients see `/card-images/598052_dachsbun-ex-full-art-160-142-stellar-crown.jpg`.

## Root causes (stacked)

### 1. Exclusive projection refresh (primary outage)

At 13:05 UTC a session ran:

```sql
set statement_timeout = 0;
set idle_in_transaction_session_timeout = 0;
select public.refresh_marketplace_oracle_projections();
```

PID held **AccessExclusiveLock** on `marketplace_cards` and
`pokoin_pokemon_blueprints` for **74 minutes**. `max_connections=20` on the
1 GB VM. API handlers waited on the pool (`timeout exceeded when trying to
connect`) or hit statement timeout:

- `marketplace-card-versions` (`rowsForVersions`)
- `marketplace-event` (click insert)
- `marketplace-card-url`
- `marketplace-home` / cheapest-price (earlier the same day)

Detail UI can still show the slug (`Dachsbun ex`, `160/142`). Artwork waits on
versions JSON, so the frame stays dark.

**Mitigation:** `pg_cancel_backend` on that PID (transaction rolled back).
`scripts/cardtrader-delta-import.js` will not call the wrapper unless
`POKOIN_ALLOW_FULL_PROJECTION_REFRESH=1`.

### 2. Versions lookup seq scan (always-on bug)

`marketplace_card_versions` PK is `card_id` only. The handler used:

```sql
versions.card_id = $1 OR versions.ct_id = $1
```

`EXPLAIN ANALYZE` for Dachsbun: **seq scan**, 46827 rows filtered, ~1.1s, 10k
buffers. `marketplace_search_candidates` with the same OR uses BitmapOr on PK +
unique `ct_id` (~instant).

**Fix:** resolve `card_id` from `marketplace_search_candidates`
(`card_id` UNION ALL `ct_id`, both indexed), then
`versions.card_id = coalesce(resolved, $1)` (PK). Joins to CardTrader /
listing cache / CM links use **`versions.ct_id`**, never
`coalesce(ct_id, card_id)` (public id is not a blueprint id). Unique index
`marketplace_card_versions_ct_id_key` is `020_marketplace_card_versions_ct_id_idx.sql`.

### 3. Doubled CDN prefix (client / stale cache)

If a client requests `/card-images/598052_…` the Worker maps to leftover
`299026_…` (try requested key first, then even-prefix `/ 2`). Live catalog
rows still store `299026_`; the API rewrites served URLs to `598052_`.
Do not rename R2 objects. `ct_id` numbers can overlap public ids (Nacli
`248768` vs Drifloon public `248768`) — slug + as-is lookup keep leftover
keys working.

## Verification (2026-08-29, after cancel + versions deploy)

```bash
# must be 200 and ~200–400ms on localhost API
curl -sS -o /tmp/v.json -w '%{http_code} %{time_total}\n' \
  'http://127.0.0.1:18080/api/marketplace-card-versions?cardId=598052&limit=1'
python3 -c "import json; r=json.load(open('/tmp/v.json')); print(r[0]['image_url'])"

curl -sSI 'https://cdn.pokoin.com/299026_dachsbun-ex-full-art-160-142-stellar-crown.jpg'
# public id (Worker maps to leftover key):
curl -sSI 'https://cdn.pokoin.com/598052_dachsbun-ex-full-art-160-142-stellar-crown.jpg'
```

Open the canonical path and confirm the jpg loads, not the dark frame.

## Do / do not

- Do join listing cache on `blueprint_id = ct_id` or `pokoin_card_id = card_id::text`.
- Do not join `blueprint_id = card_id` after public ids doubled.
- Do not run `refresh_marketplace_oracle_projections()` on live marketplace
  Postgres during traffic.
- Do not proxy `/card-images` through the Oracle API.


## Live image log (navigation)

Oracle API prints one JSON line per event: `marketplace-image {...}`.

```bash
# last URLs served/failed (in-memory on pokoin-oracle-api)
curl -sS 'https://api.pokoin.com/api/marketplace-image-log?limit=40'
ssh pokoin-marketplace "docker logs --since 10m pokoin-oracle-api 2>&1 | grep marketplace-image | tail"
```

`prefixKind` `public_id` is our id (the one we use). `ct_id` on a leftover object name is storage, not a public id.
Homepage GET logs the carousel URLs it served. Flutter `CachedNetworkImage` errors POST the **exact failed URL**.


## CDN ingest (2026-08-30 digest)

Homepage / expansion browse still hid newer English MEGA-era singles because
`image_url` pointed at `cardtrader.com`. Catalog rows existed; R2 did not.

Live counts **before** this ingest: `marketplace_cards` 74459, CDN-backed
**48842**, CardTrader-hosted **25617**. Mega Evolution singles were 91/188 CDN;
Phantasmal Flames / Inferno X / Mega Brave / Mega Symphonia / MEGA Dream ex
were almost all CardTrader.

### What we ingested

Script: `scripts/import-oracle-cardtrader-images.js` (run inside
`pokoin-oracle-api` with `NODE_PATH=/app/node_modules`).

Filters used:

- `ORACLE_IMAGE_EXPANSION_IDS=4256,4318,4313,4237,4238,4314`
  (Mega Evolution, Phantasmal Flames, Inferno X, Mega Brave, Mega Symphonia,
  MEGA Dream ex)
- `ORACLE_IMAGE_CATEGORY_ID=73` (Pokémon Singles)
- Two leftover Pokémon Center Set SKUs (`ct_id` 338989, 338990) by
  `ORACLE_IMAGE_IDS`

Result: **776** singles uploaded (full + preview). **0** failed.

| Set | Singles | CDN after |
| --- | ---: | ---: |
| Mega Evolution | 188 | 188 |
| Phantasmal Flames | 130 | 130 |
| Inferno X | 116 | 116 |
| Mega Brave | 93 | 93 |
| Mega Symphonia | 93 | 93 |
| MEGA Dream ex | 250 | 250 |

Catalog-wide after: CDN **49618**, still-on-CardTrader **24841** (older sets,
not this digest).

### Full art vs `preview_`

CardTrader `blueprint.image_url` is often `/preview_…` (180×250). The importer
now derives the real full file by stripping `/preview_` (and `/show_`) before
download. Example: Dachsbun SIR CT full is **662×920**, not the 180px preview
and not an upscaled 500×695 JPEG.

Do not store the preview file as `cdn_image_url`.

### Local copy

- Container: `/tmp/cdn_images_digest`
- nezopt: `/home/nez/pokoincdn/cdn_images_digest/2026-08-30`
  (**1552** files, ~137 MB — full + `previews/`)
- Compatibility symlink: `Projects/artifacts/cdn_images_digest` → that folder

Keys stay `{ct_id}_{slug}.{ext}` in bucket `cardvault-images`. Public site
loads `https://cdn.pokoin.com/{ourId}_{slug}` (Worker `pokoin-cdn-card-images`
maps to the leftover key).

### How to run another digest

CPU-heavy catalog work (CardTrader ingest, pokemontcg JPEG apply) runs on
**nezopt**, using `pokemon_card_vault/.env.local` (`MARKETPLACE_DATABASE_URL`
→ `130.61.251.250:5432`, plus R2 keys). Do not run those jobs inside
`pokoin-oracle-api` (2 vCPU VM). Dead hosts: `92.5.23.133`, `141.147.62.244`.

```bash
# nezopt — pokemontcg hires → catalog JPEG + R2 + URL update
cd pokemon_card_vault
node scripts/import-pokemontcg-expansion-hires.js --apply --concurrency=16 \
  --report=/tmp/pokemontcg-expansion-samples/expansion-sample-compare.json \
  --out=/tmp/pokemontcg-expansion-jpg
```

Optional if port 5432 is blocked from this network:

```bash
ssh -N -L 127.0.0.1:15432:127.0.0.1:5432 pokoin-marketplace
MARKETPLACE_DB_HOST_OVERRIDE=127.0.0.1 MARKETPLACE_DB_PORT_OVERRIDE=15432 \
  node scripts/import-pokemontcg-expansion-hires.js --apply
```

The API container still has R2 + `MARKETPLACE_DATABASE_URL` for small
on-box scripts. Example CardTrader digest (slow on the micro):

```bash
# on pokoin-marketplace, API container already has R2 + MARKETPLACE_DATABASE_URL
# require('./lib/sanitize-card-image') is next to the importer — copy both.
docker exec pokoin-oracle-api mkdir -p /tmp/card-image-import/lib
docker cp scripts/lib/sanitize-card-image.js \
  pokoin-oracle-api:/tmp/card-image-import/lib/sanitize-card-image.js
docker cp scripts/lib/backup-r2-original.js \
  pokoin-oracle-api:/tmp/card-image-import/lib/backup-r2-original.js
docker cp scripts/import-oracle-cardtrader-images.js \
  pokoin-oracle-api:/tmp/card-image-import/import-oracle-cardtrader-images.js
docker exec -e NODE_PATH=/app/node_modules \
  -e ORACLE_IMAGE_EXPANSION_IDS=4256,4318 \
  -e ORACLE_IMAGE_CATEGORY_ID=73 \
  -e ORACLE_IMAGE_BATCH_SIZE=10 \
  -e ORACLE_IMAGE_NEWEST_FIRST=1 \
  -e ORACLE_IMAGE_MODE=both \
  -e ORACLE_IMAGE_LOCAL_DIR=/tmp/cdn_images_digest \
  pokoin-oracle-api \
  sh -c 'cd /app && node /tmp/card-image-import/import-oracle-cardtrader-images.js'
```

Then `docker cp pokoin-oracle-api:/tmp/cdn_images_digest` to
`/home/nez/pokoincdn/cdn_images_digest/<date>/`.

Optional env:

- `ORACLE_IMAGE_IDS=ct,id,list` — specific blueprints
- `ORACLE_IMAGE_LOCAL_DIR` — write the same keys locally
- Sharp is required for sanitize + quality audit. If it is missing the
  importer uploads CardTrader bytes unchanged.

### Corner / letterbox sanitize (next import)

Catalog JPEGs are square; physical cards are round-cornered. **Next ingest**
runs `scripts/lib/sanitize-card-image.js` before `PutObject` (lossless PNG,
hard 5% die-cut, corner + 2px perimeter white punch). Live JPEGs are copied
to `originals/{key}` once, then a sibling `.png` is written. Recipe:
[card-image-sanitize.md](./card-image-sanitize.md). Copy **importer +
`scripts/lib/sanitize-card-image.js` + `scripts/lib/backup-r2-original.js`**.

`ORACLE_IMAGE_SANITIZE=0` skips it. Do **not** batch-overwrite the existing
R2 catalog in place.

React CSS `--tcg-corner` (`5% / 3.571%`) matches the PNG mask. The Worker
does not rewrite pixels.

Do **not** run `refresh_marketplace_oracle_projections()` or unscoped
`refresh_marketplace_cards_from_blueprints()`. This importer updates
`pokoin_pokemon_blueprints`, `marketplace_cards`, `marketplace_card_versions`,
and `marketplace_search_candidates` per row via `ct_id`.

### Flutter detail vs tiles

`preferDecodableMarketplaceImage` still prefers homepage/preview for tiles.
Card detail must use `preferDetailMarketplaceImage` (full raster, skip
`/previews/`). Flutter web `<img>` can decode progressive JPEG; do not paint
180px previews as heroes.

Smoke:

```bash
curl -sSI 'https://cdn.pokoin.com/360112_mega-dragonite-ex.webp'
curl -sSI 'https://cdn.pokoin.com/356870_mega-lopunny-ex.jpg'
```
