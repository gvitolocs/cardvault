const assert = require('assert');
const fs = require('fs');
const http = require('http');
const path = require('path');

const { createOracleApiServer, routeDefinitions } = require('../server/oracle-api-server');

const RESULT_PATH = path.join(__dirname, '..', 'build', 'oracle-api-smoke-results.json');

const SAFE_JSON_HEADERS = { 'content-type': 'application/json' };

const DIRECT_ENV_NAMES = new Set([
  'CARDTRADER_TOKEN_ENCRYPTION_KEY',
  'CLOUDFLARE_ACCOUNT_ID',
  'CRYPTO_PKN_AUTO_PAYOUT_ENABLED',
  'CRYPTO_PKN_SELL_ENABLED',
  'FIREBASE_CLIENT_EMAIL',
  'FIREBASE_PRIVATE_KEY',
  'FIREBASE_PROJECT_ID',
  'FIREBASE_STORAGE_BUCKET',
  'MARKETPLACE_ADMIN_EMAILS',
  'MARKETPLACE_ANALYTICS_SEARCH_REPLICA_URLS',
  'MARKETPLACE_DATABASE_URL',
  'MARKETPLACE_DEBUG_EMAILS',
  'MARKETPLACE_DIMENSION_SEARCH_TIMEOUT_MS',
  'MARKETPLACE_EXPANSION_SEARCH_DATABASE_URL',
  'MARKETPLACE_NAME_SEARCH_CIRCUIT_MS',
  'MARKETPLACE_NAME_SEARCH_DATABASE_URL',
  'MARKETPLACE_NAME_SEARCH_TIMEOUT_MS',
  'MARKETPLACE_NUMBER_SEARCH_DATABASE_URL',
  'MARKETPLACE_PEER1_DATABASE_URL',
  'MARKETPLACE_PEER2_DATABASE_URL',
  'MARKETPLACE_PEER3_DATABASE_URL',
  'MARKETPLACE_PEER4_DATABASE_URL',
  'MARKETPLACE_PREDICTIVE_POOL_ENABLED',
  'MARKETPLACE_PREDICTIVE_POOL_STRICT',
  'MARKETPLACE_RARITY_SEARCH_DATABASE_URL',
  'MARKETPLACE_SHORT_PREFIX_ANALYTICS_MAX_DEPTH',
  'MARKETPLACE_VARIATION_OWNER_SEARCH_DATABASE_URL',
  'MARKETPLACE_VARIATION_SEARCH_DATABASE_URL',
  'MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS',
  'ORACLE_API_HOST',
  'ORACLE_API_JSON_LIMIT_BYTES',
  'ORACLE_API_PORT',
  'PENDING_SIGNUP_SECRET',
  'PKN_CHECKOUT_CURRENCY',
  'PKN_CHECKOUT_USDT_PRICE',
  'POKOIN_ASSISTANT_EMAIL',
  'POKOIN_ASSISTANT_FROM',
  'POKOIN_BANK_ADDRESS',
  'POKOIN_BANK_PRIVATE_KEY',
  'POKOIN_RESERVE_ADDRESS',
  'POKOIN_RESERVE_PRIVATE_KEY',
  'POKOIN_RPC_URL',
  'POKONTACT_SERVICE_TIMEOUT_MS',
  'POKONTACT_SERVICE_TOKEN',
  'POKONTACT_SERVICE_URL',
  'PUBLIC_SITE_URL',
  'R2_ACCESS_KEY_ID',
  'R2_FORUM_MEDIA_BUCKET',
  'R2_FORUM_MEDIA_PUBLIC_URL',
  'R2_PROFILE_PICTURES_BUCKET',
  'R2_PROFILE_PICTURES_PUBLIC_URL',
  'R2_SECRET_ACCESS_KEY',
  'RESEND_API_KEY',
  'STRIPE_API_VERSION',
  'STRIPE_SECRET_KEY',
  'STRIPE_WEBHOOK_SECRET',
  'SUPABASE_ANON_KEY',
  'SUPABASE_DB_POOLER_URL',
  'SUPABASE_DB_URL',
  'SUPABASE_NAME_INDEX_DATABASE_URL',
  'SUPABASE_SERVICE_ROLE_KEY',
  'SUPABASE_URL',
]);

const SAFE_TEST_ENV = {
  STRIPE_SECRET_KEY: 'sk_test_oracle_smoke_not_secret',
  STRIPE_WEBHOOK_SECRET: 'whsec_oracle_smoke_not_secret',
  PUBLIC_SITE_URL: 'https://pokoin.com',
};

