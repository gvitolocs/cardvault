'use strict';

const assert = require('node:assert/strict');
const http = require('node:http');
const test = require('node:test');
const { CLIENT_CONTRACT, buildClientContract } = require('./_client_contract');
const { routeDefinitions } = require('../server/api-route-manifest');
const { familyForPath } = require('../server/api-route-families');

test('contract derives every installed route and its count from the manifest', () => {
  assert.equal(CLIENT_CONTRACT.version, '2026-10-01.1');
  assert.equal(CLIENT_CONTRACT.routeCount, routeDefinitions.length);
  assert.deepEqual(CLIENT_CONTRACT.routes.map((route) => route.path), routeDefinitions.map((route) => route.path));
  for (const [index, route] of CLIENT_CONTRACT.routes.entries()) {
    const source = routeDefinitions[index];
    assert.deepEqual(route.methods, source.methods);
    assert.equal(route.family, familyForPath(source.path));
    assert.equal(route.auth, source.auth);
    assert.deepEqual(route.params, source.params || {});
  }
});

test('custom manifests change the inventory without publishing implementation dependencies', () => {
  const source = {
    path: '/api/example', methods: ['POST'], purpose: 'Example', auth: 'Required.',
    params: { body: 'Example body' }, rawBody: true, file: 'private-handler.js',
    dependencies: { env: ['PRIVATE_KEY'], services: ['Private service'] },
  };
  const result = buildClientContract([source]);
  assert.equal(result.routeCount, 1);
  assert.equal(result.routes[0].rawBody, true);
  assert.equal(result.routes[0].file, undefined);
  assert.equal(result.routes[0].dependencies, undefined);
  result.routes[0].methods.push('GET');
  result.routes[0].params.body = 'Changed';
  assert.deepEqual(source.methods, ['POST']);
  assert.equal(source.params.body, 'Example body');
});

test('empty manifests do not retain the old frozen route count', () => {
  const result = buildClientContract([]);
  assert.equal(result.routeCount, 0);
  assert.deepEqual(result.routes, []);
});

test('independent contract builds do not share mutable reference fields', () => {
  const first = buildClientContract();
  first.hosts.api = 'changed';
  first.search.notes.push('changed');
  const second = buildClientContract();
  assert.equal(second.hosts.api, 'https://api.pokoin.com');
  assert.ok(!second.search.notes.includes('changed'));
});

test('generated JSON documentation equals the local runtime contract', () => {
  assert.deepEqual(require('../docs/react-api-contract.json'), CLIENT_CONTRACT);
});

test('public GET contract and route introspection describe the same local release', async () => {
  const { createOracleApiServer } = require('../server/oracle-api-server');
  const server = createOracleApiServer();
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const read = (path) => new Promise((resolve, reject) => {
    const req = http.get({ hostname: '127.0.0.1', port: server.address().port, path }, (res) => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => resolve({ status: res.statusCode, contentType: res.headers['content-type'], body: JSON.parse(body) }));
    });
    req.on('error', reject);
  });
  try {
    const contract = await read('/api/__contract');
    const routes = await read('/api/__routes');
    assert.equal(contract.status, 200);
    assert.match(contract.contentType, /application\/json/);
    assert.deepEqual(contract.body, CLIENT_CONTRACT);
    assert.equal(contract.body.routeCount, routes.body.count);
    assert.deepEqual(contract.body.routes.map((route) => route.path), routes.body.routes.map((route) => route.path));
  } finally {
    await new Promise((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  }
});
