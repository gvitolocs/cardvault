# CardTrader Search Preview Workflow

Use this workflow when changing marketplace autocomplete, CardTrader-style fuzzy
search, Oracle marketplace schema, or CDN preview thumbnails.

## Goal

The marketplace search should behave like CardTrader:

- Typing in `/marketplace` starts debounced remote autocomplete after 1
  meaningful character for backend warming/context, but the visible typed
  autocomplete panel opens only after 3 meaningful characters. Empty focus may
  still show hot/recent cards before typing.
- The panel must be anchored to the top-bar search field and use the field
  width. Do not let it stretch across the viewport or cover the whole page.
- The preview candidate pool is a lightweight server/client context. One
  character may warm/refine on the backend, but it must not send a huge Flutter
  local pool. Typed requests use this candidate ladder: 2 chars -> `5000`
  IDs/labels, 3 chars -> `2500`, 4 chars -> `1250`, then `500` for 5+ chars.
  Full preview rows are still capped to `searchPreviewLimit` (`20`), with about
  9 rows visible at a time and the rest reachable by scrolling.
- Google-style autocomplete contract:
  - Empty focus shows the hot 1000 cache with the user's last two recently seen
    blueprints prepended client-side, then renders 20 rows.
  - The first typed character, for example `p`, immediately starts Layer A:
    `/api/searchbar-token-predict`, a Supabase unique-name token prediction call.
    It queries `marketplace_card_name_tokens` by `compact_name`,
    `normalized_name`, and compacted `name_tokens` prefixes, then returns only
    predicted token strings plus tiny score/count metadata for ghost
    autocomplete. It must not return full card rows, context labels, Oracle
    hydration, or a broad Flutter local candidate pool.
  - Layer B remains `/api/searchbar-cards` / `/api/marketplace-autocomplete`.
    It returns rows, context IDs, candidate labels, and full ranking metadata in
    the background. Flutter must not wait for Layer B before showing a Tab ghost
    token from Layer A.
  - Longer prefixes such as `pi`, `pik`, and `pika` must refine toward stronger
    matching rows or query an equivalent matching prefix pool. They must not show
    unrelated hot rows while waiting.
  - Structured queries such as `mew 232` must let exact name plus collector
    number dominate generic popularity.
  - Trainer-owned cards such as `Ash's Pikachu` may appear only when the typed
    prefix/query actually matches them and their score earns the rank.
- Results show a small preview image, card name plus collector/expansion number,
  set and action text. Example: `Mew ex 232/091` with no `#` prefix. Typed query
  terms should be highlighted inside the result title/set text.
- Empty focus may show the server-cached hot/recent preview pool, but typing
  makes preview rows remote-authoritative. Do not seed typed previews from loaded
  Flutter cards, local home-cache rows, similar-query rows, or generic hot
  fallback rows.
- Numeric searches such as `mew 232` should be solved in the Oracle/Vercel
  backend path. Flutter may dedupe exact blueprint/card IDs while preserving
  backend order, but it must not merge local matches into typed preview rows.
- Flutter may hold the backend `search_context` as lightweight blueprint/card ID
  state for smoothing query transitions: bounded `card_ids`, depth scores,
  latest-depth/order metadata, candidate-ID ladder metadata, query, language,
  strategy, and a bounded `candidate_labels` list for the lightweight pool. It
  also keeps bounded prefix-pool history for the current typed search session,
  keyed by normalized prefix plus language/session, so `p`, `pi`, `pik`, and
  `pika` remain available as separate lightweight ID/label pools while later
  requests are pending. It must not hold or rank thousands of full `PokemonCard`
  objects for typed autocomplete.
  The typed popup materializes and renders only the visible
  `searchPreviewLimit` (`20`) rows from the current ranked context/ID pool: full
  backend rows whose IDs are in `search_context.card_ids`, or temporary
  name-only rows from `search_context.candidate_labels`. If no current ranked IDs
  or labels exist, keep the typed popup in the skeleton/no-data state instead of
  filling it from broad retained rows.
- Compound searches should still show similar results. `mew 232` should rank the
  exact `Mew ex #232/091` match first, then fall back to the strongest text term
  (`mew`) so related singles/products can fill the 9-result panel.
- The full `/marketplace/search` page must query Oracle-backed APIs directly.
  Do not limit it to the 500-card marketplace/home catalog loaded in
  `CardState.cards`.
- Typed search results are remote-authoritative in Flutter. After the backend
  returns ranked blueprints/cards, Flutter may dedupe exact blueprint/card IDs
  while preserving response order, but it must not merge those rows back into a
  hot/local catalog and then filter in cache or alphabetical order.
- Preview images live in the same R2 bucket as full card images under
  `previews/...`. Generated previews use `.webp`; CardTrader API preview imports
  currently preserve the downloaded preview bytes under `.jpg` keys.
- Flutter receives `preview_image_url` when available and falls back to the full
  card image when preview generation is incomplete.
- Home carousel rows use `homepage_image_url` when present, then fall back to
  `preview_image_url`, then the full image. Every marketplace blueprint with any
  source image should have `homepage_image_url` populated, preferably with a
  CDN/R2 `_homepage.webp` derivative. The current homepage reference is 240px
  wide, preserving each source image's natural aspect ratio.

## Target Search Architecture

CardTrader feels instantaneous because it does not treat every keystroke as a
fresh full-catalog search. Pokoin should move toward the same two-stage design,
then improve it with marketplace-specific signals.

### Stage 1: Warm Candidate Pool Before Reveal

- Start a debounced remote candidate search from 1 meaningful character to warm
  backend context. Render the visible typed autocomplete panel only once the
  query has at least 3 meaningful characters.
- At the first typed character, replace the empty-focus hot pool with a bounded
  backend prefix-matching warmup. Keep the visible typed popup closed and avoid
  sending/retaining a huge Flutter local pool. Continue querying indexed Oracle
  projections as the user types. Search fields should include:
  - `name`
  - `rarity`
  - `card_number` / `expansion_number`
  - `set_name` / `expansion_name`
  - `trainer_name`
  - `product_variant` for sealed/product rows
  - variation dimensions from `marketplace_variations` /
    `marketplace_card_variations`
  - product fields (`item_kind`, `product_type`) when looking for sealed items
- Keep this query against lightweight projection tables only:
  - `marketplace_cards` for autocomplete/home/full row payloads.
  - `marketplace_card_versions` for expansion navigation and single-card search.
  - Never parse full blueprint JSON during active typing.
- Use trigram/text indexes and small selected columns. Current preview
  autocomplete asks the Vercel endpoint for the visible 20 rows plus a bounded
  lightweight `pool_limit` of `5000`, `2500`, `1250`, or `500` for typed depths
  2, 3, 4, and 5+. The server returns the rendered rows and a compact
  `search_context` over that candidate pool. Do not reintroduce a full-card
  Flutter-side ranker.
- For structured queries such as `manaphy ex`, autocomplete must start from the
  name/text candidate set and then validate suffixes against stored dimensions
  such as `marketplace_card_variations`. Do not intersect with only the top-N
  generic `ex` rows; valid cards can sit outside that generic pool.
- If the name RPC returns zero for a valid exact token, the API should use the
  compact exact/prefix fallback from `marketplace_search_candidates` before
  applying stored variation filters. The target trace strategy is
  `name_first_stored_dimension_intersection`.
- If that zero-row case appears, inspect legacy expansion-alias collisions:
  CardTrader set codes can be Pokemon names such as `manaphy`, `mew`, `latias`,
  `gyarados`, or `lucario`. The SQL name RPC should keep those as card-name
  tokens even when they also exist in `marketplace_expansion_aliases`.
- Structured name-plus-number queries must not cap the name side to the visible
  preview pool. `mew 232` and typo `mee 232` should be able to reach `Mew ex`
  `Special Illustration Rare | 232/091`, then filter by the collector number.
- Structured name-plus-number filtering must resolve the card-name side first,
  including bounded typo matches such as `mee` -> `mew`, then apply collector
  number facets. If `marketplace_search_candidates.card_number` is empty, the
  backend must use CardTrader version/blueprint collector fields before deciding
  the number token has no match.
- Collector number matching should find numeric tokens inside rarity-prefixed
  values such as `Special Illustration Rare | 232/091`, not only compact strings
  that start with the number.
- The language selector sends `search_language` to the remote endpoint. Backend
  name matching swaps to fixture-backed tables through
  `marketplace_card_names_for_language(...)`; rebuild those tables with
  `node scripts/import-fixture-card-name-languages.js` when fixture translations
  change.
- Languages present in the UI but absent from the fixture currently fall back to
  English. Do not treat that as a UI bug unless fixture rows have been imported
  for the selected language.

### Stage 2: Render Remote Results Directly

- While the user types, `CardNotifier.searchPreviewsOnly(...)` debounces each
  visible autocomplete query and calls `/api/marketplace-autocomplete`.
- Flutter must treat that response as authoritative for preview rows:
  `state.searchPreviews` is assigned from the API result list directly, after
  response-order-preserving dedupe only.
- Do not merge loaded Hive cards, fallback cards, similar-query results, or
  locally narrowed cached pools into autocomplete previews. Those paths caused
  stale or broad rows to mask accurate Oracle results.
- Flutter must not alphabetically rerank remote autocomplete rows. If a future
  client refinement layer is added, it may only filter or score within the
  backend-provided blueprint/card-id pool, and ties must keep source order.
- If the backend returns no quick rows after a real stored-dimension
  intersection, Flutter should render no quick rows. It must not broaden the
  preview locally to unrelated suffix matches.
- The popup should show a refining state while the latest request is in flight
  and should drop stale responses by request id.
- Search preview rows use the artwork image/frame as a Hero source. On selection,
  keep the overlay/result row alive for the Hero handoff window before clearing
  search state. Card detail must preserve a route `extra` Hero tag during the
  initial render and view recording; do not replace it with the `Recently seen`
  fallback tag until no incoming Hero tag exists, or the destination detaches and
  the popup Hero appears not to play.
- Each active typed search owns a lightweight `search_session_id`. Flutter sends
  that id with the precise autocomplete request and full searchbar-backed
  requests. Request IDs still protect rendering, but the session id lets the
  backend notice when a later UI exit made older work irrelevant.
- While refining an extended typed query, Flutter may render a local bridge only
  from compatible historical prefix pools and the current ranked
  `search_context.card_ids` / `search_context.candidate_labels`, capped to 20
  and filtered by the current query. Compatible historical pools are accumulated
  as lightweight IDs/labels only; deeper prefixes rank ahead of earlier pools,
  repeated IDs across pools get stronger, and latest backend order breaks ties.
  It must not independently render `preview_mode: name` rows, empty-focus hot
  rows, loaded home-cache rows, or arbitrary retained full rows after typing
  starts.
  If a context row lacks image/set details, render it as a name-only placeholder.
- Local fallback must never broaden past completed typed tokens. Once the main
  card/name token has matched, every following token is a refinement, including
  short tokens. Completed semantic variation tokens such as `ex`, `v`, `gx`,
  `vmax`, `vstar`, `lv`, and `lv x` are required. Partial semantic prefixes such
  as `e` in `mimikyu e` or `g` in `mimikyu g` should gate/rank toward matching
  known variation rows (`ex`, `gx`) when such rows are present, rather than
  keeping ordinary same-name rows above them.
- Example: `mimikyu e` should rank `Mimikyu ex` ahead of ordinary `Mimikyu`, and
  `mimikyu ex` should require an `ex` variation match instead of allowing plain
  `Mimikyu` through the local fallback.
- Local fallback/refinement priority is: card name first; then card variation
  identity, including mechanical variants (`ex`, `v`, `gx`, `vmax`, `vstar`) and
  owner/trainer identity (`Ash's`, `Rocket's`, `Misty's`, etc.); then collector
  or expansion number; then expansion/set name; then rarity and rarity
  abbreviations such as `SIR`, `SAR`, `IR`, and `UR`. If any local candidate
  matches a higher-priority layer for the current suffix token, lower-priority
  matches must not stay above it. Recompute this from the current query each
  keystroke so deleted or changed suffix tokens drop stale boosts.
