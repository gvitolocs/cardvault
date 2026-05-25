# Limitless Competitive Workflow

Pokoin competitive marketplace data comes from the official Limitless Play API:

```text
https://play.limitlesstcg.com/api
```

The public sync stores data in Oracle/Postgres tables created by:

```text
oracle-postgres/schema/014_limitless_competitive.sql
```

## Data Model

- `limitless_games` stores game IDs, names, formats, platforms, and raw API JSON.
- `limitless_tournaments` stores the tournament list/details payload, source URL,
  phases, platform, organizer, and sync timestamps.
- `limitless_players` stores stable Limitless player IDs and display metadata.
- `limitless_tournament_standings` stores placement, record, country, deck
  summary, and decklist reference from public standings.
- `limitless_tournament_pairings` stores phase/round/table match pairings.
- `limitless_decklists` and `limitless_deck_cards` are ready for approved
  decklist access. Public standings store deck references and raw deck summary;
  full decklist fetching is intentionally disabled until Limitless approves the
  endpoint/API key.
- `limitless_sync_runs` records apply runs and partial failures.

## Apply Schema

Do not run production migrations without explicit approval. When approved, apply
schema to the writable Oracle marketplace primary only. Competitive marketplace
deployment is not complete until this non-destructive schema exists:

```bash
MARKETPLACE_DATABASE_URL=postgresql://...peer4.../pokoin_marketplace \
node scripts/oracle-marketplace-migrate.js schema
```

The required schema file is:

```text
oracle-postgres/schema/014_limitless_competitive.sql
```

Do not deploy `/marketplace/competitive` as frontend-only unless an intentional
empty-state rollout is explicitly acceptable.

## Sync

The sync is dry-run by default and reads `.env.local` plus the peer4 env file
when present:

```bash
node scripts/sync-limitless-competitive.js --dry-run --game=PTCG --max-tournaments=10
```

Apply only after schema exists. Prefer a small apply first, verify row counts and
the API response, then run the full or otherwise sensible public import:

```bash
node scripts/sync-limitless-competitive.js --apply --game=PTCG --max-tournaments=100
```

Useful options:

```text
--game=PTCG
--games=PTCG,POCKET,VGC
--tournament-id=<limitless-id>
--max-tournaments=50
--request-delay-ms=350
--skip-standings
--skip-pairings
--include-decklists
```

Environment:

```env
MARKETPLACE_DATABASE_URL=
MARKETPLACE_DATABASE_SSL_VERIFY=0
LIMITLESS_API_BASE_URL=https://play.limitlesstcg.com/api
LIMITLESS_API_KEY= # optional, only if Limitless grants restricted endpoint access
```

Public Limitless data may include games, tournaments, standings, and pairings
where the API allows. Restricted decklist endpoints may require Limitless
approval and an API key; treat missing decklists as a documented blocker, not as
data that should be silently assumed.

## API And UI

The Flutter page reads:

```text
GET /api/marketplace-competitive?includeGames=1&game=PTCG&limit=50
GET /api/marketplace-competitive?tournamentId=<limitless-id>
```

The marketplace route is:

```text
/marketplace/competitive
```

The top bar and mobile marketplace menu link to this route with the trophy icon.

## Rollout Verification

After schema, sync, Oracle API deploy, and frontend deploy, verify:

```bash
curl -fsS https://api.pokoin.com/healthz
curl -fsS https://api.pokoin.com/api/marketplace-competitive
```

Then confirm `https://api.pokoin.com/api/marketplace-competitive` returns a
non-empty competitive payload, `https://pokoin.com/marketplace/competitive` shows
visible data, and the trophy icon route is present in desktop and mobile
marketplace navigation.
