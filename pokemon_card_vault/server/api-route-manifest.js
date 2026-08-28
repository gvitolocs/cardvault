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
      query: '`id` required blueprint ID, `locale` optional two-letter locale, `format=json` optional.',
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
    purpose: 'Redirect a CardTrader blueprint ID to CardTrader.',
    auth: 'Public.',
    params: {
      query: '`id` required numeric CardTrader blueprint ID.',
    },
    dependencies: {
      env: [],
      services: ['CardTrader website'],
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
    purpose: 'Return recent paid sale history for a marketplace card from Firestore orders.',
    auth: 'Public.',
    params: {
      query: '`cardId` required, `limit` optional.',
    },
    dependencies: {
      env: ['FIREBASE_*'],
      services: ['Firebase Admin'],
    },
  },
  {
    path: '/api/marketplace-card-shortlink',
    file: 'marketplace-card-shortlink.js',
    methods: ['GET', 'HEAD'],
    purpose: 'Redirect numeric root short links to canonical marketplace card URLs.',
    auth: 'Public.',
    params: {
      query: '`cardId` required via rewrite or query string.',
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
    purpose: 'Return the stored canonical marketplace card URL for a card id or legacy root path.',
    auth: 'Public.',
    params: {
      query: '`cardId` or `path` required; `language` optional.',
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
      query: 'No required query parameters.',
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
      query: '`cardId`, `sellerUid`, `sellerUsername`, `id`, `action`, and `limit` supported.',
      body: 'Create/update listing fields such as `cardId`, seller display fields, condition, language, `pricePkn`, quantity, and source flags.',
    },
    dependencies: {
      env: ['MARKETPLACE_DATABASE_URL', 'FIREBASE_*'],
      services: ['Oracle/Postgres marketplace DB', 'Firebase Admin'],
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
    purpose: 'Start email/password signup by storing pending signup data and sending verification mail.',
    auth: 'Public.',
    params: {
      body: '`email`, password fields, and optional requested username/profile fields.',
    },
    dependencies: {
      env: ['FIREBASE_*', 'RESEND_API_KEY', 'PUBLIC_SITE_URL', 'PENDING_SIGNUP_SECRET'],
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
    purpose: 'Verify a pending email signup token, create/claim the Firebase user, and send welcome/notification emails.',
    auth: 'Public token verification.',
    params: {
      body: 'Signup verification token and matching email/password verification fields.',
    },
    dependencies: {
      env: ['FIREBASE_*', 'RESEND_API_KEY', 'PENDING_SIGNUP_SECRET'],
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
];

module.exports = { routeDefinitions };
