# Card Market Modification Workflow

Use this workflow for every future change to the Pokoin Card Reserve market,
especially `/marketplace`, `/card/:id`, seller listings, cart, and checkout.

## Product Direction

- The card page must not regress to a static mockup.
- Card identity and images come from Oracle marketplace projections populated
  from CardTrader blueprint data.
- Seller listings, cart entries, and pending orders live in Firebase/Firestore.
- The UI should stay dark and Pokoin-branded, not white shop-template styling.
- The website must never expose a white browser frame, including refresh and
  first paint before Flutter boots. Keep `web/index.html` and static SEO fallback
  pages on the same dark `#050816` document background.
- Pricing is Pokoin-first. Show PKN clearly; fiat can be secondary context.
- Do not show CardTrader-specific labels such as `CT Min Price` or
  `CT Market Price` in the graph panel.
- Cart and checkout should feel like first-party Pokoin flows: dark navy
  surfaces, gold/cyan accents, clear seller/listing snapshot context, and no
  generic ecommerce template language.

## Current Data Flow

- `lib/services/card_service.dart`
  - Uses Oracle-backed Vercel APIs for marketplace card data.
  - Uses `/api/marketplace-cards` for homepage/catalog/search preview rows.
  - Uses `/api/marketplace-artist-cards` for artist gallery/collection rows by
    `normalized_artist` slug. This endpoint must be included in Vercel API
    rewrites and deploy packaging so `/api/...` returns JSON instead of the
    Flutter HTML shell.
  - Uses `/api/marketplace-home` for dynamic carousel sections. That endpoint
    returns both section IDs and a card payload; merge `snapshot.cards` into
    `CardState.cards` before resolving carousel IDs, otherwise Best sellers and
    Featured can render empty when their IDs are not in the capped catalog load.
  - Records marketplace interactions through `/api/marketplace-event`.
    Flutter should include safe card/search metadata only: card name, set,
    number, rarity, type, product kind, tags, query/result context. Do not send
    user IDs, emails, wallet addresses, auth tokens, or other PII.
  - Uses `/api/marketplace-card-versions` for expansion-scoped navigation and
    full search result rows.
  - Does not read Supabase marketplace tables directly. Marketplace cards,
    images, expansion logos, listings, prices, and autocomplete row hydration
    are Oracle/R2-backed through Vercel APIs. A backend endpoint may use the
    optional derived Supabase name-index layer only for card-name candidate
    IDs/labels; it must hydrate visible rows and logos from Oracle before
    returning data to Flutter.
  - Falls back to Hive cache and then local sample cards only when remote data is
    unavailable.
- `lib/providers/card_listing_provider.dart`
  - Streams active `card_listings` from Firestore by `cardId`.
  - Also exposes `activeCardListingsProvider` for aggregate signal/dashboard
    metrics.
- `lib/models/card_listing.dart`
  - Defines seller listing fields: condition, language, reverse holo, signed,
    graded, grading company, grade, shipping, reserve availability, NFT, seller
    snapshot, card snapshot, price, and quantity.
- `lib/providers/cart_provider.dart`
  - Stores listing-aware cart entries keyed by listing id.
  - On browser refresh, hydrates the user-scoped Hive box first so top-bar cart
    counts do not flash or stay at zero while Firebase auth/Firestore restore.
    After local hydration it reconciles with `user_carts/{uid}` and writes the
    merged listing-aware snapshot back to both local and remote storage.
  - Cart loads are serialized and generation-checked. Do not start parallel
    constructor/auth-listener loads or let stale remote reads overwrite a newer
    UID/account switch.
  - Authenticated carts use UID-scoped local boxes. Guest carts use a guest box.
    Logout/account switch must clear or abandon the previous user's local cart
    cache before loading the next account.
- `lib/screens/cart_screen.dart`
  - Owns `/cart`. Keep both empty and populated states dark Pokoin-branded.
  - Quantity/remove actions must operate on `CartItem.cartKey`, not only
    `card.id`, so listing-specific cart rows remain distinct.
- `lib/screens/checkout_screen.dart`
  - Owns `/checkout`. Keep the current premium step-based Pokoin flow: account
    status, item snapshots, fulfillment notes, wallet context, and final review.
  - Places paid marketplace orders through
    `marketplaceAccountServiceProvider.createPaidOrder(...)`, which calls
    `/api/marketplace-orders`; do not restore the older client-only pending
    order path for paid marketplace checkout.
- `lib/screens/card_detail_screen.dart`
  - Owns `/card/:id`, sell dialog, real listing table, no-seller state, and
    chart/market panels.
  - Loads the ordered version list for the current expansion once through
    `CardService.getExpansionVersionCards(...)`; previous/next is computed
    locally from that cached list.
