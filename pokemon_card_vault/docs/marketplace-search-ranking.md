# Marketplace search ranking (files, functions, `search_weight`)

Canonical for typeahead vs catalog rank. Related: [`workflows/meilisearch-peer-workflow.md`](../workflows/meilisearch-peer-workflow.md), Flutter name-intent rules in [`workflows/cardtrader-search-preview-workflow.md`](../workflows/cardtrader-search-preview-workflow.md) (§ plain prefixes / `pikac`).

Live: Meili on **pi-home** `127.0.0.1:7700` (`pokoin-meili` v1.53.1), API Docker `pokoin-oracle-api`, public `https://api.pokoin.com`. Handlers are under `/api/…`. Index files stay locked in RAM (`pokoin-meili-resident.service` / `vmtouch -l`); see the Meili workflow.

## Verdict: `search_weight` is intended catalog score, not dead code

`marketplace_search_candidates.search_weight` is a **small static “interestingness” integer** (typically 0–40). It was designed in May 2026 with the search-candidate table as an **additive tiebreaker** under SQL name/token scores of hundreds–thousands.

It is **not** leftover unused columns. Home, SQL search RPCs, Flutter autocomplete, name-index sync, and Meili all still read it.

It is **the wrong primary rank for typeahead**. Meili’s linguistic rules **tie** on a prefix like `mimik`, so `search_weight:desc` becomes the only sort — and the formula **boosts GX/EX/VMAX and products**. That contradicts the Flutter rule: plain prefix → base display name first (`pikac` → Pikachu before Pikachu GX).

| Question | Answer |
| --- | --- |
| Delete the column? | **No.** Home, SQL token search, Flutter hot/empty pool, Meili search-page order still use it. |
| Invert GX/product bonuses in Postgres? | **Not without a product call.** That would change home fallback order and SQL catalog ties, not only the popup. |
| Where typeahead was fixed (2026-09-01) | `api/_meili_suggest.js` reorders **groups** after Meili. No Meili reindex. Formula unchanged. |

Lived example `q=mimik` (before suggest rerank): Meili `words`/`typo`/`proximity`/`attribute`/`exactness` all identical; then weight 24 (Mimikyu GX) beat 16 (pin/coin) beat 14 (Mimikyu). Popup showed GX first.

---

## Three client pipelines

```text
pokoin-web header (Chrome.jsx, 120ms debounce, min 2 chars)
  GET /api/marketplace-suggest?q=
    → Meili hits (display fields only, no SQL)
    → groupSuggestHits + suggestGroupTier  (name intent)
    → groups[] of printings

Flutter searchbar
  POST /api/marketplace-autocomplete
    → Meili ID pool (optional) + SQL name/token fanout
    → name_score / compact-name tiers  (hundreds–hundreds of thousands)
    → + capped search_weight  (must not invert name tiers)

Search results page (pokoin-web)
  GET /api/marketplace-search-page?query=
    → Meili IDs in Meili order (search_weight last rule)
    → SQL identity hydrate only (lightHydrate: true)
    → cheapest_homepage_cache_blueprint overlay (listed PKN), not the snapshot listing join
```

Non-English title language uses the same English-identity Meili index
(`language = "en"`). Localized names from `card_name_languages` are extra
`nicknames`. After grouping, `attachTitleLanguageOnGroups` stamps
`localized_name` / `localized_set` / `localized_rarity` so the SPA popup
switches copy when the title-language flag changes. `useMeiliSearchForLanguage`
is on for every title-language code.

---

## Extra suggest pipeline blocks (easy to revert)

These sit **after** Meili and name-intent. They do **not** change `search_weight`, Meili ranking rules, or the search-page ranker.

```text
Meili hits (name + number, up to 96, `_rankingScore` unchanged)
  → rememberHotSuggestQuery          BLOCK: hot query
  → groupSuggestHits (name intent, printing pool 96)
  → attachExpansionNationality
  → applySuggestPrintPriority        BLOCK: western tie-break + 20-cap
  → JSON groups[]

Enter / GET marketplace-search-page offset 0
  → takeHotSuggestCandidates (same IDs, skip second Meili)
  → SQL identity hydrate
SPA: prefetchSearchPage after typeahead so Enter paints from memory
```

