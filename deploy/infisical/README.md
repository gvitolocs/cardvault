# Infisical (peer1)

Canonical shared secrets for CardVault / Pokoin developers and agents.

## Host

- **Deployed on:** `oracle-peer1` (`pokoin-peer1`, 92.5.153.117)
- **Not on:** `pokoin-marketplace` (peer2) — that host runs CardTrader ingest / Postgres writer
- **Bind:** `127.0.0.1:8088` only (no public port)
- **Honcho:** untouched; remains nezopt `:8000` reverse-tunneled to peer1 `:18000`

## Access

```bash
ssh -L 8088:127.0.0.1:8088 oracle-peer1
# open http://127.0.0.1:8088
```

Root env (ENCRYPTION_KEY / AUTH_SECRET / Postgres password) lives only at:

- local: `~/secrets/infisical/peer1.env`
- peer1: `/opt/pokoin-infisical/.env` (mode 600)

Never commit those files.

## Layout in Infisical

Projects / environments (intended):

- `cardvault` → `dev`, `prod`
- `pokoin` → `dev`, `prod`

Machine identities: one Universal Auth identity per developer/agent; CardVault agents get CardVault secrets only; `dev` ≠ `prod`.

## Ops

```bash
ssh oracle-peer1 'cd /opt/pokoin-infisical && sudo docker compose ps'
ssh oracle-peer1 'cd /opt/pokoin-infisical && sudo docker compose logs -f --tail=100 backend'
```

## Current status (2026-09-19)

- Compose + env are on peer1; Postgres migrations completed; Redis uses `noeviction`.
- HTTP on `:8088` is **not ready yet** on this 1 GB micro: Infisical hangs before bind (Fastify `@fastify/static` / plugin timeout under swap).
- PokoinPoS on peer1 remains healthy. Honcho (nezopt `:8000` → peer1 `:18000`) untouched.
- Next options: wait for a larger Oracle A1 shape, or run Infisical on nezopt and SSH-tunnel to peer1 if you want the same access path.
