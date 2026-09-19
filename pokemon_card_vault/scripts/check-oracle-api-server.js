const assert = require('assert');
const http = require('http');

const {
  createOracleApiServer,
  routeDefinitions,
  routeForPathname,
} = require('../server/oracle-api-server');

function request({ server, method, path, body, headers = {} }) {
  return new Promise((resolve, reject) => {
    const { port } = server.address();
    const payload = body == null ? null : Buffer.from(body);
    const req = http.request(
      {
        host: '127.0.0.1',
        port,
        path,
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

async function main() {
  const originalObservability = process.env.ORACLE_API_OBSERVABILITY;
  process.env.ORACLE_API_OBSERVABILITY = '0';
  try {
    for (const route of routeDefinitions) {
      const resolved = routeForPathname(route.path.replace('/:action', '/status'));
      assert.ok(resolved, `Route did not resolve: ${route.path}`);
      assert.equal(resolved.route.file, route.file, `Route resolved to wrong file: ${route.path}`);

      const handler = require(`../api/${route.file}`);
      assert.equal(typeof handler, 'function', `${route.file} does not export a function`);
    }

    assert.ok(routeForPathname('/api/stripe-webhook'), 'Stripe webhook route missing');
    assert.ok(routeForPathname('/api/stripe-webhook.js'), 'Vercel .js route compatibility missing');
    assert.ok(routeForPathname('/api/wpkn-exchange/quote'), 'Action route compatibility missing');

    const server = createOracleApiServer();
    await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
    try {
      const health = await request({ server, method: 'GET', path: '/healthz' });
      assert.ok([200, 503].includes(health.statusCode), 'healthz should return 200 or 503');
      const healthJson = JSON.parse(health.body);
      assert.equal(healthJson.service, 'pokoin-oracle-api');
      assert.equal(healthJson.ok, health.statusCode === 200);
      assert.equal(typeof healthJson.checks.postgres.ok, 'boolean');
      assert.equal(typeof healthJson.checks.valkey.ok, 'boolean');
      assert.equal(typeof healthJson.checks.meili.ok, 'boolean');
      assert.equal(typeof healthJson.checks.cdn.ok, 'boolean');
      if (health.statusCode === 503) {
        assert.equal(healthJson.checks.postgres.ok, false);
      }

      const contract = await request({ server, method: 'GET', path: '/api/__contract' });
      assert.equal(contract.statusCode, 200, '__contract should return 200');
      const contractJson = JSON.parse(contract.body);
      assert.equal(contractJson.hosts.api, 'https://api.pokoin.com');
      assert.equal(contractJson.identity.decision, 'Codevira D00000B');
      assert.equal(contractJson.images.r2KeyPrefix, 'ct_id');
      assert.equal(contractJson.availability.serverOwnsFlag, true);
      assert.equal(contractJson.navigation.routesGrouped, 'GET /api/__routes?group=1');

      const routes = await request({ server, method: 'GET', path: '/api/__routes' });
      assert.equal(routes.statusCode, 200, '__routes should return 200');
      const routesJson = JSON.parse(routes.body);
      assert.ok(Array.isArray(routesJson.routes), '__routes.routes should be an array');
      const expansion = routesJson.routes.find((row) => row.path === '/api/marketplace-expansion-page');
      assert.equal(expansion.family, 'page-bff');

      const grouped = await request({ server, method: 'GET', path: '/api/__routes?group=1' });
      assert.equal(grouped.statusCode, 200, '__routes?group=1 should return 200');
      const groupedJson = JSON.parse(grouped.body);
      assert.ok(Array.isArray(groupedJson.families));
      assert.ok(groupedJson.families.some((row) => row.id === 'page-bff' && row.routes.length));

      const root = await request({ server, method: 'GET', path: '/' });
      assert.equal(root.statusCode, 200, 'API origin / should return the operator landing page, not 404');
      assert.match(root.body, /Pokoin Oracle API/);
      assert.match(root.body, /marketplace-suggest/);

      const marketplace = await request({ server, method: 'GET', path: '/marketplace' });
      assert.equal(marketplace.statusCode, 200, 'marketplace landing page should return 200');
      assert.match(marketplace.body, /Pokoin Oracle API/);

      const missing = await request({ server, method: 'GET', path: '/api/not-a-route' });
      assert.equal(missing.statusCode, 404, 'missing route should return 404');

      const json = await request({
        server,
        method: 'POST',
        path: '/api/auth-login',
        body: '{not-json',
        headers: { 'content-type': 'application/json' },
      });
      assert.equal(json.statusCode, 400, 'invalid JSON should fail before handler');

      const stripe = await request({
        server,
        method: 'GET',
        path: '/api/stripe-webhook',
      });
      assert.equal(stripe.statusCode, 405, 'Stripe webhook should be loadable and preserve method guard');
    } finally {
      await new Promise((resolve) => server.close(resolve));
    }
  } finally {
    if (originalObservability === undefined) {
      delete process.env.ORACLE_API_OBSERVABILITY;
    } else {
      process.env.ORACLE_API_OBSERVABILITY = originalObservability;
    }
  }

  console.log(`Validated ${routeDefinitions.length} Oracle API routes.`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