### Western popup cap (`api/_suggest_western_priority.js`)

Visual only. Among printings that already share the same Meili `_rankingScore` (rounded to 4 decimals), show `nationality=western` before JP/CN, then cap 20. A western row with a **lower** score never jumps a higher-scoring JP/CN row. `search_weight` is not read or written.

Print-language pill (`print_language=japanese|chinese|western`) filters **before** the 20-cap.

Revert: `SUGGEST_PRINT_PRIORITY=0` (alias `SUGGEST_WESTERN_FIRST=0`), or delete the `applySuggestPrintPriority()` call in `marketplace-suggest.js`.

### Hot query (`api/_suggest_hot_query.js` + `pokoin-web/market/src/search-hot.js`)

Typeahead already paid for Meili. Keep those card IDs in process memory (60s, not Valkey) so search-page offset 0 hydrates them. The SPA prefetches the first search page while the popup is open.

Revert: `SUGGEST_HOT_QUERY=0`, and/or stop calling `prefetchSearchPage` from `Chrome.jsx`.

---

## File and function inventory

### pokoin-web (popup UI)

| File | What |
| --- | --- |
| `pokoin-web/market/src/components/Chrome.jsx` | Combobox. `useEffect` debounce **120ms**, `fetchSuggest(term, { limit: 20 })`, prefetch search page, keyboard, “View all N” → `/marketplace/search?q=`. |
| `pokoin-web/market/src/search-hot.js` | **SPA hot-query block.** Prefetch `marketplace-search-page` after suggest. Revert: stop calling it from Chrome. |
| `pokoin-web/market/src/api.js` | `fetchSuggest` → `GET /api/marketplace-suggest?q=&limit=&search_language=&print_language=`. `fetchSearch` → search-page BFF. Do not GET autocomplete. |
| `pokoin-web/docs/MARKET.md` | Client contract for which URL the SPA may call. |

### Suggest API (Meili-only typeahead)

| File | Functions / role |
| --- | --- |
| `api/marketplace-suggest.js` | `createHandler`. GET only. Empty/`meili_unavailable`/`meili_error` → `{ groups: [] }`. Meili → hot cache → `groupSuggestHits` → nationality → **western tie-break** → cap 20. Cache `max-age=5, s-maxage=30`. |
| `api/_suggest_western_priority.js` | **Visual tie-break only.** Same Meili points → western before JP/CN, then cap 20. Does not touch `search_weight`. `SUGGEST_PRINT_PRIORITY=0` disables. |
| `api/_suggest_hot_query.js` | **Hot Meili IDs** for search-page offset 0. Process memory, 60s. `SUGGEST_HOT_QUERY=0` disables. |
| `api/_meili_suggest.js` | **Name-intent rank for the popup.** `groupSuggestHits`, `suggestMeiliHitLimit`. Hit pool `max(groupLimit*8, 48)` capped at **96**. Copies `_rankingScore` onto printings as `_rank` (stripped before JSON). |
| `api/marketplace-suggest.test.js` | Document mapping, grouping cap, Meili-only (no SQL fallback), `mimik` → Mimikyu before GX, `mimikyu gx` → GX first. |
| `server/api-route-manifest.js` | Route `/api/marketplace-suggest`. |
| `api/_client_contract.js` | Live `GET /api/__contract` `pageApis.suggest` / `search.suggest`. |

`suggestGroupTier` (lower wins):

| Tier | When |
| --- | --- |
| 0 | Compact group name equals compact query (`mimikyu gx` → Mimikyu GX) |
| 1 | Query is a prefix **of the card name** (`mimik` → Mimikyu; `mimikyu g` → Mimikyu GX) |
| 2 | Extra tokens beyond a base name that are **not** variant prefixes (`charizard base` stays Charizard) |
| 3 | Variant name the query is not typing into |
| 4 | Product-ish tokens (`collection`, `pin`, `coin`, `tin`, …) |
| 5 | Extra leftover is a variant prefix (`g`/`e`/`v`) but this group’s **name** does not continue it (base Mimikyu under `mimikyu g`) |
| 6 | No prefix relationship |

