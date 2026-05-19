# CardTrader Search Preview Workflow

Use this workflow when changing marketplace autocomplete, CardTrader-style fuzzy
search, Oracle marketplace schema, or CDN preview thumbnails.

## Goal

The marketplace search should behave like CardTrader:

- Typing in `/marketplace` starts warming autocomplete candidates from the first
  meaningful character, but the visible autocomplete panel opens only after 3
  meaningful characters.
- The panel must be anchored to the top-bar search field and use the field
  width. Do not let it stretch across the viewport or cover the whole page.
- The preview candidate pool is a background working set, currently capped at
  `searchPreviewPoolLimit` (`1000` rows in Flutter). The popup renders only the
  best `searchPreviewLimit` (`20`) rows from that pool, with about 9 rows
  visible at a time and the rest reachable by scrolling.
- Results show a small preview image, card name plus collector/expansion number,
  set and action text. Example: `Mew ex #232/091`, not the rarity as the
  hashtag. Typed query terms should be highlighted inside the result title/set
  text.
- Search previews may be seeded from the loaded Flutter catalog, then merged
  with Oracle projection results through Vercel APIs.
- Numeric searches such as `mew 232` should wait for full Oracle projection
  results instead of showing weak local-cache-only suggestions from the capped
  home catalog.
- Compound searches should still show similar results. `mew 232` should rank the
  exact `Mew ex #232/091` match first, then fall back to the strongest text term
  (`mew`) so related singles/products can fill the 9-result panel.
- The full `/marketplace/search` page must query Oracle-backed APIs directly.
  Do not limit it to the 500-card marketplace/home catalog loaded in
  `CardState.cards`.
- Preview images live in the same R2 bucket as full card images under
  `previews/...`. Generated previews use `.webp`; CardTrader API preview imports
  currently preserve the downloaded preview bytes under `.jpg` keys.
- Flutter receives `preview_image_url` when available and falls back to the full
  card image when preview generation is incomplete.

## Target Search Architecture

CardTrader feels instantaneous because it does not treat every keystroke as a
fresh full-catalog search. Pokoin should move toward the same two-stage design,
then improve it with marketplace-specific signals.

### Stage 1: Warm Candidate Pool Before Reveal

- Start a quiet background candidate search from the first meaningful character.
  Do not render the visible autocomplete panel until the user has typed 3
  meaningful characters, except for explicit route/search-page loads.
- At 3 characters, reveal autocomplete from the warmed pool and continue querying
  indexed Oracle projections. Search fields should include:
  - `name`
  - `rarity`
  - `card_number` / `expansion_number`
  - `set_name` / `expansion_name`
  - `trainer_name`
  - `product_variant` for sealed/product rows
  - variation dimensions from `marketplace_variations` /
    `marketplace_card_variations`
  - product fields (`item_kind`, `product_type`) when looking for sealed items
- Keep this query against lightweight projection tables only:
  - `marketplace_cards` for autocomplete/home/full row payloads.
  - `marketplace_card_versions` for expansion navigation and single-card search.
  - Never parse full blueprint JSON during active typing.
- Use trigram/text indexes and small selected columns. The first pool should be
  larger than the UI limit but still bounded. Current production asks for up to
  1000 ranked autocomplete rows, stores them in Flutter, and displays only the
  best 20.

### Stage 2: Narrow The Pool Locally

- While the user keeps typing past the initial 3-character prefix, narrow the
  existing candidate pool locally first. Flutter is expected to handle the
  1000-row pool in memory and re-rank/filter it character by character.
- Do not show a loading reset or swap the popup surface on every keystroke after
  the 3-character prefix is loaded. The popup should remain stable and only
  become more accurate as the existing pool is filtered.
- Only hit Oracle/Vercel search again when:
  - The first 3-character prefix changes.
  - The current local pool is empty or too weak.
  - The selected language changes.
  - The query category changes materially, for example card search to product
    search.
- This avoids repeated full projection scans and keeps keystrokes feeling
  instant.

### Popularity-Aware Pool Cache

- Store/search-count signals so popular cards and products warm up faster.
- Candidate pools can be cached by normalized 3-character prefix plus language
  and product scope:
  - `prefix = normalizedQuery.substring(0, 3)`
  - `language = selected search language`
  - `scope = singles | products | all`
