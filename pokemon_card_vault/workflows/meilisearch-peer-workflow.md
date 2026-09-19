# Meilisearch on pi-home (English typeahead + search)

**Ranking inventory (every file, `search_weight` formula, leftover vs intended):**
[`docs/marketplace-search-ranking.md`](../docs/marketplace-search-ranking.md).

Meili runs on the **same box** as the public API: **pi-home**,
`http://127.0.0.1:7700` (Docker `pokoin-meili`,
`getmeili/meilisearch:v1.53.1`, data `/srv/pokoin/meili`). There is no
dedicated Meili peer and no `pokoin-meili-peer-tunnel`. Do not put Meili on
`pokoin-peer1`. Do not pin or recreate `v1.10.3`. Oracle `pokoin-marketplace`
is the CardTrader dump / Postgres writer only.

Postgres on Oracle stays the write source of truth. The Pi API reads a
streaming replica. Meili is candidate retrieval for **English only**.
Non-English stays on the legacy SQL/Supabase path.

## Two client paths

| Client | Endpoint | Meili role | SQL |
| --- | --- | --- | --- |
| pokoin-web header popup | `GET /api/marketplace-suggest?q=` | Display fields only (grouped printings) | **None** |
| Flutter searchbar | `POST /api/marketplace-autocomplete` | ID pool (legacy ranking still wraps it) | Hydrate + rank |
| Search results page | `GET /api/marketplace-search-page?query=` | IDs | Identity + image only (no listing-cache join) |

Price and stock stay on the **card page**. Typeahead is a card picker
(CardTrader-style groups), not a mini results grid.

Plain prefixes (`mimik`, `pikac`) rank the **base display name** first.
`search_weight` boosts GX/EX/VMAX and products in Meili; suggest reorders
groups after grouping so that cannot bury Mimikyu under Mimikyu GX. Typing
`gx` / `ex` / `vmax` keeps the variant first.

`MARKETPLACE_SEARCH_ENGINE=meili` must stay set on `pokoin-oracle-api`.
`MEILI_HOST=http://127.0.0.1:7700` (or the docker-bridge address of the host).

## Indexes

- `marketplace_cards` (default `MEILI_MARKETPLACE_INDEX`)
- `marketplace_name_tokens` (token prediction for Flutter)

Documents in `marketplace_cards` include `name*`, `card_number`, `set_name`,
`rarity`, `cdn_image_url` (full JPEG, never `/previews/`), `canonical_path`,
and `name_group` (gameplay name used to group printings).

## Install / data

Live Pi path is Docker, not the systemd binary. Recreate / pin:

```bash
# from nezopt
bash /home/nez/Projects/pokoin-web/scripts/install-pokoin-meili-docker.sh
```

That pulls `getmeili/meilisearch:v1.53.1`, recreates `pokoin-meili` with
`/srv/pokoin/meili/docker.env` and `/srv/pokoin/meili:/meili_data`, host
network, `restart=always`. Do **not** pass `--import-dump` when `data.ms`
already exists. Do not wipe `/srv/pokoin/meili`.

Jumping from Meili older than v1.12 needs a dump import (dumpless
`--upgrade-db` cannot read 1.10 databases). After import, recreate without
`--import-dump` or the container restart-loops.

Binary installer (A1 / non-Docker) default is also **v1.53.1**:
`bash deploy/meili/install-meili-peer.sh`. Config example:
`deploy/meili/meili.toml.example`. Docker env lives at
`/srv/pokoin/meili/docker.env` (`MEILI_HTTP_ADDR=127.0.0.1:7700`,
`MEILI_DB_PATH=/meili_data/data.ms`, `MEILI_DUMP_DIR=/meili_data/dumps`,
`MEILI_MAX_INDEXING_MEMORY=256Mb`).

Index build (API host, DB + Meili reachable):