Leftover `g` is treated as typing **GX in the card name**, not Guardians Rising / GX Starter Decks in the set. Leftover set tokens (`palkia cl` → Call of Legends) reorder printings already in the pool by compact set name / `expansion_aliases`; they do not add set names to Meili typeahead search-on. Suggest Meili uses `attributesToSearchOn` name + collector number + **card nicknames** (`Moonbreon`), not set names. Search **page** still searches set names and `expansion_aliases` (PAL, SM1S, CSV10, …). Source: `data/pokemon_tcg_expansion_shortnames_and_card_nicknames.txt`. Do not alias `EX` (Expedition vs the EX mechanic).

Variant words match Flutter `MODIFIER_ONLY_ANCHOR_WORDS` in `marketplace-autocomplete.js` (`gx`, `ex`, `v`, `vmax`, `vstar`, `mega`, …). Tie-break: shorter compact name, then higher group `_weight` (`search_weight` from Meili, not returned to the client).

### Meili client, documents, sync

| File | Functions / role |
| --- | --- |
| `api/_meili_client.js` | `meiliHost`, `meiliApiKey`, `meiliConfigured`, `meiliRequest`, `meiliSearch`, `defaultIndexName`. Host from `MEILI_HOST`. Do not log the key. |
| `api/_meili_marketplace.js` | `queryTokens`, `meiliMarketplaceCandidates` (search **page** IDs + `_rankingScore`), `meiliMarketplaceSuggestHits` (popup: `attributesToSearchOn` name + number, not set), `meiliPredictedNameTokens` (Flutter token index). Filter `language = "en"`. |
| `api/_meili_document.js` | `preferFullImage` (never `/previews/`), `meiliMarketplaceIndexSettings` (searchable attrs + ranking rules), `MARKETPLACE_MEILI_SYNC_SELECT`, `mapMarketplaceMeiliDoc`. **`name_group` is currently the full `name`** (GX is a separate group from Mimikyu — correct). `search_weight` copied from Postgres. |
| `api/_marketplace_canonical_path.js` | `canonicalPathForRow` for suggest hrefs without loading the shortlink route. |
| `api/_marketplace_search_engine.js` | `useMeiliSearch`, `useMeiliSearchForLanguage` (all title langs; Meili docs stay `language=en`). Env `MARKETPLACE_SEARCH_ENGINE=meili`. |
| `scripts/meili-sync-marketplace-full.js` | Full reindex from `MARKETPLACE_MEILI_SYNC_SELECT`. Live: `MEILI_SYNC_BATCH_SIZE=400` on the 1 GB micro. ~74k docs. |
| `scripts/meili-sync-marketplace-delta.js` | Incremental `--since=`. systemd timer on the marketplace VM. |
| `scripts/meili-sync-name-tokens-full.js` | `marketplace_name_tokens` for Flutter prediction. Orders representative IDs by `search_weight desc`. |
| `deploy/systemd/pokoin-meili-marketplace-delta.{service,timer}` | Delta on this VM, not peer3. |
| `deploy/meili/*` | Install / `meili.toml` example. Data dir `/var/lib/meilisearch` — **do not wipe**. |

Meili ranking rules (`meiliMarketplaceIndexSettings`):

1. `words`
2. `typo`
3. `proximity`
4. `attribute`
5. `exactness`
6. **`search_weight:desc`** ← only remaining discriminator when 1–5 tie (typical prefix typeahead)

### Search page (not the popup)

| File | Functions / role |
| --- | --- |
| `api/marketplace-search-page.js` | BFF. `rowsForCards({ lightHydrate: true })`. |
| `api/marketplace-cards.js` | `rowsForCards` → `rowsForSearchTerm` when EN Meili. Forwards `lightHydrate`. Flutter `GET /api/marketplace-cards` keeps default `lightHydrate: false` (listing hydrate). |
| `api/marketplace-search-candidates.js` | SQL name/number/variation fanout **and** Meili page path. `rowsForMeiliSearchTerm`, `searchRowsByCardIdsIdentity` (no listing-cache), `searchRowsByCardIdsWithDatabase`, `rankRowsByQueryCollectorNumber`. Token SQL still does `token_score + search_weight`. |
| `api/_marketplace_react_card.js` | `toReactCards`, `availabilityKnown` (search tiles must not all say Out of stock when listings were skipped). |