- `lib/utils/card_url.dart`
  - Generates canonical share/detail URLs as
    `/marketplace/{lang}/cards/{publicNumber}/{rarity}-{name}-{number}-{set}`.
  - Canonical card slugs remain human-readable while the public number segment
    makes the path globally unique. Example: Leafeon `316600` has public number
    `633200` and becomes
    `/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions`.
  - Root links such as `/{blueprintId}/{slug}` are legacy-compatible and must
    continue to resolve for pasted links and crawler unfurls.
  - `legacyCardDetailSlug(...)`, `cardIdFromSlug(...)`, and public-number helpers
    exist for compatibility with old numeric links and canonical route parsing.
- `lib/main.dart`
  - Routes `/:cardId/:cardSlug` to normal card detail pages.
  - Routes `/marketplace/:lang/cards/:cardPage/:cardSlug` and
    `/marketplace/:lang/cards/:cardPage/:cardSlug/versions` to legacy card
    detail/version pages, decoding `cardPage` as a public number only when the
    slug segment is present.
  - Routes `/marketplace/:lang/cards/:cardPage` and
    `/marketplace/:lang/cards/:cardPage/versions` remain compatibility routes
    for simple real ids and legacy numeric slugs.
  - Keeps the legacy `/card/:id` detail route available.
  - Intercepts digit-only root paths such as `/129834` by rendering
    `CardDetailScreen(cardId: '129834')` directly; do not client-redirect these
    links through `/marketplace/en/cards/:id`, because failed intermediate
    resolution can bounce to `/`. The card detail resolver canonicalizes to the
    public-number marketplace URL once the card payload is loaded.
- `api/marketplace-card-seo.js`
  - Owns server-rendered Open Graph/Twitter metadata for crawler requests to
    canonical marketplace card URLs and legacy root card URLs.
  - For canonical marketplace URLs, the first path segment after `cards` is a
    public number and must be divided by 2 before Oracle lookup. Example:
    `/marketplace/en/cards/248768/card-drifloon-lv-17-non-holo-promo-6-17-pop-series-6`
    must resolve blueprint/card id `124384`, not `248768`.
  - Must emit absolute `og:image`, `og:url`, `twitter:image`, and
    `summary_large_image` tags from Oracle/R2 card image fields; Flutter client
    route updates are too late for Discord, Slack, Telegram, and Twitter unfurls.
  - For noisy legacy root slugs, treat the numeric blueprint id as authoritative
    and fall back to id-only lookup before returning the default site banner.
  - Verify previews with crawler user agents, for example
    `curl -A "Discordbot/2.0" https://pokoin.com/124384/card-drifloon-lv-17-non-holo-promo-6-17-pop-series-6`
    and canonical examples for Leafeon/Fan Rotom.
- `lib/screens/marketplace_signal_screen.dart`
  - Owns `/marketplace/signal`.
  - Shows real loaded catalog/projection metrics plus active Firestore listing
    metrics: listing count, quantity, sellers, floor, median, total ask, top
    expansions, product types, and listed cards.
  - Must not show completed sales, 24h volume, or historical charts until
    settled order/event aggregates exist.

## Oracle Projection Tables

- `public.marketplace_cards`
  - Lightweight marketplace card rows for home, search preview, and catalog
    surfaces.
  - Refreshed by `public.refresh_marketplace_cards_from_blueprints()`.
- `public.marketplace_card_events`
  - Analytics input for dynamic home sections and rolling 24h marketplace
    signals. These are interaction events, not completed-sale volume.
- `public.marketplace_hot_blueprints`
  - Durable hot blueprint rollup refreshed by
    `public.refresh_marketplace_hot_blueprints()`.
  - Stores 1h/24h/7d view/search/click/cart/reserve/sale counts plus hot scores.
  - `public.get_marketplace_home_snapshot(...)` reads this table for real Best
    sellers and Featured section IDs. Best sellers are the top score order.
    Featured is selected from the top 36 rare/promo/variant candidates and
    rotates the 12-card window every six hours, so it changes without abandoning
    score-based curation. Do not recompute raw events or rotate IDs inside
    Flutter.
  - If Featured cards do not change while users are navigating, compare
    `max(marketplace_card_events.occurred_at)` with
    `max(marketplace_hot_blueprints.refreshed_at)`. Raw events can be healthy
    while the homepage stays static if the hot rollup is stale.
  - `/api/marketplace-event` is responsible for opportunistically refreshing
    this rollup when it is older than a few minutes. `/api/marketplace-home`
    performs the same stale check before reading the snapshot so Featured is
    not blocked when users only load the homepage. Keep both refresh paths
    throttled by `refreshed_at`; do not run them unconditionally.
