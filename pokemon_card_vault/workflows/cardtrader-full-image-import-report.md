# CardTrader Full Image Import Report

## 2026-05-18 Full/show candidate retry behavior

Production policy: Pokoin must serve card images from our own CDN
(`https://cdn.pokoin.com`) through the app `/card-images/...` route. CardTrader
URLs are source inputs only and should not be used directly by the Flutter app.
Full card images must come from CardTrader's full source (`blueprint.image.url`
first, then `blueprint.image.show.url`) whenever that source exists. Do not keep
or regenerate full-image rows from CardTrader preview URLs just because a CDN
object already exists; preview URLs are only for thumbnail/preview fields.

The full-image importer in `scripts/import-cardtrader-full-images.js` now treats
each CardTrader blueprint row as a set of possible full-image candidates, not as
a single fragile URL.

Candidate order:

1. `blueprint.image.url`
2. `blueprint.image.show.url`
3. `blueprint.image_url`
4. `cardtrader_image_url`
5. `image_url` only when it is still a CardTrader URL

Rules saved from the fix:

- Ignore CardTrader preview URLs and fallback uploader placeholders for full
  image imports.
- Treat `blueprint.image.url` as the preferred full-card source. `show_` images
  are allowed only as a fallback when the full source is missing or fails.
- Never use `preview_` images for full/card-detail images when
  `blueprint.image.url` or `blueprint.image.show.url` exists. Preview images
  belong only in `preview_image_url`.
- Before repairing existing CDN rows, compare the current R2 object dimensions
  against the preferred full source. Reupload only when the current image is
  materially lower resolution, or when an explicit source-metadata repair is
  requested.
- Try every usable full/show candidate before failing a row.
- Record all candidate download failures in the row failure message.
- Detect actual image format from bytes first, then response content type, then
  URL extension. Some CardTrader `.jpg` URLs return WebP bytes.
- Upload to R2 using the existing `<blueprint_id>_<slug>.<ext>` key format.
- Update Oracle `cardtrader_pokemon_blueprints`, `marketplace_cards`, and
  `marketplace_card_versions` for each imported row. The existing importer was
  originally Supabase-era; port database writes to Oracle before running it
  again.
- Do not run full projection refreshes during normal image-only import chunks;
  row-by-row projection updates are safer and avoid known timeout risks.
- Full card images are used for card detail and normal marketplace cards.
  Preview images under `previews/...` are intended for autocomplete/search
  suggestion thumbnails and low-cost grids, not as a substitute when a full
  CardTrader image is available.

Known fragility:

- Some CardTrader blueprint images are stale upstream. For those rows, both the
  full image URL and `show` URL can return `404`. Those are not CDN import
  failures; they need either a later CardTrader data refresh or a different
  upstream source.
- Row `389418` is the known example to retest after importer changes because it
  previously failed all candidates with upstream `404` responses.

Recommended repair run for missing CDN images:

```bash
FULL_IMAGE_MISSING_ONLY=1 FULL_IMAGE_NEWEST_FIRST=1 FULL_IMAGE_BATCH_SIZE=50 FULL_IMAGE_MAX_ROWS=1000 node scripts/import-cardtrader-full-images.js
```

Oracle full-source repair/reimport run:

```bash
ORACLE_IMAGE_MODE=full \
ORACLE_IMAGE_FORCE_FULL=1 \
ORACLE_IMAGE_FULL_KEY_SUFFIX=full-v3 \
ORACLE_IMAGE_BATCH_SIZE=50 \
ORACLE_IMAGE_MAX_ROWS=500 \
ORACLE_IMAGE_CURSOR_ID=-1 \
node scripts/import-oracle-cardtrader-images.js
```

Use a fresh `ORACLE_IMAGE_FULL_KEY_SUFFIX` when overwriting previously imported
low-resolution CDN rows so immutable CDN cache cannot serve the old object.

Quality audit/repair mode:

