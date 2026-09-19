# Pokoin Codex pack (app collaborator)

Download this folder or the zip. Point Codex / Cursor at it when working on the Pokoin **app**.

## Start here

1. **`AGENTS.md`** — short hard rules  
2. **`APP_COLLABORATOR.md`** — Pi API topology + what you can do  
3. **`docs/`** — full API / React / ids / user-actions docs  
4. **`workflows/`** — how operators run API, Meili, Postgres, auth, deploy  

## Obsidian (optional)

| Path | Use |
| --- | --- |
| `playbook/obsidian-documentation.md` | How we write atomic notes |
| `vault/Pokoin/` | Read-only snapshot of the Pi vault |

Live vault remains on the Raspberry Pi (`/home/nes/Obsidian/Pokoin`). Do not treat this zip as writable canonical knowledge.

## Download (Oracle peer1)

- Browse: `https://rpc.pokoin.com/codex-obsidian/<token>/`
- Zip: `…/pokoin-codex-obsidian-pack.zip`

## Do not

- Commit secrets or paste `.env` into notes
- Add production APIs as Vercel serverless
- Invent card ids / CDN paths / prices

Republish: `scripts/publish-codex-obsidian-pack.sh`