- `public.marketplace_card_versions`
  - Minimal ordered version/navigation rows:
    `card_id`, `name`, `expansion_name`, `expansion_number`,
    `expansion_number_int`, `blueprint_id`, and image URLs.
  - Refreshed by `public.refresh_marketplace_card_versions()`.
  - Use this table through `/api/marketplace-card-versions` for `/card/:id`
    previous/next and version search. Do not parse heavy blueprint JSON in the
    client for navigation.
- `public.marketplace_card_urls`
  - Materialized canonical card URL rows keyed by `card_id`/blueprint id.
  - Canonical paths use the public number plus a readable human slug:
    `/marketplace/{lang}/cards/{publicNumber}/{rarity}-{name}-{number}-{set}`.
  - The 2026-05-22 Oracle refresh regenerated `70,021` rows with `0`
    duplicate canonical paths. Use `public.refresh_marketplace_card_urls()` for
    targeted URL-table refreshes when a full projection refresh times out.
- `public.marketplace_blueprint_artists`
  - Separate artist/illustrator metadata table keyed by blueprint/card id.
  - Marketplace APIs may expose `artist` and `illustrator` as display-only
    attribution on home, catalog, hot, and version rows.
  - Artist names must stay out of search terms, rarity parsing, token
    dimensions, and ranking. Do not add artist columns to the main blueprint or
    projection tables.
  - Fallback artist sources may only validate or fill names whose
    `normalized_artist` already exists in this table. Unknown fallback artists
    must be reported as gaps, not inserted as new artist authorities.
  - Artist collection pages should query this table by `normalized_artist` via a
    dedicated artist endpoint. Do not emulate artist groups from search terms.
- `public.marketplace_artist_profiles`
  - Separate artist-page profile metadata keyed by `normalized_artist`, including
    display name, summary/bio, profile image source URL, cached CDN URL/object
    key, PocketMonsters reference, Bulbapedia reference, source attribution JSON,
    fetch timestamp, and raw source metadata.
  - This table enriches `/marketplace/{lang}/artists/{artistSlug}/profile` only.
    Its text must not be added to search candidates, autocomplete tokens,
    ranking, hot scores, or card identity projections.
  - PocketMonsters images should be cached to Pokoin R2/CDN when configured.
    When caching is unavailable, the API may return the source image URL as a
    fallback and importer reports should mark the row as cache-needed.
    Profile rows with `profile_image_url` but empty `profile_image_cdn_url` or
    `profile_image_object_key` are cache misses, not new profile-discovery work;
    audit them with
    `node scripts/import-marketplace-artist-profiles.js --audit-image-cache --limit=all`
    and recache verified misses with
    `node scripts/import-marketplace-artist-profiles.js --apply --recache-missing-images --artist="Mitsuhiro Arita" --limit=1 --concurrency=1`
    or the same command without `--artist` for a reviewed bulk recache.
  - After a bulk profile-image recache, run a quality audit for low-value
    cached images: tiny dimensions, mostly grayscale/low saturation, blank or
    transparent content, or one small image hash repeated across many artists.
    If the source image itself is a PocketMonsters placeholder, clear or
    suppress the image only after review so the public page falls back to
    initials rather than showing a grey portrait.
  - Bulbapedia references must show an external link and CC BY-NC-SA attribution.
    Ambiguous Bulbapedia page matches should be reported rather than inserted.
- `public.marketplace_blueprint_classification_overrides`
  - Manual product classification overrides from `/marketplace/debug/artists`.
  - The debug API writes this table on peer4 and immediately updates the current
    projection rows for the selected blueprint. Projection refreshes must honor
    the override so product classifications do not revert.
- `public.marketplace_artist_debug_skips`
  - Operator-only queue skip log for the artist curation page. It is not artist
    metadata and should not be shown on public card pages.
- `public.cardtrader_pokemon_expansions`
  - Stores expansion metadata and the R2-backed `symbol_image_url`.
  - Autocomplete/search preview rows should hydrate `expansion_symbol_url` from
    this Oracle table when a symbol exists. Supabase must not be treated as the
    logo source.

## Required Checks Before Editing

1. Search for the current implementation points:
   ```bash
   rg "CardDetailScreen|cardListingsProvider|CardListing|_CardMarketData|Sell this card" lib
   ```
2. Confirm the requested change affects one of these surfaces:
   - catalog card data
   - seller listing form
   - listing table actions
   - market chart/stats
   - cart/checkout listing behavior
   - no-seller state

## Implementation Rules

- Do not reintroduce deterministic fake sellers as the main data source.
- If a card has no seller listing, render a CardTrader-like empty state:
  `No items found`, wishlist action, and `Sell this card`.
- Every actionable listing row must refer to a real Firestore listing id.
- Cart buttons must add the exact selected listing, not just the generic card.
- Seller-created listings must persist to Firestore and appear realtime.
- Graded listings must capture both grading company and grade.
- Reverse holo should be a first-class listing option because it is common.
- Reserve is a public listing availability tag backed by its own
  `reserve_available`/`reserveAvailable` field. Do not wire it to shipping.
