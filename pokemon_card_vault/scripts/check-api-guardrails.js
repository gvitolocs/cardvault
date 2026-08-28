#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');

const { routeDefinitions } = require('../server/api-route-manifest');

const ROOT_DIR = path.resolve(__dirname, '..');
const API_DIR = path.join(ROOT_DIR, 'api');

const APPROVED_DUPLICATION_EXCEPTIONS = {
  'cardmarket-redirect.js': [
    'cardmarket redirect intentionally parses/cleans external Cardmarket URLs, not Pokoin canonical card URLs.',
  ],
  'marketplace-blueprint-price.js': [
    'Legacy CardTrader offer parser kept for compatibility; new price conversion code should move to shared helpers.',
  ],
  'marketplace-card-cheapest-price.js': [
    'Parses canonicalPath query aliases for the price API; DB canonical URL source remains marketplace-card-url.',
  ],
  'extension-card-search.js': [
    'Extension API returns DB canonical paths from marketplace_card_urls for client navigation; no local slug builder is allowed.',
  ],
  'marketplace-card-seo.js': [
    'SEO handler must parse incoming marketplace card paths from Vercel rewrites; canonical output still comes from DB lookup behavior.',
  ],
  'marketplace-card-shortlink.js': [
    'Shortlink route owns legacy numeric-root compatibility and falls back only when DB canonical paths are unavailable.',
  ],
  'marketplace-card-url.js': [
    'Canonical URL resolver owns parsing and DB lookup for marketplace card paths.',
  ],
  'marketplace-card-versions.js': [
    'Legacy slug matching helpers still exported for card route compatibility; new canonical URL behavior should use marketplace-card-url.',
  ],
  'marketplace-cards.js': [
    'Catalog query passes the configured PKN reference into Postgres price functions; new JavaScript price conversion should use shared helpers.',
  ],
  'marketplace-home.js': [
    'Home fallback query passes the configured PKN reference into Postgres price functions; new JavaScript price conversion should use shared helpers.',
  ],
  'pokoin-assistant.js': [
    'Assistant sanitizes user/page paths and reads canonical paths from Oracle; new card URL generation should call marketplace-card-url or DB URLs.',
  ],
};

const READ_HEAVY_CACHE_ROUTES = new Set([
  'cardtrader-blueprint-listings.js',
  'cardtrader-live-listings.js',
  'deck-card-version-lookup.js',
  'extension-card-search.js',
  'forum.js',
  'limitless-expansion-blueprints.js',
  'marketplace-artist-cards.js',
  'marketplace-artist-suggestions.js',
  'marketplace-blueprint-price.js',
  'marketplace-card-cheapest-price.js',
  'marketplace-card-sales.js',
  'marketplace-card-seo.js',
  'marketplace-card-shortlink.js',
  'marketplace-card-url.js',
  'marketplace-card-versions.js',
  'marketplace-cards.js',
  'marketplace-competitive.js',
  'marketplace-expansions.js',
  'marketplace-home.js',
  'marketplace-hot-blueprints.js',
  'marketplace-listings.js',
  'marketplace-search-candidates.js',
  'searchbar-cards.js',
  'searchbar-token-predict.js',
]);