function setSafeDefaults() {
  const originals = {};
  for (const [key, value] of Object.entries(SAFE_TEST_ENV)) {
    originals[key] = process.env[key];
    if (!process.env[key]) {
      process.env[key] = value;
    }
  }
  return () => {
    for (const [key, value] of Object.entries(originals)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  };
}

function missingEnvNames() {
  return [...DIRECT_ENV_NAMES].filter((name) => !process.env[name]).sort();
}

function request(server, { method, pathname, body, headers = {} }) {
  return new Promise((resolve, reject) => {
    const { port } = server.address();
    const payload = body == null ? null : Buffer.isBuffer(body) ? body : Buffer.from(String(body));
    const req = http.request(
      {
        host: '127.0.0.1',
        port,
        path: pathname,
        method,
        headers: {
          ...(payload ? { 'content-length': String(payload.length) } : {}),
          ...headers,
        },
      },
      (res) => {
        const chunks = [];
        res.on('data', (chunk) => chunks.push(chunk));
        res.on('end', () => {
          resolve({
            statusCode: res.statusCode,
            headers: res.headers,
            body: Buffer.concat(chunks).toString('utf8'),
          });
        });
      },
    );
    req.on('error', reject);
    if (payload) req.write(payload);
    req.end();
  });
}

function pathForRoute(route, action = 'status') {
  return route.path.replace(':action', action);
}

function primaryCase(route) {
  switch (route.file) {
    case 'auth-login.js':
      return post(route, {});
    case 'cache-google-profile-picture.js':
      return post(route, {});
    case 'cardmarket-redirect.js':
      return get(route, '?format=json');
    case 'cardmarket-scrape-observation.js':
      return post(route, {});
    case 'cardtrader-connect.js':
      return post(route, { token: 'not-a-real-token' });
    case 'cardtrader-redirect.js':
      return get(route);
    case 'create-pkn-checkout-session.js':
      return post(route, { pknAmount: 1000, fiatCents: 500, lookupKey: 'pkn_starter_1000_pkn_500_eur' });
    case 'crypto-pkn-purchase.js':
    case 'crypto-pkn-sale.js':
    case 'wpkn-exchange.js':
      return get(route, '?requestId=smoke-test', 'status');
    case 'extension-card-search.js':
      return post(route, { query: '', limit: 1 });
    case 'forum.js':
      return get(route, '?mode=topic&id=not-a-uuid');
    case 'forum-upload-media.js':
      return post(route, { imageBase64: '', topicId: 'not-a-uuid' });
    case 'marketplace-blueprint-price.js':
      return get(route);
    case 'marketplace-card-cheapest-price.js':
      return get(route, '?cardId=0');
    case 'marketplace-card-sales.js':
      return get(route);
    case 'marketplace-card-shortlink.js':
      return get(route);
    case 'marketplace-card-url.js':
      return get(route, '?cardId=0');
    case 'marketplace-event.js':
      return post(route, { cardId: 0, eventType: 'invalid' });
    case 'marketplace-listings.js':
      return get(route, '?cardId=not-a-card');
    case 'marketplace-orders.js':
      return post(route, { items: [], subtotalPkn: 0, totalPkn: 0 });
    case 'pokoin-assistant.js':
      return post(route, { message: '' });
    case 'register-email.js':
      return post(route, { email: '', password: '' });
    case 'search-recipient-emails.js':
      return get(route, '?q=ab');
    case 'searchbar-cancel.js':
      return post(route, { search_session_id: 'smoke-test' });
    case 'searchbar-cards.js':
      return get(route, '?query=&limit=1');
    case 'searchbar-token-predict.js':
      return get(route, '?query=&limit=1');
    case 'stripe-webhook.js':
      return {
        name: 'primary',
        method: 'POST',
        pathname: pathForRoute(route),
        body: Buffer.from('{"smoke":true}'),
        headers: { 'content-type': 'application/json' },
        expected: [400],
        mode: 'raw-body-error-path',
      };
    case 'verify-email-signup.js':
      return post(route, { token: '' });
    case 'wallet-auth-nonce.js':
      return post(route, { address: 'not-a-wallet' });
    default:
      if (route.methods.includes('GET')) return get(route);
      if (route.methods.includes('POST')) return post(route, {});
      if (route.methods.includes('DELETE')) return del(route);
      return {
        name: 'primary',
        method: route.methods[0] || 'GET',
        pathname: pathForRoute(route),
        expected: acceptableStatuses(route),
        mode: 'safe-error-path',
      };
  }
}

function get(route, query = '', action = 'status') {
  return {
    name: 'primary',
    method: 'GET',
    pathname: `${pathForRoute(route, action)}${query}`,
    expected: acceptableStatuses(route),
    mode: 'safe-read-or-error-path',
  };
}

function post(route, payload = {}, action = 'status') {
  return {
    name: 'primary',
    method: 'POST',
    pathname: pathForRoute(route, action),
    body: JSON.stringify(payload),
    headers: SAFE_JSON_HEADERS,
    expected: acceptableStatuses(route),
    mode: 'safe-error-path',
  };
}

function del(route) {
  return {
    name: 'primary',
    method: 'DELETE',
    pathname: pathForRoute(route),
    expected: acceptableStatuses(route),
    mode: 'safe-error-path',
  };
}

function optionsCase(route) {
  if (!route.methods.includes('OPTIONS')) return null;
  return {
    name: 'options',
    method: 'OPTIONS',
    pathname: pathForRoute(route),
    expected: [200, 204],
    mode: 'cors-preflight',
  };
}

function methodGuardCase(route) {
  return {
    name: 'method-guard',
    method: 'PUT',
    pathname: pathForRoute(route),
    body: JSON.stringify({ smoke: true }),
    headers: SAFE_JSON_HEADERS,
    expected: acceptableStatuses(route),
    mode: 'method-guard',
  };
}

function acceptableStatuses(route) {
  const statuses = new Set([200, 201, 204, 302, 400, 401, 403, 404, 405, 409, 413, 500, 503]);
  if (route.file === 'stripe-webhook.js') statuses.delete(500);
  return [...statuses].sort((a, b) => a - b);
}

function classify(statusCode) {
  if ([200, 201, 204, 302].includes(statusCode)) return 'ok';
  if ([400, 401, 403, 404, 405, 409, 413].includes(statusCode)) return 'safe_error_path';
  if ([500, 503].includes(statusCode)) return 'env_or_dependency_limited';
  return 'unexpected_status';
}

function assertStripeRawBodyResult(result) {
  assert.equal(result.statusCode, 400, 'Stripe webhook should return missing-signature 400');
  assert.match(
    result.body,
    /signature|Webhook Error/i,
    'Stripe webhook did not reach signature validation error path',
  );
}

async function runCase(server, route, testCase) {
  const response = await request(server, testCase);
  const passed = testCase.expected.includes(response.statusCode);
  if (passed && route.file === 'stripe-webhook.js' && testCase.mode === 'raw-body-error-path') {
    assertStripeRawBodyResult(response);
  }
  return {
    route: route.path,
    file: route.file,
    test: testCase.name,
    method: testCase.method,
    path: testCase.pathname,
    statusCode: response.statusCode,
    class: classify(response.statusCode),
    mode: testCase.mode,
    passed,
  };
}

async function main() {
  const restoreEnv = setSafeDefaults();
  const unhandled = [];
  const unhandledRejection = (reason) => unhandled.push({ type: 'unhandledRejection', reason: String(reason?.message || reason) });
  const uncaughtException = (error) => unhandled.push({ type: 'uncaughtException', reason: String(error?.message || error) });
  process.on('unhandledRejection', unhandledRejection);
  process.on('uncaughtException', uncaughtException);

  const server = createOracleApiServer();
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));

  const originalError = console.error;
  const originalWarn = console.warn;
  console.error = () => {};
  console.warn = () => {};

  const results = [];
  try {
    const health = await request(server, { method: 'GET', pathname: '/healthz' });
    results.push({
      route: '/healthz',
      file: 'server',
      test: 'health',
      method: 'GET',
      path: '/healthz',
      statusCode: health.statusCode,
      class: classify(health.statusCode),
      mode: 'health',
      passed: health.statusCode === 200,
    });

    for (const route of routeDefinitions) {
      const tests = [primaryCase(route), optionsCase(route), methodGuardCase(route)].filter(Boolean);
      for (const testCase of tests) {
        try {
          results.push(await runCase(server, route, testCase));
        } catch (error) {
          results.push({
            route: route.path,
            file: route.file,
            test: testCase.name,
            method: testCase.method,
            path: testCase.pathname,
            statusCode: null,
            class: 'request_failed',
            mode: testCase.mode,
            passed: false,
            error: error.message,
          });
        }
      }
    }
  } finally {
    console.error = originalError;
    console.warn = originalWarn;
    await new Promise((resolve) => server.close(resolve));
    process.off('unhandledRejection', unhandledRejection);
    process.off('uncaughtException', uncaughtException);
    restoreEnv();
  }

  await new Promise((resolve) => setImmediate(resolve));

  const byClass = results.reduce((acc, result) => {
    acc[result.class] = (acc[result.class] || 0) + 1;
    return acc;
  }, {});
  const failed = results.filter((result) => !result.passed);
  const routeCount = new Set(results.filter((result) => result.file !== 'server').map((result) => result.file)).size;
  const summary = {
    generatedAt: new Date().toISOString(),
    routeCount,
    manifestRouteCount: routeDefinitions.length,
    testCount: results.length,
    passedCount: results.length - failed.length,
    failedCount: failed.length,
    byClass,
    missingEnvNames: missingEnvNames(),
    unhandled,
    failed,
    results,
  };

  fs.mkdirSync(path.dirname(RESULT_PATH), { recursive: true });
  fs.writeFileSync(RESULT_PATH, JSON.stringify(summary, null, 2) + '\n');

  console.log(JSON.stringify({
    routeCount: summary.routeCount,
    testCount: summary.testCount,
    passedCount: summary.passedCount,
    failedCount: summary.failedCount,
    byClass: summary.byClass,
    missingEnvNames: summary.missingEnvNames,
    unhandledCount: unhandled.length,
    resultPath: path.relative(path.join(__dirname, '..'), RESULT_PATH),
  }, null, 2));

  if (failed.length > 0 || unhandled.length > 0) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