- Variation prefix tokens such as `e`, `ex`, `g`, `gx`, `v`, `vm`, `vmax`, and
  `vstar` must match or boost true card variation/identity fields before they
  can match expansion/set names. Example: `mimikyu g` should favor true
  `Mimikyu GX` rows over ordinary `Mimikyu` rows whose expansion is named
  `GX Battle Boost`, `GX Starter Decks`, or similar.
- 2026-05-22 audit follow-up: keep token classifiers aligned across
  `/api/marketplace-autocomplete`, `/api/marketplace-search-candidates`, and
  Flutter fallback ranking. A previous split left the search-candidates fallback
  and Dart local ranker still using the old `length >= 2 || v || n` tokenizer,
  which dropped `g`/`e` in multi-token variation-prefix queries and did not treat
  prefixes such as `vm` as `vmax` intent. Regression coverage should include
  `mimikyu e`, `mimikyu g`, `pikachu vm`, `mew ex 216`, `az`, `n`, rarity
  abbreviations, set-vs-variation collisions, and owner identity collisions.
- If a UI screenshot shows rows that only match lower-priority expansion/set
  names while a higher-priority variation prefix is typed, first identify the
  layer that produced the order. Flutter local fallback bugs belong in the
  provider/fallback hierarchy; backend, Oracle, or Supabase-name-index ordering
  bugs belong in the API ranker or candidate source that returned the rows.
- Short real card/trainer names are valid tokens. Whole-query `n` and `az` are
  exact short-name queries and should allow exact `N` and `AZ` rows from the
  backend/context pool instead of being discarded by a blind length threshold.
  Arbitrary short garbage tokens should not broaden the local fallback; keep them
  soft only when backend/context labels identify a matching display/name token.
- Variation identity in Flutter fallback should be derived from card identity
  fields such as name, rarity, type, product type, and explicit tags. Do not infer
  card variation from expansion/set text alone; labels without full variation
  metadata can only be filtered by their visible name/trainer/product fields
  until the backend returns full rows.
- Backend performance work belongs in the Oracle/Vercel autocomplete endpoint,
  not in a client-side pool ranker.

### Incremental Candidate Context

- Debounce reduces request volume, but it does not make autocomplete incremental:
  each accepted query still reaches `/api/marketplace-autocomplete` as a fresh
  request. When a user types `mew`, then `mew 2`, then `mew 23`, the backend
  should be able to refine the previous candidate set instead of rediscovering
  the same canonical-name universe for every debounced input.
- Add a stateless continuation contract before reintroducing any Flutter-side
  ranking. The API should return a compact `search_context` with the current
  normalized query, selected language, strategy, and a bounded list of candidate
  `card_id` values from the precise autocomplete working set.
- The context also carries bounded `non_name_context.depth_scores`,
  `latest_depths`, and `latest_orders` maps. Each
  accepted typed depth adds the current meaningful-character count to blueprint
  ids returned by that depth's matching backend candidate set. For example, a row
  present for `pi` and `pik` accumulates `2 + 3`, while its `latest_depths`
  value becomes `3`. Latest/deeper occurrence outranks broader earlier pools;
  accumulated depth score is secondary.
- The context may also carry lightweight `candidate_labels`
  (`id`, `name`, `item_kind`, `product_type`, and optional set/number/trainer
  labels) for the current candidate ladder target. These labels are for visual
  continuity during the next in-flight refinement only; they are not full card
  objects and must not replace the backend-ranked row payload once it arrives.
- Flutter may send that context back only when the next precise query extends
  the previous query, uses the same language, and the previous response was not
  stale. The typed UI no longer renders an independent fast `preview_mode: name`
  response; visible typed rows come from the precise autocomplete response and
  its ranked context only.
- Temporary context-label rows still must be filtered by the same strict
  current-query logic before rendering. They are a visual bridge only; they must
  not show ordinary same-name rows after a required suffix such as `ex`, a
  collector number, set token, owner, or rarity abbreviation has narrowed the
  active query.
- The API should validate context defensively: reject it if the query was
  shortened, language changed, too many ids were supplied, or the context is too
  old. Invalid or empty contexts must fall back to normal candidate fanout.
- A valid context should run an ID-bounded refinement:
  `marketplace_search_candidates.card_id = any(previous_ids)`, then apply the
  same targeted number, set, trainer, rarity, product variant, and
  `marketplace_card_variations` checks used by candidate fanout.
- Depth weights are ranking signals only after the current query has produced a
  matching candidate pool. Latest/deeper pools dominate earlier pools, and
  accumulated depth score only breaks ties after latest depth. They must not
  append generic hot rows, revive stale preview rows, or boost a row that failed
  the current query's name/number/set/variation filters. Shortened queries,
  language changes, stale contexts, search exit, or unrelated query branches
  clear or branch away from the prior prefix-pool history and start a fresh
  context.
- Debug traces should expose `candidate_context_refine` when the subset path is
  used, plus candidate id count, matched row count, and fallback reason when the
  API returns to normal fanout.
- The context can contain up to 5000 lightweight candidate ids/labels so the next
  typed refinement can filter the most probable preview pool without a new broad
  scan. The ladder target narrows by typed depth (`5000`, `2500`, `1250`, then
  `500`); one-character warmup remains backend-only or small/no Flutter context.

### Search Session Exit And Cancel

- Focus, typing, popup visibility, and cancellation are one lifecycle:
  1. Focus with an empty query may show local hot/recent rows without opening a
     typed backend session.
  2. The first non-empty typed query creates a Flutter `search_session_id`.
     Debounced autocomplete sends that id to `/api/marketplace-autocomplete`
     along with the current query, language, pool limit, preview mode, and
     optional context.
  3. The popup opens only when the visible typed threshold is met, but backend
     warmup may already be in flight for one- and two-character inputs.
  4. Blur, clear, preview selection, submit, navigation, route disposal, or
     provider disposal cancels the debounce, increments provider request ids,
     clears preview/context state, and posts
     `/api/searchbar-cancel` with `search_session_id`, `last_query`, and a
     reason such as `blur`, `clear`, `selection`, or `dispose`.
  5. Stale responses from older request ids must still be ignored even if the
     backend cancel signal races with the response.
- `/api/searchbar-cancel` is anonymous-safe and cheap. It does not write to the
  database; it records the canceled id in a short-lived in-process map and
  returns success. In Vercel serverless this map is best effort and only affects
  the warm instance that receives the cancel or later search request.
- Searchbar/autocomplete handlers should check the canceled session before
  starting work and again after candidate retrieval. When canceled, they return
  an empty `session_canceled` response, skip analytics boosts, skip depth/context
  refinement, and avoid ladder/fallback work that would continue to press
  Oracle/peer4 after the UI is gone.
- Request connection aborts are also treated as cancellation where the runtime
  exposes them. This avoids optional post-candidate work after disconnect, but it
  is not a substitute for abortable database queries.
- Serverless cancellation is intentionally documented as best effort. True
  cross-instance or already-running SQL cancellation requires a shared
  cancellation store and abortable database/query support. Until then, keep
  short-prefix requests bounded, skip primary/peer4 broad fallbacks for canceled
  sessions, and rely on request-id drops plus backend cancellation checks to
  prevent stale UI and reduce wasted optional work.

### Server-Cached Preview Pool

- Empty search focus calls `/api/marketplace-autocomplete` with an empty
  `search_term` or `/api/marketplace-hot-blueprints?includeCards=1&limit=1000`.
  Both paths use the analytics/hot rollup (`marketplace_hot_blueprints`) and
  cache the pool server-side for about 60 seconds with stale revalidation.
- The first typed character replaces the empty-focus hot pool with a backend
  name-prefix warmup. Those rows must have a Pokemon/card canonical name starting
  with the typed character; analytics/hot signals may rank inside that prefix
  pool, but must not introduce unrelated hot cards or a broad Flutter local pool.
- Site-level ranking comes from `marketplace_hot_blueprints`; signed-in
  personalization comes from `marketplace_card_events.user_uid` when a Firebase
  bearer token is present. Anonymous requests keep public behavior. Both signal
  types are boosts applied after candidate filtering, never sources of extra
  typed rows.
- Typed autocomplete uses `typed_predictive_ngrams` as the first broad candidate
  source once the query has at least two compact characters. The API extracts
  consecutive compact chunks from the whole typed input, currently 2- and
  3-character ngrams such as `ar`, `fr`, `jof`, or `ggr`, and looks them up in
  `marketplace_name_ngrams`.
- `marketplace_name_ngrams` is linked to `marketplace_search_candidates` and the
  card-name/localization tables. It stores chunk, language, source name, chunk
  position, prefix flag, and source weight for canonical, display, and localized
  names. This lets misspells and partial inputs seed a bounded candidate pool
  without scanning the full catalog.
- Search events may call `record_marketplace_query_chunks(...)`, which stores
  aggregate chunk and next-chunk counts in `marketplace_query_chunk_events`.
  Store normalized chunks/counts only; do not build a raw-query history table.
- Sharding across peer4/peer3/peer2/peer1 is execution infrastructure for these
  predictive indexed chunk queries and the existing structured fanout paths. It
  is not an alphabet-only `p` range split. One-character prefix sharding may
  remain as a narrow compatibility fallback until the ngram index can serve
  one-character warmups from aggregate data.
- Predictive candidates are deduped by blueprint/card id, filtered by structured
  tokens when present, and then ranked by text/chunk quality, fuzzy/coverage
  score, stored number/variation/set matches, site analytics, and optional user
  personalization inside the candidate set only. No generic hot rows may be
  appended after typing.
- Clean single-token alphabetic prefixes such as `pika`, `pikach`, and
  `pikachu` are backend name intent, not fuzzy intent. The autocomplete endpoint
  should first use the card-name direct/fanout path (`name_table_direct` or
  equivalent) and rank exact display-name matches before display-name prefixes,
  before canonical-name owner variants such as `Pitch's Pikachu`, and before
  substring/ngram fuzzy hits. `typed_predictive_ngrams` is a fallback for
  misspellings and broad fuzzy discovery; if it is used for a clean exact prefix,
  the backend ranker must still keep exact/prefix display-name rows above
  possessive or substring candidates. Analytics boosts and depth-weighted
  `search_context` can break ties inside those tiers, but must not invert them.
- Plain name prefixes with no structured variation token should keep the base
  display-name tier ahead of variants, owner forms, and trainer forms. Example:
  `pikac` should generally show base `Pikachu` before `Pikachu GX`,
  `Pikachu ex`, `Ash's Pikachu`, or other variant/owner rows. TODO decision
  gate: if product wants analytics/popularity to let variants rank first for
  plain prefixes, document the cap explicitly and keep it narrow enough that it
  cannot erase the base/exact display-name tier.
- The optional Supabase name-index path must follow the same rule. Its local
  rank should prefer `display_name == canonical_name` for plain prefix queries
  and cap imported `search_weight` so analytics/popularity cannot put suffix
  variants ahead of base display-name rows before the main API ranker sees them.
- Typed search sends the ID-ladder `pool_limit` (`5000`, `2500`, `1250`, then
  `500` for depths 2+) and `result_limit: 20`. The API computes the probable
  bounded candidate pool with the optional Supabase name-index tier for short
  single-name prefixes when configured, name search on peer3, variation/search
  dimension fanout on peer2/peer1 when configured, and peer4 fallback only for
  safe narrow paths when a replica is unset, slow, or in circuit-open state.
- The opt-in predictive 5000 pool path is stricter during development. Set
  `MARKETPLACE_PREDICTIVE_POOL_ENABLED=1` to use the dynamic predicted-token
  model: Supabase returns the top bounded provisional card-name tokens for the
  current name fragment on every character, then Oracle/Postgres verifies the
  remaining typed tokens by dimension. A 70%+ confidence prediction is only a
  ranking boost, never a lock; `me` can rank Mew/Mewtwo/Meowth, and `mewt` must
  recompute and pivot to Mewtwo.
