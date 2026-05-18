# CardTrader Search Preview Workflow

Use this workflow when changing the marketplace autocomplete, CardTrader fuzzy
search, Supabase blueprint schema, or CDN preview thumbnails.

## Goal

The marketplace search should behave like CardTrader:

- Typing in `/marketplace` opens an autocomplete panel.
- Results show a small preview image, card name, number, set and action text.
- Search previews are seeded from the loaded Flutter catalog, then merged with
  Supabase projection results.
- The full `/marketplace/search` page must query Supabase projections directly.
  Do not limit it to the 500-card marketplace/home catalog loaded in
  `CardState.cards`.
- Preview images live in the same R2 bucket as full card images under
  `previews/...webp`.
- Flutter receives `preview_image_url` when available and falls back to the full
  card image when preview generation is incomplete.

## Files Involved

- `lib/screens/home_screen.dart`
  - Search input and CardTrader-style preview dropdown.
- `lib/providers/card_provider.dart`
  - Local preview ranking, async search preview state and stale request guard.
- `lib/services/card_service.dart`
  - Supabase catalog loading, projection search, preview image mapping and
    fallback behavior.
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
- `scripts/generate-cardtrader-preview-images.js`
  - Generates WebP previews with `sharp`, uploads to R2, updates Supabase rows.
- `workflows/generate-cardtrader-preview-images.sh`
  - Wrapper for running the preview generator.

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

## Verify Fuzzy Search

Run a small projection-search check with the anon key:

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

for term in ['pik', 'char', 'Unified Minds Booster']:
    params = urllib.parse.urlencode({
        'select': 'card_id,name,expansion_name,expansion_number',
        'or': f'(name.ilike.*{term}*,expansion_name.ilike.*{term}*,expansion_number.ilike.*{term}*)',
        'limit': '5',
    })
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
depend on the capped Flutter home catalog.

The older `search_cardtrader_pokemon_blueprints` RPC may still exist for
fallbacks, but new UI work should prefer `marketplace_cards` and
`marketplace_card_versions` because they avoid parsing heavy blueprint JSON.

## Generate Preview Images

Preview generation is long because it covers every CardTrader blueprint image.
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

## Deploy Web Changes

Always use the project deploy script:

```bash
./deploy-pokoin-web.sh
```

Do not run plain `vercel deploy` from the project root. It can deploy an
incomplete output without the Flutter build, API files, or Dart defines.

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
    'View all results for',
    'marketplace_card_versions',
    'marketplace_cards',
    'preview_image_url',
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
- Search preview rows should use the card name as the main title. Avoid appending
  raw numbers or CardTrader IDs in the primary row title because product names
  and championship variants can overflow.
- The full search page is intentionally separate from the home catalog. If it
  returns only a few cards while Supabase has more matches, check that it is
  calling `CardService.searchMarketplaceCards(...)` instead of filtering
  `state.filteredCards`.
