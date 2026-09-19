# Obsidian documentation for Pokoin (Codex / Cursor playbook)

Clear instructions for AI collaborators (Codex, Cursor) writing Pokoin knowledge into Obsidian.

## Verdict

**Yes — Pokoin already has Obsidian notes.** They are **not** in this git repo.

| Location | Role |
| --- | --- |
| **Canonical vault** | `/home/nes/Obsidian` on **pi-home / pi-cursor** (user `nes`) |
| **Pokoin project folder** | `/home/nes/Obsidian/Pokoin/` (~275 Permanent notes + Events + MOCs) |
| **Hub** | `Pokoin/00 Pokoin hub.md` |
| **Repo stub (do not use)** | `/home/nez/Projects/pokoin/obsidian/` — leftover; README says do not add notes |

Locked decisions (pokoin Codevira): **D00000A**, **D00000B** — Obsidian is always the Raspberry Pi vault; never nezopt, never inside a git repo.

---

## Memory layers (do not conflate)

| Layer | Where | What goes here |
| --- | --- | --- |
| **Repo docs** | `pokemon_card_vault/docs/`, `workflows/` | Operator truth: APIs, deploy, schemas, playbooks |
| **Codevira** | decisions / `AGENTS.md` | Locked conventions (`do_not_revert`) |
| **Honcho** (`pokoin-cursor`) | conversational memory | Short claims / session continuity — **no file dumps** |
| **Obsidian Pokoin** | Pi vault | Atomic Zettelkasten: one claim per note, wikilinks, file ↔ note map |
| **Flareon handoff** | `memory/flareon-handoff.md` | 5–20 bullets of current focus — **no code** |

Obsidian is the **knowledge graph**. Repo docs remain the **operational source of truth**. When both exist, repo paths win for “how to run / deploy”; Obsidian wins for “how ideas connect.”

---

## Access

```bash
ssh pi-cursor
# vault root
cd /home/nes/Obsidian
# Pokoin project
cd /home/nes/Obsidian/Pokoin
```

- Cursor project on the Pi: `home-nes-Obsidian`
- Write as user `nes`. Prefer `pi-cursor`, not root `pi-home`.
- **Never** create Pokoin Permanent notes under `/home/nez/Projects/...` or `cardvault/`.

### Coworker download (Oracle / peer1)

For Codex collaborators without Pi SSH (especially **app** work), a snapshot pack is served from Oracle peer1 via Cloudflare (`rpc.pokoin.com`):

| | |
| --- | --- |
| **Page** | `https://rpc.pokoin.com/codex-obsidian/<token>/` |
| **Zip** | `https://rpc.pokoin.com/codex-obsidian/<token>/pokoin-codex-obsidian-pack.zip` |
| **Token file (operator)** | `~/.config/pokoin/codex-obsidian-token` |
| **Republish** | `./scripts/publish-codex-obsidian-pack.sh` |

Pack contents:

- `APP_COLLABORATOR.md` — Pi API topology + what the product can do  
- `docs/` — `pokoin-api`, React page BFFs, public ids, route catalog, …  
- `workflows/` — API / Meili / Postgres / auth / deploy playbooks  
- `memory/` — architecture / current-state  
- Obsidian playbook + `vault/Pokoin/` snapshot  

Wrong token → 404. Rotate with `--new-token` if the link leaks.

---

## Vault layout (Pokoin)

```
/home/nes/Obsidian/
  00 Home.md                          # all vaults index
  Templates/
    AI project vault notes.md         # meta: AI generates notes
  Pokoin/
    00 Pokoin hub.md                  # spine + MOC links + recent events
    Pokoin topology.md                # request/chain diagram with wikilinks
    Permanent/                        # atomic claims (majority of notes)
    Events/                           # dated session digests YYYY-MM-DD …
    MOC/                              # maps of content (indexes, not essays)
    Sources/                          # rare: external memos / imports
    Templates/
      Template Pokoin zettel.md
      Template Pokoin event.md
```

Start every Pokoin docs pass from **`00 Pokoin hub.md`**.

---

## When Codex must write Obsidian

After a **meaningful** change set, if any of these are true:

1. New or renamed **program files** that other sessions will touch
2. A **locked product rule** (ids, auth, topology, sanitize, deploy path)
3. A multi-file feature that needs a **dated Event** + several Permanent claims
4. Giuseppe / Karl explicitly asks for “Obsidian notes” / “document in Obsidian”

Skip Obsidian for: typo fixes, test-only tweaks, secrets, one-off debug, or content that already has a Permanent note with the same claim (update the existing note instead).

---

## Note types