```bash
node scripts/meili-sync-marketplace-full.js
node scripts/meili-sync-name-tokens-full.js
node scripts/meili-sync-marketplace-delta.js --since="$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)"
```

Delta timer (this VM, not peer3):

```bash
sudo cp deploy/systemd/pokoin-meili-marketplace-delta.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now pokoin-meili-marketplace-delta.timer
```

Do not wipe `/srv/pokoin/meili` (Docker) or `/var/lib/meilisearch` (binary)
as a product. Rebuild indexes from Postgres.

## Rollback

1. `MARKETPLACE_SEARCH_ENGINE=legacy`
2. Reload `pokoin-oracle-api`
3. pokoin-web popup will return empty groups until Meili is back; Flutter
   autocomplete falls through to its legacy SQL pool.

## Keep the index in RAM

Meili mmaps LMDB under `/var/lib/meilisearch/data.ms`. The kernel can steal
those pages; a 30s ping of `q=p` does **not** pin the catalog.

On the Frankfurt micro, pin the files with `vmtouch -l` (mlock). That process
holds ~the on-disk size (~177M today) in RSS so typeahead does not wait for
fault-in.

```bash
sudo apt-get install -y vmtouch
sudo cp deploy/systemd/pokoin-meili-resident.service /etc/systemd/system/
sudo mkdir -p /etc/systemd/system/pokoin-meili-marketplace-delta.service.d
sudo cp deploy/systemd/pokoin-meili-marketplace-delta.service.d/resident.conf \
  /etc/systemd/system/pokoin-meili-marketplace-delta.service.d/
sudo cp scripts/meili-keepalive.sh /usr/local/bin/pokoin-meili-keepalive.sh
sudo chmod 755 /usr/local/bin/pokoin-meili-keepalive.sh
sudo cp deploy/systemd/pokoin-meili-keepalive.{service,timer} /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now pokoin-meili-resident.service
sudo systemctl enable --now pokoin-meili-keepalive.timer
vmtouch /var/lib/meilisearch/data.ms
```

`pokoin-meili-resident.service` is the pin. Keepalive only health-checks and
`vmtouch -t` (no `docker exec`, no SQL autocomplete). After a delta write,
the drop-in `try-restart`s the locker.

If the micro OOMs, the locker has `OOMScoreAdjust=200` so it dies before
Postgres. Search still works; first queries after that are cold until the
locker restarts.

Do not wipe `/srv/pokoin/meili` or `/var/lib/meilisearch`. After Madrid A1 (12 GB), raise
`MemoryMax` in `deploy/systemd/meilisearch.service` if Meili’s own cgroup
needs more than 256M; residency is still `vmtouch`.

## Health

```bash
curl -sS http://127.0.0.1:7700/health
sudo systemctl status meilisearch
sudo systemctl status pokoin-meili-resident
sudo systemctl status pokoin-meili-marketplace-delta.timer
```

Suggest smoke (after a full sync with display fields):

```bash
curl -sS 'https://api.pokoin.com/api/marketplace-suggest?q=pika&limit=12'
```

The `/api` prefix is required. These are **not** the suggest route:

| URL | What you get |
| --- | --- |
| `https://api.pokoin.com/` | Operator landing HTML (not JSON) |
| `https://api.pokoin.com/marketplace-suggest` | `404` `API route not found` |
| `GET /api/marketplace-autocomplete` | `405` — Flutter path is **POST** |

EN search page should still use Meili IDs. IT/FR stay legacy.

## Snapshots

- `/var/lib/meilisearch/snapshots`
- `/var/lib/meilisearch/dumps`
- `sudo tar -czf /var/backups/meili-$(date -u +%Y%m%d%H%M%S).tgz /var/lib/meilisearch/snapshots /var/lib/meilisearch/dumps`

After Madrid A1 (12 GB), raise `MemoryMax` in `deploy/systemd/meilisearch.service`
if Meili’s own cgroup needs more than 256M; residency is still `vmtouch`.
