const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const Module = require('node:module');
const test = require('node:test');

const rootDir = path.join(__dirname, '..');
const apiDir = path.join(rootDir, 'api');

const deployHelpers = [
  '_artist_display',
  '_email',
  '_firebase',
  '_firebase_roles',
  '_marketplace_card_emoji',
  '_marketplace_card_rarity',
  '_marketplace_db',
  '_marketplace_search_engine',
  '_meili_client',
  '_meili_marketplace',
  '_native_pkn',
  '_pending_signup',
  '_pkn_checkout_pricing',
  '_pkn_purchase',
  '_r2',
  '_search_debug_auth',
  '_searchbar_session',
  '_slug',
  '_supabase',
  '_username',
  '_wpkn_exchange',
];

function copyApiFile(name, targetDir) {
  fs.copyFileSync(
    path.join(apiDir, `${name}.js`),
    path.join(targetDir, `${name}.js`),
  );
}

function withStubbedExternalPackages(fn) {
  const originalLoad = Module._load;
  Module._load = function load(request, parent, isMain) {
    if (request === 'stripe') {
      return function Stripe() {};
    }
    if (request === 'firebase-admin') {
      return { apps: [] };
    }
    if (request === 'pg') {
      return { Pool: class Pool {} };
    }
    return originalLoad.apply(this, arguments);
  };
  try {
    return fn();
  } finally {
    Module._load = originalLoad;
  }
}

function copiedEndpointNames() {
  const deployScript = fs.readFileSync(path.join(rootDir, 'deploy-pokoin-web.sh'), 'utf8');
  const endpointBlock = deployScript.match(/for endpoint in \\\n([\s\S]*?)\n\s*done/);
  assert.ok(endpointBlock, 'deploy-pokoin-web.sh endpoint copy loop exists');
  return new Set(
    endpointBlock[1]
      .split(/\s+/)
      .map((entry) => entry.replace(/\\$/, '').trim())
      .filter((entry) => /^[a-z0-9][a-z0-9-]*$/i.test(entry)),
  );
}

function assertApiRoutePackaged(routePath, fileName) {
  const vercelConfig = JSON.parse(fs.readFileSync(path.join(rootDir, 'vercel.json'), 'utf8'));
  const { routeDefinitions } = require('../server/api-route-manifest');
  const endpointName = fileName.replace(/\.js$/, '');

  assert.equal(copiedEndpointNames().has(endpointName), true, `${endpointName} is copied by deploy`);
  assert.equal(
    vercelConfig.rewrites.some((rewrite) => (
      rewrite.source === routePath &&
      rewrite.destination === `/api/${fileName}`
    )),
    true,
    `${routePath} has a Vercel rewrite`,
  );
  assert.equal(
    routeDefinitions.some((route) => (
      route.path === routePath &&
      route.file === fileName
    )),
    true,
    `${routePath} is documented in the API route manifest`,
  );
}

test('Pokoin Stripe endpoints module-load in deploy-pokoin-web output layout', () => {
  const deployDir = fs.mkdtempSync(path.join(os.tmpdir(), 'pokoin-web-deploy-'));
  try {
    const deployApiDir = path.join(deployDir, 'api');
    const deployServerDir = path.join(deployDir, 'server');
    fs.mkdirSync(deployApiDir);
    fs.mkdirSync(deployServerDir);

    for (const helper of deployHelpers) {
      copyApiFile(helper, deployServerDir);
    }
    copyApiFile('create-pkn-checkout-session', deployApiDir);
    copyApiFile('stripe-webhook', deployApiDir);

    const loaded = withStubbedExternalPackages(() => ({
      checkout: require(path.join(deployApiDir, 'create-pkn-checkout-session.js')),
      webhook: require(path.join(deployApiDir, 'stripe-webhook.js')),
    }));

    assert.equal(typeof loaded.checkout, 'function');
    assert.equal(typeof loaded.webhook, 'function');
  } finally {
    fs.rmSync(deployDir, { force: true, recursive: true });
  }
});

