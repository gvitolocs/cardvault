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

For large imports, use high parallelism (IO-bound image downloads should saturate
`--image-concurrency`; expansion export saturates `--concurrency`):

```bash
node scripts/cardtrader-multigame-import.js \
  --game=magic \
  --stream-all \
  --database-url-env=MAGIC_MARKETPLACE_DATABASE_URL \
  --schema=marketplace_magic \
  --table=cardtrader_blueprints \
  --batch-size=1000 \
  --concurrency=12 \
  --image-concurrency=12 \
  --images
```

Review the dry-run counts before adding `--apply`.

## Images

`--images` plans or generates CardTrader art for imported rows:

- Full CDN image from the best CardTrader full-size source.
- Preview derivative under `<game-prefix>/previews/...`.
- Homepage derivative as `<game-prefix>/<id>_<slug>_homepage.webp`.

Dry-run `--images` plans jobs for newly imported (or missing) IDs only.
`--images --apply` also loads any existing row whose `cdn_image_url` is still
null and uploads those too. `--backfill-images` skips expansion export and
only repairs rows still missing CDN objects.

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
- Image object keys are deterministic per game prefix. `--images --apply`
  uploads newly inserted IDs and any row still missing `cdn_image_url`.
- Failed expansion fetches are reported per expansion; retry the same bounded
  command after reviewing errors.
- To roll back a failed non-Pokemon batch, delete from that game's isolated raw
  table by reviewed ID range or expansion ID. Do not truncate or mutate Pokemon
  tables.
- If image upload partially succeeds, rerun `--backfill-images --apply` for that
  game. Do not start a second image job on peer1 while a dump is still running.
- Never run broad production imports until the target database/schema, refresh
  SQL, image prefix, and verification command are explicit.

## One Piece + Riftbound full dump (peer1)

Frankfurt `pokoin-peer1` (`oracle-peer1`, `10.0.0.170`) runs the importer.
Postgres stays on `pokoin-marketplace` (`10.0.0.223:5432`). Do **not** write
these games into `pokoin_marketplace` / `public.cardtrader_pokemon_blueprints`.

Auth: `CARDTRADER_AUTH_TOKEN` (Bearer) from `.env.local`. Never put the token
in git or chat.

| Game | CardTrader id | Isolated DB | Schema | CDN prefix | Expansions (2026-09-01) |
| --- | ---: | --- | --- | --- | ---: |
| One Piece | 15 | `pokoin_one_piece` | `marketplace_one_piece` | `one-piece/` | 98 |
| Riftbound | 22 | `pokoin_riftbound` | `marketplace_riftbound` | `riftbound/` | 17 |

Env vars (peer1 `/home/ubuntu/pokoin-cardtrader-multigame/.env`):

- `ONE_PIECE_MARKETPLACE_DATABASE_URL` → db `pokoin_one_piece` on `10.0.0.223`
- `RIFTBOUND_MARKETPLACE_DATABASE_URL` → db `pokoin_riftbound` on `10.0.0.223`
- `CARDTRADER_AUTH_TOKEN`, R2 (`CLOUDFLARE_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`,
  `R2_SECRET_ACCESS_KEY`), optional `POKOIN_CARD_IMAGES_BUCKET` /
  `POKOIN_CARD_CDN_BASE_URL`

Importer: `scripts/cardtrader-multigame-import.js`. Full dump flags:

```bash
# Full multithread: expansion workers (--concurrency) + image workers (--image-concurrency).
# peer1 is E2.1.Micro (2 vCPU / ~1 GB). Image downloads are IO-bound — run both games
# in parallel at 12 / 12. Cap only if pokoin-peer1 swap/OOM threatens the chain seed.
# Script max is 50 / 50.
node scripts/cardtrader-multigame-import.js \
  --game=one_piece --cardtrader-game-id=15 \
  --database-url-env=ONE_PIECE_MARKETPLACE_DATABASE_URL \
  --schema=marketplace_one_piece --table=cardtrader_blueprints \
  --stream-all --ensure-schema --images --apply \
  --batch-size=1000 --concurrency=12 --image-concurrency=12

node scripts/cardtrader-multigame-import.js \
  --game=riftbound --cardtrader-game-id=22 \
  --database-url-env=RIFTBOUND_MARKETPLACE_DATABASE_URL \
  --schema=marketplace_riftbound --table=cardtrader_blueprints \
  --stream-all --ensure-schema --images --apply \
  --batch-size=1000 --concurrency=12 --image-concurrency=12
```