const HELPER_IMPORTS = [
  {
    label: 'emoji normalization',
    helper: './_marketplace_card_emoji',
    patterns: [
      /\bcardIdentityEmojis?\b/,
      /\bcard_identity_emojis?\b/,
      /\brarityVariantEmoji\b/,
      /\brarity_variant_emoji\b/,
    ],
    requiredImport: /require\(['"]\.\/_marketplace_card_emoji['"]\)/,
  },
  {
    label: 'seller comment filtering',
    helper: './_seller_comment_filter',
    patterns: [
      /\bsellerComment\b/,
      /\bseller_comment\b/,
    ],
    requiredImport: /require\(['"]\.\/_seller_comment_filter['"]\)/,
  },
];

const DUPLICATED_LOGIC_PATTERNS = [
  {
    label: 'direct PKN reference price fallback',
    pattern: /PKN_CHECKOUT_USDT_PRICE[\s\S]{0,80}0\.005|0\.005[\s\S]{0,80}PKN_CHECKOUT_USDT_PRICE/,
    helper: './_pkn_checkout_pricing or CardTrader cache helper',
  },
  {
    label: 'canonical card slug generation',
    pattern: /\bcanonicalSlug(?:ForRow|Matches)?\b|\bcardDetailSlugParts\b/,
    helper: './marketplace-card-url or DB marketplace_card_urls',
  },
  {
    label: 'manual marketplace card path construction',
    pattern: /\/marketplace\/(?:\$|[a-z{])[\s\S]{0,160}\/cards\//,
    helper: './marketplace-card-url or DB marketplace_card_urls',
  },
  {
    label: 'manual promotional seller comment filtering',
    pattern: /\bcheck\s+my\s+store\b|\bmore\s+cards\s+available\b|\bexternal\s+marketplace\b/i,
    helper: './_seller_comment_filter',
  },
];

function routeFiles() {
  return fs
    .readdirSync(API_DIR)
    .filter((name) => name.endsWith('.js') && !name.endsWith('.test.js') && !name.startsWith('_'))
    .sort();
}

function exceptionReasons(file) {
  return APPROVED_DUPLICATION_EXCEPTIONS[file] || [];
}

function hasException(file) {
  return exceptionReasons(file).length > 0;
}

function checkRouteInventory(files, errors) {
  const manifestFiles = new Set(routeDefinitions.map((route) => route.file));
  for (const file of files) {
    if (!manifestFiles.has(file)) {
      errors.push(`${file} is not listed in server/api-route-manifest.js.`);
    }
  }
  for (const route of routeDefinitions) {
    if (!fs.existsSync(path.join(API_DIR, route.file))) {
      errors.push(`${route.file} is listed in the manifest but missing from api/.`);
    }
  }
}

function checkHelperUsage(file, source, errors) {
  for (const rule of HELPER_IMPORTS) {
    const mentions = rule.patterns.some((pattern) => pattern.test(source));
    if (mentions && !rule.requiredImport.test(source) && !hasException(file)) {
      errors.push(`${file} mentions ${rule.label}; import ${rule.helper} or add a reviewed exception.`);
    }
  }

  for (const rule of DUPLICATED_LOGIC_PATTERNS) {
    if (rule.pattern.test(source) && !hasException(file)) {
      errors.push(`${file} appears to contain ${rule.label}; prefer ${rule.helper} or add a reviewed exception.`);
    }
  }
}

function checkReadCaching(file, source, errors) {
  if (!READ_HEAVY_CACHE_ROUTES.has(file)) return;
  const hasCacheControl = /Cache-Control/.test(source);
  if (!hasCacheControl) {
    errors.push(`${file} is a read-heavy public route but does not set Cache-Control.`);
  }
}

function checkObservability(errors) {
  const serverSource = fs.readFileSync(path.join(ROOT_DIR, 'server', 'oracle-api-server.js'), 'utf8');
  if (!/observeApiRequest/.test(serverSource)) {
    errors.push('server/oracle-api-server.js must wrap route calls with observeApiRequest().');
  }
  if (!fs.existsSync(path.join(API_DIR, '_api_observability.js'))) {
    errors.push('api/_api_observability.js is missing.');
  }
}

function main() {
  const files = routeFiles();
  const errors = [];
  checkRouteInventory(files, errors);
  checkObservability(errors);

  for (const file of files) {
    const source = fs.readFileSync(path.join(API_DIR, file), 'utf8');
    checkHelperUsage(file, source, errors);
    checkReadCaching(file, source, errors);
  }

  if (errors.length) {
    console.error('API guardrail check failed:');
    for (const error of errors) {
      console.error(`- ${error}`);
    }
    console.error('\nApproved duplication exceptions:');
    for (const [file, reasons] of Object.entries(APPROVED_DUPLICATION_EXCEPTIONS).sort()) {
      console.error(`- ${file}: ${reasons.join(' ')}`);
    }
    process.exit(1);
  }

  console.log(`API guardrails OK: ${files.length} route files, ${READ_HEAVY_CACHE_ROUTES.size} read-heavy cache contracts, Oracle observability wrapper enabled.`);
}

main();