Search **page** still follows Meili order (GX can still outrank base Mimikyu on `?q=mimik` until a separate page rerank). Only the **header popup** was reranked 2026-09-01.

### Flutter autocomplete (legacy ranker — still live)

| File | Functions / role |
| --- | --- |
| `api/marketplace-autocomplete.js` | 7k-line searchbar. `nameTokenSearchRank` (compact exact 240000 / prefix 120000 / … + `baseDisplayBonus` 100000 + **capped `search_weight` ≤ 5000**). SQL `matched_names.name_score` (1400 exact / 1220 prefix / …) **`+ c.search_weight`**. Hot/empty pool: `search_weight + analytics`. `MODIFIER_ONLY_ANCHOR_WORDS`. |
| `api/searchbar-cards.js` | Wrapper around autocomplete ranking. |
| `api/searchbar-token-predict.js` | Name-token prediction; uses capped `search_weight`. |

Name-intent here is supposed to **dwarf** `search_weight`. Workflow still warns: do not let popularity invert `pikac` vs Pikachu GX.

### Postgres: column, refresh, RPCs

| File | Functions / role |
| --- | --- |
| `oracle-postgres/schema/001_marketplace_core.sql` | Column `marketplace_search_candidates.search_weight numeric not null default 0`. Indexes `(name_prefix, search_weight desc, …)`, set_prefix, expansion_name. |
| `oracle-postgres/schema/002_marketplace_functions.sql` | **`refresh_marketplace_search_candidates()`** — **live writer of the formula** (see below). Also `refresh_marketplace_cards_from_blueprints` / `classify_marketplace_product_type` (`item_kind` single vs product). |
| `oracle-postgres/schema/003_marketplace_search_rpc.sql` | Token RPCs: `token_score + {300–1320} + search_weight`. Weight is a **+0–40 bump** on a 300–1400 match. |
| `oracle-postgres/schema/004_marketplace_home.sql` | Home SQL; chase-name regex includes GX/EX (section eligibility), not the weight formula itself. |
| `supabase/migrations/20260518211500_marketplace_search_candidates.sql` | **Original** formula + `search_marketplace_candidates()` rank_score = name match (1200/1000/…) **+ suffix-name bonus 360** **+ search_weight**. Historical source. |
| `scripts/sync-card-name-index-to-supabase.js` | Recomputes a **subset** of the formula for the name-index (no product +12; products excluded). |

### Other readers (still intended)

| File | Use |
| --- | --- |
| `api/marketplace-home.js` | Fallback carousel: `item_kind = 'single'` `order by search_weight desc` (GX/rares float up on home when the hot snapshot is empty). |
| `api/marketplace-home-page.js` | React home BFF; uses indexed newest-set SQL, not this weight, for new arrivals. |
| `api/pokoin-assistant.js` | Candidate order `search_weight` with a small cap in the rank mix. |
| `api/marketplace-competitive.js` | Tie-break after Limitless confidence. |
| `api/marketplace-card-cheapest-price.js` | Tie-break. |
| `scripts/sync-limitless-expansion-blueprints.js` | Pick a card row `order by search_weight desc`. |
| `api/_cardtrader_daily_listings_refresh.js` / `_cardtrader_blueprint_listing_cache_refresh.js` | Refresh order, not user typeahead. |

### Tests / ops

| File | Role |
| --- | --- |
| `scripts/check-oracle-api-server.js` | Origin `/` landing, `__contract`, route load. |
| `scripts/check-api-guardrails.js` | Manifest includes `marketplace-suggest.js`. |
| `scripts/generate-api-docs.js` | Regenerates `docs/oracle-api-migration.md`. |

---

## The formula (live Oracle)

Written by `refresh_marketplace_search_candidates()` in `002_marketplace_functions.sql`:

