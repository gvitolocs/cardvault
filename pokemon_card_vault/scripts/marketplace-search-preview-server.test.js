'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const { createPreviewHandler } = require('./marketplace-search-preview-server');

test('preview forwards quick searches without auth/debug or write access', async (t) => {
  const calls = [];
  const server = http.createServer(createPreviewHandler({
    read: async (path, body) => {
      calls.push({ path, body });
      return path.includes('autocomplete')
        ? { rows: [{ card_id: 42, name: 'Pikachu' }] }
        : { predictions: [{ display: 'Pikachu' }] };
    },
  }));
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise((resolve) => server.close(resolve)));
  const base = `http://127.0.0.1:${server.address().port}`;
  const post = (path, body) => fetch(`${base}${path}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: 'Bearer do-not-forward' },
    body: JSON.stringify(body),
  });
  const response = await post('/api/marketplace-autocomplete', {
    search_term: 'Pikachu', result_limit: 8, pool_limit: 999999,
    search_language: 'en', debug: true, token: 'do-not-forward',
    search_session_id: 'private-session',
  });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('access-control-allow-origin'), '*');
  assert.equal((await response.json()).rows[0].name, 'Pikachu');
  assert.deepEqual(calls[0].body, {
    search_term: 'Pikachu', result_limit: 8, pool_limit: 15874,
    search_language: 'en', preview_mode: '',
  });
  const prediction = await post('/api/searchbar-token-predict', {
    query: 'Pika', limit: 100, search_language: 'en', debug: true,
  });
  assert.equal(prediction.status, 200);
  assert.deepEqual(calls[1].body, { query: 'Pika', limit: 5, search_language: 'en' });
  assert.equal((await post('/api/cart', {})).status, 405);
  assert.equal(calls.length, 2);
  const preflight = await fetch(`${base}/api/marketplace-autocomplete`, { method: 'OPTIONS' });
  assert.equal(preflight.status, 204);
});
