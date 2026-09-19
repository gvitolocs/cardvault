const routeDefinitions = [
  {
    path: '/api/auth-login',
    file: 'auth-login.js',
    methods: ['POST', 'OPTIONS'],
    purpose: 'Validate the current Firebase bearer token and return safe auth metadata.',
    auth: 'Required Firebase bearer token.',
    params: {
      body: 'No required JSON body fields.',
    },
    dependencies: {
      env: ['FIREBASE_PROJECT_ID', 'FIREBASE_CLIENT_EMAIL', 'FIREBASE_PRIVATE_KEY'],
      services: ['Firebase Admin'],
    },
  },
  {
    path: '/api/cache-google-profile-picture',
    file: 'cache-google-profile-picture.js',
    methods: ['POST'],
    purpose: 'Download the authenticated user Google avatar, optimize it, and store it in R2.',
    auth: 'Required Firebase bearer token.',
    params: {
      body: 'No required fields; uses the authenticated Firebase profile picture URL.',
    },
    dependencies: {
      env: ['FIREBASE_*', 'R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY', 'R2_PROFILE_PICTURES_BUCKET', 'R2_PROFILE_PICTURES_PUBLIC_URL'],
      services: ['Firebase Admin', 'Cloudflare R2', 'sharp'],
    },
  },
  {
    path: '/api/cardmarket-redirect',
    file: 'cardmarket-redirect.js',
    methods: ['GET'],
    purpose: 'Resolve a marketplace blueprint to a Cardmarket product/search URL and redirect, or return JSON when requested.',
    auth: 'Public.',
    params: {
      query: '`id` public card_id or leftover ct_id, optional `blueprintId` leftover, `locale` optional two-letter locale, `format=json` optional, `game` for One Piece / Riftbound.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/cardmarket-scrape-observation',
    file: 'cardmarket-scrape-observation.js',
    methods: ['POST', 'OPTIONS'],
    purpose: 'Record Cardmarket scrape/association observations used by marketplace import review tooling.',
    auth: 'Required Firebase bearer token.',
    params: {
      body: 'Cardmarket observation payload including blueprint/product identifiers and scrape metadata.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'FIREBASE_*'],
      services: ['Oracle/Postgres marketplace DB', 'Firebase Admin'],
    },
  },
  {
    path: '/api/cardtrader-blueprint-listings',
    file: 'cardtrader-blueprint-listings.js',
    methods: ['GET', 'OPTIONS'],
    purpose: 'Return historical/daily CardTrader marketplace listing snapshots for one blueprint/card ID from Oracle.',
    auth: 'Public.',
    params: {
      query: '`blueprintId` required for CardTrader blueprint IDs; `cardId` accepted for mapped Pokoin card IDs; `limit`, `page`, and `cursor` optional.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/cardtrader-live-listings',
    file: 'cardtrader-live-listings.js',
    methods: ['GET', 'OPTIONS'],
    purpose: 'Return live on-demand CardTrader marketplace listings for one blueprint/card ID without persisting results.',
    auth: 'Public.',
    params: {
      query: '`blueprintId` for a CardTrader blueprint ID or `cardId` for a Pokoin card ID such as `248856`; `language`/`lang` and `limit` optional. Without `limit`, returns all rows from CardTrader for the blueprint; explicit limits cap the client response only.',
    },
    dependencies: {
      env: ['CARDTRADER_AUTH_TOKEN', 'CARDTRADER_API_TOKEN', 'MARKETPLACE_DATABASE_URL'],
      services: ['CardTrader API', 'Oracle/Postgres marketplace DB for optional cardId mapping'],
    },
  },
  {
    path: '/api/cardtrader-clean-listings',
    file: 'cardtrader-clean-listings.js',
    methods: ['POST'],
    purpose: 'Deactivate CardTrader-linked listings owned by the authenticated seller.',
    auth: 'Required Firebase bearer token for the seller.',
    params: {
      body: 'No required fields.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'FIREBASE_*'],
      services: ['Oracle/Postgres marketplace DB', 'Firebase Admin'],
    },
  },
  {
    path: '/api/cardtrader-connect',
    file: 'cardtrader-connect.js',
    methods: ['POST', 'DELETE'],
    purpose: 'Connect, replace, or disconnect an authenticated seller CardTrader token.',
    auth: 'Required Firebase bearer token.',
    params: {
      body: '`token` required for POST. DELETE has no body.',
    },
    dependencies: {
      env: ['CARDTRADER_TOKEN_ENCRYPTION_KEY', 'FIREBASE_*'],
      services: ['Firebase Admin', 'CardTrader API'],
    },
  },
  {
    path: '/api/cardtrader-daily-listings-refresh',
    file: 'cardtrader-daily-listings-refresh.js',
    methods: ['GET', 'POST'],
    purpose: 'Manual/admin diagnostic trigger for global CardTrader marketplace listing snapshots; scheduled ingestion is owned by the Oracle/peer4 host script.',
    auth: 'Required CARDTRADER_DAILY_LISTINGS_SECRET, CARDTRADER_DAILY_REFRESH_SECRET, or CRON_SECRET bearer/header secret.',
    params: {
      query: '`dryRun`, `maxBlueprints`, `maxProducts`, `archiveMissing`, `removedDay`, `blueprintId`, `blueprintIds`, `expansionId`, and `language` are optional bounded controls.',
      body: 'Same controls as query parameters for POST.',
    },
    dependencies: {
      env: ['CARDTRADER_AUTH_TOKEN', 'CARDTRADER_API_TOKEN', 'CARDTRADER_DAILY_LISTINGS_SECRET', 'CRON_SECRET', 'MARKETPLACE_DATABASE_URL', 'PKN_CHECKOUT_USDT_PRICE'],
      services: ['CardTrader API', 'Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/cardtrader-disconnect',
    file: 'cardtrader-disconnect.js',
    methods: ['POST'],
    purpose: 'Disconnect the authenticated seller CardTrader integration.',
    auth: 'Required Firebase bearer token.',
    params: {
      body: 'No required fields.',
    },
    dependencies: {
      env: ['FIREBASE_*'],
      services: ['Firebase Admin'],
    },
  },
  {
    path: '/api/cardtrader-webhook/:uid',
    file: 'cardtrader-webhook.js',
    methods: ['POST'],
    purpose: 'Receive CardTrader order webhooks for a connected seller and decrement linked Pokoin inventory.',
    auth: 'CardTrader Signature HMAC using the seller shared_secret.',
    params: {
      path: '`uid` Firebase seller uid registered as the webhook URL suffix.',
      body: 'Raw CardTrader webhook JSON (order.create / order.update / order.destroy).',
    },
    dependencies: {
      env: ['CARDTRADER_TOKEN_ENCRYPTION_KEY', 'FIREBASE_*', 'MARKETPLACE_DATABASE_URL', 'MARKETPLACE_WRITER_DATABASE_URL'],
      services: ['Firebase Admin', 'Oracle/Postgres marketplace writer', 'CardTrader webhooks'],
    },
    rawBody: true,
  },
  {
    path: '/api/cardtrader-import-dry-run',
    file: 'cardtrader-import-dry-run.js',
    methods: ['POST'],
    purpose: 'Read the authenticated seller CardTrader export and return a redacted import summary without writing inventory.',
    auth: 'Required Firebase bearer token.',
    params: {
      body: 'Optional dry-run controls; no writes are performed.',
    },
    dependencies: {
      env: ['CARDTRADER_TOKEN_ENCRYPTION_KEY', 'FIREBASE_*'],
      services: ['Firebase Admin', 'CardTrader API'],
    },
  },
  {
    path: '/api/cardtrader-redirect',
    file: 'cardtrader-redirect.js',
    methods: ['GET'],
    purpose: 'Redirect a public card id or leftover ct_id to the CardTrader leftover blueprint page.',
    auth: 'Public.',
    params: {
      query: '`id` public card_id (ct_id × 2) or leftover ct_id. Optional `blueprintId` leftover. `game` for One Piece / Riftbound. `format=json` returns `{ url, ct_id }`.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'ONE_PIECE_MARKETPLACE_DATABASE_URL', 'RIFTBOUND_MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB', 'CardTrader website'],
    },
  },
  {
    path: '/api/cardtrader-status',
    file: 'cardtrader-status.js',
    methods: ['GET'],
    purpose: 'Return safe CardTrader integration status for the authenticated seller.',
    auth: 'Required Firebase bearer token.',
    params: {
      query: 'No required query parameters.',
    },
    dependencies: {
      env: ['FIREBASE_*'],
      services: ['Firebase Admin'],
    },
  },
  {
    path: '/api/create-pkn-checkout-session',
    file: 'create-pkn-checkout-session.js',
    methods: ['POST'],
    purpose: 'Create or reconcile a Stripe Checkout session for buying PKN account balance.',
    auth: 'Required Firebase bearer token.',
    params: {
      body: '`pknAmount`, `fiatCents`, and `lookupKey` for new checkout; `checkoutSessionId` for reconciliation.',
    },
    dependencies: {
      env: ['STRIPE_SECRET_KEY', 'STRIPE_API_VERSION', 'PUBLIC_SITE_URL', 'PKN_CHECKOUT_CURRENCY', 'PKN_CHECKOUT_USDT_PRICE', 'FIREBASE_*'],
      services: ['Stripe', 'Firebase Admin'],
    },
  },
  {
    path: '/api/crypto-pkn-purchase/:action',
    file: 'crypto-pkn-purchase.js',
    methods: ['GET', 'POST'],
    purpose: 'Quote, request, and check crypto-to-PKN purchase flows.',
    auth: 'Required Firebase bearer token.',
    params: {
      path: '`action` is `quote`, `request`, or `status`.',
      body: '`asset` and `amountIn` for quote; `quoteId` and `depositTxHash` for request.',
      query: '`requestId` optional for status.',
    },
    dependencies: {
      env: ['FIREBASE_*', 'POKOIN_RPC_URL', 'POKOIN_BANK_ADDRESS', 'POKOIN_BANK_PRIVATE_KEY'],
      services: ['Firebase Admin', 'Pokoin RPC', 'configured crypto RPCs'],
    },
  },
  {
    path: '/api/crypto-pkn-sale/:action',
    file: 'crypto-pkn-sale.js',
    methods: ['GET', 'POST'],
    purpose: 'Quote, request, and check PKN-to-crypto sale flows.',
    auth: 'Required Firebase bearer token.',
    params: {
      path: '`action` is `quote`, `request`, or `status`.',
      body: '`asset` and `amountIn` for quote; `quoteId`, `depositTxHash`, and `payoutAddress` for request.',
      query: '`requestId` optional for status.',
    },
    dependencies: {
      env: ['CRYPTO_PKN_SELL_ENABLED', 'CRYPTO_PKN_AUTO_PAYOUT_ENABLED', 'FIREBASE_*', 'POKOIN_RPC_URL', 'POKOIN_BANK_ADDRESS', 'POKOIN_BANK_PRIVATE_KEY'],
      services: ['Firebase Admin', 'Pokoin RPC', 'configured crypto payout services'],
    },
  },
  {
    path: '/api/deck-card-version-lookup',
    file: 'deck-card-version-lookup.js',
    methods: ['GET', 'POST', 'OPTIONS'],
    purpose: 'Return ranked marketplace card versions for structured decklist card fields.',
    auth: 'Public.',
    params: {
      query: '`name`, `setCode`, `collectorNumber`, optional Limitless expansion fields, `language`, and `limit` are supported.',
      body: 'Same fields as query parameters for POST.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/extension-card-search',
    file: 'extension-card-search.js',
    methods: ['POST', 'OPTIONS'],
    purpose: 'Search marketplace cards from browser-extension scraped card fields.',
    auth: 'Public.',
    params: {
      body: '`query` or structured fields such as `name`, `collectorNumber`, `expansion`, `rarity`, `variation`, `language`, and `limit`.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'MARKETPLACE_*_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/earn-pkn',
    file: 'earn-pkn.js',
    methods: ['POST', 'OPTIONS'],
    purpose: 'Receive Earn PKN sharding inquiries and email the completed form to Pokoin contact.',
    auth: 'Public.',
    params: {
      body: '`email`, `numberOfCards`, and `valueOfCards` required; optional `cardList`, `language`, and `conditions`.',
    },
    dependencies: {
      env: ['RESEND_API_KEY', 'EARN_PKN_EMAIL_TO', 'EARN_PKN_EMAIL_FROM'],
      services: ['email provider'],
    },
  },
  {
    path: '/api/flutter-debug-logs',
    file: 'flutter-debug-logs.js',
    methods: ['GET', 'POST'],
    purpose: 'Record and read protected Flutter client debug logs.',
    auth: 'Required debug token or authorized debug/admin Firebase bearer token.',
    params: {
      query: 'GET filters include `limit`, `sessionId`, `userId`, `path`, `category`, and `eventName`.',
      body: 'POST requires `sessionId` and `eventName`, with optional route/url/user/payload fields.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'FLUTTER_DEBUG_LOG_TOKEN', 'FIREBASE_*'],
      services: ['Oracle/Postgres marketplace DB', 'Firebase Admin for debug auth'],
    },
  },
  {
    path: '/api/forum',
    file: 'forum.js',
    methods: ['GET'],
    purpose: 'Read forum categories, topic lists, or a single topic with posts.',
    auth: 'Public.',
    params: {
      query: '`categoryId` optional for topic lists, `topicId` optional for a single topic.',
    },
    dependencies: {
      env: ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY'],
      services: ['Supabase REST'],
    },
  },
  {
    path: '/api/forum-create-post',
    file: 'forum-create-post.js',
    methods: ['POST'],
    purpose: 'Create an authenticated forum reply.',
    auth: 'Required Firebase bearer token.',
    params: {
      body: '`topicId` and post content fields.',
    },
    dependencies: {
      env: ['FIREBASE_*', 'SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY'],
      services: ['Firebase Admin', 'Supabase REST'],
    },
  },
  {
    path: '/api/forum-create-topic',
    file: 'forum-create-topic.js',
    methods: ['POST'],
    purpose: 'Create an authenticated forum topic.',
    auth: 'Required Firebase bearer token.',
    params: {
      body: 'Topic title/content/category fields.',
    },
    dependencies: {
      env: ['FIREBASE_*', 'SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY'],
      services: ['Firebase Admin', 'Supabase REST'],
    },
  },
  {
    path: '/api/forum-upload-media',
    file: 'forum-upload-media.js',
    methods: ['POST'],
    purpose: 'Optimize forum image media and store it in R2.',
    auth: 'Required Firebase bearer token.',
    params: {
      body: '`imageBase64` and either `topicId` or `postId`.',
    },
    dependencies: {
      env: ['FIREBASE_*', 'SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY', 'R2_FORUM_MEDIA_BUCKET', 'R2_FORUM_MEDIA_PUBLIC_URL'],
      services: ['Firebase Admin', 'Supabase REST', 'Cloudflare R2', 'sharp'],
    },
  },
  {
    path: '/api/limitless-expansion-blueprints',
    file: 'limitless-expansion-blueprints.js',
    methods: ['GET'],
    purpose: 'Return Limitless expansion-to-Pokoin blueprint mapping rows.',
    auth: 'Public.',
    params: {
      query: '`expansionKey`, `setCode`, `name`, `includeBlueprints=1`, and `limit` are supported.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/marketplace-artist-cards',
    file: 'marketplace-artist-cards.js',
    methods: ['GET'],
    purpose: 'Return artist profile data and marketplace cards grouped by illustrator/artist attribution.',
    auth: 'Public.',
    params: {
      query: '`artistSlug` or `artist`; `limit` optional.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/marketplace-artist-suggestions',
    file: 'marketplace-artist-suggestions.js',
    methods: ['GET'],
    purpose: 'Return marketplace artist suggestion rows for artist pages and admin review.',
    auth: 'Public.',
    params: {
      query: 'Search/filter query parameters including artist text and limit.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/marketplace-suggest',
    file: 'marketplace-suggest.js',
    methods: ['GET', 'OPTIONS'],
    purpose: 'Meili-only typeahead for pokoin-web: grouped printings, no SQL listing hydrate.',
    auth: 'Public.',
    params: {
      query: '`q` or `query`; `limit` max groups (default 12, max 24); `lang` / `search_language` (EN Meili only).',
    },
    dependencies: {
      env: ['MEILI_HOST', 'MEILI_API_KEY', 'MEILI_MARKETPLACE_INDEX', 'MARKETPLACE_SEARCH_ENGINE'],
      services: ['Meilisearch on pokoin-marketplace localhost :7700'],
    },
  },
  {
    path: '/api/marketplace-autocomplete',
    file: 'marketplace-autocomplete.js',
    methods: ['POST', 'OPTIONS'],
    purpose: 'Return ranked marketplace autocomplete/search suggestions with optional debug metadata.',
    auth: 'Public for normal search; debug and personalization use optional Firebase bearer token.',
    params: {
      body: '`search_term`/`query`, `result_limit`, `pool_limit`, `search_language`, optional previous context and debug fields.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'MARKETPLACE_NAME_SEARCH_DATABASE_URL', 'MARKETPLACE_PEER1_DATABASE_URL', 'MARKETPLACE_PEER2_DATABASE_URL', 'MARKETPLACE_PEER3_DATABASE_URL', 'SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_NAME_INDEX_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB', 'optional Supabase name index', 'Firebase Admin for optional auth'],
    },
  },
  {
    path: '/api/marketplace-blueprint-price',
    file: 'marketplace-blueprint-price.js',
    methods: ['GET', 'OPTIONS'],
    purpose: 'Return the public PKN floor price for a marketplace blueprint/card ID.',
    auth: 'Public.',
    params: {
      query: '`blueprintId` required; `cardId` accepted as an alias.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'PKN_CHECKOUT_USDT_PRICE'],
      services: ['Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/marketplace-card-cheapest-price',
    file: 'marketplace-card-cheapest-price.js',
    methods: ['GET', 'OPTIONS'],
    purpose: 'Return the homepage-backed cheapest marketplace price for a card, including CardTrader cache availability.',
    auth: 'Public.',
    params: {
      query: '`cardId`, `cardIds`, `canonicalPath`, or structured `name`/`setName`/`collectorNumber`; `language` and bounded `limit` optional.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'PKN_CHECKOUT_USDT_PRICE'],
      services: ['Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/marketplace-card-page',
    file: 'marketplace-card-page.js',
    methods: ['GET', 'OPTIONS'],
    purpose: 'React BFF: one card-detail payload (card, versions, versionCount, offers, cheapest, artist, canonicalPath).',
    auth: 'Public.',
    params: {
      query: '`cardId` required (public id). `lang`, `slug`, `includeSales`, `includeOffers`, `includeSameAs` (off by default), `liveOffers` optional.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB', 'optional Firebase for sales'],
    },
  },
  {
    path: '/api/marketplace-card-seo',
    file: 'marketplace-card-seo.js',
    methods: ['GET'],
    purpose: 'Return server-rendered HTML metadata for marketplace card social previews.',
    auth: 'Public.',
    params: {
      query: '`cardId`, `cardSlug`, `language`, or `cardPath` depending on the rewrite source.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/marketplace-card-sales',
    file: 'marketplace-card-sales.js',
    methods: ['GET'],
    purpose: 'Daily sold-median series from CardTrader inferred comps. Pi aggregates the requested language/condition slice; default payload is series + available filter keys, not observation rows.',
    auth: 'Public.',
    params: {
      query: '`cardId` required. Optional `condition` / `cond` (NM, SP, MP, PL, Poor) and `language` / `lang` (EN, IT, JP, …). Series includes `sampleCount` (observations in the current slice) and per-day `sampleCount`. `includeRows=1` returns a capped observation sample; omit it for series-only. `limit` only applies with includeRows.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/marketplace-sales-pulse',
    file: 'marketplace-sales-pulse.js',
    methods: ['GET', 'OPTIONS'],
    purpose: 'Return the latest completed daily marketplace sales leaders plus a bounded activity trend.',
    auth: 'Public.',
    params: {
      query: '`metric=sales` (default, observed samples) or diagnostic `metric=quantity`; `limit` (max 24) and `days` (max 30) are optional.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL'],
      services: ['Pi/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/marketplace-card-last-median',
    file: 'marketplace-card-last-median.js',
    methods: ['GET'],
    purpose: 'Return the latest UTC-day median inferred sold PKN for one or more marketplace cards from CardTrader removed-sale comps.',
    auth: 'Public.',
    params: {
      query: '`cardId` or comma-separated `cardIds` (max 40). `blueprintId` is accepted as an alias of `cardId`. Optional `condition` / `cond` and `language` / `lang` slice the last-day median the same way as marketplace-card-sales.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/marketplace-card-shortlink',
    file: 'marketplace-card-shortlink.js',
    methods: ['GET', 'HEAD'],
    purpose: 'Redirect our-id short links to canonical marketplace card URLs (our id = CardTrader ct_id * 2).',
    auth: 'Public.',
    params: {
      query: '`cardId` is our marketplace id (ct_id * 2) or leftover ct_id; `path` is `/marketplace/220962` or `/220962/slug`. See docs/marketplace-public-ids.md.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/marketplace-card-url',
    file: 'marketplace-card-url.js',
    methods: ['GET', 'HEAD'],
    purpose: 'Return stored canonical_path. cardId is our marketplace id (ct_id * 2); path numbers are the same our-id.',
    auth: 'Public.',
    params: {
      query: '`cardId` (our id, or leftover ct_id) or `path` (our-id URL); `language` optional. See docs/marketplace-public-ids.md.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/marketplace-card-versions',
    file: 'marketplace-card-versions.js',
    methods: ['GET'],
    purpose: 'Return card detail/version rows for marketplace card pages.',
    auth: 'Public.',
    params: {
      query: '`cardId`, `sameAsCardId`, `cardSlug`, `expansionName`, `query`, `limit`, `productType`, and `language` are supported.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/marketplace-version-set',
    file: 'marketplace-version-set.js',
    methods: ['GET', 'OPTIONS'],
    purpose: 'Return the pokoin_version_sets key, member_count, and printings for one public card id.',
    auth: 'Public.',
    params: {
      query: '`cardId` (public marketplace id).',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/marketplace-cardmarket-guess-review',
    file: 'marketplace-cardmarket-guess-review.js',
    methods: ['GET'],
    purpose: 'Return protected Cardmarket guess review data for search/debug operators.',
    auth: 'Required authorized debug/admin Firebase bearer token.',
    params: {
      query: 'Review filters and pagination query parameters.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'MARKETPLACE_ADMIN_EMAILS', 'MARKETPLACE_DEBUG_EMAILS', 'FIREBASE_*'],
      services: ['Oracle/Postgres marketplace DB', 'Firebase Admin'],
    },
  },
  {
    path: '/api/marketplace-cart',
    file: 'marketplace-cart.js',
    methods: ['POST'],
    purpose: 'Record marketplace cart add/remove analytics with optional verified user context.',
    auth: 'Public; optional Firebase bearer token attaches user UID when valid.',
    params: {
      body: '`cardId` or `blueprintId`, `action`, and optional anonymous/session ID.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'FIREBASE_*'],
      services: ['Oracle/Postgres marketplace DB', 'optional Firebase Admin'],
    },
  },
  {
    path: '/api/marketplace-cards',
    file: 'marketplace-cards.js',
    methods: ['GET'],
    purpose: 'Return searchable marketplace card and product rows.',
    auth: 'Public.',
    params: {
      query: '`query`, `limit`, `language`, `productType`, and `productSearchOnly` are supported.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/marketplace-debug-artists',
    file: 'marketplace-debug-artists.js',
    methods: ['GET', 'POST'],
    purpose: 'Inspect and update marketplace artist enrichment/debug classification data.',
    auth: 'Required authorized debug/admin Firebase bearer token.',
    params: {
      query: 'GET filters for artist debug views.',
      body: '`action` plus action-specific artist/classification payload for POST.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'MARKETPLACE_ADMIN_EMAILS', 'MARKETPLACE_DEBUG_EMAILS', 'FIREBASE_*'],
      services: ['Oracle/Postgres marketplace DB', 'Firebase Admin'],
    },
  },
  {
    path: '/api/marketplace-debug-cardtrader-blueprints',
    file: 'marketplace-debug-cardtrader-blueprints.js',
    methods: ['GET', 'POST'],
    purpose: 'Inspect and enqueue protected CardTrader blueprint debug/import work.',
    auth: 'Required authorized debug/admin Firebase bearer token.',
    params: {
      query: 'GET filters/status fields.',
      body: 'POST queue/review payload fields.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'MARKETPLACE_ADMIN_EMAILS', 'MARKETPLACE_DEBUG_EMAILS', 'FIREBASE_*'],
      services: ['Oracle/Postgres marketplace DB', 'Firebase Admin'],
    },
  },
  {
    path: '/api/marketplace-debug-events',
    file: 'marketplace-debug-events.js',
    methods: ['GET'],
    purpose: 'Return marketplace event analytics debug data.',
    auth: 'Required authorized debug/admin Firebase bearer token.',
    params: {
      query: 'Event/card/search filters and limits.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'MARKETPLACE_ADMIN_EMAILS', 'MARKETPLACE_DEBUG_EMAILS', 'FIREBASE_*'],
      services: ['Oracle/Postgres marketplace DB', 'Firebase Admin'],
    },
  },
  {
    path: '/api/marketplace-debug-refinement',
    file: 'marketplace-debug-refinement.js',
    methods: ['GET', 'POST'],
    purpose: 'Inspect and update marketplace search refinement/debug data.',
    auth: 'Required authorized debug/admin Firebase bearer token.',
    params: {
      query: 'GET refinement filters.',
      body: 'POST action-specific refinement payload.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'MARKETPLACE_ADMIN_EMAILS', 'MARKETPLACE_DEBUG_EMAILS', 'FIREBASE_*'],
      services: ['Oracle/Postgres marketplace DB', 'Firebase Admin'],
    },
  },
  {
    path: '/api/marketplace-image-log',
    file: 'marketplace-image-log.js',
    methods: ['GET', 'POST', 'OPTIONS'],
    purpose: 'Ring-buffer exact marketplace image URLs served or failed during navigation.',
    auth: 'Public; POST is IP rate-limited. GET returns the in-memory buffer.',
    params: {
      query: 'GET `limit` (max 250).',
      body: 'POST `url` required-ish; optional `cardId`, `ctId`, `source`, `status`, `error`, `route`.',
    },
    dependencies: {
      env: [],
      services: ['in-memory ring on pokoin-oracle-api'],
    },
  },
  {
    path: '/api/marketplace-event',
    file: 'marketplace-event.js',
    methods: ['POST'],
    purpose: 'Record public marketplace interaction/search events and refresh hot-card aggregates opportunistically.',
    auth: 'Public; optional Firebase bearer token attaches user UID when valid.',
    params: {
      body: '`cardId`, `eventType`, optional `source` and bounded metadata.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'FIREBASE_*'],
      services: ['Oracle/Postgres marketplace DB', 'optional Firebase Admin'],
    },
  },
  {
    path: '/api/marketplace-expansion-symbols',
    file: 'marketplace-expansion-symbols.js',
    methods: ['GET', 'POST'],
    purpose: 'Read or update marketplace expansion symbol metadata.',
    auth: 'Required authorized debug/admin Firebase bearer token for both GET and POST.',
    params: {
      query: 'GET filters for expansions.',
      body: 'Expansion symbol update fields for POST.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'MARKETPLACE_ADMIN_EMAILS', 'MARKETPLACE_DEBUG_EMAILS', 'FIREBASE_*'],
      services: ['Oracle/Postgres marketplace DB', 'Firebase Admin'],
    },
  },
  {
    path: '/api/marketplace-expansion-page',
    file: 'marketplace-expansion-page.js',
    methods: ['GET', 'OPTIONS'],
    purpose: 'React BFF: expansion metadata plus paginated singles for a set browse page.',
    auth: 'Public.',
    params: {
      query: '`expansionName` or `slug`; `productType` default card; `limit` and `offset` optional. Omit both name and slug to list expansions.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/marketplace-expansions',
    file: 'marketplace-expansions.js',
    methods: ['GET'],
    purpose: 'Return marketplace expansion list or detail snapshots.',
    auth: 'Public.',
    params: {
      query: 'Expansion slug/id/detail filters and optional limit.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/marketplace-home',
    file: 'marketplace-home.js',
    methods: ['GET'],
    purpose: 'Return marketplace home snapshot and carousel sections.',
    auth: 'Public.',
    params: {
      query: '`recentCardIds` optional comma-separated public ids; returned as sections.recentlySeenIds / spotlightIds.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/marketplace-rails',
    file: 'marketplace-rails.js',
    methods: ['GET', 'OPTIONS'],
    purpose: 'Pi browse rails. Public card_id only. No Supabase.',
    auth: 'Public.',
    params: { query: '`id` rail id (`new_cards`, `set:destined-rivals`).' },
    dependencies: { env: ['MARKETPLACE_DATABASE_URL'], services: ['Pi Postgres'] },
  },
  {
    path: '/api/marketplace-card-tiles',
    file: 'marketplace-card-tiles.js',
    methods: ['GET', 'OPTIONS'],
    purpose: 'Pi card tiles by public id. No Supabase.',
    auth: 'Public.',
    params: { query: '`ids` comma-separated public card ids.' },
    dependencies: { env: ['MARKETPLACE_DATABASE_URL'], services: ['Pi Postgres'] },
  },
  {
    path: '/api/marketplace-home-page',
    file: 'marketplace-home-page.js',
    methods: ['GET', 'OPTIONS'],
    purpose: 'React BFF: fast home carousels (newest English sets + hot blueprints). No CardTrader hydrate.',
    auth: 'Public.',
    params: {
      query: '`recentCardIds` optional comma-separated public ids; `limit` optional (max 48).',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/marketplace-competitive',
    file: 'marketplace-competitive.js',
    methods: ['GET'],
    purpose: 'Return Limitless-backed competitive deck metagame, deck detail, tournament, standings, and pairings data for the marketplace competitive page.',
    auth: 'Public.',
    params: {
      query: '`game`, `format`, `year`, `limit`, and `includeGames=1` for the dashboard; `deckId` for public Limitless deck detail; `tournamentId` for tournament standings/pairings detail.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/marketplace-hot-blueprints',
    file: 'marketplace-hot-blueprints.js',
    methods: ['GET'],
    purpose: 'Return hot marketplace blueprint rows and rolling interaction counts.',
    auth: 'Public.',
    params: {
      query: '`includeCards` and `limit` optional.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/marketplace-listings',
    file: 'marketplace-listings.js',
    methods: ['GET', 'POST', 'PATCH'],
    purpose: 'Read public active listings and create/update/decrement authenticated seller listings.',
    auth: 'Public for active listing reads; writes and seller-owned reads require Firebase bearer token. Reserve listings require reserve role.',
    params: {
      query: '`cardId`, `sellerUid`, `sellerUsername`, `id`, `action`, and `limit` supported. `nativeOnly=1` (or `live=0`) skips live CardTrader merge on public card reads.',
      body: 'Create/update listing fields such as `cardId`, seller display fields, condition, language, `pricePkn`, quantity, and source flags.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'FIREBASE_*'],
      services: ['Oracle/Postgres marketplace DB', 'Firebase Admin'],
    },
  },
  {
    path: '/api/marketplace-collection-summary',
    file: 'marketplace-collection-summary.js',
    methods: ['GET'],
    purpose: 'Authenticated owned-card totals for dashboard Portfolio. Admin Firestore read; uid only from verified bearer.',
    auth: 'Firebase bearer token required. Never accepts a client uid.',
    params: {
      query: 'None. Owner is decoded.uid from the Authorization bearer.',
    },
    dependencies: {
      env: ['FIREBASE_*'],
      services: ['Firebase Admin'],
    },
  },
  {
    path: '/api/marketplace-collection',
    file: 'marketplace-collection.js',
    methods: ['GET'],
    purpose: 'Authenticated owned holdings rows for /collection (physical + NFT). Admin Firestore read; uid only from verified bearer.',
    auth: 'Firebase bearer token required. Never accepts a client uid.',
    params: {
      query: 'None. Owner is decoded.uid from the Authorization bearer.',
    },
    dependencies: {
      env: ['FIREBASE_*'],
      services: ['Firebase Admin'],
    },
  },
  {
    path: '/api/marketplace-portfolio',
    file: 'marketplace-portfolio.js',
    methods: ['GET', 'OPTIONS'],
    purpose: 'React BFF: Pokoin catalog + native PKN overlay (Portfolio / Explore). No CardTrader leftover images. No USD.',
    auth: 'Public.',
    params: {
      query: '`id` / `cardId` optional public card id or leftover ct_id; `limit` optional (Pokemon max 500, satellite max 2500); `game` for One Piece / Riftbound.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace DB'],
    },
  },
  {
    path: '/api/marketplace-orders',
    file: 'marketplace-orders.js',
    methods: ['POST'],
    purpose: 'Create paid marketplace orders, decrement listings, credit sellers, and send seller notifications.',
    auth: 'Required Firebase bearer token.',
    params: {
      query: '`action=checkout` default, `action=notify-sellers` for notification retry/admin flows.',
      body: '`items`, `subtotalPkn`, and `totalPkn` for checkout; notification payload for notify-sellers.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'FIREBASE_*', 'RESEND_API_KEY'],
      services: ['Oracle/Postgres marketplace DB', 'Firebase Admin', 'email provider'],
    },
  },
  {
    path: '/api/marketplace-search-page',
    file: 'marketplace-search-page.js',
    methods: ['GET', 'OPTIONS'],
    purpose: 'React BFF: Meili/SQL search results with pagination and product facets.',
    auth: 'Public.',
    params: {
      query: '`query` or `q`; `limit`, `offset`, `productType`, `productSearchOnly`, `lang`, `includeFacets`.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'MEILI_HOST', 'MEILI_API_KEY'],
      services: ['Oracle/Postgres marketplace DB', 'Meilisearch'],
    },
  },
  {
    path: '/api/marketplace-search-candidates',
    file: 'marketplace-search-candidates.js',
    methods: ['POST'],
    purpose: 'Return split/search candidate rows for marketplace search diagnostics and clients.',
    auth: 'Public for normal search; debug output requires authorized debug/admin Firebase bearer token.',
    params: {
      body: '`search_term`/`searchTerm`, `result_limit`, `result_offset`, `search_language`, optional previous context/debug fields.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'MARKETPLACE_*_DATABASE_URL', 'MARKETPLACE_ADMIN_EMAILS', 'MARKETPLACE_DEBUG_EMAILS', 'FIREBASE_*'],
      services: ['Oracle/Postgres marketplace DB', 'Firebase Admin for debug auth'],
    },
  },
  {
    path: '/api/marketplace-recents',
    file: 'marketplace-recents.js',
    methods: ['GET', 'PUT', 'POST', 'OPTIONS'],
    purpose: 'Signed-in recently seen public card ids. Writer is nezopt 15T. Tile JSON is not stored.',
    auth: 'Firebase bearer token required.',
    params: {
      body: '`cardIds` array (PUT/POST), optional `cardId` prepended. Max 24 unique public ids.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'MARKETPLACE_WRITER_DATABASE_URL', 'FIREBASE_*'],
      services: ['nezopt 15T writer', 'Pi replica reads', 'Firebase Admin'],
    },
  },
  {
    path: '/api/marketplace-watchlist',
    file: 'marketplace-watchlist.js',
    methods: ['POST'],
    purpose: 'Record marketplace watchlist add/remove analytics with optional verified user context.',
    auth: 'Public; optional Firebase bearer token attaches user UID when valid.',
    params: {
      body: '`cardId` or `blueprintId`, `action`, and optional client context.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'FIREBASE_*'],
      services: ['Oracle/Postgres marketplace DB', 'optional Firebase Admin'],
    },
  },
  {
    path: '/api/pokoin-assistant',
    file: 'pokoin-assistant.js',
    methods: ['POST'],
    purpose: 'Answer Pokontact assistant chat requests with marketplace grounding and optional service handoff.',
    auth: 'Public; optional Firebase bearer token attaches verified user context.',
    params: {
      body: '`message` required, optional `messages`, `page`, `pageContext`, and `username`.',
    },
    dependencies: {
      env: ['POKOIN_ASSISTANT_EMAIL', 'POKOIN_ASSISTANT_FROM', 'POKONTACT_SERVICE_URL', 'POKONTACT_SERVICE_TOKEN', 'POKONTACT_SERVICE_TIMEOUT_MS', 'MARKETPLACE_DATABASE_URL', 'FIREBASE_*', 'RESEND_API_KEY'],
      services: ['Oracle/Postgres marketplace DB', 'Firebase Admin optional', 'email provider', 'optional Pokontact service'],
    },
  },
  {
    path: '/api/user-current-page',
    file: 'user-current-page.js',
    methods: ['GET', 'POST'],
    purpose: 'Store or read the current internal Pokoin page for an assistant browser session.',
    auth: 'Public anonymous session ID; optional Firebase bearer token scopes reads/writes to the verified user.',
    params: {
      query: 'GET accepts `sessionId` or `session_id`.',
      body: 'POST requires `sessionId` and a safe internal `path` or Pokoin URL; optional `source`.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'FIREBASE_*'],
      services: ['Oracle/Postgres marketplace DB', 'Firebase Admin optional'],
    },
  },
  {
    path: '/api/social-autopost',
    file: 'social-autopost.js',
    methods: ['POST'],
    purpose: 'Post supplied Pokoin social copy or card payloads to configured Telegram and X channels, optionally using the dedicated peer2 social copy agent.',
    auth: 'Required shared social autopost secret, CRON_SECRET bearer, or authorized debug/admin Firebase bearer token.',
    params: {
      body: '`targets`, `message`, optional card fields, `dryRun`, `sendPhoto`, `silent`, and `useAgent`.',
    },
    dependencies: {
      env: ['SOCIAL_AUTOPOST_SECRET', 'CRON_SECRET', 'SOCIAL_AGENT_ENDPOINT', 'SOCIAL_AGENT_TOKEN', 'SOCIAL_AGENT_TIMEOUT_MS', 'TELEGRAM_BOT_TOKEN', 'TELEGRAM_CHANNEL_ID', 'X_ACCESS_TOKEN', 'MARKETPLACE_DATABASE_URL', 'FIREBASE_*'],
      services: ['Telegram Bot API', 'X API v2', 'dedicated peer2 social agent optional', 'Oracle/Postgres marketplace DB optional', 'Firebase Admin optional'],
    },
  },
  {
    path: '/api/social-autopost/hot-card',
    file: 'social-autopost-hot-card.js',
    methods: ['GET', 'POST'],
    purpose: 'Select a hot Pokoin marketplace card and post it to configured social channels, optionally using the dedicated peer2 social copy agent.',
    auth: 'Required shared social autopost secret, CRON_SECRET bearer, or authorized debug/admin Firebase bearer token.',
    params: {
      query: '`targets`, `window`, `limit`, `dryRun`, `sendPhoto`, `silent`, and `useAgent` for GET.',
      body: 'Same fields as query for POST; optional `message`, `hook`, and `hashtags` override generated copy.',
    },
    dependencies: {
      env: ['SOCIAL_AUTOPOST_SECRET', 'CRON_SECRET', 'SOCIAL_AGENT_ENDPOINT', 'SOCIAL_AGENT_TOKEN', 'SOCIAL_AGENT_TIMEOUT_MS', 'TELEGRAM_BOT_TOKEN', 'TELEGRAM_CHANNEL_ID', 'X_ACCESS_TOKEN', 'MARKETPLACE_DATABASE_URL', 'FIREBASE_*'],
      services: ['Telegram Bot API', 'X API v2', 'dedicated peer2 social agent optional', 'Oracle/Postgres marketplace DB', 'Firebase Admin optional'],
    },
  },
  {
    path: '/api/social-post-agent',
    file: 'social-post-agent.js',
    methods: ['POST'],
    purpose: 'Generate Telegram and X copy through the dedicated peer2 social agent without posting to providers.',
    auth: 'Required shared social autopost secret, CRON_SECRET bearer, or authorized debug/admin Firebase bearer token.',
    params: {
      body: '`targets`, card/message fields, and optional `prompt`; returns generated copy and deterministic fallback metadata.',
    },
    dependencies: {
      env: ['SOCIAL_AUTOPOST_SECRET', 'CRON_SECRET', 'SOCIAL_AGENT_ENDPOINT', 'SOCIAL_AGENT_TOKEN', 'SOCIAL_AGENT_TIMEOUT_MS', 'FIREBASE_*'],
      services: ['dedicated peer2 social agent optional', 'Firebase Admin optional'],
    },
  },
  {
    path: '/api/register-email',
    file: 'register-email.js',
    methods: ['POST'],
    purpose: 'Start email/password signup by storing pending signup data and sending verification mail, or resend a pending verification (resend: true) with per-email rate limiting.',
    auth: 'Public.',
    params: {
      body: '`email`, `password`, optional `username` and `redirectPath`; or `resend: true` with `email` only.',
    },
    dependencies: {
      env: ['FIREBASE_*', 'RESEND_API_KEY', 'PUBLIC_SITE_URL', 'SIGNUP_ENCRYPTION_SECRET', 'POKOIN_REQUIRE_VERIFIED_PASSWORD'],
      services: ['Firebase Admin', 'email provider'],
    },
  },
  {
    path: '/api/remove-profile-picture',
    file: 'remove-profile-picture.js',
    methods: ['POST'],
    purpose: 'Remove the authenticated user custom profile picture and delete old R2 object when present.',
    auth: 'Required Firebase bearer token.',
    params: {
      body: 'No required fields.',
    },
    dependencies: {
      env: ['FIREBASE_*', 'R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY', 'R2_PROFILE_PICTURES_BUCKET'],
      services: ['Firebase Admin', 'Cloudflare R2'],
    },
  },
  {
    path: '/api/request-pkn-withdraw',
    file: 'request-pkn-withdraw.js',
    methods: ['POST'],
    purpose: 'Withdraw PKN from site balance to a linked native PKN address.',
    auth: 'Required Firebase bearer token.',
    params: {
      body: 'Withdrawal amount/address or linked-wallet withdrawal fields used by the wallet UI.',
    },
    dependencies: {
      env: ['FIREBASE_*', 'POKOIN_RPC_URL', 'POKOIN_BANK_ADDRESS', 'POKOIN_BANK_PRIVATE_KEY'],
      services: ['Firebase Admin', 'Pokoin RPC'],
    },
  },
  {
    path: '/api/scan-batch',
    file: 'scan-batch.js',
    methods: ['GET', 'POST', 'OPTIONS'],
    purpose: 'Scan Connect staged batch: snapshot, Batch Defaults, row edits (duplicate, merge undo), idempotent submit to marketplace_user_listings.',
    auth: 'Required Firebase bearer token; rows are scoped to the seller uid.',
    params: {
      query: '`batchId`; `list=open`; `action=image&itemId=` returns the scan JPEG.',
      body: '`action` = defaults | item | add | remove | restore | duplicate | unmerge | submit | discard (pokoin-web docs/SCAN_LISTING_WORKFLOW.md).',
    },
    dependencies: {
      env: ['MARKETPLACE_WRITER_DATABASE_URL', 'MARKETPLACE_DATABASE_URL', 'FIREBASE_*'],
      services: ['Oracle/Postgres marketplace writer', 'Firebase Admin'],
    },
  },
  {
    path: '/api/scan-pair',
    file: 'scan-pair.js',
    methods: ['POST', 'OPTIONS'],
    purpose: 'Phone claims a 4-digit Scan Connect pairing code or QR secret and receives a session-scoped phone token.',
    auth: 'Public. Postgres-backed per-IP and global failure limits; identical error for wrong, expired and used codes.',
    params: {
      body: '`pin` (4 digits) or `qr`, optional `device` label.',
    },
    dependencies: {
      env: ['MARKETPLACE_WRITER_DATABASE_URL', 'MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace writer'],
    },
  },
  {
    path: '/api/scan-phone',
    file: 'scan-phone.js',
    methods: ['POST', 'OPTIONS'],
    purpose: 'Paired phone heartbeat, idempotent scan events (scanEventId), and leave.',
    auth: '`Authorization: Scan <phoneToken>` from /api/scan-pair. No Firebase.',
    params: {
      query: '`action` = heartbeat | scan | leave.',
      body: 'scan: `scanEventId`, `clientSequence`, `capturedAt`, `clockOffsetMs`, `recognition.hits`, optional `image` (base64 JPEG ≤ 45 KB), `timings`.',
    },
    dependencies: {
      env: ['MARKETPLACE_WRITER_DATABASE_URL', 'MARKETPLACE_DATABASE_URL'],
      services: ['Oracle/Postgres marketplace writer'],
    },
  },
  {
    path: '/api/scan-session',
    file: 'scan-session.js',
    methods: ['GET', 'POST', 'OPTIONS'],
    purpose: 'Desktop Scan Session: start/resume with pairing code, regenerate code, disconnect phone, pause, end.',
    auth: 'Required Firebase bearer token.',
    params: {
      query: '`sessionId` (GET), `action` = start | pairing | disconnect | pause | end (POST).',
      body: '`batchId`, `sessionId`, `paused`, `reason`.',
    },
    dependencies: {
      env: ['MARKETPLACE_WRITER_DATABASE_URL', 'MARKETPLACE_DATABASE_URL', 'FIREBASE_*'],
      services: ['Oracle/Postgres marketplace writer', 'Firebase Admin'],
    },
  },
  {
    path: '/api/scan-stream',
    file: 'scan-stream.js',
    methods: ['GET', 'OPTIONS'],
    purpose: 'Server-sent change stream for one Scan Batch (rows, defaults, session) with cursor replay; closes after 55 s.',
    auth: 'Required Firebase bearer token.',
    params: {
      query: '`batchId`, `after` cursor.',
    },
    dependencies: {
      env: ['MARKETPLACE_WRITER_DATABASE_URL', 'MARKETPLACE_DATABASE_URL', 'FIREBASE_*'],
      services: ['Oracle/Postgres marketplace writer', 'Firebase Admin'],
    },
  },
  {
    path: '/api/search-recipient-emails',
    file: 'search-recipient-emails.js',
    methods: ['GET', 'POST'],
    purpose: 'Search usernames for transfers, ensure a username, or update the authenticated user username.',
    auth: 'Required Firebase bearer token.',
    params: {
      query: '`q` for GET username search.',
      body: 'Optional `username` for POST update; empty POST ensures a unique username.',
    },
    dependencies: {
      env: ['FIREBASE_*'],
      services: ['Firebase Admin'],
    },
  },
  {
    path: '/api/searchbar-cancel',
    file: 'searchbar-cancel.js',
    methods: ['GET', 'POST'],
    purpose: 'Mark a searchbar session as cancelled for in-process search cancellation checks.',
    auth: 'Public.',
    params: {
      query: '`search_session_id`/`sessionId` supported.',
      body: '`search_session_id`/`sessionId` supported.',
    },
    dependencies: {
      env: [],
      services: ['In-process search session memory'],
    },
  },
  {
    path: '/api/searchbar-cards',
    file: 'searchbar-cards.js',
    methods: ['GET', 'POST'],
    purpose: 'Stable wrapper around marketplace autocomplete ranking for searchbar experiments and clients.',
    auth: 'Public; debug/personalization may use optional Firebase bearer token.',
    params: {
      query: '`query`, `search_language`, `limit`, and `pool_limit` supported for GET.',
      body: '`query`, `search_language`, `limit`, `pool_limit`, previous context, debug, and mode fields for POST.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'MARKETPLACE_*_DATABASE_URL', 'SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY'],
      services: ['Oracle/Postgres marketplace DB', 'optional Supabase name index'],
    },
  },
  {
    path: '/api/searchbar-token-predict',
    file: 'searchbar-token-predict.js',
    methods: ['GET', 'POST', 'OPTIONS'],
    purpose: 'Return lightweight card-name token predictions for active typed fragments.',
    auth: 'Public.',
    params: {
      query: '`query`, `search_language`, and `limit` for GET.',
      body: '`query`, `search_language`, `limit`, and optional previous prediction context for POST.',
    },
    dependencies: {
      env: ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_NAME_INDEX_DATABASE_URL', 'MARKETPLACE_DATABASE_URL'],
      services: ['Supabase REST/Postgres token table', 'Oracle/Postgres fallback'],
    },
  },
  {
    path: '/api/signup-notification',
    file: 'signup-notification.js',
    methods: ['POST'],
    purpose: 'Send signup notification email for the authenticated user once.',
    auth: 'Required Firebase bearer token.',
    params: {
      body: 'Optional signup/profile metadata.',
    },
    dependencies: {
      env: ['FIREBASE_*', 'RESEND_API_KEY'],
      services: ['Firebase Admin', 'email provider'],
    },
  },
  {
    path: '/api/stripe-webhook',
    file: 'stripe-webhook.js',
    methods: ['POST'],
    purpose: 'Handle Stripe Checkout webhooks and credit completed PKN purchases.',
    auth: 'Stripe webhook signature using raw request body.',
    params: {
      body: 'Raw Stripe webhook payload. Do not pre-parse JSON before signature verification.',
    },
    dependencies: {
      env: ['STRIPE_SECRET_KEY', 'STRIPE_WEBHOOK_SECRET', 'STRIPE_API_VERSION', 'FIREBASE_*'],
      services: ['Stripe', 'Firebase Admin'],
    },
    rawBody: true,
  },
  {
    path: '/api/top-up-account-balance',
    file: 'top-up-account-balance.js',
    methods: ['POST'],
    purpose: 'Verify a native PKN funding transaction and credit authenticated site balance.',
    auth: 'Required Firebase bearer token.',
    params: {
      body: '`amountPkn`, `fundingTxHash`, and optional `reconcileRecent`.',
    },
    dependencies: {
      env: ['FIREBASE_*', 'POKOIN_RPC_URL', 'POKOIN_BANK_ADDRESS'],
      services: ['Firebase Admin', 'Pokoin RPC'],
    },
  },
  {
    path: '/api/trainingai-card-classify',
    file: 'trainingai-card-classify.js',
    methods: ['POST', 'OPTIONS'],
    purpose: 'Proxy card image classification requests to the Pokoin TrainingAI Oracle classifier or Hugging Face Space fallback.',
    auth: 'Public by default; protect upstream classifier with TRAININGAI_HF_TOKEN when private.',
    params: {
      body: '`imageBase64` JSON or multipart image upload required; `topK`/`top_k` optional from 1 to 10.',
    },
    dependencies: {
      env: ['TRAININGAI_CLASSIFIER_URL', 'TRAININGAI_HF_TOKEN', 'TRAININGAI_CLASSIFIER_TIMEOUT_MS', 'TRAININGAI_CLASSIFIER_MAX_IMAGE_BYTES'],
      services: ['TrainingAI Oracle classifier or Hugging Face Space classifier'],
    },
  },
  {
    path: '/api/transfer-account-balance',
    file: 'transfer-account-balance.js',
    methods: ['POST'],
    purpose: 'Transfer PKN site balance from the authenticated user to another Pokoin account.',
    auth: 'Required Firebase bearer token.',
    params: {
      body: 'Recipient username/email/uid and PKN amount fields.',
    },
    dependencies: {
      env: ['FIREBASE_*', 'RESEND_API_KEY'],
      services: ['Firebase Admin', 'email provider'],
    },
  },
  {
    path: '/api/unlock-silver',
    file: 'unlock-silver.js',
    methods: ['POST'],
    purpose: 'Unlock Silver status/features for the authenticated account.',
    auth: 'Required Firebase bearer token.',
    params: {
      body: 'Unlock request fields used by the client.',
    },
    dependencies: {
      env: ['FIREBASE_*'],
      services: ['Firebase Admin'],
    },
  },
  {
    path: '/api/upload-profile-picture',
    file: 'upload-profile-picture.js',
    methods: ['POST'],
    purpose: 'Optimize an uploaded profile picture and store it in R2.',
    auth: 'Required Firebase bearer token.',
    params: {
      body: '`imageBase64` required, max 6 MB source image.',
    },
    dependencies: {
      env: ['FIREBASE_*', 'R2_ACCESS_KEY_ID', 'R2_SECRET_ACCESS_KEY', 'R2_PROFILE_PICTURES_BUCKET', 'R2_PROFILE_PICTURES_PUBLIC_URL'],
      services: ['Firebase Admin', 'Cloudflare R2', 'sharp'],
    },
  },
  {
    path: '/api/verify-email-signup',
    file: 'verify-email-signup.js',
    methods: ['POST'],
    purpose: 'Idempotently finalize a verified email signup into an ACTIVE Pokoin account (Firebase user, pok_email_verified claim, username claim, balances) and return a sign-in custom token.',
    auth: 'Public token verification.',
    params: {
      body: 'Signup verification `token`.',
    },
    dependencies: {
      env: ['FIREBASE_*', 'RESEND_API_KEY', 'SIGNUP_ENCRYPTION_SECRET', 'POKOIN_REQUIRE_VERIFIED_PASSWORD'],
      services: ['Firebase Admin', 'email provider'],
    },
  },
  {
    path: '/api/wallet-auth/nonce',
    file: 'wallet-auth-nonce.js',
    methods: ['POST'],
    purpose: 'Create a nonce challenge for wallet sign-in.',
    auth: 'Public.',
    params: {
      body: 'Wallet address and client challenge metadata.',
    },
    dependencies: {
      env: ['FIREBASE_*'],
      services: ['Firebase Admin'],
    },
  },
  {
    path: '/api/wallet-auth/verify',
    file: 'wallet-auth-verify.js',
    methods: ['POST'],
    purpose: 'Verify a signed wallet nonce and sign in/create the corresponding Firebase user.',
    auth: 'Public signed wallet challenge.',
    params: {
      body: 'Wallet address, signature, nonce/session fields, and optional profile fields.',
    },
    dependencies: {
      env: ['FIREBASE_*', 'RESEND_API_KEY'],
      services: ['Firebase Admin', 'email provider'],
    },
  },
  {
    path: '/api/wallet-link',
    file: 'wallet-link.js',
    methods: ['POST'],
    purpose: 'Link a wallet to the authenticated Firebase account.',
    auth: 'Required Firebase bearer token.',
    params: {
      body: 'Wallet address/signature/session fields.',
    },
    dependencies: {
      env: ['FIREBASE_*'],
      services: ['Firebase Admin'],
    },
  },
  {
    path: '/api/wallet-link/complete',
    file: 'wallet-link-complete.js',
    methods: ['POST'],
    purpose: 'Complete a wallet-link session from a signed wallet payload.',
    auth: 'Signed wallet-link session payload.',
    params: {
      body: 'Wallet-link session id, address, signature, and profile fields.',
    },
    dependencies: {
      env: ['FIREBASE_*'],
      services: ['Firebase Admin'],
    },
  },
  {
    path: '/api/wallet-link/session',
    file: 'wallet-link-session.js',
    methods: ['POST'],
    purpose: 'Create a wallet-link session for an authenticated Firebase account.',
    auth: 'Required Firebase bearer token.',
    params: {
      body: 'Wallet address and session metadata.',
    },
    dependencies: {
      env: ['FIREBASE_*'],
      services: ['Firebase Admin'],
    },
  },
  {
    path: '/api/wpkn-exchange/:action',
    file: 'wpkn-exchange.js',
    methods: ['GET', 'POST'],
    purpose: 'Quote, request, and check native PKN/wPKN exchange flows.',
    auth: 'Required Firebase bearer token.',
    params: {
      path: '`action` is `quote`, `request`, or `status`.',
      body: '`direction`, `amountIn`, `quoteId`, and `toAddress` depending on action.',
      query: '`requestId` optional for status.',
    },
    dependencies: {
      env: ['FIREBASE_*', 'POKOIN_RPC_URL', 'POKOIN_RESERVE_ADDRESS', 'POKOIN_RESERVE_PRIVATE_KEY'],
      services: ['Firebase Admin', 'Pokoin RPC', 'BSC/Pancake helpers'],
    },
  },
  {
    path: '/api/wpkn-pkn-quote',
    file: 'wpkn-pkn-quote.js',
    methods: ['GET', 'POST'],
    purpose: 'Return a public wPKN/PKN market quote from GeckoTerminal plus the configured PKN USD price.',
    auth: 'Public.',
    params: {
      query: '`direction`, `amountIn`.',
      body: '`direction`, `amountIn` (POST).',
    },
    dependencies: {
      env: ['PKN_USDT_PRICE', 'PKN_CHECKOUT_USDT_PRICE'],
      services: ['GeckoTerminal'],
    },
  },
];

module.exports = { routeDefinitions };
