# CardTrader Search Preview Workflow

Use this workflow when changing the marketplace autocomplete, CardTrader fuzzy
search, Supabase blueprint schema, or CDN preview thumbnails.

## Goal

The marketplace search should behave like CardTrader:

- Typing in `/marketplace` opens an autocomplete panel.
- The panel must be anchored to the top-bar search field and use the field
  width. Do not let it stretch across the viewport or cover the whole page.
- The preview panel is capped at 15 mixed results and can contain both singles
  and products.
- Results show a small preview image, card name plus collector/expansion number,
  set and action text. Example: `Mew ex #232/091`, not the rarity as the
  hashtag.
- Search previews may be seeded from the loaded Flutter catalog, then merged
  with Supabase projection results.
- Numeric searches such as `mew 232` should wait for full Supabase projection
  results instead of showing weak local-cache-only suggestions from the capped
  home catalog.
- Compound searches should still show similar results. `mew 232` should rank the
  exact `Mew ex #232/091` match first, then fall back to the strongest text term
  (`mew`) so related singles/products can fill the 15-result panel.
- The full `/marketplace/search` page must query Supabase projections directly.
  Do not limit it to the 500-card marketplace/home catalog loaded in
  `CardState.cards`.
- Preview images live in the same R2 bucket as full card images under
  `previews/...`. Generated previews use `.webp`; CardTrader API preview imports
  currently preserve the downloaded preview bytes under `.jpg` keys.
- Flutter receives `preview_image_url` when available and falls back to the full
  card image when preview generation is incomplete.

## Files Involved

- `lib/screens/home_screen.dart`
  - Search input and CardTrader-style preview dropdown. The dropdown uses a
    `CompositedTransformFollower`, the search field width, and a short delayed
    close so row clicks are not swallowed by focus loss.
- `lib/providers/card_provider.dart`
  - Local preview ranking, async search preview state, 15-result preview limit,
    and stale request guard.
- `lib/services/card_service.dart`
  - Supabase catalog loading, projection search, preview image mapping and
    fallback behavior. `searchCardPreviews` merges exact remote/local results
    with a similar-query fallback for compound searches.
- `lib/models/pokemon_card.dart`
  - `previewImageUrl`, defaulting to `imageUrl`.
- `supabase/migrations/20260518070000_cardtrader_search_previews.sql`
  - Adds preview columns, trigram support and initial RPC.
- `supabase/migrations/20260518073000_optimize_cardtrader_search.sql`
  - Optimizes the RPC to avoid statement timeouts.
- `supabase/migrations/20260518090000_marketplace_projection_analytics.sql`
  - Creates `marketplace_cards` and `marketplace_card_events`.
- `supabase/migrations/20260518103000_card_version_navigation.sql`
  - Creates `marketplace_card_versions` and its refresh function.
- `supabase/migrations/20260518104000_fix_expansion_navigation_scope.sql`
  - Keeps expansion navigation scoped to exact expansion name.
- `supabase/migrations/20260518164500_cardtrader_expansion_symbols.sql`
  - Creates `cardtrader_pokemon_expansions` for imported expansion symbol URLs.
- `scripts/generate-cardtrader-preview-images.js`
  - Generates WebP previews with `sharp`, uploads to R2, updates Supabase rows.
- `scripts/import-cardtrader-preview-images.js`
  - Imports CardTrader API preview images directly, uploads them to R2 under
    `previews/...jpg`, updates blueprint and marketplace projection rows.
- `scripts/import-ptcg-expansion-symbols.js`
  - Imports `symbol.png` files from `ptcg-assets`, maps CardTrader expansion
    codes/names to asset folder codes, uploads to R2, and upserts
    `cardtrader_pokemon_expansions`.

## Required Env

Read these from `.env.local`. Never print the values.

- `SUPABASE_PROJECT_REF`
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_DB_URL`
- `CLOUDFLARE_ACCOUNT_ID`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `POKOIN_CARD_IMAGES_BUCKET`
- `POKOIN_CARD_CDN_BASE_URL`

## Supabase Migration Procedure

Do not use the direct DB URL blindly. On this machine the direct host
`db.<project-ref>.supabase.co:5432` can resolve to IPv6 and fail with
`no route to host`.

1. Link the project with the DB password extracted from `SUPABASE_DB_URL`.

   ```bash
   PROJECT_REF="$(python3 - <<'PY'
