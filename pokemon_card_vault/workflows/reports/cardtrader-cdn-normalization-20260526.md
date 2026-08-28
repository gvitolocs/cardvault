# CardTrader CDN Normalization Report - 2026-05-26

## Cause

The non-normalized URL pattern came from the raw CardTrader blueprint/delta import
that preserved `blueprint.image_url` into Oracle `image_url`/source metadata
before the image pipeline had copied or uploaded an R2 object. CardTrader fallback
blueprints share the same URL:

```text
https://cardtrader.com/fallbacks/card_uploader/preview.png
```

That URL is not unique per blueprint and must not be used as a lookup key or
served marketplace CDN/image URL.

## Audit Snapshot

- Oracle `public.cardtrader_pokemon_blueprints`: `72,056` rows.
- Rows mentioning the CardTrader fallback placeholder anywhere in image/source
  fields: `1,192`.
- Metadata-only fallback rows: `1,191`; all imported on `2026-05-17`, with no
  `cdn_image_url`, `cdn_object_key`, `preview_image_url`, or `homepage_image_url`.
- Served marketplace fallback row: `1` (`390877`, `Chien-Pao`, `CSV9C | Master
  Ball Reverse | 053/208`) had the CardTrader fallback in `image_url` and was
  projected into `marketplace_cards`, `marketplace_card_versions`, and
  `marketplace_search_candidates`.
- Generic R2 object keys found in Oracle image object columns: `0`.
- CDN object keys not prefixed by blueprint id: `0`.

## Normalization Rule

Served image fields must point to Pokoin CDN/R2 only. When a source URL has a
generic basename such as `preview.png`, upload/copy it first under:

```text
<blueprint_id>_<slug(name-version-set)>.<source-ext>
```

Then update `image_url`, `cdn_image_url`, `cdn_object_key`, and projection table
copies. Keep the original CardTrader URL only as source metadata.

## Implementation

- Added `scripts/normalize-oracle-cardtrader-fallback-cdn-images.js` for dry-run
  and apply normalization with a JSON report.
- Hardened `scripts/cardtrader-delta-import.js` and
  `scripts/cardtrader-multigame-import.js` so future raw imports do not persist
  `/fallbacks/card_uploader/preview.png` into `image_url`.
- Documented the guardrail in `workflows/oracle-marketplace-postgres-workflow.md`
  and `workflows/cardtrader-search-preview-workflow.md`.

## Verification Notes

Use:

```bash
node scripts/normalize-oracle-cardtrader-fallback-cdn-images.js --limit=all
node scripts/normalize-oracle-cardtrader-fallback-cdn-images.js --apply --ids=390877
node scripts/verify-marketplace-card-urls.js --ids=390877 --limit=1
```

Applied result:

- All `1,192` CardTrader fallback source rows now have normalized R2 object keys
  and Pokoin CDN URLs.
- `390877` was the only row that had the fallback in a served field; it was
  uploaded to R2 as
  `390877_chien-pao-csv9c-master-ball-reverse-053-208-csv9-master-ball-reverse.png`.
- Oracle `cdn_image_url` and `cdn_object_key` now point to normalized Pokoin CDN
  objects for every fallback source row; `image_url` was updated where needed.
- Projection fallback URL counts are now `0` for `marketplace_cards`,
  `marketplace_card_versions`, and `marketplace_search_candidates`.
- R2 `HeadObject` samples returned `image/png`, `3,674` bytes.
- Public HTTP checks from this machine returned `403` for both the new object and
  a known existing card image, so public CDN reachability was not a reliable
  local verifier; use R2 head checks and app-side image proxy checks.
- TrainingAI best-images manifest was regenerated locally and now includes
  all `1,192` fallback rows with source `r2_best`; Wrangler upload was blocked by
  missing `CLOUDFLARE_API_TOKEN` in the non-interactive environment.

Do not delete old R2/CDN objects or CardTrader source URLs while references may
still exist.