- Only Firebase reserve-role accounts can create or update reserve listings.
  Enforce this in `/api/marketplace-listings`; Flutter UI gating is only a
  convenience. Assign `pknreserve` with
  `node scripts/set-firebase-reserve-role.js --identifier=pknreserve --apply`
  after the dry run resolves exactly one account.
- NFT listing state should be labelled `NFT` in compact listing forms, not
  `NFT claim`.
- Keep old catalog blueprints intact. They are metadata, not mutable inventory.
- The marketplace home/catalog can be capped for performance. Do not assume
  `CardState.cards` contains every card.
- The marketplace home carousel sections must not depend only on the capped
  catalog. Use the `MarketplaceHomeSnapshot.cards` payload to hydrate section
  IDs, then fall back per section if some IDs are unavailable.
- Best sellers and Featured must use Oracle-provided section IDs. Do not
  hardcode Prismatic Evolutions, SAR, or any other single expansion in Flutter.
  If curation needs to change, update `get_marketplace_home_snapshot(...)` or
  the hot blueprint projection, then deploy.
- `GET /api/marketplace-home` has a 30 second function memory cache and sends
  `Cache-Control: public, max-age=10, s-maxage=30, stale-while-revalidate=60`.
  The hourly Featured rotation is visible after those caches expire and after
  the updated API/database function is deployed/applied.
- Full search and "View all versions" style results must call Oracle-backed
  marketplace APIs, not just filter the loaded home catalog.
- Previous/next must stay within the exact same expansion name. Load the whole
  expansion list once and calculate next/previous locally; do not call an
  adjacent-card RPC for every arrow click.
- Direct card URLs should prioritize the card detail payload first. Warm the
  marketplace home/catalog only after the card detail has resolved and rendered,
  so `/marketplace/{lang}/cards/{doubledId}/{humanSlug}` is not blocked by
  broad market preload.
- Marketplace entry warmup must not replace the API-hydrated carousel sections
  with a generic skeleton on normal route mounts or card-detail returns. The
  carousel tiles are Hero destinations for card page back/artwork navigation, so
  their real widgets must be mounted immediately once data is available. Keep
  heavier lower content such as Card spotlight/footer deferred instead. The
  landing page should prewarm marketplace home data after its first paint so the
  marketplace carousel boxes/data can already exist before the user taps
  `Marketplace`. Do not hide the whole marketplace body behind an empty blue
  panel during the route transition.
- Generated card detail human slugs must use the normalized rarity plus readable
  card metadata after the raw numeric blueprint id path segment.
- Share links and newly generated internal links must use root `/:id/:slug`
  card URLs, not `/card/:id`, bare root short links, legacy numeric marketplace
  slugs, or old no-id human-only paths. For Leafeon `316600`, use
  `/316600/rare-leafeon-005-131-prismatic-evolutions`; for Fan Rotom `316698`,
  use `/316698/common-fan-rotom-085-131-prismatic-evolutions`.
- Human-slug resolution must work for search-preview product/deck rows as well
  as singles. Do not force `productType=card` during slug lookup. Since Oracle
  can classify some product-contained cards as `Fixed` while the preview URL may
  use the generic `card` prefix, exact slug matching may ignore only the leading
  classifier/rarity token after the server candidate set has been narrowed.
- Legacy numeric marketplace URLs remain supported for compatibility:
  `/marketplace/en/cards/316600-leafeon-005-131-prismatic-evolutions` and
  `/marketplace/en/cards/316600` should load the card by id and canonicalize to
  the current root `/:id/:slug` URL after resolution.
- Root numeric short links are a narrow compatibility path. Only digit-only root
  paths are intercepted (`/129834` -> direct `CardDetailScreen(cardId: '129834')`);
  root paths containing letters, hyphens, or mixed id/name text such as
  `/wallet`, `/forum`, `/leafeon`, or `/129834-leafeon` must continue through
  normal app routing and must not be treated as card short links.
- Homepage/search/card-detail/cart/versions top bars should stay consistent and
  fixed-height. Use the shared `MarketplaceTopBar` action layout and shared
  `marketplaceTopBarHeight` / `marketplaceTopBarColor` constants; do not put
  wallet/profile/cart controls in `SliverAppBar.actions`, because Hero
  transitions can make the header appear to resize. The shared topbar must not
  clip the trailing action row with a hardcoded width; let language/actions take
  their natural width and make the search field shrink into the remaining space
  so the cart never collapses when debug or wallet controls are visible.
- Seller actions belong in the authenticated user profile/seller area, not the
  global marketplace top bar. Keep desktop and mobile top bars focused on
  search, primary navigation, wallet, cart, and profile/sign-in. Entry points
  such as `Sell`, manage listings, seller inventory, and CardTrader connection
  should live under `/profile`, `/inventory`, or contextual card/seller tools
  rather than as global header actions.