`--stream-all` fetches `/blueprints/export?expansion_id=` for every expansion
of that `game_id`, in a worker pool (`runWorkers`). Upserts are
`on conflict (id) do nothing`. `--images --apply` uploads full/preview/homepage
to R2 for newly inserted IDs and any leftover row still missing `cdn_image_url`.
After a dump, leftovers:

```bash
node scripts/cardtrader-multigame-import.js \
  --game=one_piece --cardtrader-game-id=15 \
  --database-url-env=ONE_PIECE_MARKETPLACE_DATABASE_URL \
  --schema=marketplace_one_piece --table=cardtrader_blueprints \
  --backfill-images --apply --image-concurrency=12
```

`--backfill-images` does **not** call CardTrader `/games` (Cloudflare can 403 that). It only
reads rows still missing `cdn_image_url` and downloads art.

## CardTrader images vs Cloudflare (Qwen: read this)

Oracle Frankfurt `pokoin-peer1` (`92.5.153.117`) is **Cloudflare 403** for
`cardtrader.com` / `www.cardtrader.com` image hosts. Expansion JSON dump can
still run on peer1. Image download must leave via **WARP or nezopt**, never the
raw FRA IP after a 403.

Full infra runbook (hosts, netns, iptables, isolation, multithread):

`/home/nez/secrets/docs/CARDTRADER_MULTIGAME_DUMP.md`

VPN scripts (no keys in git): `/home/nez/secrets/deploy/cardtrader-ctvpn/`

### nezopt (netns `igvpn`, already up)

```bash
/home/nez/secrets/deploy/cardtrader-ctvpn/exec-igvpn.sh \
  env UV_THREADPOOL_SIZE=16 \
  ONE_PIECE_MARKETPLACE_DATABASE_URL="$ONE_PIECE_MARKETPLACE_DATABASE_URL" \
  node scripts/cardtrader-multigame-import.js \
    --game=one_piece --cardtrader-game-id=15 \
    --database-url-env=ONE_PIECE_MARKETPLACE_DATABASE_URL \
    --schema=marketplace_one_piece --table=cardtrader_blueprints \
    --backfill-images --apply --image-concurrency=16
```

Prove first: `nezopt-sudo ip netns exec igvpn curl -sS https://ifconfig.me/ip`
must not be the FRA or DK residential IP you use for SSH, and a sample
`www.cardtrader.com/uploads/blueprints/image/...` GET must be HTTP 200 ~50 KB,
not 403 HTML.

### peer1 (netns `ctvpn`, seed stays on ens3)

```bash
sudo /home/ubuntu/ctvpn/up-peer1-warp-netns.sh   # WireGuard WARP; split-routes 10.0.0.0/8
sudo ip netns exec ctvpn curl -sS https://ifconfig.me/ip   # expect WARP, not 92.5.153.117
sudo ip netns exec ctvpn env UV_THREADPOOL_SIZE=16 \
  node scripts/cardtrader-multigame-import.js --backfill-images --apply --image-concurrency=12 ...
sudo /home/ubuntu/ctvpn/down-peer1-warp-netns.sh
```

Never `wg-quick up` on the host (that hijacks the default route). Oracle
`FORWARD` is REJECT-by-default; the up script **inserts** ACCEPT for `ctv0`
at the top. VCN Postgres test: `echo >/dev/tcp/10.0.0.223/5432` inside `ctvpn`.

Use `--image-concurrency=12` (peer1) or `16` (nezopt). Both games in parallel.
Do not start a second image job on the same host while one is still running.

Projection/search SQL is not configured yet (`refreshSql` / `syncCommand`
empty) — raw dump only.

Logs on peer1: `/home/ubuntu/pokoin-cardtrader-multigame/logs/`.
`--discover-only` first if the token or game id needs a check.

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
