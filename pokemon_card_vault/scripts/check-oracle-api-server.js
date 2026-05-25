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
    assert.equal(health.statusCode, 200, 'healthz should return 200');
    assert.match(health.body, /pokoin-oracle-api/);

    const marketplace = await request({ server, method: 'GET', path: '/marketplace' });
    assert.equal(marketplace.statusCode, 200, 'marketplace staging page should return 200');
    assert.match(marketplace.body, /Oracle API staging endpoint/);

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

  console.log(`Validated ${routeDefinitions.length} Oracle API routes.`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
