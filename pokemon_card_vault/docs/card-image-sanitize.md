# Card image sanitize (ingest recipe)

White triangles at the corners of marketplace card art are **in the JPEG**, not
only a CSS bug. Physical Pokémon cards are die-cut with round corners. CardTrader
catalog files are axis-aligned rectangles, so the four corner triangles stay in
the raster as near-white pixels. JPEG has no alpha channel, so a dark UI shows
those pixels as ears.

This is the recipe the **next** CardTrader → R2 import must run. Do not overwrite
the existing ~50k R2 objects in place. CardTrader remains the unsanitized source.
The CDN Worker is pass-through for pixels (no Sharp). It maps public-id
`{card_id}_` prefixes to leftover `{ct_id}_` R2 keys. Do not put Sharp in
the Worker.

Code: `scripts/lib/sanitize-card-image.js`. Tests:
`scripts/lib/sanitize-card-image.test.js`. Full-pass classifier (FA / IR /
SIR / over-number / EX secrets): `docs/card-border-rebuild-pass.md`.

**Visual QA:** [test.pokoin.com/sanitize](https://test.pokoin.com/sanitize) —
local before/after JPEGs, not live CDN. See `docs/test-pokoin-sanitize-review.md`.
Regenerate: `node scripts/generate-sanitize-review-assets.js`.

## What we measured (2026-08-30)

| Object | Size | Aspect | Corners | Letterbox |
| --- | ---: | ---: | --- | --- |
| `351690_mega-gardevoir-ex.jpg` | 500×700 | 0.7143 (poker) | `(255,255,255)` | none |
| `351691_mega-lucario-ex.jpg` | 330×460 | 0.7174 | near-white | none |

Poker card aspect is `63.5 / 88.9 ≈ 0.7143`. After the sanitizer, Gardevoir
corners are **transparent PNG**; the gold interior is unchanged. Radius on that
file is `round(min(500,700) * 3.175/63.5) = 25px` (circular 5% of the short
side). New catalog keys are `{ct_id}_{slug}.png`. Existing `.jpg` objects stay
until re-imported.

React and the PNG mask use **`5% / 3.571%`** (`market/src/styles.css`
`--tcg-corner`). That remains the display-side clip for files already on CDN.

## Physical spec vs catalog

Official English TCG (poker size):

- Trim: **63.5 mm × 88.9 mm** (2.5 × 3.5 in)
- Corner radius: **0.125 in = 3.175 mm** → `3.175 / 63.5 ≈ 5.0%` of width
- Printers often quote a 3 mm radius on a 63 mm card (~4.8%)

We clip at the **official circular radius**: 5% of the short side
(`3.175 / 63.5`). CSS is `border-radius: 5% / 3.571%` so the pixel radius
matches on a poker-aspect card. Do not use a single `6%` (that is an
ellipse and larger than the die-cut). Do not use `border-radius: 5%` without
the slash (that sets ry = 5% of **height** ≈ 4.45 mm).

### What the round may touch

On a poker-aspect raster whose AABB **is** the trim, pixel radius is

`R = round(min(W, H) × 3.175 / 63.5)`

Centers of the four quarter-circles: `(R, R)`, `(W−1−R, R)`, `(R, H−1−R)`,
`(W−1−R, H−1−R)`. The clip may change pixels only in those four corner
squares **outside** the arc (`hypot > R`) — the cardboard crescents.

| Keep (printed face) | Punch (cardboard) |
| --- | --- |
| Silver SV TRAINER chrome, nameplate, art | White studio ears |
| Yellow/silver rim **inside** the circle | Square-cut 90° outline triangles in the crescent |
| Already-rounded pokemontcg / leftover silhouette | Existing matte / transparent crescents |

Light interiors (Air Balloon name bar ≈ `(253,253,253)`) match “ear white”.
The 1 px JPEG collar **must snapshot** the clear mask. Reseeding from freshly
painted matte floods the whole header to `#0b0b0f`. Already-rounded leftovers
(`cornerKind` matte/transparent corners) already **are** the die-cut: flatten
remaining paper; do not clip extra printed pixels at 5% and do not
fringe-punch silver.

Code: `inDieCutCrescent` / `inDieCutCap` / `lockPrinted` on
`applySupersampledRoundedRectAlpha` in `scripts/lib/sanitize-card-image.js`.

## Printed outer frame by era (English vs Japanese)

Trim size is **63 × 88 mm** worldwide (often quoted 63.5 × 88.9 poker). Japanese
cards are not a smaller trim; they look larger in the art box because the
**printed frame is thinner**. Card stock is ~0.30 mm EN / ~0.32–0.34 mm JP.

Clipping a square-cut scan at 5% without restoring frame width **pinches**
the corner. Remaining yellow along the 45° is `R − √2(R − T)`. On Gulpin
33/100 (500 px, T = 10, R = 25) that is **~3.8 px (~0.5 mm)** vs **~2.5 mm**
on the sides. Physical yellow is ~2.5 mm vs a 3.175 mm radius (T/R ≈ 0.79).
The JPEG rebuild pads the outline until T′ ≥ 0.78 R, then die-cuts at 4×
supersample so the arc has enough pixels to look defined.

| Era | When | Outer frame | Typical side width | Notes |
| --- | --- | --- | ---: | --- |
| EN Wizards (Base–Neo–e-Card) | 1999–2003 | Yellow | **2.3 mm sides** (ratio **0.0367**) | pokemontcg.io neo3/65: 21–22 px on 600 ≈ 2.22–2.33 mm. Bottom ~2.4 mm. Inner join is a straight AABB. The old ~3.16 mm was leftover yellow on a 322 px Base Set studio crop, not the printed frame. |
| EN EX–HGSS | 2003–2010 | Yellow | ~2.5–2.8 mm (~0.040–0.044) | Square-cut scans often **crop into** this band (Gulpin T = 10 px / 1.3 mm leftover) |
| EN BW–SWSH | 2011–2022 | Yellow | ~2.5 mm (~0.040) | Trapinch / Spinda 500 px: T = 19–22 px ≈ 2.5–2.8 mm. Japan had already switched |
| EN SV+ | 31 Mar 2023 | Silver/gray | ~1.5 mm (~0.024) | TPCi: yellow becomes gray to match Japan. Scarlet & Violet launch |
| JP original–LEGEND | 1996–2010 | Pale gold / cream | ~1.7–1.9 mm (~0.026–0.030) | Advent of Arceus 2009: ~14 px on 500 px ≈ 1.8 mm, chroma ~15 (not EN yellow) |
| JP BW+ | 17 Dec 2010 | Silver/gray | ~1.5 mm (~0.024) | BW1 Black/White Collection. Holos first; then the standard JP frame |
| Full art / IR / gold / VMAX / Tera ex | various | **No** yellow/silver frame | — | Skip frame restore; die-cut only if the raster is still a card |

Exceptions (do not invent a yellow stroke):

- Full-art, alt-art, illustration rare, gold secret, Amazing Rare
- BREAK (horizontal half), LEGEND (two-card)
- Energy / Trainer layouts still have a frame but colours differ by era
- Jumbo / oversized (different trim; `isCardRaster` aspect gate)

Bottom band is **thicker on purpose** (copyright, set number, artist). Pad
is applied **outside** the original pixels so that text is not painted over.

## JPEG has no alpha — so ingest writes lossless PNG

Rounded-corner tools that output PNG make the four triangles **transparent**.
JFIF/JPEG cannot. If you round and save JPEG, those pixels become a solid fill
(white ears, or a dark matte that only matches one UI chrome).

**Next import writes PNG.** Sharp's PNG `quality` / `effort` / `palette` flags
turn on **lossy** libimagequant. We only set zlib `compressionLevel: 9` (lossless).
See [sharp PNG output](https://sharp.pixelplumbing.com/api-output/#png) and
[lovell/sharp#3555](https://github.com/lovell/sharp/issues/3555).

Do **not** call `sharp(jpeg).rotate().toBuffer()` before the mask: that
re-encodes JPEG at default quality 80, which is why some earlier PNGs looked
softer than the source JPEG. Stay in `.raw()` until the lossless PNG encode.

CardTrader photos are not tight to the die-cut, so a 5% mask alone leaves a
white crescent between the CSS round and the printed border. Studio JPEGs also
leave a 1px white halo around the **whole** perimeter (visible on dark UI):

1. Flood-fill near-white pixels connected to each corner (stop at the sampled
   outline / silver rim) and punch them to alpha 0. Do not flood the TRAINER
   nameplate.
2. Punch a 2px **paper** perimeter fringe (studio white / cream JPEG halo),
   not silver chrome and not `luma ≥ 160` pixels that match the outline.
3. 8× coverage rounded-rect at 5% of the short side, **crescents only**.
   Already-rounded sources lock printed pixels (`lockPrinted`). No SVG
   `dest-in`.
4. 1 px matte collar from a **snapshot** of already-clear pixels — never
   flood connected ear-white interiors.
5. Encode **JPEG** (q100, 4:4:4, mozjpeg) flattened onto `#0b0b0f`. Object
   key extension stays `.jpg`.

`ORACLE_IMAGE_SANITIZE_FORMAT=png` is the alpha-mask path only: transparent
corners, lossless PNG. Catalog is JPEG (D00000E). Do not punch yellow
corners to matte on the JPEG path (that thins the frame). Fill white ears
with outline colour, **pad** a cropped frame until T′ ≥ 0.78 R, clip an
**8× coverage-sampled** rounded rect (corners only; no full-image lanczos).

Homepage derivatives stay `_homepage.webp` (resized 240px; lossy WebP is OK
for tiles). Catalog masters stay JPEG.

Do **not** rewrite existing `.jpg` CDN objects in place without a backup. A
re-import copies the live JPEG to `originals/{key}` first. Catalog URLs stay
`.jpg` / `.webp` (D00000E). Lossless sibling PNG is not viable (~8× the JPEG).
Sibling PNGs written on 2026-08-31 were deleted; catalog reverted to the
original keys. Do not delete `originals/` or the live JPEG.

## Letterbox / pillarbox

Some catalog files pad the card with uniform black (or white) bars. The
sanitizer crops a band only when **both opposite edges** are ≥98% near-black
(`≤28`) or near-white (`≥242`), each band ≤25% of that dimension, leftover
≥32 px.

A real card top edge is **not** a uniform band: corners are light, the border
is coloured (Gardevoir top-mid was `(95,101,97)`). That is why we do **not**
call `sharp.trim()`. Trim would eat black-bordered Mega frames.

JPEG ringing can leave ~1 px of a black bar. That is acceptable.

## What other people do (and why we do the inverse)

| Source | What they do | Ours |
| --- | --- | --- |
| [cardbleed](https://pypi.org/project/cardbleed/) `--fill-corners` | Flood transparent/black/white **corner triangles with border colour** so a rounded scan becomes a **square** for print bleed | Inverse: we **clip** the square JPEG to the die-cut |
| [silhouette-card-maker `--extend_corners`](https://github.com/Alan-Cha/silhouette-card-maker) | Sample the arc and **extend** into the corner so a cutter has bleed; otherwise cut cards show a sliver of white | Print-proxy problem. Do not run this on CDN masters |
| [OpenImages round-corners](https://openimages.app/round-corners/) | Canvas `clip()` + PNG; they spell out that JPEG would fill corners white/black | We write **PNG** for the same reason |
| Scanly / CSS `border-radius` + `overflow: hidden` | Clip at **display** time | React `--tcg-corner` (`5% / 3.571%`) |
| [SO: wrapper radius leaves a dark fringe](https://stackoverflow.com/questions/66288711/unwanted-border-radius-corners-around-images-in-brave-chrome-browser) | Radius the **image**, not only the tile | `.tile img` uses `--tcg-corner` |
| Local Qwen `qwen3.8:27b-128k` (`think: false`, 2026-08-30) | Radius `width * 0.05`; JPEG cannot grow alpha; Worker must stay pass-through; backup before overwrite | PNG for alpha; same 5% circular radius as CSS |

Qwen also said “paint corners with the card background or crop inward.” Cropping
inward would shave art. We mask to the official rounded rect and leave the
pixels **outside** the die-cut transparent.

## Pipeline (next import)

```
CardTrader full/preview
  → download (never store /preview_ as the full object)
  → if a live R2 key exists: CopyObject to originals/{key} (once)
  → scripts/lib/sanitize-card-image.js
       1. EXIF rotate in-pipeline (no JPEG re-encode)
       2. crop uniform letterbox/pillarbox if both opposite edges qualify
       3. rotate so the inner printed rectangle is axis-aligned
          (left/right yellow→face join, Theil–Sen; not the name-bar /
          evo-box step). Gold HR / foil-to-edge: four straight outer
          borders (L/R agree, T/B agree, then vertical matches horizontal),
          tight crop to those intercepts, die-cut only. FA / IR / SIR
          filenames skip this step (no inner frame).
       4. classify by treatment + era (yellow Wizards/DP, silver SV, gold
          secret, full-art). Measure outer rim millimetres only after the
          face is upright.
       5. rebuild a clipped yellow/silver frame to era width, or die-cut
          only (gold, FA, complete studio photo — D00000F / D00000G).
          Already-rounded leftovers: crescents only; do not rewrite the
          printed TRAINER / nameplate.
       6. 8× rounded-rect onto the dark matte (printed-lock when the
          silhouette is already the die-cut); encode catalog JPEG
  → R2 PutObject leftover {ct_id}_{slug}.jpg
  → catalog URLs use our id prefix; leftover key stays ct_id
```

Hooked from:

- `scripts/import-oracle-cardtrader-images.js` (Oracle digest — **this is the one**)
- `scripts/import-cardtrader-full-images.js`
- `scripts/import-cardtrader-preview-images.js`
- `scripts/generate-oracle-homepage-card-images.js` (sanitize, then 240 px WebP)

`pokoin-cdn-card-images-worker.js` does **not** transform pixels. Do not put
sharp in the Worker.

## Env

| Variable | Default | Meaning |
| --- | --- | --- |
| `ORACLE_IMAGE_SANITIZE` | `1` | `0` uploads the CardTrader bytes unchanged |
| `ORACLE_IMAGE_SANITIZE_FORMAT` | `jpg` | `png` is opt-in transparent corners only |
| `ORACLE_IMAGE_SANITIZE_JPEG_QUALITY` | `100` | q100 + 4:4:4 when ≥95 |
| `ORACLE_IMAGE_CORNER_RADIUS_RATIO` | `0.05` | Fraction of `min(w,h)` (official 3.175/63.5). Circular die-cut only; not a second clip of the printed face. |
| `ORACLE_IMAGE_SANITIZE_MATTE` | `#0b0b0f` | JPEG flatten colour |
| `ORACLE_IMAGE_BACKUP_ORIGINALS` | `1` | `0` skips CopyObject to `originals/{key}` |

If `sharp` is missing, import **warns and uploads the source** (same as today).
The API container has `sharp`. nezopt historically lacked the linux-x64 binary;
`npm install --os=linux --cpu=x64 --libc=glibc sharp` fixes local tests.

## How to run another digest (copy the lib)

`require('./lib/sanitize-card-image')` is resolved next to the importer
file. Copy **both** into the container, not only the importer.

```bash
# on pokoin-marketplace, from pokemon_card_vault/
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

`ORACLE_IMAGE_SANITIZE` defaults on. Set `=0` only to compare against CardTrader.

Do **not** run `refresh_marketplace_oracle_projections()`. The importer still
updates `cardtrader_pokemon_blueprints` / `marketplace_cards` /
`marketplace_card_versions` / `marketplace_search_candidates` per `ct_id`.

## Existing catalog

Already on R2: **leave the public JPEG**. CSS `--tcg-corner` hides ears in
React. Flutter tiles that skip that CSS still show ears and a white perimeter
halo until those objects are re-imported as PNG.

Explicit rewrite (one card or a filtered digest, never a silent 50k batch):

1. `backupExistingObject` copies the live key to `originals/{key}` **once**.
   It does not overwrite an existing backup. It does not delete the live JPEG.
2. PutObject the sanitized **sibling** `{ct_id}_{slug}.png`.
3. Point catalog URLs at the PNG. CDN Cache-Control is `immutable` for a year
   — the old JPEG URL keeps serving the old bytes until caches expire. That is
   why we change the key extension rather than overwrite `.jpg`.
4. Code: `scripts/lib/backup-r2-original.js`, hooked from
   `import-oracle-cardtrader-images.js` on every upload when a live key exists.

Local digest rewrite (this copy only, not the full ~50k catalog):

```bash
cd pokemon_card_vault
node scripts/rewrite-local-digest-png.js --apply --no-db
# catalog (on pokoin-marketplace, API container has MARKETPLACE_DATABASE_URL):
# node scripts/apply-digest-png-catalog.js /path/to/rewrite.log.jsonl
```

Source: `/home/nez/pokoincdn/cdn_images_digest/2026-08-30`.
Sanitized PNGs also land in `cdn_images_digest/2026-08-30-png/`.
Catalog updates match `ct_id` from the leftover filename (not `card_id`,
because leftover prefixes can overlap a different card's public id). Do
**not** run `refresh_marketplace_oracle_projections()`.

Do not batch-rewrite ~50k objects without an explicit go-ahead.

Homepage WebP can pick up the mask on the next
`generate-oracle-homepage-card-images.js --apply` without touching full JPEGs.

## Studio paper punch (Milotic League) and tilt-then-rebuild (theme-deck Swampert)

Two leftover JPEGs from Supreme Victors. **Not uploaded.** Do not mix the two
Swampert printings.

| Printing | Public id | Leftover key | Catalog size | What was wrong |
| --- | ---: | --- | --- | --- |
| Milotic C League 35/147 | **257448** | `128724_milotic-c-pokemon-league-35-147-supreme-victors-promos.jpg` | 333×450 | Complete printed yellow + ~8–10 px white studio ring. Already rounded. Do **not** swap official `pl3/35` (no League stamp). |
| Swampert non-holo theme-deck 12/147 | **257432** | `128716_swampert-non-holo-theme-deck-12-147-supreme-victors-promos.jpg` | 314×450 | Tilted scan, AABB-clipped left yellow. |
| Swampert rare holo 12/147 | **257516** | `128758_swampert-rare-holo-12-147-supreme-victors.jpg` | 500×688 | Tight crop, almost upright. **Leave this file alone** unless asked. |

### Punch (complete studio photo)

4-connected flood from the image border. Predicate (Qwen `qwen3.8:27b-128k`
agreed; chroma 22 also punches cream C20):

- Punch: luma ≥ 220, chroma ≤ 22, not yellow-hue
- Stop: `isYellowHue` (chroma ≥ 35) and `belongsToPrintedRim`
- Never punch a whole scanline (that cuts the card)
- Never flood yellow (holo sparkle holes leak into SP art)

Then crop to the remaining card AABB and 8× round onto `#0b0b0f`. Do not
`fillInsideRoundCaps` (that paints yellow back into the punched ring). Do not
pad a second rim (D00000G).

Measured on leftover `128724_` (local CDN, not R2): **10 799** paper pixels
punched, canvas 333×450 → 324×444, pad 0, no deskew. Mid-side x=0 is matte;
washed yellow around x=2–10 stays.

### Deskew then rebuild (clipped theme-deck)

1. **First** rotate so the inner printed rectangle is upright. Use the
   left/right yellow→face join (Theil–Sen), not the top name-bar. The
   Swampert evolution-box step made OLS read **−4.50°** while the silver
   inner line was only ~1–2°. Stop when the **vertical** join is `< 0.25°`,
   even if the top join is still a few degrees. Do **not** then rotate by
   the AABB side-edge atan — after a good inner rotate that is the crop,
   not the face.
2. Gold secrets / foil-to-edge arts have no inner yellow rectangle. Fit four
   straight outer borders (corners inset), rotate so vertical matches
   horizontal, crop tight to those intercepts, then die-cut only. Do not
   punch yellow gold as fringe. FA / IR / SIR skip deskew (the art *is* the
   face).
3. **Then** measure the outer rim. If a side walk is T ≤ 2 after deskew
   (left yellow was clipped), peel leftover yellow to the inner face and
   paint a straight AABB of era width (`22/600` ≈ **2.33 mm** on poker
   63.5 mm). 5% die-cut. Era table is above; do not invent a yellow stroke
   on gold / full-art.

Measured on leftover `128716_`:

| | Before | After |
| --- | ---: | ---: |
| Inner join | −4.50° | **0.12°** after rotate (`deskewDeg` +3.15°); rebuild paints axis-aligned yellow outside that |
| Left / right T | 10 / 6 px (left clipped) | **11 / 11 px** |
| Side yellow | uneven | **2.22 mm** (era 2.33 mm; allowed 1.98–2.80) |
| Pad | — | 11 px |

Tests: `white studio surround… punched, not welded` and `tilted studio crop is
deskewed then missing yellow is rebuilt to era width` in
`scripts/lib/sanitize-card-image.test.js`. Previews (JFIF, do not commit):
`sanitize-five-preview/revised/*-pipeline.preview.jpg`.

## Local check

```bash
node --test pokemon_card_vault/scripts/lib/sanitize-card-image.test.js \
  pokemon_card_vault/scripts/lib/backup-r2-original.test.js \
  pokemon_card_vault/scripts/import-oracle-cardtrader-images.test.js \
  pokemon_card_vault/scripts/generate-oracle-homepage-card-images.test.js
```

Smoke one live file through the helper (does not upload):

```javascript
const fs = require('fs');
const { sanitizeCardImage } = require('./scripts/lib/sanitize-card-image');
// corners of 351690 go from (255,255,255) to near-black
```