- Cache rows should track usage signals such as:
  - `search_count`
  - `click_count`
  - `cart_add_count`
  - `last_searched_at`
  - `last_clicked_at`
- Ranking should combine textual relevance with these signals, but relevance
  must still win for exact collector-number and exact name matches.
- This is especially useful because many users repeatedly search popular cards
  such as Charizard, Pikachu, Mew, Umbreon, and key sealed products.

### Trainer-Aware Matching

- Trainer names belong in their own structured field, not only as free text in
  card names.
- `marketplace_cards.trainer_name` and
  `marketplace_card_versions.trainer_name` should be indexed and filled by
  projection refreshes.
- `marketplace_trainers` should hold a small canonical trainer list plus aliases,
  because the list is small and stable compared with cards. Example aliases:
  - `Cynthia`: `Camilla`, `Shirona`, `C`
  - `Misty`: `Ondine`, `Kasumi`
  - `Brock`: `Pierre`, `Takeshi`
- Query normalization should rewrite owner phrases into exact variants:
  - `garchomp di camilla`
  - `garchomp cynthia`
  - `cynthia garchomp`
  - `Cynthia's Garchomp`
- Do not run broad fuzzy matching across every language. Use selected-language
  search plus small deterministic alias expansion.

### Multilingual Search Boundary