```bash
ORACLE_IMAGE_MODE=full \
ORACLE_IMAGE_AUDIT_QUALITY=1 \
ORACLE_IMAGE_SOURCE_MISMATCH_ONLY=1 \
ORACLE_IMAGE_PRODUCT_TYPE=card \
ORACLE_IMAGE_FULL_KEY_SUFFIX=full-v4 \
ORACLE_IMAGE_BATCH_SIZE=250 \
ORACLE_IMAGE_MAX_ROWS=1000 \
ORACLE_IMAGE_CURSOR_ID=0 \
node scripts/import-oracle-cardtrader-images.js
```

This mode downloads the preferred CardTrader full source and the current R2
object, reads both dimensions with `sharp`, and only reimports rows where the
current CDN full image is below `ORACLE_IMAGE_QUALITY_MIN_RATIO` of the source
pixel count. The default ratio is `0.85`.

If the CDN image dimensions are already acceptable but
`cardtrader_image_url` still points to an old `preview_` or `show_` source, leave
the row alone by default. Set `ORACLE_IMAGE_REPAIR_SOURCE_MISMATCH=1` only when
you intentionally want to rewrite source metadata and reupload equal-quality
objects.

## 2026-05-23 Preview-Derived Full Image Audit

Targeted verification after manually repairing row `274402`:

```text
ORACLE_IMAGE_MODE=full ORACLE_IMAGE_AUDIT_QUALITY=1 ORACLE_IMAGE_IDS=274402 node scripts/import-oracle-cardtrader-images.js
```

Result: row `274402` was skipped as `current-full-ok`, confirming the CDN/R2
object now matches the preferred CardTrader full source closely enough for the
quality audit.

Bounded source-mismatch audit/repair chunks:

```text
ORACLE_IMAGE_MODE=full \
ORACLE_IMAGE_AUDIT_QUALITY=1 \
ORACLE_IMAGE_SOURCE_MISMATCH_ONLY=1 \
ORACLE_IMAGE_PRODUCT_TYPE=card \
ORACLE_IMAGE_BATCH_SIZE=100 \
ORACLE_IMAGE_MAX_ROWS=500 \
ORACLE_IMAGE_CURSOR_ID=0 \
ORACLE_IMAGE_FULL_KEY_SUFFIX=full-audit-1779521232 \
node scripts/import-oracle-cardtrader-images.js
```

Result:

- Processed: `500`
- Imported/repaired: `7`
- Failed: `0`
- Resume cursor: `115531`
- Repaired IDs: `110992`, `111048`, `111287`, `111708`, `112917`, `114324`,
  `114326`

Second chunk:

```text
ORACLE_IMAGE_MODE=full \
ORACLE_IMAGE_AUDIT_QUALITY=1 \
ORACLE_IMAGE_SOURCE_MISMATCH_ONLY=1 \
ORACLE_IMAGE_PRODUCT_TYPE=card \
ORACLE_IMAGE_BATCH_SIZE=100 \
ORACLE_IMAGE_MAX_ROWS=500 \
ORACLE_IMAGE_CURSOR_ID=115531 \
ORACLE_IMAGE_FULL_KEY_SUFFIX=full-audit-1779521467 \
node scripts/import-oracle-cardtrader-images.js
```

Result:

- Processed: `500`
- Imported/repaired: `5`
- Failed: `0`
- Resume cursor: `120650`
- Repaired IDs: `117703`, `117717`, `117719`, `118760`, `120310`

Focused verification for the 12 repaired IDs returned `current-full-ok` for
every row.

Most skipped rows in both chunks were `current-full-ok-source-metadata-stale`:
their `cardtrader_image_url` metadata still pointed at an older preview/show
source, but the current R2 object dimensions already matched the preferred full
CardTrader source. They were intentionally left untouched.

Resume from the printed cursor:

