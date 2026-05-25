# CardTrader Multi-Game Marketplace Workflow

Use this workflow when importing CardTrader data for card games other than the
current Pokemon marketplace. The rule is strict: one card game maps to one
isolated database/schema target, and non-Pokemon data must not enter the active
Pokemon Oracle tables, Supabase name-index tokens, or marketplace APIs.

## Isolation Model

- Pokemon keeps using the existing Oracle target:
  `public.cardtrader_pokemon_blueprints`, Pokemon projection functions,
  Pokemon search tokens, and existing CDN keys.
- Every other game needs one of these isolated targets before `--apply`:
  - A separate Postgres database URL, preferred for production games.
  - A private schema/table namespace in a non-Pokemon database, acceptable for
    staging or early validation.
- Do not point non-Pokemon imports at `MARKETPLACE_DATABASE_URL`,
  `public.cardtrader_pokemon_blueprints`, `marketplace_cards`,
  `marketplace_search_candidates`, or the Pokemon Supabase name-index.
- Keep target credentials in environment variables named per game, for example
  `MAGIC_MARKETPLACE_DATABASE_URL`; never store secrets in config files.

## Config

Copy `config/cardtrader-marketplaces.example.json` to
`config/cardtrader-marketplaces.json` when real game targets are known. The
example file intentionally contains placeholders only.

Each game entry records:

- CardTrader game/category hints.
- The target database URL environment variable.
- The target schema and raw blueprint table.
- The CDN key prefix, such as `magic/` or `one-piece/`.
- Optional game-local projection refresh SQL.
- Optional game-local search-token sync command.

## Discovery

Start every game with CardTrader discovery:

```bash
node scripts/cardtrader-multigame-import.js \
  --game=magic \
  --discover-only
```

This reads CardTrader `/games`, `/categories?game_id=...`, and `/expansions`.
If the game or category match is ambiguous, pass `--cardtrader-game-id` and
optionally `--cardtrader-category-id`.

## Delta Import

The importer streams CardTrader expansion exports and compares blueprint IDs
against the target game's raw table. CardTrader's workflow uses
`/blueprints/export?expansion_id=...`; there is no IDs-only endpoint assumed
here, so comparison happens expansion by expansion.

Dry-run a bounded expansion first:

```bash
node scripts/cardtrader-multigame-import.js \
  --game=magic \
  --cardtrader-game-id=1 \
  --database-url-env=MAGIC_MARKETPLACE_DATABASE_URL \
  --schema=marketplace_magic \
  --table=cardtrader_blueprints \
  --expansion-ids=<expansion_id> \
  --limit=500 \
  --images
```

The default mode is dry-run. It reports fetched, existing, missing, sample rows,
schema SQL, and planned image jobs without writing.

Apply only after the target env var is configured and the dry-run is reviewed:

```bash
node scripts/cardtrader-multigame-import.js \
  --game=magic \
  --cardtrader-game-id=1 \
  --database-url-env=MAGIC_MARKETPLACE_DATABASE_URL \
  --schema=marketplace_magic \
  --table=cardtrader_blueprints \
  --expansion-ids=<expansion_id> \
  --ensure-schema \
  --images \
  --apply
```

For large imports, use high but bounded parallelism:

```bash
node scripts/cardtrader-multigame-import.js \
  --game=magic \
  --stream-all \
  --database-url-env=MAGIC_MARKETPLACE_DATABASE_URL \
  --schema=marketplace_magic \
  --table=cardtrader_blueprints \
  --batch-size=1000 \
  --concurrency=12 \
  --image-concurrency=8 \
  --images
```

Review the dry-run counts before adding `--apply`.

## Images

`--images` plans or generates only for newly imported rows:

- Full CDN image from the best CardTrader full-size source.
- Preview derivative under `<game-prefix>/previews/...`.
- Homepage derivative as `<game-prefix>/<id>_<slug>_homepage.webp`.

Non-Pokemon games must use a non-empty `cdnKeyPrefix` unless the target is a
separate bucket/domain. This prevents object-key collisions with Pokemon cards.

## Projection And Search

Raw imports are not enough for a marketplace. Each game needs its own projection
and search-token generation against that game's isolated tables. Do not reuse
Pokemon functions such as `public.refresh_marketplace_oracle_projections()` or
Pokemon-specific name roots unless the target game is Pokemon.

For a new game, define game-local SQL that projects:

- Raw CardTrader blueprints into game-local marketplace card rows.
- Game-local expansion/version navigation.
- Game-local search candidates and token tables.
- Game-local URL/slug contracts.
- Game-local listing/order/event tables when commerce is enabled.

Then wire `refreshSql` and `syncCommand` in
`config/cardtrader-marketplaces.json` for that game. Until those are configured,
`--refresh` and `--sync-search` should be treated as blocked.

## Verification

Before applying:

- Confirm the resolved CardTrader game/category/expansion IDs.
- Confirm the database URL env var is for the target game, not Pokemon.
- Confirm the schema/table is not `public.cardtrader_pokemon_blueprints`.
- Confirm the dry-run missing samples match the requested game.
- Confirm image jobs include the correct game CDN prefix.

After applying a bounded batch:

- Count raw rows in the game target table.
- Re-run the same dry-run and confirm missing rows are now zero.
- Verify image columns only changed for the inserted IDs.
- Run game-local projection/search refresh if configured.
- Smoke test game-local APIs before exposing UI routes.

## Retry, Idempotency, And Rollback

- Raw upserts use `on conflict (id) do nothing`; rerunning a batch is safe.
- Image jobs are limited to newly inserted IDs and deterministic CDN keys.
- Failed expansion fetches are reported per expansion; retry the same bounded
  command after reviewing errors.
- To roll back a failed non-Pokemon batch, delete from that game's isolated raw
  table by reviewed ID range or expansion ID. Do not truncate or mutate Pokemon
  tables.
- If image upload partially succeeds, rerun the same bounded command with
  `--images --apply` after fixing the cause; existing rows can be targeted by a
  future game-local image repair job.
- Never run broad production imports until the target database/schema, refresh
  SQL, image prefix, and verification command are explicit.

## Current Pokemon-Only Assumptions

The existing marketplace stack is Pokemon-specific in these places:

- `scripts/cardtrader-delta-import.js` resolves Pokemon and writes
  `public.cardtrader_pokemon_blueprints`.
- `scripts/import-oracle-cardtrader-images.js` updates Pokemon raw and
  projection tables.
- `scripts/generate-oracle-homepage-card-images.js` updates Pokemon raw and
  projection tables.
- Oracle schema and projection SQL reference Pokemon tables, Pokemon name roots,
  Pokemon trainer ownership, and Pokemon marketplace APIs.
- Supabase name-index sync reads Pokemon Oracle projections only.

Keep those paths as Pokemon paths unless a deliberate game-local equivalent is
created.
