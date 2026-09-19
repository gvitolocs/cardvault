# Pokoin card ids

**Our id** is the only marketplace id. `marketplace_cards.card_id` is the old
CardTrader blueprint multiplied by 2. We **do not use `ct_id`** in URLs, API
public fields, Flutter `card.id`, or image URLs.

Examples: Espurr `220962`, Magcargo `587148`, Dachsbun `598052`.

`018_pokoin_card_id_ct_id.sql` is applied on the Oracle dump primary
(`pokoin-marketplace`). The Pi replica follows. Do not apply writes on the replica.

Codevira: CardVault **D00000B** (supersedes D00000A). BattleScan **D00000E**
(supersedes D000009). D00000A said CDN/internal ids stay on the scrape
original — that is stale.

## Namespaces

| Name | Formula | Example (Espurr BREAKpoint 58/122) | Where it lives |
| --- | --- | --- | --- |
| **Our id** | leftover `ct_id` × 2 | `220962` | `marketplace_cards.card_id`, paths `/{n}` and `/marketplace/en/cards/{n}/…`, API `cardId`, Flutter `card.id`, image URL prefix |
| **ct_id / Milo `id`** | leftover CardTrader blueprint | `110481` | R2 object prefix, Postgres join, scan gallery `hit.id` (`identity: ct_id`). **× 2** for the desk. Not a TCGplayer product id. |

There is no public `ct_id`. A leftover DB column or R2 object name may still
hold the old blueprint number. That is storage / a CardTrader join key, not
an id we expose. Do not rewrite our id back to that number in API or Flutter.

`pokoin_public_number(n)` / `doubledCardId` convert a **raw** leftover
`ct_id` (Milo `hit.id` / CLIP blueprint) → our id. Catalog `card.id` is already
our id — running `doubledCardId` on it 4×s.

## CDN

Public image URLs use **our id** (`/{card_id}_…`). Leftover R2 keys may still
be named with the old blueprint number. The CDN must map our id to the
object; do not tell clients to request the old number.

## Lookups

- `GET /api/marketplace-card-url?cardId=220962` (our id) → Espurr.
- Autocomplete `rows[].card_id` is our id.
- Flutter `CardDetailScreen.cardId` and `PokemonCard.id` are our id.
- Never treat an even path number as "still doubled" and half it again.
- Sales lookups (`marketplace-card-sales`) must **prefer `card_id`**, then leftover `ct_id` only if that number is not already a public id. `OR ct_id` without that order mixes another card’s sold comps (Hidden Fates Mew `242572` + Morpeko V-UNION blueprint `242572` → fake 1,660 PKN). Same rule as `_marketplace_leftover`.

## Parse

`canonical_path` is `/marketplace/en/cards/{card_id}/…` with **our id**.

Espurr: **our id `card_id=220962`**,
`canonical_path=/marketplace/en/cards/220962/card-espurr-58-122-breakpoint`.

```bash
curl -sS 'https://api.pokoin.com/api/marketplace-card-url?cardId=220962'
curl -sS -D - -o /dev/null 'https://api.pokoin.com/api/marketplace-card-shortlink?path=/marketplace/220962'
curl -sS -D - -o /dev/null 'https://pokoin.com/220962'
```

## Code map

- SQL: `oracle-postgres/schema/018_pokoin_card_id_ct_id.sql` (applied)
- URL build: `lib/utils/card_url.dart` — paths take **our id**; `doubledCardId` only for raw scan/CLIP blueprint
- Images: API `rewriteCdnPokoinPrefix` emits `{card_id}_`; Worker maps to leftover `{ct_id}_` R2 keys (`scripts/lib/cdn-object-key.js`)
- Scan: `lib/utils/scan_marketplace.dart` (Milo/CLIP leftover `ct_id` → × 2)
- Lookup: `api/marketplace-card-url.js`, `api/marketplace-card-shortlink.js`

## Memory

- Honcho workspace `pokoin-cursor`; Codevira CardVault D00000B, BattleScan D00000E
