<!-- codevira:begin (auto-generated; do not edit) -->

## Codevira-tracked project memory: cardvault

### Locked decisions (do_not_revert)

- **D000001** Cursor Honcho MCP uses peer1 self-hosted Docker via SSH tunnel (:18765) and local wrangler MCP (:18787); HONCHO_API_KEY…  ·  `.env.honcho.local`  ·  _cardvault, honcho, secrets_
- **D000002** Hermes/Flareon operator secrets live only in ~/Hermes/private/flareon/ (local) and /opt/hermes-flareon/secrets/ (peer1)…  ·  `docs/flareon-secrets.md`  ·  _flareon, hermes, secrets_
- **D000003** Flareon Pokoin awareness without code dumps: edit cardvault/memory/flareon-handoff.md then run cardvault/scripts/sync-f…  ·  `memory/flareon-handoff.md`  ·  _flareon, memory, pokoin_
- **D000004** Pokoin app runtime secrets (Stripe, DB, Oracle API) belong in pokemon_card_vault/.env.local and server env on peer3 — n…  ·  `pokemon_card_vault/.env.local`  ·  _pokoin, secrets, security_
- **D000005** Production English marketplace autocomplete/searchbar uses Meilisearch for candidate retrieval; Oracle remains the hydr…  ·  `pokemon_card_vault/workflows/meilisearch-peer-workflow.md`  ·  _meili, pokoin, production, search_

### Active conventions

_None yet._


For the full decision log + outcomes + reverts, see `.codevira/decisions.jsonl` or run `codevira list-decisions`.

<!-- codevira:end -->