- For each predicted name token, the backend treats that token as the canonical
  candidate name and fans out the remaining tokens to collector number,
  expansion/set, rarity, variation/owner, and existing item/product checks.
  Results are merged/deduped/ranked into up to 5000 lightweight IDs/labels in
  `search_context`; full `rows` stay capped to the 20 visible preview rows.
  With `MARKETPLACE_PREDICTIVE_POOL_STRICT=1` (default for that path), missing
  Supabase prediction data or missing required dimension routes surface as
  explicit debug/error state instead of hot/generic/peer4 fallback.
- Predictive pool source hierarchy is card name, variation/owner, collector
  number, expansion name, rarity, then item/product type. Source flags,
  predicted tokens, confidence, route status, and score components travel with
  candidate labels/debug so Flutter can keep the backend order, store compatible
  historical prefix pools, and render only the top 20 visible rows from the
  latest ranked ID pool.
- Flutter may surface the top backend predicted card-name token as provisional
  ghost text in the search field when it extends the active trailing typed name
  fragment. Example: `mewt` can show `Mewtwo`, and desktop/web users may press
  Tab to accept it. This is a debug/product aid only: it must not lock ranking,
  replace structured suffixes, or create a separate client-side predictor. When
  `SearchDebugTrace` is enabled, the UI may show confidence/source details and
  should record suggestion/accept trace events.
- The Supabase tier is a derived card-name index only. It may contain
  blueprint/card ID, language, display/canonical/search names,
  normalized/compact names, name tokens, set/card-number label fields,
  item/product type, trainer/variant labels, emoji, and search weight. It must
  not contain marketplace listings, user data, prices, analytics events, or full
  blueprint JSON. Oracle still hydrates full rows/details and remains source of
  truth.
- If `SUPABASE_NAME_INDEX_DATABASE_URL` is absent, slow, empty, or unhealthy, the
  endpoint falls back to the existing Oracle peer3/peer2/peer1/peer4 paths. A
  Supabase miss must never make autocomplete fail outright. Missing-table or
  connection failures should open the short-lived name-index circuit so active
  typing does not re-probe Supabase on every keypress.
- One-character and short queries must stay bounded: when Supabase is configured,
  one-character autocomplete uses `supabase_one_char_name_index` over the
  unique-name token table instead of Oracle prefix shards. It should scan compact
  buckets such as `pa` through `p9` plus normalized punctuation forms and return
  top predicted name tokens, IDs, and labels only. Structured short queries
  refine prior context or use name/dimension fanout. Avoid full-catalog scans
  during active typing.
- After peer4 hit sustained 100% CPU and was manually rebooted from the Oracle
  panel on 2026-05-22, short-prefix fallback policy is stricter: one- and
  two-character typed searchbar paths must not fall back to broad peer4 primary
  reads. If replicas are unavailable, return empty/light typed results and retry
  on the next prefix instead of waking the primary.
- Autocomplete analytics reads use replica routing through
  `MARKETPLACE_ANALYTICS_SEARCH_REPLICA_URLS` or the configured peer2/peer1/peer3
  read URLs. One-character typed warmups skip analytics by default via
  `MARKETPLACE_SHORT_PREFIX_ANALYTICS_MAX_DEPTH=1`; use `2` during incidents if
  two-character warmups are also pressuring the database.
- The response should include `pool` and debug metadata: `searchPath`,
  `poolSource`, `poolSize`, `candidateDurationMs`, `rankDurationMs`,
  `replicaPath`, and `replicaFallback`. For predictive ngram searches, debug
  also includes chunks used, ngram candidate count, fallback/schema status,
  fuzzy/relevance scores, and analytics boosts. Browser/service traces should
  also log `Server-Timing`.

### Supabase Name-Index Searchbar Workflow

Supabase is optional search infrastructure for typed card-name prefixes. Oracle
remains authoritative for complete cards, listings, users, prices, analytics,
and all writes.

Layer split:

- Layer A is `/api/searchbar-token-predict`. Input is raw `query`/current token
  `fragment`, `search_language`, optional `limit` (default `5`), and optional
  `previous_prediction_context`. Output is `predictions[]` with `display_token`,
  `normalized_token`, `confidence`, `score`, `source_rank`, `matched_prefix`,
  `card_count`, `ids_count`, up to a few `representative_card_ids`, and a
  bounded `candidate_card_ids` pool for backend verification, plus a tiny
  `prediction_context` containing the bounded ordered candidate tokens used for
  the next character. The first character may query
  `public.marketplace_card_name_tokens`; characters 2 and 3 refine from the top
  half of the previous context when language/query extension is valid. After
  three meaningful characters the endpoint uses the previous context first in
  fuzzy near-prefix mode, allowing small edit distances such as `girati` ->
  `Giratina`. If valid context produces no matches or only weak matches, it must
  run a bounded full-table Supabase token prediction for the current token (for
  example `laprs` -> `Lapras`) instead of treating the narrowed context as final.
  It stays tokens-only and must not hydrate full rows.
- Layer B is `/api/searchbar-cards` and `/api/marketplace-autocomplete`. It keeps
  returning ranked rows, `search_context.card_ids`, `candidate_labels`, pool
  metadata, and debug timings. Flutter starts this request on the normal preview
  debounce and uses it for visible rows/context while Layer A handles ghost text.
  When Flutter sends `prediction_context`, the predictive dimension pool should
  verify dimensions against that predicted token set instead of re-deriving raw
  name candidates from the whole DB. If no prediction context is present, the
  current Oracle/Supabase fallback behavior remains valid.
- Browser extensions should call Layer A to identify the Pokemon/card-name token,
  then call `/api/extension-card-search` with structured fields (`name`,
  collector number, expansion, rarity, variation, language) for full matching.

Architecture:

- Store only derived/cache data in Supabase:
  `card_id`, `language`, display/canonical/search names, normalized/compact
  names, name tokens, set/card-number labels, product/variant labels,
  `item_kind`, `product_type`, optional emoji, and `search_weight`.
- Keep the table rebuildable from Oracle. Do not store marketplace listings,
  user records, prices, events, full blueprint JSON, image payloads, or any
  Flutter write target.
- For 1+ character broad single-name prefixes, the backend can query Supabase
  first for candidate IDs/labels and rank hints. A one-character query such as
  `p` should report `supabase_one_char_name_index`, query the unique-name table
  instead of Oracle's `typed_one_character_sharded_prefix`, return predicted
  tokens such as `Pikachu` when ranked highly enough, and keep full row
  hydration bounded. This is fast because the one-character prediction scans the
  compact unique-name/token rows, not thousands of full marketplace card rows.
  Longer prefixes report `supabase_name_index`; they hydrate only the visible
  top rows from Oracle and keep `rows` capped to 20.
- Supabase matching must follow the same compact/normalized model as backend
  ranking. Punctuation and special forms in card names are normalized rather
  than hard-coded: apostrophes and curly apostrophes (`Ash's Pikachu`,
  `Lt. Surge's Pikachu`, `_____'s Pikachu`), ampersand tag-team names
  (`Pikachu & Zekrom GX`, with `&` normalized to `tagteam` where available),
  underscores, hyphens/dashes, periods, brackets (`Unown [N]`), gender symbols,
  colons, slashes, spaces, and diacritics should match through
  `compact_name`, `normalized_name`, or compacted `name_tokens`.
- The fast prediction payload should flow through `/api/searchbar-token-predict`
  with predicted token display text, compact token, confidence, source rank,
  language, card/count signals, a tiny representative ID sample, a bounded
  candidate card-id pool, and the bounded `prediction_context`. Flutter stores
  this separately from
  `search_context`; it sends it only while the next typed value extends the
  previous token in the same language, and clears it on branch/backspace,
  language change, clear, accepted completion, or search exit. The heavy
  autocomplete response may still expose predictive metadata for diagnostics, but
  Flutter ghost text should not depend on the heavy response.
- Flutter receives full backend rows plus `search_context.card_ids` and
  lightweight `candidate_labels`. It may use labels as temporary in-flight
  context, but final rendering order comes from backend rows.
- If Supabase is absent, empty, slow, or unhealthy, autocomplete falls back to
  Oracle peer/name-replica paths. Missing-table/connection failures should open
  a short-lived circuit and must not make `/api/searchbar-cards` fail.

Operational sequence:

1. Apply only the additive Supabase name-index schema when approved:
   `supabase/name-index/002_marketplace_card_name_tokens.sql` or
   `supabase/migrations/20260522173045_marketplace_card_name_tokens.sql`.
2. Dry-run Oracle export first:
   `node scripts/sync-card-name-index-to-supabase.js --languages=en --limit=1000`.
3. Review counts and target env. Apply sync only with explicit approval:
   `node scripts/sync-card-name-index-to-supabase.js --apply --full-refresh --languages=en --limit=all`.
4. Deploy backend after checks pass.
5. Run bounded `2pikabench`, inspect per-depth timers, status/failures,
   rows/context counts, search paths, payload bytes, and final top rows.

When new CardTrader blueprints are the reason a search term is missing, run the
Oracle delta catalog workflow before refreshing this Supabase cache. For example,
the Mega Darkrai check should first dry-run the newly released CardTrader
expansions:

```bash
node scripts/cardtrader-delta-import.js \
  --input=data/cardtrader/pokemon-blueprints.jsonl \
  --expansion-ids=4611,4639 \
  --limit=all
```

For a full remote check without relying on `data/cardtrader/pokemon-blueprints.jsonl`,
use streaming mode:

```bash
node scripts/cardtrader-delta-import.js \
  --stream-all \
  --limit=all \
  --sleep-ms=100
```

Streaming mode calls CardTrader's expansion export endpoint one expansion at a
time and compares blueprint IDs against Oracle as it goes. CardTrader does not
currently expose an IDs-only Pokemon blueprint feed in this workflow, so the
remote stream still reads full blueprint rows per expansion; it just avoids a
local full-catalog snapshot.

If the dry-run shows the expected missing single-card blueprints, apply the
bounded import and image/search refresh:

```bash
node scripts/cardtrader-delta-import.js \
  --apply \
  --input=data/cardtrader/pokemon-blueprints.jsonl \
  --expansion-ids=4611,4639 \
  --limit=all \
  --images \
  --refresh \
  --sync-supabase \
  --languages=en \
  --supabase-transport=rest
```

For a full approved apply:

```bash
node scripts/cardtrader-delta-import.js \
  --apply \
  --stream-all \
  --limit=all \
  --images \
  --refresh \
  --sync-supabase \
  --languages=en \
  --supabase-transport=rest
```

The delta importer inserts only missing raw CardTrader blueprint IDs into Oracle.
It does not update existing blueprint rows or run a broad Supabase-to-Oracle copy.
If the Oracle full refresh wrapper references optional helper functions that are
not present on the target database, the importer falls back to the established
component refreshes needed for search candidates and token data, and reports the
skipped optional helpers.
After apply, repeat the token-prediction and full autocomplete/searchbar smokes
for `mega darkrai ex`, `giratina`, `lapras`, and `p/pik/pikachu`.

### Timing Measurement

- Use the benchmarkable searchbar API contract for repeatable timing and quality
  runs. Local or deployed command:

```bash
node scripts/benchmark-searchbar-api.js \
  --base-url http://localhost:3000 \
  --endpoint /api/searchbar-cards \
  --runs 3 \
  --queries "pikachu,mew ex 216,mimikyu,charizard,pikchu,charzard"
```

- The script types each query character by character, forwards the previous
  `search_context` into the next request, and prints failures, avg/p50/p95
  latency by meaningful depth, payload sizes, search paths, pool sizes, and final
  top results.