```bash
FULL_IMAGE_MISSING_ONLY=1 FULL_IMAGE_NEWEST_FIRST=1 FULL_IMAGE_CURSOR_ID=<id> FULL_IMAGE_BATCH_SIZE=50 FULL_IMAGE_MAX_ROWS=1000 node scripts/import-cardtrader-full-images.js
```

Targeted retest:

```bash
FULL_IMAGE_IDS=389418 node scripts/import-cardtrader-full-images.js
```

## 2026-05-18 Repair run results

Targeted retest:

```text
FULL_IMAGE_IDS=389418 node scripts/import-cardtrader-full-images.js
```

Result:

- Imported: `0`
- Skipped: `0`
- Failed: `1`
- Finding: both CardTrader candidates returned upstream `404`.
- Failed candidates:
  - `https://cardtrader.com/uploads/blueprints/image/389418/lisia-s-appeal-csv9c-special-illustration-rare-257-208-csv9-stellar-crystal.png`
  - `https://cardtrader.com/uploads/blueprints/image/389418/show_lisia-s-appeal-csv9c-special-illustration-rare-257-208-csv9-stellar-crystal.png`

Newest-first missing-CDN chunk:

```text
FULL_IMAGE_MISSING_ONLY=1 FULL_IMAGE_NEWEST_FIRST=1 FULL_IMAGE_BATCH_SIZE=50 FULL_IMAGE_MAX_ROWS=300 node scripts/import-cardtrader-full-images.js
```

Result:

- Processed: `300`
- Imported: `0`
- Skipped: `299`
- Failed: `1`
- Resume cursor: `379106`
- Finding: newest missing rows mostly had no usable full-image candidate in the
  CardTrader blueprint payload. Row `389418` remained an upstream-stale `404`.

Oldest-first missing-CDN repair chunk:

```text
FULL_IMAGE_MISSING_ONLY=1 FULL_IMAGE_BATCH_SIZE=50 FULL_IMAGE_MAX_ROWS=1000 node scripts/import-cardtrader-full-images.js
```

Result:

- Processed: `1000`
- Imported: `946`
- Skipped: `54`
- Failed: `0`
- Resume cursor: `135937`
- Finding: older missing rows still contain many valid CardTrader full/show
  candidates. Continue oldest-first from cursor `135937` to repair more CDN
  gaps.

Second oldest-first missing-CDN repair chunk:

```text
FULL_IMAGE_MISSING_ONLY=1 FULL_IMAGE_CURSOR_ID=135937 FULL_IMAGE_BATCH_SIZE=50 FULL_IMAGE_MAX_ROWS=1000 node scripts/import-cardtrader-full-images.js
```

Result:

- Processed: `1000`
- Imported: `985`
- Skipped: `15`
- Failed: `0`
- Resume cursor: `138347`
- Finding: this older range had a very high repair rate. Continue oldest-first
  from cursor `138347` for the next cleanup pass.

## Related 2026-05-18 Expansion Symbol Import

Expansion symbols are handled by a separate importer:

```bash
DRY_RUN=1 PTCG_ASSETS_DIR=../ptcg-assets node scripts/import-ptcg-expansion-symbols.js
PTCG_ASSETS_DIR=../ptcg-assets node scripts/import-ptcg-expansion-symbols.js
```

That job reads `symbol.png` from `https://github.com/1niceroli/ptcg-assets`,
maps CardTrader expansion codes such as `bs`, `ju`, `blw`, `ssh`, and `svi` to
asset folder codes such as `base1`, `base2`, `bw1`, `swsh1`, and `sv1`, uploads
to R2 under `expansions/symbols/<expansion-name>.png`, and should upsert Oracle
`public.cardtrader_pokemon_expansions` after the cutover.

The first production symbol run uploaded 182 symbols. Direct HTTP checks against
`https://cdn.pokoin.com/...` returned `403` from this machine for both new symbol
paths and older image paths, so verify symbol imports through Oracle rows and
direct R2 `HeadObject` checks before assuming an object is missing.
