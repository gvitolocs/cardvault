# Poko Peer4 Site-Data Schema Guide

Poko may use peer4 marketplace Postgres as a read-only site-data source through
server-side helper functions only. Chat users must never receive arbitrary SQL
execution, database credentials, auth tokens, or raw private identifiers.

Use `POKO_ASSISTANT_READONLY_DATABASE_URL` for the assistant runtime when
available. That database role should have `CONNECT` plus `USAGE` on `public` and
`SELECT` on the readable site-data tables/views only. If the env is absent, the
code can still use existing marketplace read helpers, but production should move
Poko to a least-privilege read-only credential.

## Join Keys And URL Rules

- `card_id` and `blueprint_id` refer to the same marketplace/Pokoin blueprint id
  in marketplace card tables. Some tables keep `card_id` as text
  (`marketplace_user_listings.card_id`) and must cast only after numeric checks.
- Marketplace public card page ids are doubled blueprint ids:
  `publicPageId = card_id * 2`. Internal queries should join by `card_id` /
  `blueprint_id`, then use `marketplace_card_urls.canonical_path`.
- `marketplace_card_urls.card_id` joins to
  `marketplace_search_candidates.card_id` and stores the canonical internal card
  path. Poko should navigate only to safe internal paths from this table.
- Limitless deck cards map to marketplace cards through
  `limitless_marketplace_expansion_blueprints.blueprint_id`, `set_code`,
  `collector_number`, and normalized card names.

## Core Card Tables

- `cardtrader_pokemon_blueprints`: raw marketplace blueprint source for Pokemon
  cards/products. Internal table name is provider-specific; Poko must not mention
  the provider name to users. Key: `id`. Contains names, expansion JSON, image/CDN fields,
  editable properties, card palette, emoji, and raw blueprint data.
- `cardtrader_pokemon_expansions`: marketplace expansion source rows used for set
  browsing and projection. Do not expose the provider name in chat.
- `marketplace_cards`: projected marketplace card rows used by app search/browse
  surfaces before the richer candidate/version projections.
- `marketplace_card_versions`: one row per projected card version with name,
  display/canonical name, expansion, number, product variant, image fields, and
  `blueprint_id`.
- `marketplace_search_candidates`: main assistant/search candidate table. Key:
  `card_id`. Contains names, set, number, rarity, item/product type, image
  fields, `search_text`, prefixes, and `search_weight`.
- `marketplace_card_urls`: canonical direct marketplace card URLs. Key:
  `card_id`; use `canonical_path` for Poko navigate actions.
- `marketplace_pokemon_name_roots`, `marketplace_card_names`,
  `marketplace_name_ngrams`, `marketplace_card_names_en/it/fr/de/es/pt/id/th/ja/zh_*`,
  `marketplace_card_name_translations`, and
  `marketplace_expansion_name_translations`: name, translation, and ngram indexes
  for typo-tolerant search and multilingual matching.
- `marketplace_rarities`, `marketplace_expansion_numbers`,
  `marketplace_variations`, `marketplace_expansion_aliases`,
  `marketplace_card_variations`, `cards_type`, and `cards_name_type`: controlled
  dimensions for rarity, set, variation/type, and autocomplete/filtering.

## Card Enrichment Tables

- `marketplace_blueprint_artists`: artist/illustrator authority keyed by
  `blueprint_id`/generated `card_id`. Use `artist`, `illustrator`, and
  `normalized_artist` for display and artist-themed recommendations.
- `marketplace_artist_profiles`: artist profile text/images keyed by
  `normalized_artist`. Use for public artist context, not as a ranking source
  unless explicitly needed.
- `marketplace_blueprint_tcg_metadata`: TCG metadata keyed by `blueprint_id` /
  `card_id`; includes set metadata, types, HP, stage, attacks, abilities,
  weaknesses, resistances, retreat, description, flavor text, regulation mark,
  legal flags, and raw metadata. Useful for theme/type matching such as ice,
  fire, dragon, or beginner explanations.
- `marketplace_blueprint_emojis` and `marketplace_card_emoji_rules`: curated
  public display emoji/identity metadata. Do not use rare unsupported emoji in
  assistant replies.
- `marketplace_blueprint_classification_overrides` and
  `marketplace_artist_debug_skips`: admin/debug projection controls. Poko can
  understand their meaning but should not query them for user-facing advice.

## Analytics, Hotness, Stock, And Price

- `marketplace_card_events`: raw site events (`view`, `search`, `click`,
  `reserve`, `cart_add`, `sale`) with `card_id`, weight, metadata, and time.
  Some rows may contain pseudonymous `user_uid`; Poko helpers should aggregate
  counts and never expose identifiers.
- `marketplace_hot_blueprints`: rollup keyed by `blueprint_id` with 1h/24h/7d
  views, searches, clicks, cart adds, reserves, sales, hot scores, and last event
  time. Preferred source for popularity/hotness recommendations.
