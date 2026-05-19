# Oracle Marketplace Postgres Workflow

Use this workflow when changing marketplace/catalog/search storage, migrating
data from Supabase, deploying Oracle-backed marketplace APIs, or cleaning up old
Supabase marketplace objects.

## Current Architecture

- Oracle Postgres is the source of truth for marketplace/catalog/search data.
- Supabase is retained for forum tables only.
- Vercel API functions connect to Oracle through `MARKETPLACE_DATABASE_URL`.
- Flutter must not call Supabase marketplace tables directly.
- Firebase remains the auth/profile/listings/cart/order store.

## Oracle Runtime Tables

- `public.cardtrader_pokemon_blueprints`
- `public.cardtrader_pokemon_expansions`
- `public.marketplace_cards`
- `public.marketplace_card_versions`
- `public.marketplace_search_candidates`
- `public.marketplace_card_events`
- `public.marketplace_trainers`
- `public.marketplace_variations`
- `public.marketplace_card_variations`
- `public.cards_type`
- `public.cards_name_type`
- Tokenized search dimensions:
  - `public.marketplace_card_names`
  - `public.marketplace_rarities`
  - `public.marketplace_expansion_numbers`

## Runtime API Surface

- `GET /api/marketplace-home`
- `GET /api/marketplace-cards`
- `GET /api/marketplace-card-versions`
- `POST /api/marketplace-search-candidates`
- `POST /api/marketplace-autocomplete`
- `POST /api/marketplace-event`

Forum APIs keep using Supabase:

- `GET /api/forum`
- `POST /api/forum-create-topic`
- `POST /api/forum-create-post`
- `POST /api/forum-upload-media`

## Required Environment

Read from `.env.local` or Vercel env. Never print secret values.

```bash
MARKETPLACE_DATABASE_URL=
SUPABASE_DB_URL= # migration/copy/cleanup only
SUPABASE_URL= # forum only
SUPABASE_ANON_KEY= # forum only
SUPABASE_SERVICE_ROLE_KEY= # forum writes only
```

Production deploy requires `MARKETPLACE_DATABASE_URL` in Vercel. The deploy
script intentionally refuses to publish without it.

## Apply Or Refresh Oracle

Run from `pokemon_card_vault`:

```bash
node scripts/oracle-marketplace-migrate.js schema
node scripts/oracle-marketplace-migrate.js refresh
node scripts/oracle-marketplace-migrate.js verify
```

For initial migration from Supabase:

```bash
node scripts/oracle-marketplace-migrate.js all
```

The `all` command applies schema, copies non-forum marketplace tables from
Supabase, refreshes Oracle projections, and verifies key search queries.

Search/variation changes must live in `oracle-postgres/schema/*.sql`. After
changing variation logic, run both schema and refresh so
`marketplace_card_variations` is rebuilt. Variation tagging should come from
card identity fields (`name`, `card_number`, `rarity`, `card_type`,
`product_variant`) and not from expansion/search text, otherwise sets such as
`Shiny Star V` can incorrectly tag every card in the set as `V`.

Card palette/type changes must also live in `oracle-postgres/schema/*.sql`.
`cards_type` stores canonical Pokemon/TCG types such as `water`, `darkness`,
`item`, and `supporter`; `cards_name_type` maps a card name to one or more
types with priority. Use this mapping for species that can legitimately have
multiple types across printings, for example Chien-Pao as both `water` and
`darkness`.

## Backfill Missing Card Palettes

When many marketplace cards render with the grey fallback, check whether their
Oracle rows have `card_palette->>'key' = 'fallback'`. Most misses come from
CardTrader rows whose `card_type` is only `Trading card`.

Use the repeatable classifier to enrich `cards_name_type` and propagate palette
JSON into the projected marketplace tables:

```bash
node scripts/backfill-marketplace-card-palettes.js
node scripts/backfill-marketplace-card-palettes.js --apply --refresh
```