### 1) Permanent (default)

- **One idea only.** Title = a full claim sentence (not a noun label).
  - Good: `marketplace-public-ids.md is the public-id namespace guide`
  - Bad: `Public IDs` or `Notes about marketplace`
- Body: 2–5 sentences in plain language. No pasted diffs. No secrets.
- Filename = title + `.md` (Obsidian-style; spaces OK).

Required sections (match existing notes):

```markdown
---
type: permanent
tags:
  - pokoin
created: YYYY-MM-DD
source:          # optional path to repo doc or file
---

# <exact claim as title>

<2–5 sentences>

## Project files

- `/home/nes/Projects/cardvault/pokemon_card_vault/...`

## Connects to

- [[related claim]]

## Enables

- [[downstream claim]]

## Index

- [[00 Pokoin hub]] · [[Pokoin topology]] · [[MOC …]]

## Part of

- [[One Pokoin account is shared across web extension wallet and APIs]]
- [[cardvault is the production hub for pokoin.com marketplace and APIs]]
```

Template on disk: `Pokoin/Templates/Template Pokoin zettel.md`

### 2) Event (session / ship digest)

- Filename: `YYYY-MM-DD <short topic>.md` under `Pokoin/Events/`
- Summarize what shipped, what was discovered (not assumed), and link every new Permanent note under `## Output`
- Link the Event from `00 Pokoin hub.md` → **Events** list (newest first)

Template: `Pokoin/Templates/Template Pokoin event.md`

### 3) MOC (map of content)

- Thin index only: bullets of `[[wikilinks]]` + short path hints
- Do **not** put long prose in MOCs
- Update `MOC Pokoin project files by repo` when adding file-level Permanent notes

---

## Codex procedure (copy this checklist)

```text
[ ] 1. SSH / open /home/nes/Obsidian/Pokoin (never the nezopt stub)
[ ] 2. Read 00 Pokoin hub.md + relevant MOC(s)
[ ] 3. Search Permanent/ for an existing note with the same claim
[ ] 4. Prefer UPDATE over inventing a duplicate
[ ] 5. Write Permanent notes (one claim each) using Template Pokoin zettel
[ ] 6. If this was a ship/session: write Events/YYYY-MM-DD ….md
[ ] 7. Link new notes from hub Events + correct MOC(s)
[ ] 8. Paths in ## Project files use /home/nes/Projects/... (Pi paths)
[ ] 9. Do NOT invent repo paths — only files that exist in the working tree
[ ] 10. Seed Honcho with 1–3 short conclusions (claims only), not note bodies
[ ] 11. If a convention locked: record Codevira decision; point Obsidian at it
[ ] 12. Update cardvault memory/*.md only when architecture/security/state changed
```

### Drafting help

Qwen / local LLM may draft zettels; **the writing agent must reject invented paths** (e.g. fake `src/marketplaces/...`). Every `## Project files` path must exist.

### Path convention

- On the Pi vault, prefer **`/home/nes/Projects/cardvault/...`** (Pi checkout).
- If documenting from nezopt only, still write Pi-style paths when that is the canonical tree; otherwise use the real absolute path and say which host.

---

## Examples of good vs bad

| Bad | Good |
| --- | --- |
| Dump a whole API file into a note | Claim + path + links |
| “Scan stuff” as title | `The phone must not free the pairing on pagehide` |
| Notes under `cardvault/obsidian/` | Notes under `/home/nes/Obsidian/Pokoin/Permanent/` |
| Duplicate claim with new wording | Edit the existing Permanent note |
| Secrets / tokens / `.env` | Never — see `memory/secrets-workflow.md` |

---

## What already exists (do not rebuild from scratch)

- Spine notes linked from the hub (account unity, cardvault hub, topology)
- MOCs for extension, repos, online services, public ids, catalog SEO, scan index, project files by repo
- Hundreds of Permanent notes for API files, Flutter services, extension sources, deploy scripts
- Dated Events through at least 2026-09-17 (Scan Connect, SEO, extension leftover, etc.)

Before creating a “whole vault” for Pokoin again: **read the hub and search Permanent.**

---

## Repo stub reminder

`/home/nez/Projects/pokoin/obsidian/README.md` exists only to redirect agents to the Pi. Do not flesh that folder out as a second vault.

---

## Related repo files

- `memory/cursor-to-codex-handoff.md` — session resume for Codex
- `memory/architecture.md` / `memory/current-state.md` — operator state
- `memory/flareon-handoff.md` — short awareness sync (not Obsidian)
- Pi: `Templates/AI project vault notes.md` — same policy, vault-native