from pathlib import Path
for line in Path('.env.local').read_text().splitlines():
    stripped = line.strip()
    if not stripped or stripped.startswith('#') or '=' not in stripped:
        continue
    name, value = stripped.split('=', 1)
    if name.removeprefix('export ').strip() == 'SUPABASE_PROJECT_REF':
        print(value.strip().strip('"').strip("'"))
        break
PY
)"

   DB_PASSWORD="$(python3 - <<'PY'
from pathlib import Path
from urllib.parse import urlparse
for line in Path('.env.local').read_text().splitlines():
    stripped = line.strip()
    if not stripped or stripped.startswith('#') or '=' not in stripped:
        continue
    name, value = stripped.split('=', 1)
    if name.removeprefix('export ').strip() == 'SUPABASE_DB_URL':
        print(urlparse(value.strip().strip('"').strip("'")).password or '')
        break
PY
)"

   supabase link --project-ref "$PROJECT_REF" --password "$DB_PASSWORD"
   ```

2. Check local and remote migration history.

   ```bash
   supabase migration list
   ```

3. If remote has orphan migrations that are not in this repo, repair only the
   migration history, not the schema/data. The known orphan versions from the
   first setup were:

   ```bash
   supabase migration repair --status reverted 20260517185705 20260517190827
   ```

4. Push migrations.

   ```bash
   supabase db push
   ```

5. Verify history is aligned.

   ```bash
   supabase migration list
   ```

Expected aligned versions:

- `20260517184500`
- `20260518070000`
- `20260518073000`
- Later marketplace projection versions may also be present, including
  `20260518090000`, `20260518100000`, `20260518101000`, `20260518102000`,
  `20260518103000`, and `20260518104000`.

After blueprint imports or classifier/navigation migrations, refresh the
projection tables:

```sql
select public.refresh_marketplace_cards_from_blueprints();
select public.refresh_marketplace_card_versions();
```

## Expansion Symbol Import

Expansion symbols are imported from
`https://github.com/1niceroli/ptcg-assets`. Each source expansion folder
contains `symbol.png`; the importer maps CardTrader expansion codes/names to
those source folders and writes the symbol to R2 as:

```bash
expansions/symbols/<cardtrader-expansion-name>.png
```

The importer also upserts `public.cardtrader_pokemon_expansions`, storing the
CardTrader expansion id, CardTrader code/name, matched source asset code, CDN
URL, and R2 object key.

Run from the project root:

```bash
git clone --depth 1 https://github.com/1niceroli/ptcg-assets.git ../ptcg-assets
DRY_RUN=1 PTCG_ASSETS_DIR=../ptcg-assets node scripts/import-ptcg-expansion-symbols.js
PTCG_ASSETS_DIR=../ptcg-assets node scripts/import-ptcg-expansion-symbols.js
```

The first production run on 2026-05-18 uploaded 182 symbols. Verification was
done through Supabase rows and direct R2 `HeadObject` checks. Local HTTP checks
against `https://cdn.pokoin.com/...` returned `403` for both new symbol paths
and pre-existing preview paths, so do not treat that local CDN check alone as
proof that an object is missing.

## Verify Fuzzy Search

Run app-shaped projection-search checks with the anon key. Do not add DB-side
ordering to active search queries unless it has been tested with compound
numeric searches; client ranking should sort active search results.

```bash
python3 - <<'PY'
from pathlib import Path
import json, urllib.parse, urllib.request, time

def env_value(key):
    for line in Path('.env.local').read_text().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith('#') or '=' not in stripped:
            continue
        name, value = stripped.split('=', 1)
        if name.removeprefix('export ').strip() == key:
            return value.strip().strip('"').strip("'")
    return ''

url = env_value('SUPABASE_URL').rstrip('/')
key = env_value('SUPABASE_ANON_KEY')

checks = {
    'pika uni': '(or(name.ilike.*pika*,expansion_name.ilike.*pika*,expansion_number.ilike.*pika*),or(name.ilike.*uni*,expansion_name.ilike.*uni*,expansion_number.ilike.*uni*))',
    'mew 232': '(or(name.ilike.*mew*,expansion_name.ilike.*mew*,expansion_number.ilike.*mew*),or(name.ilike.*232*,expansion_name.ilike.*232*,expansion_number.ilike.*232*))',
}

for term, and_filter in checks.items():
    params = urllib.parse.urlencode({
        'select': 'card_id,name,expansion_name,expansion_number',
        'and': and_filter,
        'limit': '20',
    }, safe='(),.*')
    req = urllib.request.Request(
        f'{url}/rest/v1/marketplace_card_versions?{params}',
        headers={
            'apikey': key,
            'Authorization': f'Bearer {key}',
        },
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
`Mew ex | Paldean Fates | Special Illustration Rare | 232/091`.

The older `search_cardtrader_pokemon_blueprints` RPC may still exist for
fallbacks, but new UI work should prefer `marketplace_cards` and
`marketplace_card_versions` because they avoid parsing heavy blueprint JSON.

## Generate Preview Images

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

The importer stores `preview_object_key` only on
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

Check DB progress:

```bash
python3 - <<'PY'
from pathlib import Path
import urllib.request