```text
search_weight =
    +12  if item_kind = 'product'
    +8   if rarity ILIKE '%rare%'          -- "Ultra Rare" yes; many rows store rarity 'Card' → 0
    +10  if name matches word-boundary ex | vmax | vstar | gx | lv.x
    +10  if card_number contains '/'       -- has a collector number
    +6   if trainer_name <> ''
    +4   if preview_image_url is not null
```

Lived `mimik` documents:

| Name | Weight | Breakdown |
| --- | --- | --- |
| Mimikyu GX (Lost Thunder) | 24 | GX +10, slash +10, preview +4 (`rarity` often `Card` → no +8) |
| Mimikyu Pin / Coin | 16 | product +12, preview +4 |
| Mimikyu (Cosmic Eclipse) | 14 | slash +10, preview +4 |

Original Supabase migration also had `+8` when `card_number` matched illustration/secret/promo/gold/shiny. **Oracle refresh dropped that term.** Name-index sync drops product +12 because it only indexes singles.

`search_marketplace_candidates` (legacy SQL search) **also** adds +360 when the **query** is a prefix of `Name GX/EX/…` (the opposite of typeahead: it *boosts* suffix variants when you type the base name). That RPC is not the pokoin-web popup.

### Why those bonuses exist

They are **catalog heuristics from the first search-candidate projection**, not analytics and not “leftover unused”:

- **Product +12** — sealed SKUs sort above a random common when the query is weak or empty.
- **GX/EX/VMAX +10** — chase names win ties (home fallback, mixed SQL pages).
- **Rare +8 / slash +10 / preview +4** — prefer numbered, imaged, “looks like a real card” rows over junk titles.
- **Trainer +6** — owner/trainer forms slightly up.

For **typeahead name intent they are the wrong sign**. Flutter’s written rule (and now `_meili_suggest.js`) is: do not let this score bury `Mimikyu` under `Mimikyu GX` when the user typed `mimik`.

---

## What each layer is allowed to do with the number

| Layer | Role of `search_weight` |
| --- | --- |
| SQL token / name_score | Additive **after** a 300–1400 (or 100k+) name score. Cannot invert exact/prefix name tiers if those scores are applied. |
| Flutter `nameTokenSearchRank` | Capped 0–5000 on top of 60k–240k name tiers. Same idea. |
| Home fallback | **Primary** sort among singles with stock. GX-first is **intentional** here. |
| Meili rules | Last rule. Becomes **primary** when the query is a shared prefix. |
| `GET /api/marketplace-suggest` | May use it only as **intra-tier** tie-break after `suggestGroupTier`. |
| `GET /api/marketplace-search-page` | Still Meili order (GX can lead). Page rerank not done. |

---

## Smoke

```bash
curl -sS 'https://api.pokoin.com/api/marketplace-suggest?q=mimik&limit=12'
# groups[0].name should be Mimikyu, not Mimikyu GX

curl -sS 'https://api.pokoin.com/api/marketplace-suggest?q=mimikyu%20gx&limit=8'
# groups[0].name should be Mimikyu GX

curl -sS 'https://api.pokoin.com/api/marketplace-suggest?q=palkia%20cl'
# first Palkia printing should be Call of Legends (CL), not Surging Sparks

curl -sS 'https://api.pokoin.com/api/marketplace-search-page?query=SM1S'
# Collection Sun cards (Japanese printed code)

curl -sS 'https://api.pokoin.com/api/marketplace-search-page?query=CSV10'
# Chasing Glory / Together in Pursuit
```

Ship popup rank: rsync `api/_meili_suggest.js` `api/marketplace-suggest.js` `api/_suggest_western_priority.js` `api/_suggest_hot_query.js` `api/marketplace-search-candidates.js` → bind-mount, `docker restart pokoin-oracle-api`. Changing the SQL formula requires `refresh_marketplace_search_candidates()` then a Meili full sync — do not do that for typeahead. New expansion aliases or card nicknames: `node scripts/seed-tcg-search-aliases.js` on nezopt 15T, then `node scripts/meili-sync-marketplace-full.js` on the Pi (delta `--since` misses alias/nickname fields on old docs).