- Backend/API `2pikabench` measures API behavior only. Flutter/UI screenshots
  can still expose local fallback hierarchy bugs while a request is in flight, so
  compare API records and Flutter traces before assigning a ranking regression to
  the backend.
- Before `/api/searchbar-cards` is deployed, run the same script against
  production `/api/marketplace-autocomplete` as a baseline:

```bash
node scripts/benchmark-searchbar-api.js \
  --base-url https://pokoin.com \
  --endpoint /api/marketplace-autocomplete \
  --runs 1
```

- Interpret results by depth, not only by final query. Depth 1 should stay
  bounded on backend prefix warmup. Depth 2 should be allowed to carry up to
  5000 IDs/labels, depth 3 up to 2500, depth 4 up to 1250, and depth 5+ up to
  500. Full rendered `rows` remain capped to 20.
- Latency wins should show up as stable p50/p95 after the first warmup and as
  `candidate_context_refine` or equivalent context paths on extended queries.
  If p95 spikes at depth 2 or 3, inspect candidate fanout and replica fallback.
  If quality regresses but latency improves, keep backend order authoritative and
  fix ranking/path selection rather than adding Flutter-side broadening.
- Quality interpretation should check the final top result for exact examples
  (`pikachu`, `mew ex 216`, `mimikyu`, `charizard`) and typo examples
  (`pikchu`, `charzard`). For structured queries, exact name plus variation or
  collector-number intent must outrank generic hot or set-only rows.
  `pikac` is a plain prefix check: base `Pikachu` should lead variant rows unless
  the TODO decision gate above has been resolved in favor of capped popularity
  inversion.
- Why char-length narrowing was incomplete before: early searchbar preview
  smoothing treated short terms as noise and used guards such as `length >= 2`
  or `length >= 3` to avoid broad partial-token fanout. That was reasonable
  before the semantic hierarchy was explicit, but after the user has already
  identified the main card name, the next token is a refinement even when it is
  one or two characters (`g`, `e`, `vm`, `n`, `az`, numbers, rarity aliases).
  Backend candidate pools narrowed with typed depth, but Flutter fast/fallback
  previews and some backend fallback helpers did not enforce the same semantic
  token hierarchy, so later characters could fail to sharpen the visible rows.

### Backend/API 2pikabench

Use backend/API `2pikabench` as the named repeated prefix-chain benchmark for
the searchbar workflow. It simulates a user typing a target card name or search
phrase character by character, forwards the previous `search_context` into the
next request like Flutter does, and records timing, ranking, payload, context,
and debug-path output for every prefix. The benchmark is for both timer evidence
and ranking-correctness evidence; every report must tell readers whether it is a
backend/API-only run or a Flutter-side local fallback run. The default chain
currently covers `p -> pi -> pik -> pika -> pikac` and continues through the
final `pikachu` query.

Prefer the benchmark script when it is available:

```bash
node scripts/benchmark-searchbar-api.js \
  --base-url https://pokoin.com \
  --endpoint /api/searchbar-cards \
  --runs 3 \
  --queries "pikachu"
```

For local or preview runs, change `--base-url`. Keep `/api/searchbar-cards` as
the preferred benchmark endpoint, set `--runs` to the repeated sample count, and
use `--queries` or repeated `--query` flags to override the target card/search
phrase. The script sends `query`, `search_language`, `limit`, `pool_limit`,
`previous_search_context`, `debug`, and `mode: "benchmark_step"` to
`/api/searchbar-cards`; it sends the equivalent production probe shape
(`search_term`, `search_language`, `result_limit`, `pool_limit`,
`previous_search_context`, and `debug`) when pointed at
`/api/marketplace-autocomplete`.

If the script is unavailable, use the same production probe shape manually:

```json
{
  "search_term": "pik",
  "search_language": "en",
  "result_limit": 20,
  "pool_limit": 5000,
  "previous_search_context": { "...": "context from the previous prefix" },
  "debug": true
}
```

Run that POST body against `${BASE_URL}/api/searchbar-cards` with `query`/`limit`
field names, or against `${BASE_URL}/api/marketplace-autocomplete` with
`search_term`/`result_limit` field names. Capture every prefix in order and pass
each returned `search_context` into the next request when the query is extended
and the language is unchanged.

Do not run heavy production `2pikabench` while peer4 is recovering from a reboot
or sustained 100% CPU. During an incident, use a single debug run for `p`, `pi`,
`pik`, and `pika` only if needed, then inspect `searchPath`, `replicaPath`,
`replicaFallback`, `analyticsSkipped`, `candidateDurationMs`, and
`analyticsDurationMs`. A healthy protected short-prefix run either uses peer3 or
peer2/peer1 read replicas, or skips analytics/fallback for the broadest prefixes;
it must not report broad `primary_*_fallback` for `p` or `pi`. When the optional
Supabase name index is configured, a healthy `p` run should report
`supabase_one_char_name_index`, low candidate latency, bounded context/labels,
and predicted token/confidence metadata in `meta.predictive`; it should not
report `typed_one_character_sharded_prefix` except as a compatibility fallback
when Supabase is absent, empty, or unhealthy. Healthy 2+ character short-prefix
runs may report `supabase_name_index` for the candidate pool. Both Supabase pools
are built from `public.marketplace_card_name_tokens`: one row per language-local
unique name, with `card_ids` expanded and hydrated through Oracle only as needed
for visible rows.

Every `2pikabench` report is incomplete unless it includes both timing and
ranking sections. Each per-depth/per-prefix record should preserve:

- HTTP status.
- Elapsed/client milliseconds per prefix.
- Server duration from response metadata or `Server-Timing`.
- Candidate milliseconds, analytics milliseconds, and rank milliseconds when
  exposed in `meta.timings`, `debug`, or `Server-Timing`.
- Payload bytes.
- Row count, context ID count, candidate label count, and any pool/context count
  available.
- Failures and timeouts, including the prefix where they happened.
- Search path such as `candidate_context_refine`, `name_table_direct`, or
  `typed_predictive_ngrams`.
- First rows/top rows with IDs, names, sets, numbers, and labels when present.

Each report must also include a correctness section:

- Per-depth/per-prefix top rows and whether they match the expected narrowing
  intent for that prefix.
- Whether plain card-name prefixes keep base display-name rows above variants.
  Example: `p -> pi -> pik -> pika -> pikac` should stay in the Pikachu family,
  and plain `pikac` should prefer base `Pikachu` before `Pikachu GX`,
  `Pikachu ex`, owner variants, or trainer forms unless the user has typed an
  explicit variation token.
- Variation-token behavior. Example: `mimikyu g` and `mimikyu ex` should rank
  true `Mimikyu GX`/`Mimikyu ex` rows first, not ordinary `Mimikyu` rows that
  only match expansion or set names such as `GX Battle Boost`.
- Number, set, and rarity token behavior when those tokens are present. Example:
  `mew ex 216` should reward name plus variation plus collector number, and
  rarity aliases such as `sir`, `sar`, `ir`, or `ur` should narrow within the
  matched card-name/variation set instead of broadening to unrelated rows.
- Final top rows and an explicit correctness verdict such as `pass`, `fail`, or
  `inconclusive` with the reason.

Supabase acceptance gates:

- Before the Supabase table is applied/populated, the benchmark may show Oracle
  fallback paths, but every prefix must stay HTTP 200 and bounded.
- After Supabase apply/sync, one-character broad name prefixes should be
  eligible for `supabase_one_char_name_index`, and 2+ character broad name
  prefixes should be eligible for `supabase_name_index` candidate generation
  from the unique-name table, while visible full rows remain hydrated from
  Oracle and capped to 20.
- A post-change `2pikabench` for `pikachu` should show `p` completing quickly
  from Supabase unique-name tokens, expose top predicted tokens/confidence for
  ghost autocomplete, keep `Pikachu` near the top when it is the best ranked
  token, and continue narrowing through `pi`, `pik`, `pika`, and later prefixes
  without broad Oracle primary fallback.
- A missing Supabase table, empty result, timeout, or connection failure must be
  visible in debug metadata as fallback/circuit behavior, not as an endpoint
  failure.

Current production blocker: the deployed `/api/marketplace-autocomplete.js`
bundle can fail with `Cannot find module './_supabase'`. This is a deploy
packaging/helper-copy issue, not a valid ranking or fallback result. Backend/API
`2pikabench` against production is invalid until the deployed API bundle includes
the Supabase helper or the import is safely lazy/optional and redeployed.

`2pikabench` is not Pikachu-specific. Reuse the same char-by-char context
forwarding for other names and phrases such as `mimikyu`, `charizard`,
`mew ex 216`, `eevee`, and misspellings such as `pikchu`, `charzard`, or other
real user typo paths.

### Flutter 2pikabench

Flutter `2pikabench` is the local provider/fallback counterpart to the backend
benchmark. It must not hit production. Use a fake `CardService` and drive
`CardNotifier.searchPreviewsOnly(...)` through `p -> pi -> pik -> pika -> pikac`
to verify the UI behavior that the API benchmark cannot see:

- `p` and `pi` warm silently: backend calls happen, and their lightweight prefix
  pools are retained for the session, but the visible typed popup remains closed
  and `state.searchPreviews` stays empty.
- `pik` and later prefixes can show bounded bridge rows from the compatible
  union of historical prefix pools plus the current ranked
  `search_context.card_ids` and `search_context.candidate_labels` while the
  latest response is in flight.
- Bridge rows are capped to `searchPreviewLimit` (`20`), preserve context ID
  order as a tie breaker, weight deeper/repeated IDs above earlier-only IDs, and
  are constrained by the local hierarchy: card name, variation or owner,
  collector number, expansion name, then rarity/abbreviation.
- No stale broad row may remain above a narrower current-query match when the
  typed suffix changes.

Add variant chains for hierarchy regressions when changing fallback logic:
`mimikyu -> mimikyu e -> mimikyu ex`, `mew ex 216`, exact short-name queries
`n` and `az`, owner/trainer queries such as `pikachu ash`, and rarity
abbreviations such as `mew sir`, `mew sar`, `mew ir`, and `mew ur`.

### 2pikabench Failure Analysis

Backend/API `2pikabench` and Flutter `2pikabench` verify different layers:

- Backend/API `2pikabench` exercises the deployed or local Vercel searchbar API
  path. It is valid only when the API bundle can load all required helpers. The
  current production blocker is `Cannot find module './_supabase'` from deployed
  `/api/marketplace-autocomplete.js`, so production backend results should be
  treated as invalid until the helper is included in the deploy bundle or the
  import is safely lazy/optional and redeployed.
- Backend/API `2pikabench` currently answers "what did the API rank?" not "what
  did the Flutter popup show?" If Flutter screenshots show `pikac` or
  `mimikyu g` rows in a different hierarchy, first confirm the rows are in the
  current ranked context/ID pool before changing backend ranking.
- Flutter `2pikabench` is local provider bridge coverage. It uses a fake
  `CardService`, does not hit production, and verifies visible popup timing,
  context-label filtering, and ranking-pool order while backend requests are in
  flight.

After the bundle blocker is fixed and deployed, a healthy backend run should
produce a fast lightweight pool of up to `5000` IDs/labels at the two-letter
step, return valid `search_context`, avoid broad peer4 fallback for `p`/`pi`, and
then refine later prefixes from that context. Short-prefix full candidate fanout,
payload building, and analytics scoring can still dominate latency if they run
before the lightweight pool exists; keep ID/label pool generation separate from
full row materialization and heavy analytics.

### Searchbar Optimization Plan

The target searchbar architecture keeps Flutter lightweight while making the
backend prefix path incremental:

- 1 character: backend warmup only. Do not show the typed popup and do not build
  or retain a giant Flutter pool.
- 2 characters: generate a fast lightweight local/context pool with a target of
  `5000` IDs/labels.
- 3 characters: open the typed popup immediately using the retained 2-character
  pool while the backend builds the 3-character pool, target `2500`.
