# Flareon handoff — Pokoin / Cursor (summary only)

Keep this file **short** (bullets, no code dumps). Flareon on peer1 reads
`/opt/hermes-flareon/data/pokoin-handoff.md` after you run `scripts/sync-flareon-handoff-peer1.sh`.

Last updated: 2026-05-28

## What I am working on

- **Pokoin / cardvault** — marketplace, Oracle API on peer3, Flutter web on pokoin.com
- **Cursor repo root**: `/Users/giuseppe/cardvault` (Codevira + Honcho `pokoin-cursor`)

## Recent Cursor topics (no code)

- Honcho Cloud + Codevira memory setup for Pokoin (workspace `pokoin-cursor`, separate from full coding blobs in Hermes personal chat)
- OpenAI subscription proxy for Cursor via peer1 tunnel `https://hermes-flareon-codex.loca.lt/v1` (`codex-as-api`)
- Local Mac `codex-cursor-proxy` removed; peer1 tunnel only
- Telegram voice / Flareon transcription uses ChatGPT OAuth on peer1 (not raw API key)
- Pokoin English searchbar/autocomplete is now production Meilisearch-backed:
  `api.pokoin.com` and `pokoin.com/api/*` use Meili for English, non-English
  stays legacy. peer3 keeps a Meili SSH tunnel + delta-sync timer alive.

## Current focus

- Monitor Pokoin production Meili search health and ranking quality
- Do **not** assume payment/wallet/auth changes unless explicitly in progress

## Blockers / limits

- ChatGPT Plus/Codex usage limits (`429 usage_limit_reached`) can block proxy chat until reset

## What Flareon should **not** expect here

- Full file contents or thousand-line diffs
- Hermes operator secrets or Poko customer data
- Detailed Codevira decision log (use handoff bullets only)