- Marketplace chrome routes must not use the app-wide page slide/fade
  transition. Keep `_appPage` returning the child directly for `/marketplace`,
  every `/marketplace/...` route, legacy `/card/...` detail routes, cart,
  checkout, wallet, orders, auth, buy, admin/debug, inventory, favorites,
  profile, collection, product, and related marketplace pages so pinned top bars
  stay physically fixed while Hero flights animate only the card artwork/content.
  The circular marketplace reveal is only for true website surfaces such as `/`,
  docs, about, contact, privacy, health, and scan/explorer routes. Do not apply
  that website-entry animation to app/account surfaces such as wallet, forum,
  buy, auth, orders, NFT, admin/debug, cart, checkout, inventory, profile,
  collection, favorites, marketplace subroutes, card detail, artist pages,
  versions, or search. Browser-back from `/marketplace` to `/` must use the
  paired dark-backed circular return transition, never the generic app
  transition or a transparent/white substrate.
- Homepage landing top bar should keep a single primary `Marketplace` CTA and
  should not duplicate `Forum`/`Marketplace` in adjacent controls. Website
  surfaces should label marketplace buttons as `Marketplace`, not `Shop`.
- The marketplace autocomplete overlay should be the width of the search field,
  not a full-width page panel. Result rows must be selectable before focus loss
  removes the overlay.
- The autocomplete popup must not render a top/header action row or visible
  `Show all` button. Full search remains available through submit/search
  navigation; do not reintroduce `showAllBuilder`,
  `_SearchPreviewLoadingActionRow`, or section-header `Show all` controls.
- On mobile, focusing an empty search input must not open the empty-focus popup;
  only open previews after the typed threshold is met.
- Homepage carousel rows should stay lazy on both mobile and desktop: use zero
  offscreen cache, avoid automatic keep-alives, and animate each card as it is
  built while horizontally scrolling. Mobile rows should use preview images
  instead of `_homepage.webp`; desktop may keep using `_homepage.webp`, but must
  not eagerly keep all carousel cards alive.
- `Card spotlight` on desktop is lazy: it should start with lightweight anchors,
  render tiles only when the section is near/inside the viewport, animate tiles
  in, fade/derender when scrolled away, and keep `Show next` plus the footer
  behind their own viewport gates. Do not eagerly build 12 full image tiles or
  the footer while offscreen.
- Keep Card spotlight data warmed separately from tile rendering. The homepage
  snapshot should save a compact local spotlight card list, and provider state
  should expose that warmed list before the section enters the viewport. The UI
  may read and rank this lightweight data early, but heavy card widgets/images
  must still stay behind the existing viewport lazy-render gate and live listing
  stock/price should be merged before display.
- Entering `/marketplace` from non-marketplace website routes should use the
  landing prewarm cache when available and mount the real carousel sections
  immediately. Keep Card spotlight/footer lazy, but do not show an empty
  dark-blue takeover panel after `/` has already loaded. The circular
  marketplace reveal should be allowlisted to true website surfaces (`/`, docs,
  about, contact, privacy, health, scan/explorer routes). App/account surfaces
  such as wallet, orders, auth, buy, admin/debug, cart, checkout, inventory,
  collection, favorites, profile, NFT, forum, and marketplace subroutes must use
  normal app navigation and never the reveal/clip transition.
- `Card spotlight` tiles use full-art backgrounds with a translucent shaded
  gradient overlay for text/signals/price. The artwork should nearly fill the
  tile background with only a small inset, while the lower vapor/shadow overlay
  must be strong enough for title, set, signals, and price to stay readable. Do
  not replace the lower text area with a solid opaque block.
- Card detail marketplace external buttons are `CT` (CardTrader), `CM`
  (Cardmarket), and `VT` (Vinted search). Keep all three behind the same Silver
  access gate: Silver users see the buttons on both desktop and mobile, while
  non-Silver users see the existing unlock/sign-in flow. Do not attach hover or
  long-press tooltips such as `Open on CardTrader`, `Open on Cardmarket`, or
  `Search on Vinted` to these external market pills; they should read as compact
  branded actions without suggestion popups.
- `VT` opens a Vinted search, not a direct product page. Build a short query of
  about/max 10 characters: prefer the card name first; if the name reaches the
  limit, stop/truncate at 10; only append expansion/card number when the whole
  token fits in the remaining room without truncating it. Do not append long
  expansion names.

## Debug Artist Curation Checklist

When changing `/marketplace/debug/artists` or
`/api/marketplace-debug-artists`, verify:

- The route stays behind `_DebugGate`, and the API uses
  `authorizeSearchDebugRequest`.
- The displayed artwork uses the full source/CDN image when available and offers
  an open-image action so the illustrator text is readable.
