# Meilisearch Dedicated Peer Workflow (English-only v1)

This rollout repurposes one Oracle Postgres peer as a dedicated Meilisearch node.
In v1, Meili is used **only when**:

- `MARKETPLACE_SEARCH_ENGINE=meili`
- request `search_language` resolves to `en`

All non-English (`it`, `fr`, etc.) traffic remains on legacy Oracle/Supabase search paths.

## Architecture

- **Legacy source of truth:** Oracle Postgres/Supabase (unchanged)
- **Meili role:** first-stage candidate retrieval (names/prefix/fuzzy) for English only
- **Verifier/ranker:** Oracle candidate hydration/ranking remains authoritative
- **Immediate rollback:** flip flag back to `legacy` and reload API

## Current Production Shape (2026-05-28)

- `https://api.pokoin.com` is live with `MARKETPLACE_SEARCH_ENGINE=meili`.
- The API runs in Docker on peer3, so it cannot use a host-loopback Meili tunnel.
  peer3 provides `pokoin-meili-peer-tunnel.service`, which binds the peer Meili
  tunnel to Docker bridge `172.17.0.1:27700`; production `MEILI_HOST` points
  there.
- peer3 `pokoin-meili-marketplace-delta.timer` runs the delta sync every 2
  minutes from the Oracle API bundle.
- `https://pokoin.com/api/*` should be deployed in Oracle API mode via
  `ORACLE_API_BASE_URL=https://api.pokoin.com` so public web traffic also hits
  the Oracle API Meili path instead of stale Vercel serverless functions.

## Dedicated Peer Setup

Target peer example: `peer2`.

1. SSH to peer:
   - `ssh opc@<peer2-host>`
2. Clone/update repo and move to project root.
3. Run installer:
   - `bash deploy/meili/install-meili-peer.sh`
4. Edit `/etc/pokemon-card-vault/meili.toml` and `/etc/pokemon-card-vault/meili.env` (master key).
5. Open network/firewall for API peer to reach `:7700` (private network only).

## Index Build + Sync

Run from API host (or CI worker with DB + Meili reachability):

- Full cards index:
  - `node scripts/meili-sync-marketplace-full.js`
- Full name-token index:
  - `node scripts/meili-sync-name-tokens-full.js`
- Delta updates (cron every 1-5 min):
  - `node scripts/meili-sync-marketplace-delta.js --since="$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)"`
- On peer3, install bundled timer files after API deploy:
  - `sudo cp deploy/systemd/pokoin-meili-marketplace-delta.{service,timer} /etc/systemd/system/`
  - `sudo systemctl daemon-reload`
  - `sudo systemctl enable --now pokoin-meili-marketplace-delta.timer`

## Cutover (English-only)

1. Set API env:
   - `MARKETPLACE_SEARCH_ENGINE=meili`
   - `MEILI_HOST=http://172.17.0.1:27700` on peer3 Docker API, or `http://<peer2-private-ip>:7700` for non-Docker/API-host-local runs
   - `MEILI_API_KEY=<redacted>`
2. Optional shadow:
   - `MARKETPLACE_SEARCH_SHADOW=1`
3. Reload API service.
4. Smoke checks:
   - `curl -sS https://<api>/api/marketplace-autocomplete -X POST -H 'content-type: application/json' -d '{"search_term":"giratina","search_language":"en","limit":5}'`
   - `curl -sS https://<api>/api/marketplace-autocomplete -X POST -H 'content-type: application/json' -d '{"search_term":"giratina","search_language":"it","limit":5}'`
   - Verify EN takes Meili path (debug), IT stays legacy.
5. Public web proxy check:
   - `node scripts/benchmark-searchbar-api.js --base-url https://pokoin.com --endpoint /api/searchbar-cards --queries pikachu --language en --debug`
   - Verify `paths=meili_en_candidates`.

## 1-minute Rollback

1. Set `MARKETPLACE_SEARCH_ENGINE=legacy`
2. Reload API service
3. Smoke checks:
   - EN query returns results via legacy path
   - non-EN unchanged (legacy)

No data migration rollback is needed because Oracle remains source of truth.

## Observability

- API logs:
  - meili fallback errors (`meili search failed...`, `meili token prediction failed...`)
- Meili health:
  - From peer3 host: `curl -sS http://127.0.0.1:27700/health`
  - From API container: `fetch("${MEILI_HOST}/health")` with the Meili API key
- systemd status:
  - `sudo systemctl status meilisearch`
  - `sudo systemctl status pokoin-meili-peer-tunnel.service`
  - `sudo systemctl status pokoin-meili-marketplace-delta.timer`

## Backup/Snapshots

- Snapshot path: `/var/lib/meilisearch/snapshots`
- Dump path: `/var/lib/meilisearch/dumps`
- Example backup:
  - `sudo tar -czf /var/backups/meili-$(date -u +%Y%m%d%H%M%S).tgz /var/lib/meilisearch/snapshots /var/lib/meilisearch/dumps`