- TCGdex is useful for language-scoped card-name translation. It supports a
  multilingual Pokemon TCG API with more than 10 languages according to the
  [TCGdex API docs](https://tcgdex.dev/?ref=api.tcgdex.net).
- Use TCGdex only for the selected language, then map localized names back to
  English/internal search variants.
- Do not search all supported languages at once. That creates too many false
  positives and ruins ranking.
- Trainer aliases should remain small, curated, and deterministic. They are not
  a replacement for TCGdex card-name localization.

### Implementation Target

Future implementation should introduce a dedicated candidate-pool layer:

```text
User types "g"
  -> quiet remote warmup starts

User types "gar"
  -> visible autocomplete opens from the warmed pool
  -> remote indexed search builds/refines pool for prefix "gar"
  -> cache pool under (gar, language, scope)

User types "garch"
  -> filter/rank cached "gar" pool locally
  -> no network request unless pool is weak

User types "garchomp di camilla"
  -> deterministic aliases add Cynthia variants
  -> search/rank against name + trainer_name + expansion fields
```

The UI should render a 9-row viewport over the best 20 candidates selected from
the larger background pool, so the panel stays compact while local filtering can
continue to improve results as the user types.

## Current Production Workflow

As of 2026-05-19, marketplace autocomplete uses a broad remote seed plus local
refinement:

```text
User types 1-2 meaningful chars
  -> Flutter starts warming a candidate pool quietly from the first meaningful char
  -> visible popup stays closed

User types 3 meaningful chars
  -> Flutter requests `/api/marketplace-autocomplete` with result_limit=1000
     and pool_limit=1000
  -> autocomplete calls Oracle tokenized search through
     `/api/marketplace-search-candidates` helpers, ranks the database pool, and
     returns up to 1000 candidates
  -> Flutter caches the returned 1000-row pool under the normalized
     3-character key
  -> the popup renders the best `searchPreviewLimit` rows

User keeps typing
  -> Flutter narrows and re-ranks the cached 1000-row pool locally
  -> no new remote request is needed while the prefix pool is useful
  -> character coverage and typo tolerance affect ranking
  -> the highlighter marks both full terms and ordered single-character matches
```

The remote fuzzy search is not the final ranker for every keystroke. Its job is
to identify and roughly order a useful background candidate pool from the
lightweight `public.marketplace_search_candidates` projection. After that, the
app performs fast interactive narrowing locally in Dart and only renders the top
20 visible suggestions.

### Vercel Aggregation Endpoint

Use Vercel for the server-side search adapter because `pokoin.com` is already
deployed there and Vercel can hold `MARKETPLACE_DATABASE_URL` outside the
browser.

Production preview endpoint:

```text
POST /api/marketplace-autocomplete
```

Request body used by Flutter preview warmup:

```json
{
  "search_term": "miraidon",
  "result_limit": 1000,
  "pool_limit": 1000,
  "search_language": "en"
}
```

The endpoint ranks the Oracle candidate pool server-side, prioritizing Pokemon
identity/name matches before expansion, set, product, or rarity-only noise. It
returns the background pool to Flutter; Flutter stores it and shows only the
best 20 rows after local narrowing.

Production raw candidate endpoint:

```text
POST /api/marketplace-search-candidates
```

Request body:

```json
{
  "search_term": "pillu",
  "result_limit": 1000,
  "result_offset": 0
}
```

The raw candidate endpoint lives in `api/marketplace-search-candidates.js`.
Autocomplete ranking lives in `api/marketplace-autocomplete.js`. Both are
copied into `build/web/api` by `deploy-pokoin-web.sh`. Keep the matching routes
in `vercel.json`.

The endpoint uses Oracle marketplace Postgres directly through `pg` and calls
`public.search_marketplace_blueprint_candidates_v2(...)`. Supabase remains for
forum APIs only.

### Oracle Marketplace Database Notes

Vercel needs `MARKETPLACE_DATABASE_URL` with `sslmode=require`. Classic Vercel
serverless outbound IPs are not stable enough for strict allowlisting, so use
Vercel static egress/secure compute if a hard IP allowlist is required.

Environment names supported by the marketplace Vercel endpoints:

- `MARKETPLACE_DATABASE_URL`
- `MARKETPLACE_DATABASE_POOL_MAX` optional
- `MARKETPLACE_DATABASE_SSL_VERIFY=1` optional for trusted server certificates

Forum endpoints still use `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and
`SUPABASE_SERVICE_ROLE_KEY`.

### Local Ranking And Highlighting

Keep ranking and highlighting aligned. Users expect stronger character coverage
to move results upward as they type, and they expect the same characters to be
visible in the popup.

Relevant behavior:

- `lib/services/card_service.dart` fetches the broad autocomplete candidate pool
  from `/api/marketplace-autocomplete`.
- `lib/providers/card_provider.dart` stores the 1000-row preview pool and
  narrows it locally as the query grows. `state.searchPreviews` should contain
  only the currently visible top 20, not the full background pool.
- `lib/screens/home_screen.dart` renders title/set highlights. It must merge
  full-term ranges with ordered single-character ranges; do not only highlight
  complete words.
- `test/card_service_test.dart` covers the character coverage ranking behavior.

For example, a query such as `pillu` can return candidates whose database fuzzy
score is close enough for the initial pool. The visible row text should still
highlight ordered characters when full token highlighting cannot explain the
local match.

### Variation-Aware Search

Pokemon card variations are structured Oracle search dimensions, not just fuzzy
text. Keep canonical variation metadata in `marketplace_variations` and card
membership in `marketplace_card_variations`.

Current seeded variation keys include `ex`, `v`, `vmax`, `vstar`, `gx`, `lvx`,
`mega`, `delta`, `gold_star`, `shining`, `radiant`, `prime`, `break`,
`tag_team`, and `ace_spec`.

Important ranking rules:

- A standalone `v` token is meaningful and should be weighted like other exact
  variation tokens such as `ex`, `gx`, and `vmax`.
- Avoid broad one-letter prefix matching for names, translated names, or
  expansions. Otherwise query `v` can match almost every name/set starting with
  `v` and drown out actual `... V` cards.
- Variation tagging should use card identity fields only: `name`, `card_number`,
  `rarity`, `card_type`, and `product_variant`. Do not tag from `set_name`,
  `expansion_name`, or broad `search_text`; sets like `Shiny Star V` would make
  non-V cards look like V cards.
- Combined searches should reward name plus variation matches. Examples:
  `darkrai v` should rank `Darkrai V` before generic V cards, and
  `azief lv x` should still find `Azelf LV.X`.

### Candidate Pool Size

`searchPreviewPoolLimit` is currently `1000` in
`lib/providers/card_provider.dart`. This is the background pool size, not the
number of rows shown in the UI.

For a query like `pillu`, production returned 888 candidates during smoke
testing because the SQL function found 888 candidates that matched its filters.
The endpoint can ask for 1000, but it cannot invent rows outside the SQL
candidate definition. If Oracle returns fewer matches, Flutter caches the
smaller returned pool.

If the user asks for lower latency, reduce the pool cap first or add a
popularity/prefix cache. Do not remove local narrowing; that is what keeps
continued typing responsive.

## Files Involved

- `lib/screens/home_screen.dart`
  - Search input and CardTrader-style preview dropdown. The dropdown uses a
    `CompositedTransformFollower`, the search field width, and a short delayed
    close so row clicks are not swallowed by focus loss.
- `lib/providers/card_provider.dart`
  - Local preview ranking, async search preview state, 1000-row background pool,
    20-row visible previews, and stale request guard.
- `lib/services/card_service.dart`
  - Oracle-backed marketplace API loading, projection search, preview image
    mapping and fallback behavior. `searchCardPreviews` uses
    `/api/marketplace-search-candidates` for broad pools.
- `lib/models/pokemon_card.dart`
  - `previewImageUrl`, defaulting to `imageUrl`, plus structured marketplace
    fields such as `itemKind`, `productType`, and `trainerName`.
- `api/marketplace-search-candidates.js`
  - Vercel serverless search adapter. It calls Oracle Postgres through `pg` and
    `public.search_marketplace_blueprint_candidates_v2(...)`.
- `api/marketplace-autocomplete.js`
  - Server-side autocomplete ranking over the Oracle candidate pool. It should
    be able to return the full background pool requested by Flutter, not only
    the visible row count.
- `api/marketplace-cards.js` and `api/marketplace-card-versions.js`
  - Oracle-backed catalog/product and expansion/version rows used by Flutter.
- `vercel.json`
  - Routes `/api/marketplace-search-candidates` to the serverless function.
- `deploy-pokoin-web.sh`
  - Copies the search endpoint into `build/web/api` before Vercel deployment.
- `oracle-postgres/schema/*.sql`
  - Oracle marketplace schema, projection refreshes, tokenized search
    dimensions, variation dimensions, home snapshot, and autocomplete/search
    RPCs.
- `scripts/oracle-marketplace-migrate.js`
  - Applies schema, copies non-forum data from Supabase during migration,
    refreshes projections, and verifies searches.
- `scripts/generate-cardtrader-preview-images.js`
  - Legacy Supabase-era preview generator. Port database writes to Oracle before
    running again.
- `scripts/import-cardtrader-preview-images.js`
  - Legacy Supabase-era CardTrader preview importer. Keep the R2 behavior, but
    port database writes to Oracle before running again.
- `scripts/import-ptcg-expansion-symbols.js`
  - Legacy Supabase-era expansion symbol importer. Port writes to Oracle
    `cardtrader_pokemon_expansions` before running again.

## Required Env

Read these from `.env.local`. Never print the values.

- `MARKETPLACE_DATABASE_URL`
- `SUPABASE_DB_URL` only for migration/copy or guarded cleanup
- `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` for forum
  APIs and old one-off import scripts only
- `CLOUDFLARE_ACCOUNT_ID`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `POKOIN_CARD_IMAGES_BUCKET`
- `POKOIN_CARD_CDN_BASE_URL`

## Oracle Migration Procedure

Marketplace/catalog/search schema now lives in `oracle-postgres/schema`.
Supabase marketplace migrations are historical and should not receive new
marketplace work.

```bash
node scripts/oracle-marketplace-migrate.js schema
node scripts/oracle-marketplace-migrate.js refresh
node scripts/oracle-marketplace-migrate.js verify
```

## Expansion Symbol Import

Expansion symbols are imported from
`https://github.com/1niceroli/ptcg-assets`. Each source expansion folder
contains `symbol.png`; the importer maps CardTrader expansion codes/names to
those source folders and writes the symbol to R2 as:

```bash
expansions/symbols/<cardtrader-expansion-name>.png
```

After porting, the importer should upsert Oracle
`public.cardtrader_pokemon_expansions`, storing the CardTrader expansion id,
CardTrader code/name, matched source asset code, CDN URL, and R2 object key.

Run from the project root:

```bash
git clone --depth 1 https://github.com/1niceroli/ptcg-assets.git ../ptcg-assets
DRY_RUN=1 PTCG_ASSETS_DIR=../ptcg-assets node scripts/import-ptcg-expansion-symbols.js
PTCG_ASSETS_DIR=../ptcg-assets node scripts/import-ptcg-expansion-symbols.js
```

The first production run on 2026-05-18 uploaded 182 symbols. Verification was
done through database rows and direct R2 `HeadObject` checks. Local HTTP checks
against `https://cdn.pokoin.com/...` returned `403` for both new symbol paths
and pre-existing preview paths, so do not treat that local CDN check alone as
proof that an object is missing.

## Verify Fuzzy Search

Run app-shaped Oracle/Vercel checks. Do not add DB-side ordering to active
search queries unless it has been tested with compound numeric searches; client
ranking should sort active search results.

```bash
python3 - <<'PY'
import json, time, urllib.request

for term in ['pika uni', 'mew 232', 'porygon', 'char ex', 'v', 'darkrai v', 'azief lv x']:
    body = json.dumps({'search_term': term, 'result_limit': 20}).encode()
    req = urllib.request.Request(
        'https://pokoin.com/api/marketplace-search-candidates',
        data=body,
        headers={'content-type': 'application/json'},
        method='POST',
    )
    start = time.time()
    with urllib.request.urlopen(req, timeout=20) as res:
        rows = json.loads(res.read().decode())
    print(term, 'rows=', len(rows), 'ms=', round((time.time() - start) * 1000))
PY
```

Known healthy result: terms return rows in hundreds of milliseconds and do not
depend on the capped Flutter home catalog. `pika uni` should include
`Pikachu | Unified Minds`; `mew 232` should include
`Mew ex | Paldean Fates | Special Illustration Rare | 232/091`; `v` should
return actual `... V` cards; `darkrai v` should rank `Darkrai V` first; and
`azief lv x` should rank `Azelf LV.X`.

Old Supabase RPCs may still exist until cleanup runs, but new UI work should use
the Oracle-backed marketplace APIs because they avoid parsing heavy blueprint
JSON in Flutter.

## Generate Preview Images

These importers were written before the Oracle marketplace cutover and still
write to Supabase. Do not run them again until their database writes target
Oracle Postgres. R2 upload behavior can stay the same.

Preview generation is long because it covers every CardTrader blueprint image.
Prefer `import-cardtrader-preview-images.js` when you specifically want the
preview image exposed by CardTrader's API. Use the generated WebP script when
you want previews resized from our full CDN-hosted card images.

Run a targeted CardTrader API preview import first:

```bash
PREVIEW_IDS=274416,254235 node scripts/import-cardtrader-preview-images.js
```

Prioritize new CardTrader rows that do not have previews yet:

```bash
PREVIEW_MISSING_ONLY=1 PREVIEW_NEWEST_FIRST=1 PREVIEW_BATCH_SIZE=100 PREVIEW_MAX_ROWS=1000 node scripts/import-cardtrader-preview-images.js
```

For newest-first missing-only runs, the importer prints `next cursor <id>`.
Resume from that cursor:

```bash
PREVIEW_MISSING_ONLY=1 PREVIEW_NEWEST_FIRST=1 PREVIEW_CURSOR_ID=<id> PREVIEW_BATCH_SIZE=100 PREVIEW_MAX_ROWS=1000 node scripts/import-cardtrader-preview-images.js
```

After porting, the importer should store `preview_object_key` on Oracle
`cardtrader_pokemon_blueprints`; projection tables receive `preview_image_url`.
Homepage/grid/card widgets should use `previewImageUrl` first and pass the full
`imageUrl` as a fallback. This protects old recent-view entries and cards whose
preview import has not completed yet.

Run the small batch first:

```bash
PREVIEW_MAX_ROWS=5 PREVIEW_BATCH_SIZE=5 node scripts/generate-cardtrader-preview-images.js
```

Then run the full batch:

```bash
node scripts/generate-cardtrader-preview-images.js
```

Progress prints every 100 rows:

```text
processed 100, generated 95
processed 200, generated 195
```

Known status when this workflow was written:

- Total rows with card images: `41099`
- Preview rows generated at last check: `1500`
- The full job was still running and healthy.

The following historical Supabase progress check is not valid after Oracle
cutover. Port it to Oracle before use:

```bash
node scripts/oracle-marketplace-migrate.js verify
```

Verify a generated preview through the app proxy:

```bash
curl -L -I "https://pokoin.com/card-images/previews/<preview-key>.webp"
```

Expected:

- HTTP `200`
- `content-type: image/webp`

## Import Full CardTrader Images

The production image source should be our R2 bucket behind
`https://cdn.pokoin.com`, not CardTrader URLs. When CardTrader exposes a
higher-resolution blueprint image, import that source into R2 and keep the app
using the same `/card-images/...` proxy format.

For the dated operational report that preserves importer behavior, known
fragilities, and retest commands, see
`workflows/cardtrader-full-image-import-report.md`.

Run a targeted Oracle import first:

```bash
ORACLE_IMAGE_IDS=274416 node scripts/import-oracle-cardtrader-images.js
```

CardTrader is an import source only. Do not leave `cardtrader.com` URLs in
runtime image columns. The Oracle importer must download CardTrader assets,
upload them to R2, and write CDN URLs into Oracle before the app sees the row.

The importer:

- Reads `blueprint.image.url` and `blueprint.image.show.url` from
  `cardtrader_pokemon_blueprints`, trying each usable candidate before failing a
  row.
- Downloads the full CardTrader image, ignoring `/preview_` sources.
- Detects the actual image format from magic bytes and response headers before
  choosing the R2 object extension/content type. Do not trust CardTrader URL
  extensions; some `.jpg` URLs return WebP bytes.
- Uploads the bytes to R2 using the existing `<blueprint_id>_slug.ext` key
  format with the detected extension.
- Updates Oracle `cardtrader_pokemon_blueprints.image_url`,
  `cdn_image_url`, `cdn_object_key`, `preview_image_url`, and
  `preview_object_key` with CDN-backed values.
- Updates Oracle projections directly so homepage/search/card detail APIs never
  serve CardTrader-hosted image URLs.
- Does not store CardTrader source URLs by default. Only set
  `ORACLE_IMAGE_KEEP_SOURCE_URLS=1` for a deliberate audit/debug run.

Verify through the app proxy:

```bash
curl -L -I "https://pokoin.com/card-images/274416_mew-ex-special-illustration-rare-232-091-paldean-fates.jpg"
```

Expected:

- HTTP `200`
- `content-type: image/jpeg`
- A full-image `content-length` larger than the old preview-derived object.

Run the full job in resumable chunks:

```bash
ORACLE_IMAGE_BATCH_SIZE=50 ORACLE_IMAGE_MAX_ROWS=1000 node scripts/import-oracle-cardtrader-images.js
```

Prioritize new CardTrader rows that do not have CDN images yet:

```bash
ORACLE_IMAGE_NEWEST_FIRST=1 ORACLE_IMAGE_BATCH_SIZE=50 ORACLE_IMAGE_MAX_ROWS=1000 node scripts/import-oracle-cardtrader-images.js
```

For older missing rows, run oldest-first chunks. This has found product rows with
valid CardTrader images that were missed by newer-first imports:

```bash
FULL_IMAGE_MISSING_ONLY=1 FULL_IMAGE_BATCH_SIZE=50 FULL_IMAGE_MAX_ROWS=300 node scripts/import-cardtrader-full-images.js
```

If a row still fails after all candidates are tried, inspect CardTrader directly.
Some blueprint image URLs are stale and return `404` for both full and `show_`
variants; those are upstream-broken rather than CDN import failures.

If the regular full-catalog job stops after printing `next offset 1000`,
resume with:

```bash
FULL_IMAGE_OFFSET=1000 FULL_IMAGE_BATCH_SIZE=50 FULL_IMAGE_MAX_ROWS=1000 node scripts/import-cardtrader-full-images.js
```

For newest-first missing-only runs, the importer prints `next cursor <id>`.
Keep the same mode flags and resume from that cursor:

```bash
FULL_IMAGE_MISSING_ONLY=1 FULL_IMAGE_NEWEST_FIRST=1 FULL_IMAGE_CURSOR_ID=<id> FULL_IMAGE_BATCH_SIZE=50 FULL_IMAGE_MAX_ROWS=1000 node scripts/import-cardtrader-full-images.js
```

Do not set `REFRESH_MARKETPLACE_PROJECTIONS=1` for normal full-image imports.
The full projection RPCs can time out on the whole catalog, and image-only
changes are already synced row-by-row by the importer.

## Deploy Web Changes

Always use the project deploy script after changing Flutter/app/API code:

```bash
./deploy-pokoin-web.sh
```

Do not run plain `vercel deploy` from the project root. It can deploy an
incomplete output without the Flutter build, API files, or Dart defines.
Do not assume a git push or workflow/doc commit updates `pokoin.com`.

## Verification Checklist

Before deploy:

```bash
dart format lib/models/pokemon_card.dart lib/models/pokemon_card.g.dart lib/services/card_service.dart lib/providers/card_provider.dart lib/screens/home_screen.dart test/card_service_test.dart
node --check scripts/generate-cardtrader-preview-images.js
python3 -m json.tool vercel.json >/dev/null
python3 -m json.tool web/vercel.json >/dev/null
flutter analyze
flutter test
```

After deploy:

```bash
curl -L -s "https://pokoin.com/main.dart.js" -o /tmp/pokoin-main-search.js
python3 - <<'PY'
from pathlib import Path
text = Path('/tmp/pokoin-main-search.js').read_text(errors='ignore')
for marker in [
    'marketplace_card_versions',
    'marketplace_cards',
    'preview_image_url',
    'expansion_number',
    'isSearchingPreviews',
    '/card-images',
]:
    print(f'{marker}={marker in text}')
PY
```

Also verify:

```bash
curl -L -I "https://pokoin.com/marketplace"
curl -L -I "https://pokoin.com/marketplace/search?q=Steven"
curl -L -I "https://pokoin.com/card-images/<known-card-image>"
curl -L -I "https://pokoin.com/card-images/previews/<known-preview-image>"
```

If `HEAD` returns `403` for image routes, verify with a normal `GET` before
assuming the image is broken. Some CDN/proxy paths serve `GET` correctly while
rejecting `HEAD`.

Then open `https://pokoin.com/marketplace`, hard refresh if needed, and verify:

- Search suggestions for `mew 232` include Mew ex `232/091`.
- Search suggestions for `mew 232` also include similar Mew results after the
  exact match, capped at 20 candidates with about 9 visible at once.
- Search suggestion rows can be clicked reliably; if clicks fail, inspect focus
  loss/removal timing in `_MarketplaceTopSearchState`.
- The popup width matches the search bar width.
- Search suggestions show card name plus collector/expansion number.
- Search suggestions for `pika uni` include Pikachu from Unified Minds.

## Important Failure Modes

- Historical Supabase marketplace migration notes are no longer the production
  path. New marketplace schema/search changes belong in
  `oracle-postgres/schema/*.sql`.
- The Oracle tokenized search RPC must keep key smoke queries fast:
  `porygon`, `piachu 151`, `char ex`, `v`, `darkrai v`, `azief lv x`, and
  `mew special illustration rare`.
- If a short variation query such as `v` returns non-V cards first, inspect
  `marketplace_card_variations` population before adjusting UI ranking. The
  usual cause is tagging variations from expansion/search text instead of card
  identity fields.
- Preview generation is resumable. Existing `preview_image_url` rows are skipped
  unless `PREVIEW_FORCE=1` is set.
- The Flutter app must tolerate missing `preview_image_url`. Do not remove the
  fallback to `imageUrl`.
- Search preview rows should include the collector/expansion number next to the
  card name when present. Do not show opaque CardTrader blueprint IDs as if they
  were collector numbers for real singles.
- If `mew 232` returns rows in Oracle verify but the UI shows nothing,
  inspect the app request shape and deployed bundle before changing the ranking.
  Common causes are stale production builds, browser cache, DB-side ordering on
  active search, or local cached suggestions masking the remote full-catalog
  result.
- If the popup contains only one exact compound match, verify the similar-query
  fallback in `CardService.searchCardPreviews(...)` still runs and that
  `CardNotifier._loadSearchPreviews(...)` asks for 15 results.
- The full search page is intentionally separate from the home catalog. If it
  returns only a few cards while Oracle has more matches, check that it is
  calling `CardService.searchMarketplaceCards(...)` instead of filtering
  `state.filteredCards`.