def env_value(key):
    for line in Path('.env.local').read_text().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith('#') or '=' not in stripped:
            continue
        name, value = stripped.split('=', 1)
        if name.removeprefix('export ').strip() == key:
            return value.strip().strip('"').strip("'")
    return ''

url = env_value('SUPABASE_URL').rstrip('/')
key = env_value('SUPABASE_SERVICE_ROLE_KEY')

for query, label in [
    ('cdn_object_key=not.is.null', 'total_with_images'),
    ('preview_image_url=not.is.null', 'with_previews'),
]:
    req = urllib.request.Request(
        f'{url}/rest/v1/cardtrader_pokemon_blueprints?select=id&{query}',
        headers={
            'apikey': key,
            'Authorization': f'Bearer {key}',
            'Prefer': 'count=exact',
        },
        method='HEAD',
    )
    with urllib.request.urlopen(req, timeout=20) as res:
        print(label, res.headers.get('content-range'))
PY
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

Run a targeted import first:

```bash
FULL_IMAGE_IDS=274416 node scripts/import-cardtrader-full-images.js
```

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
- Updates `cardtrader_pokemon_blueprints.image_url`, `cdn_image_url`,
  `cdn_object_key`, and `cardtrader_image_url`.
- Updates `marketplace_cards` and `marketplace_card_versions` for the imported
  card ID, so no full projection refresh is required.

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
FULL_IMAGE_BATCH_SIZE=50 FULL_IMAGE_MAX_ROWS=1000 node scripts/import-cardtrader-full-images.js
```

Prioritize new CardTrader rows that do not have CDN images yet:

```bash
FULL_IMAGE_MISSING_ONLY=1 FULL_IMAGE_NEWEST_FIRST=1 FULL_IMAGE_BATCH_SIZE=50 FULL_IMAGE_MAX_ROWS=1000 node scripts/import-cardtrader-full-images.js
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
  exact match, capped at 15.
- Search suggestion rows can be clicked reliably; if clicks fail, inspect focus
  loss/removal timing in `_MarketplaceTopSearchState`.
- The popup width matches the search bar width.
- Search suggestions show card name plus collector/expansion number.
- Search suggestions for `pika uni` include Pikachu from Unified Minds.

## Important Failure Modes

- `supabase db push --db-url "$SUPABASE_DB_URL"` can fail with IPv6
  `no route to host`. Relink with `--password` and use `supabase db push`
  instead.
- Supabase Management API can return `403` for database query execution even
  when CLI/project access works. Prefer the CLI migration path.
- The first fuzzy RPC version timed out with `57014`. Keep
  `20260518073000_optimize_cardtrader_search.sql`.
- Preview generation is resumable. Existing `preview_image_url` rows are skipped
  unless `PREVIEW_FORCE=1` is set.
- The Flutter app must tolerate missing `preview_image_url`. Do not remove the
  fallback to `imageUrl`.
- Search preview rows should include the collector/expansion number next to the
  card name when present. Do not show opaque CardTrader blueprint IDs as if they
  were collector numbers for real singles.
- If `mew 232` returns rows in a direct Supabase check but the UI shows nothing,
  inspect the app request shape and deployed bundle before changing the ranking.
  Common causes are stale production builds, browser cache, DB-side ordering on
  active search, or local cached suggestions masking the remote full-catalog
  result.
- If the popup contains only one exact compound match, verify the similar-query
  fallback in `CardService.searchCardPreviews(...)` still runs and that
  `CardNotifier._loadSearchPreviews(...)` asks for 15 results.
- The full search page is intentionally separate from the home catalog. If it
  returns only a few cards while Supabase has more matches, check that it is
  calling `CardService.searchMarketplaceCards(...)` instead of filtering
  `state.filteredCards`.