- 4 characters: refine the lightweight pool, target `1250`.
- 5+ characters: refine the lightweight pool, target `500`.
- Later-depth candidates outrank earlier-depth candidates; repeated IDs across
  depths get stronger because they matched more of the typed path.
- Full rows and images stay capped to `20` and hydrate after lightweight
  candidates are available.
- Skeleton vapor rows appear only when no local retained candidates/context
  labels are available for the current in-flight query.
- Flutter prefix-pool history is bounded: keep only a small number of prefixes
  per active session (currently 16), cap each prefix by the same candidate ID
  ladder, and cap aggregate lightweight ID/label entries. The history stores
  IDs, labels, depth scores, latest depth/order, and timestamps only; full card
  rows are retained only for the visible top 20/hydrated rows.

### Next Optimization Targets

- Fix the deployed `/api/marketplace-autocomplete.js` bundle so the optional
  Supabase helper is included or lazy/optional. Production backend `2pikabench`
  is blocked until `Cannot find module './_supabase'` is gone.
- After the bundle loads, fix `/api/searchbar-cards` if `pi` does not return fast
  lightweight context.
- Decouple context ID/label generation from full row materialization.
- Cap or skip analytics during short-prefix pool generation; apply analytics only
  inside an already-built candidate set, or use asynchronous/cached analytics.
- Make production `2pikabench` a required regression before deploys that touch
  searchbar behavior.
- Measure payload bytes, parse time, candidate milliseconds, analytics
  milliseconds, rank milliseconds, and first rows for every prefix step.
- Implement the Supabase name-index tier only after the workflow above is clear:
  schema SQL, dry-run/apply sync script, optional backend query path, fallback
  circuit, focused tests, deploy, then bounded `2pikabench`.

### Popularity-Aware Pool Cache

- Store/search-count signals so popular cards and products warm up faster.
- Candidate pools can be cached by normalized typed prefix plus language and
  product scope:
  - for one-character queries, `prefix = normalizedQuery.substring(0, 1)`
  - for longer queries, cache keys may use a longer stable prefix such as
    `normalizedQuery.substring(0, 3)` when that matches the backend strategy
  - `language = selected search language`
  - `scope = singles | products | all`
- Cache rows should track usage signals such as:
  - `search_count`
  - `click_count`
  - `cart_add_count`
  - `last_searched_at`
  - `last_clicked_at`
- Ranking should combine textual relevance with these signals, but relevance
  must still win for exact collector-number and exact name matches.
- This is especially useful because many users repeatedly search popular cards
  such as Charizard, Pikachu, Mew, Umbreon, and key sealed products.

### Trainer-Aware Matching

- Trainer names belong in their own structured field, not only as free text in
  card names.
- `marketplace_cards.trainer_name` and
  `marketplace_card_versions.trainer_name` should be indexed and filled by
  projection refreshes.
- `marketplace_trainers` should hold a small canonical trainer list plus aliases,
  because the list is small and stable compared with cards. Example aliases:
  - `Cynthia`: `Camilla`, `Shirona`, `C`
  - `Misty`: `Ondine`, `Kasumi`
  - `Brock`: `Pierre`, `Takeshi`
- Query normalization should rewrite owner phrases into exact variants:
  - `garchomp di camilla`
  - `garchomp cynthia`
  - `cynthia garchomp`
  - `Cynthia's Garchomp`
- Do not run broad fuzzy matching across every language. Use selected-language
  search plus small deterministic alias expansion.

### Multilingual Search Boundary