- Artist choices come only from existing normalized
  `marketplace_blueprint_artists` rows for the same conservative
  `canonical_name`; do not offer unknown fallback artists.
- Selecting an artist writes `source = 'manual_debug'` with high confidence to
  `marketplace_blueprint_artists`, then loads the next candidate.
- Classifying a shown item as product writes
  `marketplace_blueprint_classification_overrides` on peer4 and updates the
  current Oracle projections, then loads the next candidate.
- Do not write directly to peer3, peer2, or peer1. Replicas receive peer4
  changes automatically through physical WAL streaming.

## Card Page Checklist

When changing `lib/screens/card_detail_screen.dart`, verify:

- `/card/:id` loads the real card image from Oracle projections/CDN when
  available.
- Previous/next arrows appear when the current expansion has neighboring rows in
  `marketplace_card_versions`.
- Pressing previous/next after the first page load and changing the in-card
  version dropdown should replace the URL with the selected card's canonical
  detail route and keep card detail state synchronized with that route. Use
  `context.replace(safeCardDetailPath(...), extra: heroTag)` only after checking
  the path is non-empty; never clear the route slug or navigate to an empty
  string. Preserve a valid artwork Hero tag so returning to `/marketplace` does
  not land on a blank page.
- The `/versions` page must resolve the current card from both decoded route id
  and canonical slug, reload when route params change, include the current card
  even when the same-name versions query is empty, and ignore stale async
  responses from previous URLs. `/api/marketplace-card-versions` must have both a
  Vercel rewrite and deploy-packaging assertion; missing either can return the
  Flutter shell instead of JSON and look like a white page.
- The `/versions` page current card and similar result tiles should be clickable
  back to card detail and pass a local Hero tag through `extra`; avoid falling
  back to an old homepage/recently-seen Hero source. Build those tags from
  card id plus section and tile index (`versions`/`similar`) so duplicate card
  ids on the same page do not create conflicting Hero sources. The versions
  source should be a palette-colored artwork frame, matching the card detail
  artwork Hero destination shape; a raw image source can make the flight look
  like it is not playing. Card detail and versions routes must keep a
  non-zero route transition duration so Flutter has a Hero handoff window, but
  avoid broad page motion that makes the topbar look unstable.
- Card detail headers should show the linked artist/illustrator attribution in
  the subtitle when present, replacing the generic "Trading card" label. The
  link opens `/marketplace/{lang}/artists/{artistSlug}`. That artist page should
  use the same fixed marketplace topbar and card-grid/Hero behavior as the
  versions page, sourced from `public.marketplace_blueprint_artists`.
- Artist profile pages should render `profile.imageUrl` from
  `marketplace_artist_profiles` when present, prefer cached CDN/R2 URLs over
  source URLs, display PocketMonsters and Bulbapedia reference links, and show
  Bulbapedia CC BY-NC-SA attribution beside any Bulbapedia-derived summary.
  Missing profiles should keep the initials placeholder and curation-pending
  copy rather than blocking the card gallery.
- Profile collection should expose artist collections separately from expansion
  collections. `/collection/artists/{artistSlug}` should use the same collection
  card states as expansion collections: owned cards render normally, missing
  cards remain dimmed and grayscale. Collection owned counts must use the
  `UserCardCollectionItem` ownership index, matching by card id and by normalized
  `(cardName, setName, collectorNumber)` signature, so artist/expansion summaries
  stay correct when visible rows come from different marketplace projections.
- The `/versions` page topbar search must not rebuild or refresh the versions
  grid while typing. Keep search preview watches isolated to the topbar/search
  widget, and do not call page-level `setState()` for each search keystroke.
- Search preview rows use their artwork as a Hero source. When selecting a
  search preview, keep the overlay/search results alive for the Hero handoff
  window before clearing the search state; removing the overlay immediately can
  make the card detail destination open without a source Hero. The card detail
  destination Hero should wrap only the artwork image/frame, not the whole
  artwork panel, so popup, grid, carousel, and versions sources all animate
  image-to-image. Keep the search popup attached to the route subtree with
  `OverlayPortal`, not a detached `OverlayEntry`; otherwise Flutter's route Hero
  scan can miss the source even when the popup is visually still on screen. If
  card detail receives a Hero tag via route `extra`, preserve
  it during the initial detail render; do not replace it during the forward
  route flight, because that detaches the destination while the source Hero is
  trying to attach. After the forward flight window, retarget the detail artwork
  Hero to the current card's `Recently seen` index 0 tag, because every return
  animation should land on the last product the user saw. Seed the selected card
  into the marketplace card cache and recent-view state as soon as the detail
  view records; persistence can continue in the background, but the destination
  carousel tile must be mounted for the Hero scan. Artwork taps, browser back,
  and any later Hero return should therefore land on the latest recently-seen
  tile instead of a transient search/grid source or a black/blank page.
