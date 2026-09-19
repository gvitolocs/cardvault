<!-- codevira:begin (auto-generated; do not edit) -->

## Codevira-tracked project memory: cardvault

> **Codevira** — cross-IDE persistent memory. Read it with the codevira MCP tools (`get_session_context`, `search_decisions`); do **not** open `.codevira/*.jsonl` directly — those files are large and token-heavy.

### Locked decisions (do_not_revert)

- **D000001** Cursor Honcho MCP uses peer1 self-hosted Docker via SSH tunnel (:18765) and local wrangler MCP (:18787); HONCHO_API_KEY…  ·  `.env.honcho.local`  ·  _cardvault, honcho, secrets_
- **D000002** Hermes/Flareon operator secrets live only in ~/Hermes/private/flareon/ (local) and /opt/hermes-flareon/secrets/ (peer1)…  ·  `docs/flareon-secrets.md`  ·  _flareon, hermes, secrets_
- **D000003** Flareon Pokoin awareness without code dumps: edit cardvault/memory/flareon-handoff.md then run cardvault/scripts/sync-f…  ·  `memory/flareon-handoff.md`  ·  _flareon, memory, pokoin_
- **D000006** Pokoin app runtime secrets (Stripe, DB, Oracle API, Meili master key) belong in pokemon_card_vault/.env.local and serve…  ·  `pokemon_card_vault/.env.local`  ·  _oracle, pokoin, secrets, security_
- **D00000B** Pokoin has one marketplace id: our id. marketplace_cards.card_id is the old CardTrader blueprint multiplied by 2 (Espur…  ·  `pokemon_card_vault/docs/marketplace-public-ids.md`  ·  _card-url, cdn, honcho, marketplace_
- **D00000C** Public pokoin.com strangler-replaces to Next.js using page BFFs: GET /api/marketplace-card-page, /api/marketplace-searc…  ·  `pokemon_card_vault/docs/react-page-apis.md`  ·  _react, api, marketplace, strangler_
- **D00000E** [supersedes D00000D: Lossless PNG filled R2 (~8× JPEG). Giuseppe: PNG is not viable; delete all PNG.] Do not use lossle…  ·  `pokemon_card_vault/scripts/lib/backup-r2-original.js`  ·  _cdn, r2, sanitize_
- **D00000G** Studio die-cut catalog photos (white corner ears) are rounded only — never pad a second yellow/silver rim outside an al…  ·  `pokemon_card_vault/scripts/lib/sanitize-card-image.js`  ·  _cdn, marketplace, sanitize_
- **D00000H** When a CardTrader scan is ambiguous, use images.pokemontcg.io {setId}/{number}_hires.png (Pokémon TCG API / pokemon-tcg…  ·  `pokemon_card_vault/docs/card-border-rebuild-pass.md`  ·  _cdn, marketplace, pokemontcg, sanitize_
- **D00000I** Paint the outer yellow as a straight AABB at measured T; Wizards/Neo yellow is 2.33 mm (22/600 on neo3/65), not a greed…  ·  `pokemon_card_vault/scripts/lib/sanitize-card-image.js`  ·  _cdn, marketplace, sanitize_
- **D00000M** Daily CardTrader market import uses GET /marketplace/products?expansion_id= for the whole Pokemon catalog (ct_id, not d…  ·  `pokemon_card_vault/api/_cardtrader_daily_listings_refresh.js`  ·  _cardtrader, marketplace, prices, sold_
- **D00000N** Do not paint light non-yellow interior (DP name/HP bar) as yellow ears; fillInsideDieCutEars and the 4× weld stop at me…  ·  `pokemon_card_vault/scripts/lib/sanitize-card-image.js`  ·  _cdn, dp, marketplace, sanitize_
- **D00000O** Daily CardTrader market import uses one GET /marketplace/products?expansion_id= per set, stores only the cheapest 25 li…  ·  `pokemon_card_vault/api/_cardtrader_daily_listings_refresh.js`  ·  _cardtrader, do-not-revert, marketplace, pricing_
- **D00000P** Thickness walks use belongsToPrintedRim (similarToOutline only). pokemontcg transparent corners plus a thin yellow rim …  ·  `pokemon_card_vault/scripts/lib/sanitize-card-image.js`  ·  _cdn, gold, marketplace, pokemontcg, sanitize_
- **D00000Q** Catalog image jobs read and write leftover R2 keys on the local CDN mirror at /home/nez/Projects/pokoin/PokoinTest/inde…  ·  `pokemon_card_vault/scripts/lib/local-cdn.js`  ·  _cdn, local, marketplace_
- **D00000R** [supersedes D00000L: Giuseppe prefers CardTrader foil texture on Mega Lucario 188 / Gardevoir 187. pokemontcg PNG flatt…  ·  `pokemon_card_vault/scripts/lib/sanitize-card-image.js`  ·  _cardtrader, cdn, gold, marketplace, sanitize_
- **D00000S** Sanitize: rotate the inner printed rectangle upright first (vertical yellow→face join, not the name-bar), then measure …  ·  `pokemon_card_vault/scripts/lib/sanitize-card-image.js`  ·  _cdn, deskew, marketplace, sanitize_
- **D00000T** [supersedes D000007: Giuseppe 2026-09-11: APIs are from the Pi. Meili lives with that API, not on the Frankfurt dump bo…  ·  `pokemon_card_vault/workflows/meilisearch-peer-workflow.md`  ·  _meili, pi, pokoin, production, search_
- **D00000U** Public api.pokoin.com and cdn.pokoin.com stay on pi-home (CF tunnel). Oracle pokoin-marketplace is the CardTrader dump …  ·  `memory/architecture.md`  ·  _do-not-revert, oracle, pi, pokoin, postgres, topology_
- **D00000V** Public pipeline failures return HTTP 503 {error:"We are working on a solution."} and the SPA WorkingOnIt page. Never le…  ·  `docs/API.md`  ·  _errors, pi, pokoin, uptime_

### Active conventions

_+4 more decision(s) — full log in `.codevira/decisions.jsonl`._


For the full decision log, use `search_decisions` / `list_decisions` (or the `codevira` CLI) — don't read `.codevira/*.jsonl` directly.

<!-- codevira:end -->