The script reads the peer4 Oracle env from
`/Users/giuseppe/pokoinpos/deploy/env/peer4-postgres.env` by default. It also
creates the `cards_name_type_lower_name_idx` lookup index if missing, because
`marketplace_name_palette_key()` resolves names case-insensitively.

The default `--refresh` path intentionally performs a targeted palette-only
propagation into:

- `cardtrader_pokemon_blueprints`
- `marketplace_cards`
- `marketplace_search_candidates`
- `marketplace_card_versions`

Use `--full-refresh` only when non-palette projection logic changed. The full
projection rebuild can be much slower because it recomputes the complete
marketplace card projection, not just palette JSON.

Validation query:

```sql
select coalesce(card_palette->>'key', '') as key, count(*)::int as count
from public.marketplace_search_candidates
where item_kind = 'single' and product_type = 'card'
group by 1
order by count desc, key;
```

After the 2026-05-19 backfill, single-card fallback rows dropped from `42,859`
to `4,145`. Remaining high-volume misses include names such as `Meloetta`,
`Eiscue`, `Squawkabilly ex`, `Urshifu`, `Bede`, `Artazon`, and other trainer or
form-specific cases that should be handled with deliberate manual rules rather
than blind classification.

## Deploy Web/API

```bash
./deploy-pokoin-web.sh
```

Do not run plain `vercel deploy` from the project root. It can publish an
incomplete output. The deploy script also copies `_marketplace_db.js` and rewrites
marketplace API imports for the Vercel output layout.

## Guarded Supabase Cleanup

Only run cleanup after Oracle is loaded, Vercel has `MARKETPLACE_DATABASE_URL`,
and production marketplace APIs have been verified.

Dry checks before cleanup:

```bash
node scripts/oracle-marketplace-migrate.js verify
rg "rest/v1/(marketplace|cardtrader)|rpc/search_marketplace|_supabaseUrl|_supabaseAnonKey" lib api
```

Expected:

- Oracle verify returns rows for `porygon`, `piachu 151`, and `char ex`.
- Runtime code has no Supabase marketplace/cardtrader references.
- Forum APIs still reference `_supabase`.

Destructive cleanup command:

```bash
CONFIRM_DROP_SUPABASE_MARKETPLACE=drop-marketplace \
  node scripts/supabase-cleanup-marketplace.js
```

The script refuses to run unless:

- `SUPABASE_DB_URL` is set.
- `MARKETPLACE_DATABASE_URL` is set.
- Oracle has non-empty `marketplace_search_candidates`.
- Oracle has non-empty `marketplace_card_versions`.
- Supabase forum tables exist.

The cleanup SQL is in:

```bash
supabase/cleanup/20260519_drop_marketplace_after_oracle_cutover.sql
```

It drops old marketplace/catalog/search tables and functions from Supabase while
keeping `forum_*` objects.

## Verification

```bash
node --test api/marketplace-autocomplete.test.js
node --check api/_marketplace_db.js
node --check api/marketplace-cards.js
node --check api/marketplace-card-versions.js
node --check api/marketplace-search-candidates.js
node --check scripts/oracle-marketplace-migrate.js
node --check scripts/supabase-cleanup-marketplace.js
flutter analyze lib/services/card_service.dart
flutter test test/card_service_test.dart
```

After deploy:

```bash
curl -s https://pokoin.com/api/marketplace-home | python3 -m json.tool | sed -n '1,40p'
```

Then verify user flows:

- `/marketplace` home loads cards and sections.
- `/marketplace/search?q=porygon` shows multiple matching cards.
- Autocomplete handles `piachu 151`, `char ex`, `v`, `darkrai v`,
  `azief lv x`, and `mew special illustration rare`.
- `v` returns actual `... V` cards, `darkrai v` ranks `Darkrai V` first, and
  `azief lv x` ranks `Azelf LV.X`.
- `/card/:id` previous/next stays within the expansion.
- `/forum` still reads and writes through Supabase.

## Rules

- Do not add new marketplace tables/functions to Supabase.
- Do not add new client-side Supabase marketplace reads.
- Do not delete Supabase forum tables.
- Do not run cleanup without a verified Oracle load and a backup.