test('Pokontact helper loaders resolve in deploy-pokoin-web output layout', () => {
  const deployDir = fs.mkdtempSync(path.join(os.tmpdir(), 'pokoin-web-deploy-'));
  try {
    const deployApiDir = path.join(deployDir, 'api');
    const deployServerDir = path.join(deployDir, 'server');
    fs.mkdirSync(deployApiDir);
    fs.mkdirSync(deployServerDir);

    for (const helper of deployHelpers) {
      copyApiFile(helper, deployServerDir);
    }
    copyApiFile('pokoin-assistant', deployApiDir);
    let assistantSource = fs.readFileSync(path.join(deployApiDir, 'pokoin-assistant.js'), 'utf8');
    assistantSource = assistantSource
      .replaceAll("require('./_slug')", "require('../server/_slug')")
      .replaceAll('require("./_slug")', 'require("../server/_slug")');
    fs.writeFileSync(path.join(deployApiDir, 'pokoin-assistant.js'), assistantSource);

    const loaded = withStubbedExternalPackages(() => {
      const assistant = require(path.join(deployApiDir, 'pokoin-assistant.js'));
      return {
        assistant,
        firebase: assistant._test.loadFirebaseHelper(),
        email: assistant._test.loadEmailHelper(),
        marketplaceDb: assistant._test.loadMarketplaceDbHelper(),
      };
    });

    assert.equal(typeof loaded.assistant, 'function');
    assert.equal(typeof loaded.firebase.getFirebaseAdmin, 'function');
    assert.equal(typeof loaded.email.sendEmail, 'function');
    assert.equal(typeof loaded.marketplaceDb.marketplaceQuery, 'function');
  } finally {
    fs.rmSync(deployDir, { force: true, recursive: true });
  }
});

