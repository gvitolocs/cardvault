# test.pokoin.com — sanitize review

Visual QA for the CardVault JPEG sanitizer before uploading new catalog
leftovers to R2. **Not live CDN** — local JPEGs only.

| | |
| --- | --- |
| **URL** | [https://test.pokoin.com/sanitize](https://test.pokoin.com/sanitize) |
| **Host redirect** | `test.pokoin.com/` → `/sanitize` (`pokoin-web/vercel.json`) |
| **Page** | `pokoin-web/market/src/pages/Sanitize.jsx` |
| **Assets** | `pokoin-web/market/public/review/` |
| **Manifest** | `pokoin-web/market/public/review/manifest.json` (generated) |
| **Regenerate** | `node scripts/generate-sanitize-review-assets.js` (from `pokemon_card_vault/`) |
| **Sanitizer** | `scripts/lib/sanitize-card-image.js` (44 tests) |

## What it is

A minimal React page on the Pokoin web deploy (`pokoin-web`) that shows **before /
after** pairs for sanitizer changes Giuseppe approves by eye. Hairline guides
overlay the corners for tilt judgement. Click any frame to zoom.

Nothing on this page is served from `cdn.pokoin.com`. When a pair looks right,
encode the matching leftover key separately (`?v=ct3` for Charizard) — do not
batch `--apply` the full catalog without explicit go-ahead.

## Deploy

```bash
cd pokoin-web
bash scripts/build-web.sh          # writes dist-web/
vercel deploy --prod               # needs Vercel auth on this machine
```

After deploy, hard-refresh — review JPEGs are cache-busted via
`manifest.revision` on the page.

## Regenerate assets

From `pokemon_card_vault/`:

```bash
node scripts/generate-sanitize-review-assets.js
cd ../pokoin-web/market && npm run build
```

The script:

1. Downloads live CDN inputs where noted below.
2. Runs `sanitizeCardImage` with the correct leftover filename (classifier key).
3. Measures skew, punched pixel count, and corner light-speck count.
4. Writes JPEGs + `manifest.json` into `pokoin-web/market/public/review/`.
5. Builds `charizard-deskew-compare.jpg` (left = before, right = after).

**Manual input:** `charizard-user-studio.jpg` (713×1000 Giuseppe square crop) must
already exist in `public/review/`. The script does not recreate it.

## Current review sets (revision `2026-09-01-edge-fringe`)

### 1 · Mega Charizard X ex — leftover deskew

| | Before | After |
| --- | --- | --- |
| **File** | `charizard-leftover.jpg` | `cdn-leftover-precise.jpg` |
| **Source** | CDN `356916_mega-charizard-x-ex.jpg?v=ct2` | Sanitizer output |
| **Public id** | 713832 | same |
| **Size** | 737×1021 | ~765×1041 (rotate pad) |
| **Problem** | Marketplace matte read as card edge → deskew 0° while gold face sat **−1.70°** | Four-side Theil–Sen + min-area refine |
| **Fix** | — | **+1.57°** applied, remaining **−0.06°** |
| **Pipeline** | `gold-foil` · die-cut only | same + deskew |

Live card: [pokoin.com/marketplace/en/cards/713832](https://pokoin.com/marketplace/en/cards/713832)

**Do not** PutObject `?v=ct3` until this pair looks right.

### 2 · Mega Charizard X ex — studio crop edge fringe

| | Before | After |
| --- | --- | --- |
| **File** | `charizard-user-studio.jpg` | `user-studio-precise.jpg` |
| **Source** | Manual 713×1000 crop (studio paper already removed) | Sanitizer output |
| **Deskew** | skipped (~0° AABB) | skipped |
| **Problem** | Sparse cream/gold pixels on die-cut arc beside baked matte ears | Light specks visible on `#0b0b0f` |
| **Fix** | — | Perimeter fringe + **silhouette BFS** (treat opaque matte ears as clear surround) |
| **Metric** | corner light specks (luma ≥ 200, beside matte) | **22 → 0** |

Gold HR path: punch studio white → crop → pre/post round fringe → 8× corner AA →
silhouette light-fringe punch → flatten `#0b0b0f` JPEG q100 4:4:4.

### 3 · Side-by-side strip

`charizard-deskew-compare.jpg` — leftover ct2 (left) vs precise deskew (right).

### 4 · Earlier pipeline (reference)

| Card | Before file | After file | Pipeline |
| --- | --- | --- | --- |
| Milotic C League 257448 | `milotic-league-before.jpg` (CDN 333×450) | `milotic-league.jpg` | `studio-diecut` — punch white ring, no second rim |
| Swampert theme 257432 | `swampert-theme-before.jpg` (CDN 314×450) | `swampert-theme.jpg` | Deskew inner join → rebuild clipped yellow |

Not uploaded. Do not mix Swampert theme-deck `128716_` with rare holo `128758_`.

## Edge-fringe fix (2026-09-01)

Leftover JPEG ears are often **opaque** catalog matte `#0b0b0f`, not alpha = 0.
The old fringe punch only flooded from transparent pixels, so foil highlights one
pixel inboard of the ear survived flatten and looked like white specks.

Changes in `sanitize-card-image.js`:

- `isLightMatteFringe` — cream JPEG at luma 168–209, chroma ≤ 48.
- `punchPerimeterFringe` / `punchHaloAlongRound` — pre- and post-8× round.
- `punchSilhouetteLightFringe` — BFS from transparent **or matte-like** surround;
  punch light pixels within 3 px of the silhouette.

Tests: `gold foil studio crop has no light matte specks…`,
`silhouette fringe punch treats baked matte ears as clear surround`.

## Related docs

- Ingest recipe: `docs/card-image-sanitize.md`
- Classifier / rebuild: `docs/card-border-rebuild-pass.md`
- Session state: `memory/current-state.md`