- Search preview rows should use a clearly visible card palette/accent gradient
  in the row background and divider while keeping text readable. Do not regress
  them to flat identical dark rows or make the tint so faint that the card
  identity is not visible.
- Marketplace card titles and version tiles should show collector/expansion
  numbers next to the card name without a `#` prefix, for example
  `Mew ex 232/091`. Oracle projection refreshes should normalize stored
  collector/expansion numbers with `marketplace_clean_collector_number(...)` so
  database rows do not reintroduce `#`.
- Marketplace card taps should go through a guarded detail-navigation helper
  (`safeCardDetailPath` or `safeCardDetailPathFromParts`) rather than calling
  `context.go(marketplaceCardDetailPath(card))` inline. This applies to home,
  search previews, versions, artist pages, cart, favorites, collection, NFT,
  product landing, and inventory links. If a warmed or cached row has an
  unexpected id/slug shape, do not navigate. Invalid rows should no-op and log
  debug context, not fall back to `/card/:id`, `/marketplace`, or `/`.
- API fallback queries that hydrate marketplace home rows should clean collector
  numbers in application code too. Do not make the live homepage depend on a
  newly introduced Oracle helper function being applied before deploy.
- The graph panel does not show `CT Min Price` or `CT Market Price`.
- The seller table uses `CardListing`, not a local `_Listing` mock.
- The broad marketplace home/catalog preload starts after the resolved card has
  painted, not before the direct card payload.
- The no-listing state works for cards with zero Firestore listings.
- The sell dialog can create a listing for the current user.
- Listing option chips should stay compact on one line where possible:
  `1st Ed.`, `Sealed`, `Graded`, `Signed`, then shipping/reserve/NFT options.
  Admin/debug Reserve toggles should mutate `reserveAvailable`, not
  `shippingAvailable`.
- Cart, NFT, reserve, and shipping actions/tags stay aligned in the action
  column.
- Desktop and mobile Silver users both see `CT`, `CM`, and `VT`; non-Silver
  users still get the current Silver unlock or sign-in prompt instead.
- Canonical URL checks:
  - A generated card share/detail link for Leafeon 005/131 Rare in Prismatic
    Evolutions is `/316600/rare-leafeon-005-131-prismatic-evolutions`.
  - A generated card share/detail link for Fan Rotom 085/131 Common in Prismatic
    Evolutions is `/316698/common-fan-rotom-085-131-prismatic-evolutions`.
  - `/marketplace/en/cards/316600-leafeon-005-131-prismatic-evolutions` and
    `/marketplace/en/cards/316600` still resolve by numeric id, then replace the
    browser URL with the canonical root `/:id/:slug` path after the card loads.
  - `/129834` renders the card detail route directly, then resolves and
    canonicalizes to that card's root `/:id/:slug` URL.
  - Non-numeric root paths such as `/wallet`, `/forum`, `/leafeon`, and
    `/129834-leafeon` are not short-link redirects.

## Cart And Checkout Checklist

When changing cart or checkout, verify:

- Cart rows display seller, condition, language, reverse, graded, reserve, NFT,
  and shipping metadata when available.
- Quantity clamps to the listing's `quantityAvailable`.
- Checkout calls `/api/marketplace-orders`, which pays from the buyer's PKN
  balance, decrements Oracle listings, and creates a paid `orders` document with
  listing snapshots.
- Paid marketplace orders send one `market@pokoin.com` sale notification per
  seller per order, deduped by `order_seller_sale_notifications`.
- Anonymous users can still use local cart fallback where supported.
- Refreshing while signed in should show the locally cached cart count
  immediately, then keep the same or merged count after Firestore reconciliation.
  It should not permanently show `0` unless both the user-scoped local cart and
  remote `user_carts/{uid}` document are empty.
- Switching accounts or logging out must not leak one user's cart into another
  user's scoped cart cache.
- The `/cart` empty and populated states should remain professional Pokoin UI:
  dark shell, gold primary CTAs, listing metadata, quantity controls, and a
  clear checkout summary. Do not regress to a white/simple template.
- The `/checkout` page should remain a step-based Pokoin flow with:
  account status, order progress/status, item snapshot chips, optional
  fulfillment notes, wallet context, and final review/confirmation.
- Checkout confirmation should make clear that order snapshots preserve exact
  seller/listing metadata before creating the paid order.

## Marketplace Signal Checklist

When changing `lib/screens/marketplace_signal_screen.dart`, verify:

- Catalog metrics are computed from loaded marketplace rows, not hardcoded
  placeholder copy.
- Listing metrics are computed from active Firestore `card_listings`, using only
  `status == active`, `quantityAvailable > 0`, and positive `pricePkn`.
- Floor/median/total ask are clearly active listing asks, not completed sales.
- 24h volume, completed sale count, and historical charts stay hidden until
  settled order events are aggregated.