test('marketplace autocomplete resolves Supabase helper in deploy-pokoin-web output layout', () => {
  const deployDir = fs.mkdtempSync(path.join(os.tmpdir(), 'pokoin-web-deploy-'));
  try {
    const deployApiDir = path.join(deployDir, 'api');
    const deployServerDir = path.join(deployDir, 'server');
    fs.mkdirSync(deployApiDir);
    fs.mkdirSync(deployServerDir);

    for (const helper of deployHelpers) {
      copyApiFile(helper, deployServerDir);
    }
    for (const endpoint of [
      'marketplace-autocomplete',
      'marketplace-search-candidates',
      'searchbar-cards',
      'searchbar-token-predict',
    ]) {
      copyApiFile(endpoint, deployApiDir);
    }

    for (const endpoint of [
      'marketplace-autocomplete',
      'marketplace-search-candidates',
      'searchbar-cards',
      'searchbar-token-predict',
    ]) {
      const target = path.join(deployApiDir, `${endpoint}.js`);
      let source = fs.readFileSync(target, 'utf8');
      source = source
        .replaceAll("require('./_marketplace_db')", "require('../server/_marketplace_db')")
        .replaceAll('require("./_marketplace_db")', 'require("../server/_marketplace_db")')
        .replaceAll("require('./_marketplace_card_emoji')", "require('../server/_marketplace_card_emoji')")
        .replaceAll('require("./_marketplace_card_emoji")', 'require("../server/_marketplace_card_emoji")')
        .replaceAll("require('./_marketplace_card_rarity')", "require('../server/_marketplace_card_rarity')")
        .replaceAll('require("./_marketplace_card_rarity")', 'require("../server/_marketplace_card_rarity")')
        .replaceAll("require('./_marketplace_search_engine')", "require('../server/_marketplace_search_engine')")
        .replaceAll('require("./_marketplace_search_engine")', 'require("../server/_marketplace_search_engine")')
        .replaceAll("require('./_meili_marketplace')", "require('../server/_meili_marketplace')")
        .replaceAll('require("./_meili_marketplace")', 'require("../server/_meili_marketplace")')
        .replaceAll("require('./_meili_client')", "require('../server/_meili_client')")
        .replaceAll('require("./_meili_client")', 'require("../server/_meili_client")')
        .replaceAll("require('./_firebase')", "require('../server/_firebase')")
        .replaceAll('require("./_firebase")', 'require("../server/_firebase")')
        .replaceAll("require('./_supabase')", "require('../server/_supabase')")
        .replaceAll('require("./_supabase")', 'require("../server/_supabase")')
        .replaceAll("require('./_search_debug_auth')", "require('../server/_search_debug_auth')")
        .replaceAll('require("./_search_debug_auth")', 'require("../server/_search_debug_auth")')
        .replaceAll("require('./_searchbar_session')", "require('../server/_searchbar_session')")
        .replaceAll('require("./_searchbar_session")', 'require("../server/_searchbar_session")');
      fs.writeFileSync(target, source);
    }

    assert.equal(fs.existsSync(path.join(deployServerDir, '_supabase.js')), true);
    assert.equal(fs.existsSync(path.join(deployServerDir, '_marketplace_card_rarity.js')), true);
    const autocompleteSource = fs.readFileSync(
      path.join(deployApiDir, 'marketplace-autocomplete.js'),
      'utf8',
    );
    assert.match(autocompleteSource, /require\(['"]\.\.\/server\/_supabase['"]\)/);
    assert.doesNotMatch(autocompleteSource, /require\(['"]\.\/_supabase['"]\)/);

    const loaded = withStubbedExternalPackages(() => ({
      autocomplete: require(path.join(deployApiDir, 'marketplace-autocomplete.js')),
      searchbar: require(path.join(deployApiDir, 'searchbar-cards.js')),
      tokenPredict: require(path.join(deployApiDir, 'searchbar-token-predict.js')),
    }));

    assert.equal(typeof loaded.autocomplete, 'function');
    assert.equal(typeof loaded.searchbar, 'function');
    assert.equal(typeof loaded.tokenPredict, 'function');
  } finally {
    fs.rmSync(deployDir, { force: true, recursive: true });
  }
});

test('marketplace artist APIs resolve display helper in deploy-pokoin-web output layout', () => {
  const deployDir = fs.mkdtempSync(path.join(os.tmpdir(), 'pokoin-web-deploy-'));
  try {
    const deployApiDir = path.join(deployDir, 'api');
    const deployServerDir = path.join(deployDir, 'server');
    fs.mkdirSync(deployApiDir);
    fs.mkdirSync(deployServerDir);

    for (const helper of deployHelpers) {
      copyApiFile(helper, deployServerDir);
    }
    for (const endpoint of [
      'marketplace-artist-cards',
      'marketplace-artist-suggestions',
    ]) {
      copyApiFile(endpoint, deployApiDir);
      const target = path.join(deployApiDir, `${endpoint}.js`);
      let source = fs.readFileSync(target, 'utf8');
      source = source
        .replaceAll("require('./_marketplace_db')", "require('../server/_marketplace_db')")
        .replaceAll('require("./_marketplace_db")', 'require("../server/_marketplace_db")')
        .replaceAll("require('./_marketplace_card_emoji')", "require('../server/_marketplace_card_emoji')")
        .replaceAll('require("./_marketplace_card_emoji")', 'require("../server/_marketplace_card_emoji")')
        .replaceAll("require('./_marketplace_card_rarity')", "require('../server/_marketplace_card_rarity')")
        .replaceAll('require("./_marketplace_card_rarity")', 'require("../server/_marketplace_card_rarity")')
        .replaceAll("require('./_artist_display')", "require('../server/_artist_display')")
        .replaceAll('require("./_artist_display")', 'require("../server/_artist_display")');
      fs.writeFileSync(target, source);
    }

    const artistCardsSource = fs.readFileSync(
      path.join(deployApiDir, 'marketplace-artist-cards.js'),
      'utf8',
    );
    const artistSuggestionsSource = fs.readFileSync(
      path.join(deployApiDir, 'marketplace-artist-suggestions.js'),
      'utf8',
    );
    assert.match(artistCardsSource, /require\(['"]\.\.\/server\/_artist_display['"]\)/);
    assert.match(artistSuggestionsSource, /require\(['"]\.\.\/server\/_artist_display['"]\)/);
    assert.doesNotMatch(artistCardsSource, /require\(['"]\.\/_artist_display['"]\)/);
    assert.doesNotMatch(artistSuggestionsSource, /require\(['"]\.\/_artist_display['"]\)/);

    const loaded = withStubbedExternalPackages(() => ({
      artistCards: require(path.join(deployApiDir, 'marketplace-artist-cards.js')),
      artistSuggestions: require(path.join(deployApiDir, 'marketplace-artist-suggestions.js')),
    }));

    assert.equal(typeof loaded.artistCards, 'function');
    assert.equal(typeof loaded.artistSuggestions, 'function');
  } finally {
    fs.rmSync(deployDir, { force: true, recursive: true });
  }
});

test('deploy config exposes flutter debug logs as a Vercel function route', () => {
  const deployScript = fs.readFileSync(path.join(rootDir, 'deploy-pokoin-web.sh'), 'utf8');
  const vercelConfig = JSON.parse(fs.readFileSync(path.join(rootDir, 'vercel.json'), 'utf8'));
  const { routeDefinitions } = require('../server/api-route-manifest');

  assert.match(deployScript, /\bflutter-debug-logs\b/);
  assert.equal(
    vercelConfig.rewrites.some((rewrite) => (
      rewrite.source === '/api/flutter-debug-logs' &&
      rewrite.destination === '/api/flutter-debug-logs.js'
    )),
    true,
  );
  assert.equal(
    routeDefinitions.some((route) => (
      route.path === '/api/flutter-debug-logs' &&
      route.file === 'flutter-debug-logs.js'
    )),
    true,
  );
});

test('critical marketplace and assistant APIs are deploy-packaged manifest routes', () => {
  for (const route of [
    ['/api/cardtrader-blueprint-listings', 'cardtrader-blueprint-listings.js'],
    ['/api/cardtrader-live-listings', 'cardtrader-live-listings.js'],
    ['/api/deck-card-version-lookup', 'deck-card-version-lookup.js'],
    ['/api/flutter-debug-logs', 'flutter-debug-logs.js'],
    ['/api/limitless-expansion-blueprints', 'limitless-expansion-blueprints.js'],
    ['/api/marketplace-autocomplete', 'marketplace-autocomplete.js'],
    ['/api/marketplace-blueprint-price', 'marketplace-blueprint-price.js'],
    ['/api/marketplace-card-cheapest-price', 'marketplace-card-cheapest-price.js'],
    ['/api/marketplace-card-url', 'marketplace-card-url.js'],
    ['/api/marketplace-cart', 'marketplace-cart.js'],
    ['/api/marketplace-home', 'marketplace-home.js'],
    ['/api/marketplace-listings', 'marketplace-listings.js'],
    ['/api/marketplace-orders', 'marketplace-orders.js'],
    ['/api/marketplace-search-candidates', 'marketplace-search-candidates.js'],
    ['/api/marketplace-watchlist', 'marketplace-watchlist.js'],
    ['/api/pokoin-assistant', 'pokoin-assistant.js'],
    ['/api/user-current-page', 'user-current-page.js'],
  ]) {
    assertApiRoutePackaged(route[0], route[1]);
  }
});

test('fallback Vercel packaging includes seller comment helper', () => {
  const deployScript = fs.readFileSync(path.join(rootDir, 'deploy-pokoin-web.sh'), 'utf8');

  assert.match(deployScript, /\b_seller_comment_filter\b/);
  assert.match(deployScript, /require\('\.\.\/server\/_seller_comment_filter'\)/);
  assert.match(deployScript, /server\/_seller_comment_filter\.js/);
});

test('fallback serverless route sources cover manifest endpoints', () => {
  const deployScript = fs.readFileSync(path.join(rootDir, 'deploy-pokoin-web.sh'), 'utf8');
  const vercelConfig = JSON.parse(fs.readFileSync(path.join(rootDir, 'vercel.json'), 'utf8'));
  const { routeDefinitions } = require('../server/api-route-manifest');
  const copiedEndpoints = copiedEndpointNames();
  const rewriteSources = new Set(
    vercelConfig.rewrites
      .filter((rewrite) => String(rewrite.destination || '').startsWith('/api/'))
      .map((rewrite) => rewrite.source),
  );

  for (const route of routeDefinitions) {
    const endpointName = route.file.replace(/\.js$/, '');
    if (!route.path.includes('/:')) {
      assert.equal(copiedEndpoints.has(endpointName), true, `${endpointName} is copied by deploy`);
    }
    assert.equal(rewriteSources.has(route.path), true, `${route.path} has a Vercel fallback rewrite`);
    assert.match(deployScript, new RegExp(`\\b${endpointName}\\b`), `${endpointName} is referenced by deploy`);
  }
});

test('marketplace card SEO rewrite avoids repeated wildcard destination params', () => {
  const vercelConfig = JSON.parse(fs.readFileSync(path.join(rootDir, 'vercel.json'), 'utf8'));
  const cardRewrite = vercelConfig.rewrites.find((rewrite) => (
    String(rewrite.destination || '').includes('/api/marketplace-card-seo.js') &&
    String(rewrite.destination || '').includes('cardPath=')
  ));

  assert.ok(cardRewrite);
  assert.equal(cardRewrite.source, '/marketplace/:language/cards/:cardId/:cardSlug');
  assert.equal(
    cardRewrite.destination,
    '/api/marketplace-card-seo.js?language=:language&cardPath=:cardId/:cardSlug',
  );
  assert.doesNotMatch(cardRewrite.destination, /:cardPath\*/);
});

test('web deploy runs post-deploy URL and production alias verification', () => {
  const deployScript = fs.readFileSync(path.join(rootDir, 'deploy-pokoin-web.sh'), 'utf8');
  const verifier = require('../scripts/verify-production-aliases');

  assert.match(deployScript, /verify-production-aliases\.js/);
  assert.match(deployScript, /--skip-aliases/);
  assert.match(deployScript, /--set-aliases/);
  assert.deepEqual(verifier.DEPLOYMENT_HEALTH_CHECKS.map((check) => check.path), [
    '/',
    '/marketplace',
    verifier.REPRESENTATIVE_CARD_ROUTE,
    '/api/marketplace-home',
  ]);
  assert.equal(
    verifier.DEPLOYMENT_HEALTH_CHECKS.find((check) => check.path === '/api/marketplace-home')?.expect,
    'json',
  );
  for (const alias of [
    'pokoin.com',
    'www.pokoin.com',
    'wallet.pokoin.com',
    'forum.pokoin.com',
    'cards.pokoin.com',
    'cardcaveau.pokoin.com',
    'cardvault.pokoin.com',
    'explorer.pokoin.com',
  ]) {
    assert.equal(verifier.PRODUCTION_ALIASES.includes(alias), true, `${alias} is verified`);
  }
});