- TCGdex is useful for language-scoped card-name translation. It supports a
  multilingual Pokemon TCG API with more than 10 languages according to the
  [TCGdex API docs](https://tcgdex.dev/?ref=api.tcgdex.net).
- Use TCGdex only for the selected language, then map localized names back to
  English/internal search variants.
- Do not search all supported languages at once. That creates too many false
  positives and ruins ranking.
- Trainer aliases should remain small, curated, and deterministic. They are not
  a replacement for TCGdex card-name localization.

### Implementation Target

The current implementation keeps preview rows remote-authoritative:

```text
User types "g"
  -> visible autocomplete stays closed

User types "gar"
  -> visible autocomplete opens after debounce
  -> remote indexed search returns the visible preview rows

User types "garch"
  -> latest query is sent after debounce
  -> stale "gar" responses are ignored by request id

User types "garchomp di camilla"
  -> deterministic aliases add Cynthia variants
  -> search/rank against name + trainer_name + expansion fields
```

The UI should render a 9-row viewport over the best 20 candidates returned by
`/api/marketplace-autocomplete`. If a larger candidate-pool layer is reintroduced
later, update the backend contract and this workflow before changing Flutter.

The autocomplete popup must not render a top/header action row or a visible
`Show all` button. Full search remains available through keyboard submit and
explicit navigation to `/marketplace/search`; do not reintroduce
`showAllBuilder`, `_SearchPreviewLoadingActionRow`, or section-header `Show all`
buttons in `MarketplaceTopSearch` / `_SearchPreviewPanel`.

## Current Production Workflow

As of 2026-05-21, marketplace autocomplete warms backend search from the first
typed character, retains a lightweight local pool from 2 characters onward, and
renders remote API rows only once the typed query has 3 meaningful characters:

```text
User types 1 meaningful char
  -> Flutter debounces `CardNotifier.searchPreviewsOnly(...)`
  -> Flutter records `provider.preview.local_disabled`
  -> Flutter may request `/api/marketplace-autocomplete` with result_limit=20
     and a small/backend-only pool
  -> Flutter keeps the typed popup hidden and does not retain a broad local pool

User types 2 meaningful chars
  -> Flutter requests pool_limit=5000 and keeps the typed popup hidden
  -> Flutter stores lightweight candidate IDs/labels/depth metadata for fallback

User types 3 meaningful chars
  -> Flutter requests pool_limit=2500
  -> before the backend returns, the popup may show matching lightweight rows
     only from the current ranked context/ID pool
  -> autocomplete first tries the predictive ngram candidate index for typed
     inputs with at least two compact characters, then falls back to the
     structured name/field fanout and legacy prefix paths when needed
  -> the popup renders those `searchPreviewLimit` rows directly from backend
     order after response-order-preserving dedupe

User types 4+ meaningful chars
  -> Flutter requests pool_limit=1250 at depth 4 and pool_limit=500 at depth 5+
  -> local lightweight bridge rows preserve context ID order and remain capped
     to the ranked context/ID pool

User keeps typing
  -> Flutter sends the latest visible query after debounce
  -> stale remote responses are dropped by request id
  -> if the latest precise response returned a valid search_context and the new
     query extends it, Flutter can send that context for ID-bounded refinement
  -> while the new precise request is loading, Flutter can render up to 20
     matching name-only/materialized bridge rows from the current ranked
     context IDs/labels, then replace them with full backend rows whose IDs are
     still in that context
  -> character coverage and typo tolerance affect backend ranking/debug output
  -> the highlighter marks matching terms returned for the current visible rows
```

The remote autocomplete endpoint is the final ranker for typed preview rows.
Flutter displays only rows tied to the current ranked `search_context.card_ids`
and `candidate_labels`; if that pool is empty or missing, the typed popup shows
skeleton/no-data rather than broad fallback rows. It does not maintain a full
typed-query background pool, render independent fast-name preview results,
merge loaded-card matches into `state.searchPreviews`, show generic hot fallback
rows after typing starts, or alphabetically rerank completed remote rows; a
backend miss must be fixed in the Oracle/Vercel search path. Empty search focus
is the separate exception: Flutter warms the top 1000 hot cards/products,
prepends up to two recent blueprints, and renders only the first 20 rows from
that empty-focus list.

Layer note from the `pikachu` ranking investigation: if `pikachu` returns
`typed_predictive_ngrams` and places `Pitch's Pikachu` above normal `Pikachu`,
the issue is in backend API path selection and ranking over the Oracle ngram
candidate pool. The ngram index can validly generate owner/canonical-name
candidates, and site/user/depth boosts may affect order within the returned
pool, but Flutter only preserves backend order. Fix ranking/path selection in
`api/marketplace-autocomplete.js` or, if exact/prefix rows are absent from the
candidate pool, inspect `marketplace_card_names_for_language(...)`,
`marketplace_search_candidates.canonical_name`, and `marketplace_name_ngrams`.

The same order contract applies to typed full-search state in
`CardNotifier.searchCards(...)`: once `/api/marketplace-cards`,
`/api/marketplace-card-versions`, or `/api/marketplace-autocomplete` returns a
ranked result list for the active query, `filteredCards` should start from that
backend-ordered list. Cache updates may keep card details warm, but cache order
must not drive the active typed result order.

### Vercel Aggregation Endpoint

Use Vercel for the server-side search adapter because `pokoin.com` is already
deployed there and Vercel can hold `MARKETPLACE_DATABASE_URL` outside the
browser.

Production preview endpoint:

```text
POST /api/marketplace-autocomplete
```

Request body used by Flutter preview warmup:

```json
{
  "search_term": "miraidon",
  "result_limit": 20,
  "pool_limit": 2500,
  "search_language": "en"
}
```

Flutter stores the selected `search_language` as a local
`SharedPreferences` user preference (`marketplace.search_language`). New users
start in English (`en`), invalid saved values are cleared, and the loaded
provider state drives both autocomplete request bodies and full-search `lang`
query parameters.

The endpoint ranks the Oracle candidate pool server-side, prioritizing
single-card name intent before expansion, set, product, or rarity-only noise.
Exact/prefix card names must beat product rows for single-token queries such as
`lapras`; trainer card names such as `misty` are first-class single-card names.
The endpoint returns the visible rows plus compact pool/search-context metadata,
including `candidate_id_ladder`, depth metadata, and bounded lightweight
`candidate_labels`. Flutter renders completed rows directly in backend order
after dedupe only. Full rows in `rows` remain capped to the top 20.

Dedicated searchbar experiment endpoint:

```text
POST /api/searchbar-cards
GET /api/searchbar-cards?query=pikachu&search_language=en&limit=20&pool_limit=5000
```

Preferred POST request:

```json
{
  "query": "mew ex 216",
  "search_language": "en",
  "limit": 20,
  "pool_limit": 5000,
  "previous_search_context": null,
  "debug": false,
  "mode": "benchmark_step"
}
```

The endpoint is a stable harness around `/api/marketplace-autocomplete`, not a
separate ranker. Use it for searchbar experiments, automated quality tests, and
latency benchmarks while keeping the UI endpoint unchanged. It normalizes
experiment inputs (`query`, `search_language`, `limit`, `pool_limit`,
`previous_search_context`, `debug`, and `mode`) and always returns an object
shape:

```json
{
  "ok": true,
  "endpoint": "/api/searchbar-cards",
  "mode": "benchmark_step",
  "query": "mew ex 216",
  "search_language": "en",
  "limit": 20,
  "pool_limit": 5000,
  "rows": [],
  "search_context": {},
  "meta": {
    "candidate_id_ladder": {},
    "candidate_counts": {},
    "search_path": "candidate_context_refine",
    "timings": {}
  }
}
```

`rows` is the visible full-row payload and remains capped by `limit` and the
20-row preview cap. `search_context.card_ids` and
`search_context.candidate_labels` can carry the lightweight ID/label pool for the
next typed step according to the ladder: one character has no Flutter candidate
pool, depth 2 -> `5000`, depth 3 -> `2500`, depth 4 -> `1250`, and depth 5+ ->
`500`. These labels may hydrate temporary name-only/local fallback rows while a
new request is in flight; they must not replace full backend rows or trigger a
new client-side broad ranker.

Popup behavior stays the same: backend warmup starts at one meaningful
character, the typed popup becomes visible at three meaningful characters, and
completed rows render only from the current ranked `search_context.card_ids`.
If the latest response is still loading, Flutter may show local lightweight
bridge rows from current context IDs plus `candidate_labels`, capped to 20 and
preserving context ID order. Broad retained rows and independent fast-name
preview responses are not visible typed display sources.

Production raw candidate endpoint:

```text
POST /api/marketplace-search-candidates
```

Request body:

```json
{
  "search_term": "pillu",
  "result_limit": 1000,
  "result_offset": 0
}
```

The raw candidate endpoint lives in `api/marketplace-search-candidates.js`.
Autocomplete ranking lives in `api/marketplace-autocomplete.js`, and the
benchmarkable searchbar wrapper lives in `api/searchbar-cards.js`. These files
are copied into `build/web/api` by `deploy-pokoin-web.sh`. Keep the matching
routes in `vercel.json`.

The endpoint uses Oracle marketplace Postgres directly through `pg` and calls
`public.search_marketplace_blueprint_candidates_v2(...)`. Supabase remains for
forum APIs only.

### Oracle Marketplace Database Notes

Vercel needs `MARKETPLACE_DATABASE_URL` with `sslmode=require`. Classic Vercel
serverless outbound IPs are not stable enough for strict allowlisting, so use
Vercel static egress/secure compute if a hard IP allowlist is required.

Environment names supported by the marketplace Vercel endpoints:

- `MARKETPLACE_DATABASE_URL`
- `MARKETPLACE_NAME_SEARCH_DATABASE_URL` optional peer3 name/predictive chunk
  search replica
- `SUPABASE_NAME_INDEX_DATABASE_URL` optional backend-only Supabase Postgres URL
  for the derived card-name index; if unset, the backend can reuse
  `SUPABASE_DB_URL` when that database has `marketplace_card_name_tokens`
- `SUPABASE_NAME_INDEX_DATABASE_POOL_MAX` optional connection cap for the
  Supabase name-index pool
- `SUPABASE_NAME_INDEX_DATABASE_SSL_VERIFY=1` optional for trusted Supabase
  database certificates
- `MARKETPLACE_PEER4_DATABASE_URL` optional explicit peer4 writable primary alias
- `MARKETPLACE_PEER3_DATABASE_URL` optional explicit peer3 name/search replica
- `MARKETPLACE_PEER2_DATABASE_URL` optional explicit peer2 dimension/read replica
- `MARKETPLACE_PEER1_DATABASE_URL` optional explicit peer1 dimension/read replica
- `MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS` optional comma-separated peer2 and
  peer1 read replicas for fanout/predictive execution participation
- `MARKETPLACE_VARIATION_SEARCH_DATABASE_URL` optional single legacy variation
  replica
- `MARKETPLACE_PREDICTIVE_POOL_ENABLED=1` optional opt-in for the strict
  predictive 5000 pool fanout; leave unset until source/routing tests are ready
- `MARKETPLACE_PREDICTIVE_POOL_STRICT=1` default strict/no-broad-fallback mode
  for predictive pool development; set to `0` only after product explicitly
  accepts partial-source behavior
- `MARKETPLACE_NUMBER_SEARCH_DATABASE_URL`,
  `MARKETPLACE_EXPANSION_SEARCH_DATABASE_URL`,
  `MARKETPLACE_RARITY_SEARCH_DATABASE_URL`, and
  `MARKETPLACE_VARIATION_OWNER_SEARCH_DATABASE_URL` optional per-dimension
  overrides. If unset, routing derives from peer2/peer1/peer3, and strict mode
  marks missing required routes instead of falling back to peer4.
- `MARKETPLACE_ANALYTICS_SEARCH_REPLICA_URLS` optional comma-separated read
  replicas for autocomplete hot/user analytics
- `MARKETPLACE_SHORT_PREFIX_ANALYTICS_MAX_DEPTH` optional, defaults to `1`
- `MARKETPLACE_NAME_SEARCH_TIMEOUT_MS` optional per-shard prefix/name timeout
- `MARKETPLACE_DATABASE_POOL_MAX` optional
- `MARKETPLACE_NAME_SEARCH_DATABASE_POOL_MAX`,
  `MARKETPLACE_VARIATION_SEARCH_DATABASE_POOL_MAX`, and
  `MARKETPLACE_ANALYTICS_SEARCH_DATABASE_POOL_MAX` optional per-pool connection
  caps
- `MARKETPLACE_DATABASE_SSL_VERIFY=1` optional for trusted server certificates

Forum endpoints still use `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and
`SUPABASE_SERVICE_ROLE_KEY`.

### Local Ranking And Highlighting

Keep ranking and highlighting aligned. Users expect stronger character coverage
to move results upward as they type, and they expect the same characters to be
visible in the popup.

Relevant behavior:

- `lib/services/card_service.dart` fetches the autocomplete candidate pool from
  `/api/marketplace-autocomplete`.
- `lib/providers/card_provider.dart` does not locally rank or store a background
  preview pool. `state.searchPreviews` should contain the current top 20 returned
  by `/api/marketplace-autocomplete`, in that backend order, except while the
  latest request is still loading when it may contain the bounded typed fallback
  described above.
- Flutter must not use card-name `compareTo` or any alphabetical tie-breaker for
  typed autocomplete or full marketplace search results returned by ranked
  backend APIs. Client filtering/dedupe must preserve source order unless the
  user explicitly chooses a sort.
- Pokemon suffixes such as `ex`, `gx`, `v`, `vmax`, `vstar`, `mega`, and `lv x`
  must be classified as variation tokens before rarity handling. Structured
  queries such as `manaphy ex` and typo variants such as `mapahy ex` should use
  token intersection, not broad ranked-pool fallback.
- Single-token card-name intent is strong. For `lapras`, singles should beat
  loaded products and set-name noise. Product rows should only lead when the
  query is product-like, for example `box`, `pack`, `deck`, or `tin`.
- Typo thresholds must apply to card names, not only exact Oracle candidates.
  `mee` is close enough to `mew`; when paired with `23`, a loaded
  `Mew ex #232/091` must be eligible even if the remote pool first returns
  literal `MEE` set-code rows.
- `lib/screens/home_screen.dart` renders title/set highlights. It must merge
  full-term ranges with ordered single-character ranges; do not only highlight
  complete words.
- `test/card_service_test.dart` covers the character coverage ranking behavior.

For example, a query such as `pillu` can return candidates whose database fuzzy
score is close enough for the initial pool. The visible row text should still
highlight ordered characters when full token highlighting cannot explain the
local match.

### Variation-Aware Search

Pokemon card variations are structured Oracle search dimensions, not just fuzzy
text. Keep canonical variation metadata in `marketplace_variations` and card
membership in `marketplace_card_variations`.

Current seeded variation keys include `ex`, `v`, `vmax`, `vstar`, `gx`, `lvx`,
`mega`, `delta`, `gold_star`, `shining`, `radiant`, `prime`, `break`,
`tag_team`, and `ace_spec`.

Important ranking rules:

- A standalone `v` token is meaningful and should be weighted like other exact
  variation tokens such as `ex`, `gx`, and `vmax`.
- Flutter must not drop standalone `v` in minimum-length guards. `_searchTerms`
  should preserve `v`, preview/full-search guards should treat it as structured
  intent, and local filtering should call the variation matcher instead of
  `haystack.contains('v')`.
- `N` is the only one-character printed card name currently present in the
  Oracle marketplace catalog. Flutter may preserve standalone `n` as card-name
  intent and rank exact `N` first, while still allowing reasonable `N...` name
  prefixes. Other one-character text tokens should stay blocked.
- Single-token variation queries (`v`, `ex`, `gx`, `vmax`, `mega`, `shining`,
  etc.) should filter immediately to real card variant tokens. Do not allow
  substring matches such as `ex` -> `Exeggutor` or `v` -> `Venusaur`.
- `vstar` is both a card variant and a set token. Single `vstar` should rank
  real VSTAR cards first, but it may also include cards whose set has an exact
  `VSTAR` token, such as `VSTAR Universe`.
- Avoid broad one-letter prefix matching for names, translated names, or
  expansions. Otherwise query `v` can match almost every name/set starting with
  `v` and drown out actual `... V` cards.
- Variation tagging should use card identity fields only: `name`, `card_number`,
  `rarity`, `card_type`, and `product_variant`. Do not tag from `set_name`,
  `expansion_name`, or broad `search_text`; sets like `Shiny Star V` would make
  non-V cards look like V cards.
- Combined searches should reward name plus variation matches. Examples:
  `darkrai v` should rank `Darkrai V` before generic V cards, and
  `azief lv x` should still find `Azelf LV.X`.

### Candidate Pool Size

`searchPreviewPoolLimit` is currently `420` in
`lib/providers/card_provider.dart`. This is the requested background pool size,
not the number of rows shown in the UI. The Vercel autocomplete endpoint may
internally use a larger safe minimum while building and ranking the remote pool,
but Flutter should still render only the top 20.

For a query like `pillu`, production can return fewer candidates than requested
because the SQL function only returns rows that match its filters. The endpoint
cannot invent rows outside the SQL candidate definition. If Oracle returns fewer
matches, Flutter renders the smaller backend-ordered result set and must not
fill it with local or generic hot fallback rows.

If the user asks for lower latency, reduce the pool cap first or add a
server-side popularity/prefix cache. Do not reintroduce Flutter-side local
narrowing for typed previews.

## Files Involved

- `lib/screens/home_screen.dart`
  - Search input and CardTrader-style preview dropdown. The dropdown uses a
    `CompositedTransformFollower`, the search field width, and a short delayed
    close so row clicks are not swallowed by focus loss.
- `lib/providers/card_provider.dart`
  - Remote-authoritative typed preview/search state, 20-row visible previews,
    empty-focus hot/recent previews, and stale request guards.
- `lib/services/card_service.dart`
  - Oracle-backed marketplace API loading, projection search, preview image
    mapping and fallback behavior. Marketplace card-version and row searches
    should run in parallel where possible.
- `lib/models/pokemon_card.dart`
  - `previewImageUrl`, defaulting to `imageUrl`, plus structured marketplace
    fields such as `itemKind`, `productType`, and `trainerName`.
- `api/marketplace-search-candidates.js`
  - Vercel serverless search adapter. It calls Oracle Postgres through `pg` and
    `public.search_marketplace_blueprint_candidates_v2(...)`.
- `api/marketplace-autocomplete.js`
  - Server-side autocomplete ranking over the Oracle candidate pool. It should
    be able to return the full background pool requested by Flutter, not only
    the visible row count.
  - Hydrates visible preview rows with `expansion_symbol_url` from Oracle
    `cardtrader_pokemon_expansions.symbol_image_url` when available. Keep
    `./_supabase` lazy/optional so Oracle autocomplete and logo hydration do not
    fail if the Supabase REST fallback is unavailable or not bundled.
  - Keep `api/marketplace-autocomplete.test.js` updated for typo ranking,
    strict single-token variation filters, aliases such as `&`/tag team and
    `ill`/illustration rare, and broad-query side effects.
- `api/searchbar-cards.js`
  - Stable searchbar experiment and benchmark endpoint. It wraps the autocomplete
    ranking implementation, exposes a consistent object response for tests, and
    accepts char-by-char `previous_search_context` forwarding.
- `scripts/benchmark-searchbar-api.js`
  - Local/production benchmark harness for character-by-character typing traces,
    p50/p95 latency by depth, search paths, payload sizes, and final quality
    snapshots.
- `api/marketplace-cards.js` and `api/marketplace-card-versions.js`
  - Oracle-backed catalog/product and expansion/version rows used by Flutter.
- `vercel.json`
  - Routes `/api/marketplace-search-candidates` and `/api/searchbar-cards` to
    the serverless functions.
- `deploy-pokoin-web.sh`
  - Copies the search endpoints into `build/web/api` before Vercel deployment.
  - Rewrites bundled server helper imports for copied marketplace endpoints
    (`_marketplace_db`, `_firebase`, `_search_debug_auth`, `_searchbar_session`,
    and `_supabase` when present). If production logs show
    `Cannot find module './_supabase'`, the deploy package rewrite is stale; do
    not move logo hydration to Supabase to fix it.
- `oracle-postgres/schema/*.sql`
  - Oracle marketplace schema, projection refreshes, tokenized search
    dimensions, variation dimensions, home snapshot, and autocomplete/search
    RPCs.
- `scripts/oracle-marketplace-migrate.js`
  - Applies schema, copies non-forum data from Supabase during migration,
    refreshes projections, and verifies searches.
- `scripts/generate-cardtrader-preview-images.js`
  - Legacy Supabase-era preview generator. Port database writes to Oracle before
    running again.
- `scripts/import-cardtrader-preview-images.js`
  - Legacy Supabase-era CardTrader preview importer. Keep the R2 behavior, but
    port database writes to Oracle before running again.
- `scripts/import-ptcg-expansion-symbols.js`
  - Legacy Supabase-era expansion symbol importer. Port writes to Oracle
    `cardtrader_pokemon_expansions` before running again.

## Required Env

Read these from `.env.local`. Never print the values.

- `MARKETPLACE_DATABASE_URL`
- `SUPABASE_DB_URL` only for migration/copy or guarded cleanup
- `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` for forum
  APIs and old one-off import scripts only
- `CLOUDFLARE_ACCOUNT_ID`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `POKOIN_CARD_IMAGES_BUCKET`
- `POKOIN_CARD_CDN_BASE_URL`

## Oracle Migration Procedure

Marketplace/catalog/search schema now lives in `oracle-postgres/schema`.
Supabase marketplace migrations are historical and should not receive new
marketplace work.

```bash
node scripts/oracle-marketplace-migrate.js schema
node scripts/oracle-marketplace-migrate.js refresh
node scripts/oracle-marketplace-migrate.js verify
```

## Expansion Symbol And Logo Import

Expansion symbols are imported from
`https://github.com/1niceroli/ptcg-assets`. Each source expansion folder
contains `symbol.png`; the importer maps CardTrader expansion codes/names to
those source folders and writes the symbol to R2 as:

```bash
expansions/symbols/<cardtrader-expansion-name>.png
```

After porting, the importer should upsert Oracle
`public.cardtrader_pokemon_expansions`, storing the CardTrader expansion id,
CardTrader code/name, matched source asset code, CDN URL, and R2 object key.

Run from the project root:

```bash
git clone --depth 1 https://github.com/1niceroli/ptcg-assets.git ../ptcg-assets
DRY_RUN=1 PTCG_ASSETS_DIR=../ptcg-assets node scripts/import-ptcg-expansion-symbols.js
PTCG_ASSETS_DIR=../ptcg-assets node scripts/import-ptcg-expansion-symbols.js
```

Full expansion logos come from TCGdex metadata already stored in
`public.marketplace_blueprint_tcg_metadata.set_logo_url`. The logo importer
joins through `marketplace_card_versions.blueprint_id` so the logo is tied to
the expansion rows and collector-number pipeline the app already uses. It
uploads one source logo per expansion to R2 as:

```bash
expansions/logos/<cardtrader-expansion-name>.<source-extension>
```

Then it updates `public.cardtrader_pokemon_expansions.logo_image_url`,
`logo_object_key`, and `logo_imported_at` beside the existing `symbol_*`
fields. Run a small dry run first, then apply all missing logos:

```bash
node scripts/import-tcgdex-expansion-logos.js --limit=5
node scripts/import-tcgdex-expansion-logos.js --apply --limit=all
```

The first production run on 2026-05-18 uploaded 182 symbols. Verification was
done through database rows and direct R2 `HeadObject` checks. Local HTTP checks
against `https://cdn.pokoin.com/...` returned `403` for both new symbol paths
and pre-existing preview paths, so do not treat that local CDN check alone as
proof that an object is missing.

## Verify Fuzzy Search

Run app-shaped Oracle/Vercel checks. Do not add DB-side ordering to active
search queries unless it has been tested with compound numeric searches; client
ranking should sort active search results.

```bash
python3 - <<'PY'
import json, time, urllib.request

for term in ['pika uni', 'mew 232', 'porygon', 'char ex', 'v', 'darkrai v', 'azief lv x']:
    body = json.dumps({'search_term': term, 'result_limit': 20}).encode()
    req = urllib.request.Request(
        'https://pokoin.com/api/marketplace-search-candidates',
        data=body,
        headers={'content-type': 'application/json'},
        method='POST',
    )
    start = time.time()
    with urllib.request.urlopen(req, timeout=20) as res:
        rows = json.loads(res.read().decode())
    print(term, 'rows=', len(rows), 'ms=', round((time.time() - start) * 1000))
PY
```

Known healthy result: terms return rows in hundreds of milliseconds and do not
depend on the capped Flutter home catalog. `pika uni` should include
`Pikachu | Unified Minds`; `mew 232` should include
`Mew ex | Paldean Fates | Special Illustration Rare | 232/091`; `v` should
return actual `... V` cards; `darkrai v` should rank `Darkrai V` first; and
`azief lv x` should rank `Azelf LV.X`.

Old Supabase RPCs may still exist until cleanup runs, but new UI work should use
the Oracle-backed marketplace APIs because they avoid parsing heavy blueprint
JSON in Flutter.

## Generate Preview Images

These importers were written before the Oracle marketplace cutover and still
write to Supabase. Do not run them again until their database writes target
Oracle Postgres. R2 upload behavior can stay the same.

Preview generation is long because it covers every CardTrader blueprint image.
Prefer `import-cardtrader-preview-images.js` when you specifically want the
preview image exposed by CardTrader's API. Use the generated WebP script when
you want previews resized from our full CDN-hosted card images.

Run a targeted CardTrader API preview import first:

```bash
PREVIEW_IDS=274416,254235 node scripts/import-cardtrader-preview-images.js
```

Prioritize new CardTrader rows that do not have previews yet:

```bash
PREVIEW_MISSING_ONLY=1 PREVIEW_NEWEST_FIRST=1 PREVIEW_BATCH_SIZE=100 PREVIEW_MAX_ROWS=1000 node scripts/import-cardtrader-preview-images.js
```

For newest-first missing-only runs, the importer prints `next cursor <id>`.
Resume from that cursor:

```bash
PREVIEW_MISSING_ONLY=1 PREVIEW_NEWEST_FIRST=1 PREVIEW_CURSOR_ID=<id> PREVIEW_BATCH_SIZE=100 PREVIEW_MAX_ROWS=1000 node scripts/import-cardtrader-preview-images.js
```

After porting, the importer should store `preview_object_key` on Oracle
`cardtrader_pokemon_blueprints`; projection tables receive `preview_image_url`.
Homepage/grid/card widgets should use `previewImageUrl` first and pass the full
`imageUrl` as a fallback. This protects old recent-view entries and cards whose
preview import has not completed yet.

Run the small batch first:

```bash
PREVIEW_MAX_ROWS=5 PREVIEW_BATCH_SIZE=5 node scripts/generate-cardtrader-preview-images.js
```

Then run the full batch:

```bash
node scripts/generate-cardtrader-preview-images.js
```

Progress prints every 100 rows:

```text
processed 100, generated 95
processed 200, generated 195
```

Known status when this workflow was written:

- Total rows with card images: `41099`
- Preview rows generated at last check: `1500`
- The full job was still running and healthy.

The following historical Supabase progress check is not valid after Oracle
cutover. Port it to Oracle before use:

```bash
node scripts/oracle-marketplace-migrate.js verify
```

Verify a generated preview through the app proxy:

```bash
curl -L -I "https://pokoin.com/card-images/previews/<preview-key>.webp"
```

Expected:

- HTTP `200`
- `content-type: image/webp`

## Generate Homepage Images

Homepage carousel images are separate from search previews. The coverage target
is every marketplace blueprint that has any source image: `homepage_image_url`
should be populated for each eligible row, not only for rows with weak previews.
The preferred object is a generated CDN/R2 `_homepage.webp` derivative at 240px
wide with the source image's natural aspect ratio.

Rendering contract:

- Data may be warmed from the homepage snapshot/local cache before render, but
  image-heavy carousel and Card spotlight widgets must not all build during the
  landing-to-marketplace route animation.
- Entering `/marketplace` from the landing `Shop` button should show lightweight
  placeholders until the route animation settles, then mount carousels/spotlight
  lazily. This avoids a frame spike caused by building all image cards on the
  same frame as the transition.
- Carousel rows should be lazy on both mobile and desktop: zero offscreen cache,
  no automatic keep-alives, and animated card entry as rows are built while
  horizontally scrolling. Mobile rows use preview images instead of
  `_homepage.webp`; desktop can keep `_homepage.webp` but must not eagerly keep
  every carousel card alive.
- Card spotlight data should stay warmed separately from tile rendering. Store a
  compact local spotlight list from the homepage snapshot and expose it through
  provider state, but keep full tile/image construction behind the viewport gate.

Use `scripts/generate-oracle-homepage-card-images.js` to link or create
`homepage_image_url` values in Oracle:

```bash
HOMEPAGE_IMAGE_IDS=274416 node scripts/generate-oracle-homepage-card-images.js
HOMEPAGE_IMAGE_IDS=274416,<bad-preview-id> node scripts/generate-oracle-homepage-card-images.js --apply
node scripts/generate-oracle-homepage-card-images.js --verify-coverage
node scripts/generate-oracle-homepage-card-images.js --apply --limit=5000 --concurrency=100
```

The script is dry-run by default. It uses a fixed 240px homepage reference width
(`HOMEPAGE_IMAGE_REFERENCE_WIDTH=240` by default) rather than measuring Mew ex
`274416` or any other preview as a baseline.
Use `--concurrency=100` for large apply runs on a strong local machine, and
`--limit=all` only after targeted dry-runs are clean. The run is idempotent:
existing `_homepage.webp` mappings are rechecked against the 240px reference and
linked only when already good; weak existing derivatives are regenerated from
the full/source object. For resumable chunks, use `--limit=<rows>` and continue
from the printed `next start id` with `--start-id=<id>`.

After each batch, run `--verify-coverage` and record the remaining
`missing_homepage_images` count before deploy/verification. Stopping an
unbounded or long-running apply process leaves partial coverage by design; do
not treat a stopped run as complete until the missing count is zero or every
remaining row has an explicit no-source reason. The known partial state before
the full backfill was `5,806` populated rows with `64,215` eligible source rows
still missing `homepage_image_url`.
Also require `snapshot_homepage_mismatches` to be zero. A zero missing count only
proves the source/projection tables are populated; the homepage API can still
fall back to previews if the deployed `get_marketplace_home_snapshot()` function
does not emit `homepageImageUrl`.
When users report worse homepage images, first fetch the live
`/api/marketplace-home` response and confirm it is HTTP `200` with
`homepageImageUrl` values pointing to `_homepage.webp`; a broken or stale API can
make the client render cached/fallback preview rows even though the generated
objects are correct.

Decision rules:

- Link to a preview only as an explicit degraded fallback when no full/source
  object exists and the preview is at least 240px wide. Preview-linked rows are
  not ideal and must be tracked separately from generated `_homepage.webp`
  derivatives. Below-reference previews are skipped instead of linked.
- If the preview is below the 240px reference and a full/source object is
  available, resize that object to 240px wide with natural aspect ratio,
  preserving card-like portrait images and non-card/product-like images without
  a rectangular canvas, crop, or distortion. If a source is smaller than 240px,
  Sharp's no-enlargement behavior keeps its original dimensions instead of
  upscaling.
- Do not use source width as a reason to skip a row. Existing 180px previews are
  normally below the new reference and should get a `_homepage.webp` derivative
  when a full/source object exists.
- Do not rely solely on `item_kind` or `product_type` to decide image treatment;
  those product signals can be wrong. The homepage derivative path preserves
  natural image aspect for all rows.
- Updates are written to `cardtrader_pokemon_blueprints`,
  `marketplace_cards`, `marketplace_card_versions`, and
  `marketplace_search_candidates` so `/api/marketplace-home` can serve the URL
  without a full projection refresh.
- Keep runs targeted until the dry-run output is reviewed. For full runs, stop
  and inspect if errors repeat or the script hits `--error-limit`.

## Import Full CardTrader Images

The production image source should be our R2 bucket behind
`https://cdn.pokoin.com`, not CardTrader URLs. When CardTrader exposes a
higher-resolution blueprint image, import that source into R2 and keep the app
using the same `/card-images/...` proxy format.

For the dated operational report that preserves importer behavior, known
fragilities, and retest commands, see
`workflows/cardtrader-full-image-import-report.md`.

Run a targeted Oracle import first:

```bash
ORACLE_IMAGE_IDS=274416 node scripts/import-oracle-cardtrader-images.js
```

CardTrader is an import source only. Do not leave `cardtrader.com` URLs in
runtime image columns. The Oracle importer must download CardTrader assets,
upload them to R2, and write CDN URLs into Oracle before the app sees the row.

The importer:

- Reads `blueprint.image.url` and `blueprint.image.show.url` from
  `cardtrader_pokemon_blueprints`, trying each usable candidate before failing a
  row.
- Downloads the full CardTrader image from `blueprint.image.url` first.
  `show_` URLs are fallback sources only, and `/preview_` sources must never be
  used for full/card-detail images when a full or show source exists.
- Detects the actual image format from magic bytes and response headers before
  choosing the R2 object extension/content type. Do not trust CardTrader URL
  extensions; some `.jpg` URLs return WebP bytes.
- Uploads the bytes to R2 using the existing `<blueprint_id>_slug.ext` key
  format with the detected extension.
- Updates Oracle `cardtrader_pokemon_blueprints.image_url`,
  `cdn_image_url`, `cdn_object_key`, `preview_image_url`, and
  `preview_object_key` with CDN-backed values.
- Updates Oracle projections directly so homepage/search/card detail APIs never
  serve CardTrader-hosted image URLs.
- Stores the CardTrader source URL used for the full image in
  `cardtrader_image_url`, so later quality audits can tell whether an old row was
  imported from `preview_`, `show_`, or the preferred full source.

Quality repair mode for old downsampled rows:

```bash
ORACLE_IMAGE_MODE=full \
ORACLE_IMAGE_AUDIT_QUALITY=1 \
ORACLE_IMAGE_SOURCE_MISMATCH_ONLY=1 \
ORACLE_IMAGE_PRODUCT_TYPE=card \
ORACLE_IMAGE_FULL_KEY_SUFFIX=full-v4 \
ORACLE_IMAGE_BATCH_SIZE=250 \
ORACLE_IMAGE_MAX_ROWS=1000 \
ORACLE_IMAGE_CURSOR_ID=0 \
node scripts/import-oracle-cardtrader-images.js
```

This downloads the preferred full source and the current R2 object, compares
dimensions with `sharp`, and only reimports when the current full image is
materially lower resolution than the source. Use a fresh
`ORACLE_IMAGE_FULL_KEY_SUFFIX` so immutable CDN caches cannot keep serving the
old lower-quality object.

Verify through the app proxy:

```bash
curl -L -I "https://pokoin.com/card-images/274416_mew-ex-special-illustration-rare-232-091-paldean-fates.jpg"
```

Expected:

- HTTP `200`
- `content-type: image/jpeg`
- A full-image `content-length` larger than the old preview-derived object.

Run the full job in resumable chunks:

```bash
ORACLE_IMAGE_BATCH_SIZE=50 ORACLE_IMAGE_MAX_ROWS=1000 node scripts/import-oracle-cardtrader-images.js
```

Prioritize new CardTrader rows that do not have CDN images yet:

```bash
ORACLE_IMAGE_NEWEST_FIRST=1 ORACLE_IMAGE_BATCH_SIZE=50 ORACLE_IMAGE_MAX_ROWS=1000 node scripts/import-oracle-cardtrader-images.js
```

For older missing rows, run oldest-first chunks. This has found product rows with
valid CardTrader images that were missed by newer-first imports:

```bash
FULL_IMAGE_MISSING_ONLY=1 FULL_IMAGE_BATCH_SIZE=50 FULL_IMAGE_MAX_ROWS=300 node scripts/import-cardtrader-full-images.js
```

If a row still fails after all candidates are tried, inspect CardTrader directly.
Some blueprint image URLs are stale and return `404` for both full and `show_`
variants; those are upstream-broken rather than CDN import failures.

If the regular full-catalog job stops after printing `next offset 1000`,
resume with:

```bash
FULL_IMAGE_OFFSET=1000 FULL_IMAGE_BATCH_SIZE=50 FULL_IMAGE_MAX_ROWS=1000 node scripts/import-cardtrader-full-images.js
```

For newest-first missing-only runs, the importer prints `next cursor <id>`.
Keep the same mode flags and resume from that cursor:

```bash
FULL_IMAGE_MISSING_ONLY=1 FULL_IMAGE_NEWEST_FIRST=1 FULL_IMAGE_CURSOR_ID=<id> FULL_IMAGE_BATCH_SIZE=50 FULL_IMAGE_MAX_ROWS=1000 node scripts/import-cardtrader-full-images.js
```

Do not set `REFRESH_MARKETPLACE_PROJECTIONS=1` for normal full-image imports.
The full projection RPCs can time out on the whole catalog, and image-only
changes are already synced row-by-row by the importer.

## Deploy Web Changes

Always use the project deploy script after changing Flutter/app/API code:

```bash
./deploy-pokoin-web.sh
```

Do not run plain `vercel deploy` from the project root. It can deploy an
incomplete output without the Flutter build, API files, or Dart defines.
Do not assume a git push or workflow/doc commit updates `pokoin.com`.

## Verification Checklist

Before deploy:

```bash
node --check api/marketplace-autocomplete.js
node --check api/searchbar-cards.js
node --check api/searchbar-token-predict.js
node --check api/_supabase.js
node --test api/marketplace-autocomplete.test.js
node --test api/searchbar-cards.test.js
node --test api/searchbar-token-predict.test.js
node --test api/pokoin-checkout-deploy-layout.test.js
dart format lib/models/pokemon_card.dart lib/models/pokemon_card.g.dart lib/services/card_service.dart lib/providers/card_provider.dart lib/screens/home_screen.dart test/card_service_test.dart
flutter test test/card_service_test.dart
python3 -m json.tool vercel.json >/dev/null
python3 -m json.tool web/vercel.json >/dev/null
flutter analyze
```

Docs-only changes do not need the heavy checks above. If API/helper scripts were
touched, include the Node checks/tests. If Flutter fallback code was touched,
include `flutter test test/card_service_test.dart` at minimum, then run broader
Flutter checks when the change has wider UI/model impact.

After deploy:

```bash
curl -L -s "https://pokoin.com/main.dart.js" -o /tmp/pokoin-main-search.js
python3 - <<'PY'
from pathlib import Path
text = Path('/tmp/pokoin-main-search.js').read_text(errors='ignore')
for marker in [
    'marketplace_card_versions',
    'marketplace_cards',
    'preview_image_url',
    'expansion_number',
    'isSearchingPreviews',
    '/card-images',
]:
    print(f'{marker}={marker in text}')
PY
```

Also verify:

```bash
curl -L -I "https://pokoin.com/marketplace"
curl -L -I "https://pokoin.com/marketplace/search?q=Steven"
curl -L -I "https://pokoin.com/card-images/<known-card-image>"
curl -L -I "https://pokoin.com/card-images/previews/<known-preview-image>"
```

If `HEAD` returns `403` for image routes, verify with a normal `GET` before
assuming the image is broken. Some CDN/proxy paths serve `GET` correctly while
rejecting `HEAD`.

Then open `https://pokoin.com/marketplace`, hard refresh if needed, and verify:

- Search suggestions for `mew 232` include Mew ex `232/091`.
- Search suggestions for `mew 232` also include similar Mew results after the
  exact match, capped at 20 candidates with about 9 visible at once.
- Search suggestion rows can be clicked reliably; if clicks fail, inspect focus
  loss/removal timing in `_MarketplaceTopSearchState`.
- The popup width matches the search bar width.
- Search suggestions show card name plus collector/expansion number.
- Search suggestions for `pika uni` include Pikachu from Unified Minds.

After any API deploy that touches autocomplete/searchbar bundling, run backend
`2pikabench` against production only after confirming `/api/marketplace-autocomplete`
no longer fails with `Cannot find module './_supabase'`. Separately run Flutter
`2pikabench` locally for provider fallback behavior; it does not prove production
API health.

## Important Failure Modes

- Historical Supabase marketplace migration notes are no longer the production
  path. New marketplace schema/search changes belong in
  `oracle-postgres/schema/*.sql`.
- The Oracle tokenized search RPC must keep key smoke queries fast:
  `porygon`, `piachu 151`, `char ex`, `v`, `darkrai v`, `azief lv x`, and
  `mew special illustration rare`.
- CardTrader `name` is no longer the only name-search surface. Oracle projections
  preserve `source_name`/`display_name`, but search identity uses
  `canonical_name`, with variants in `product_variant` and trainer owners in
  `trainer_name`.
- Trainer-owned Pokémon such as `Lt. Surge's Pikachu` should search as
  `Pikachu` plus trainer metadata. Actual Trainer/Supporter/Item names such as
  `Cynthia` and `Rare Candy` stay intact as canonical names.
- If `pikachu surgin` shows `Surfing Pikachu` before Surging Sparks cards,
  inspect canonical projection refresh and RPC name joins before changing the UI.
- If a short variation query such as `v` returns non-V cards first, inspect
  `marketplace_card_variations` population before adjusting UI ranking. The
  usual cause is tagging variations from expansion/search text instead of card
  identity fields.
- Preview generation is resumable. Existing `preview_image_url` rows are skipped
  unless `PREVIEW_FORCE=1` is set.
- The Flutter app must tolerate missing `preview_image_url`. Do not remove the
  fallback to `imageUrl`.
- Search preview rows should include the collector/expansion number next to the
  card name when present, without a `#` prefix. Do not show opaque CardTrader
  blueprint IDs as if they were collector numbers for real singles.
- Product results should be separated from singles with a section separator row
  labeled `Products` and the product/inventory icon. Do not draw a vertical
  divider inside each product result row; the row layout should stay consistent.
- Search preview clicks must resolve both singles and products. Do not constrain
  detail slug lookup to `productType=card`; product/deck rows can share an
  expansion slug and have no collector number. The detail resolver may tolerate
  only the leading classifier/rarity slug token difference, such as `card-...`
  versus `fixed-...`, after Oracle has narrowed candidates.
- Search preview rows should show the actual expansion symbol image whenever
  the row has one. Logos are Oracle/R2-backed: the Flutter badge already
  prefers `expansionSymbolUrl`; keep `/api/marketplace-autocomplete` hydrating
  `expansion_symbol_url` from Oracle
  `cardtrader_pokemon_expansions.symbol_image_url` before falling back to text
  set codes such as `PE`, `SBS`, or `PF`. Supabase is only an optional
  name-index fallback and must not be required for Oracle autocomplete rows or
  logo hydration.
- If `mew 232` returns rows in Oracle verify but the UI shows nothing,
  inspect the app request shape and deployed bundle before changing the ranking.
  Common causes are stale production builds, browser cache, DB-side ordering on
  active search, or an old deployed bundle that still contains local cached
  suggestions masking the remote full-catalog result.
- If the popup contains only one exact compound match, debug
  `/api/marketplace-autocomplete` and its `tokenPlan`/ranking output. Do not
  revive `CardService.searchCardPreviews(...)` or similar-query local fallbacks;
  that preview path has been retired.
- The full search page is intentionally separate from the home catalog. If it
  returns only a few cards while Oracle has more matches, check that it is
  calling `CardService.searchMarketplaceCards(...)` instead of filtering
  `state.filteredCards`.