- Empty listing state still renders honestly with `—` instead of fake liquidity.

## Verification Commands

Run from `pokemon_card_vault`:

```bash
dart format lib/screens/card_detail_screen.dart lib/screens/cart_screen.dart lib/screens/checkout_screen.dart lib/screens/marketplace_signal_screen.dart lib/providers/card_listing_provider.dart lib/services/card_listing_service.dart
flutter analyze
flutter test
flutter build web --release --pwa-strategy=none
```

Passing local checks is not the same as updating production. If the user expects
the change on `pokoin.com`, deploy after the checks:

```bash
./deploy-pokoin-web.sh
```

Before trusting a deployment, make sure `vercel.json` API rewrites and
`deploy-pokoin-web.sh` packaging stay in sync. Routed APIs such as
`marketplace-home`, `marketplace-card-seo`, `marketplace-orders`,
`marketplace-blueprint-price`, `crypto-pkn-purchase`, and `crypto-pkn-sale` must
be copied into `build/web/api`, and helper modules such as `_marketplace_db`,
`_firebase`, `_crypto_pkn_purchase`, `_bitcoin_payout`, and
`_marketplace_sale_notifications` must be copied into `build/web/server` with
relative imports rewritten. Missing packaging can look like a white page, 405,
HTML response, or empty server response in Flutter.

For version/navigation changes, also verify Oracle projection data:

```bash
node scripts/oracle-marketplace-migrate.js refresh
node scripts/oracle-marketplace-migrate.js verify
```

For card URL/routing changes, also run the focused URL tests:

```bash
flutter test test/card_url_test.dart
node scripts/verify-marketplace-card-urls.js --chunk-size=100 --chunks=all --concurrency=32 --pool-max=16
```

If Firestore rules changed:

```bash
firebase deploy --only firestore:rules --project "$FIREBASE_CLI_PROJECT_ID"
```

For production deployment, use:

```bash
./deploy-pokoin-web.sh
```

`./deploy-pokoin-web.sh` creates a new Vercel production deployment and updates
the default project alias, but custom domains can stay pinned to an older
deployment. After deploy, inspect the returned deployment URL and promote the
custom Pokoin aliases when the user expects production traffic to move:

```bash
for domain in pokoin.com www.pokoin.com wallet.pokoin.com forum.pokoin.com cards.pokoin.com cardcaveau.pokoin.com cardvault.pokoin.com explorer.pokoin.com; do
  vercel alias set <new-web-deployment>.vercel.app "$domain"
done
```

Then verify `https://pokoin.com` rather than assuming a pushed commit, local
build, or default Vercel alias is live:

```bash
python3 - <<'PY'
import urllib.request
for url in ['https://pokoin.com/checkout', 'https://www.pokoin.com/checkout', 'https://cards.pokoin.com']:
    req = urllib.request.Request(url, headers={'User-Agent': 'PokoinDeployCheck/1.0'})
    with urllib.request.urlopen(req, timeout=30) as res:
        print(url, res.status, res.geturl(), res.headers.get('x-vercel-id'))
PY
```

For homepage/carousel changes, also inspect the production home API:

```bash
python3 - <<'PY'
import json, urllib.request
with urllib.request.urlopen('https://pokoin.com/api/marketplace-home', timeout=20) as res:
    data = json.loads(res.read().decode())
print('cards', len(data.get('cards') or []))
for key, value in (data.get('sections') or {}).items():
    print(key, len(value or []), (value or [])[:10])
PY
```

Expected: non-zero `cards`, `bestSellerIds`, and `featuredIds`. If the API is
healthy but Flutter carousels are empty, check the provider merge path before
changing Oracle data.

For refresh/cart regressions, verify from a signed-in browser session:

```text
1. Add one listed card to cart.
2. Hard-refresh `/marketplace` or a card detail page.
3. Confirm the top-bar badge shows the cached item count during startup.
4. Confirm the count remains correct after Firestore reconciliation completes.
5. Log out or switch Firebase account and confirm the prior user's cart does not
   appear for the next account.
```

Featured-specific checks:

```bash
python3 - <<'PY'
import json, time, urllib.request
for i in range(2):
    url = f'https://pokoin.com/api/marketplace-home?_debug={int(time.time()*1000)}_{i}'
    with urllib.request.urlopen(url, timeout=20) as res:
        data = json.loads(res.read().decode())
    print(data.get('generatedAt'), (data.get('sections') or {}).get('featuredIds', [])[:12])
    time.sleep(2)
PY
```

Within one cache window the IDs can be identical. Across the next hour boundary,
after CDN/function cache expiry, the first 12 Featured IDs should rotate within
the scored Featured pool. If they do not, inspect `marketplace_home` SQL in
Oracle and the hot-rollup freshness query before changing Flutter.