- `marketplace_price_observations`: price observations by blueprint/source and
  listing dimensions.
- `marketplace_blueprint_price_table`: dimensioned price table by blueprint,
  condition, language, reverse/foil/graded/sealed/signed flags, listing counts,
  ask stats, and source counts.
- `marketplace_blueprint_price_summary`: one row per blueprint with active
  listing count, listed quantity, floor/median/average/high ask, observations,
  and source counts. Preferred source for simple floor/stock context.
- `marketplace_user_listings`: native Pokoin seller asks and stock. It includes
  seller fields and listing ids, so Poko should use it only through controlled
  listing/price templates that return card, price, condition, stock, and safe
  seller display context when necessary.
- `cardtrader_blueprint_listing_cache` and
  `cheapest_homepage_cache_blueprint`: cheapest/eligible partner or native
  listing cache keyed by `blueprint_id`, with PKN/EUR floor-like prices, eligible
  listing/quantity counts, sample external listing/product ids, country/shipping
  metadata, and freshness timestamps.
- `cardtrader_market_listing_snapshots`,
  `cardtrader_market_listing_removed_history`,
  `cardtrader_user_listing_snapshots`,
  `cardtrader_user_listing_removed_history`, and
  `cardtrader_blueprint_daily_analytics`: partner listing snapshots/removal
  and daily analytics for stock, sold-count, sell-through, and historical price
  signals. These are site/market data, but user/seller fields must not be exposed
  directly in chat.
- `marketplace_card_watchlist_analytics` and
  `marketplace_card_cart_analytics`: aggregate watchlist/cart interest counts.
  Prefer these over `_users` tables.
- `marketplace_card_watchlist_users` and `marketplace_card_cart_users`: contain
  holder/user keys for aggregate rebuilds. Do not select raw holder keys for
  Poko replies.
- `marketplace_query_chunk_events`: search query analytics for internal search
  quality. Treat as aggregate search-signal data only.

## CardMarket Parsing/Refinement Tables

- `marketplace_cm_expansion_parsing`, `marketplace_cm_product_parsing`,
  `marketplace_cm_expansion_rules`, `marketplace_cm_verified_links`,
  `marketplace_cm_scrape_observations`, and `marketplace_cm_refinement_log`:
  CardMarket parsing, mapping, and diagnostic records. Useful for backend
  quality/debug context, not normal Poko recommendations.

## Limitless Competitive Deck Tables

- `limitless_games`: game metadata and formats/platforms from Limitless.
- `limitless_tournaments`: tournament metadata, dates, player counts, formats,
  online/public flags, source URLs, and fetched timestamps.
- `limitless_players`: public player rows from Limitless. Avoid using player
  identity in chat unless directly tied to a public deck result.
- `limitless_tournament_standings`, `limitless_tournament_pairings`,
  `limitless_decklists`, and `limitless_deck_cards`: imported tournament
  standings, pairings, decklists, and card rows.
- `limitless_public_decks`: public metagame deck archetypes with rank, points,
  share, variants, source URL, and freshness.
- `limitless_public_deck_core_cards`: core/inclusion cards per public archetype.
- `limitless_public_deck_results`: recent public results by archetype,
  tournament, placing, variant, player, and decklist id.
- `limitless_public_deck_players`: public ranked players for a deck archetype.
- `limitless_public_tournaments` and
  `limitless_public_tournament_standings`: public tournament summaries and
  standings.
- `limitless_public_decklist_cards`: public decklist card rows by decklist id.
- `limitless_marketplace_expansions` and
  `limitless_marketplace_expansion_blueprints`: bridge Limitless card names/set
  codes/numbers to Pokoin `blueprint_id`/`card_id` for safe card-page links.

## Operational/Admin Tables Not For Poko Replies

- `marketplace_cardtrader_import_jobs`, `limitless_sync_runs`, and refresh
  function state are operational job data.
- `flutter_debug_logs`, `marketplace_firebase_users`, and
  `assistant_user_current_pages` are user/debug/session data. Do not include them
  in Poko recommendation prompts or query templates.

## Safe Query Patterns

- Prefer controlled helpers:
  `queryCardRecommendations({ subject, theme, style, budget, language, userPreferences })`
  and deck-advisor queries. These accept structured intent fields, not SQL.
- Always select from site-data tables using fixed SQL templates with bind
  parameters. Never concatenate raw user text into SQL.
- Recommendation ranking should use contextual relevance first, then hotness,
  stock, active listings, price summaries, partner availability/cache, artist/type/theme
  metadata, and only then generic search weight.
- For deck advice, use `limitless_public_decks`, core cards, recent public
  results, and source URLs. Explain uncertainty; do not invent live win rates.
- For privacy, return aggregate counts, public card/deck metadata, and safe
  paths. Do not return raw `user_uid`, holder keys, Firebase data, tokens,
  secrets, debug logs, or arbitrary JSON metadata that may contain operational
  details.
