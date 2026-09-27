const assert = require('node:assert/strict');
const Module = require('node:module');
const test = require('node:test');

function loadHandler({ verify, usernameForRequest }) {
  const target = require.resolve('./ensure-username');
  const originalLoad = Module._load;
  delete require.cache[target];
  Module._load = function load(request) {
    if (request === '../server/_firebase') {
      return { getFirebaseAdmin: () => ({ firestore: () => ({}) }), verifyBearerToken: verify };
    }
    if (request === '../server/_username') {
      return { usernameForRequest };
    }
    return originalLoad.apply(this, arguments);
  };
  try {
    return require('./ensure-username');
  } finally {
    Module._load = originalLoad;
    delete require.cache[target];
  }
}

function recorder() {
  return {
    statusCode: 200,
    headers: {},
    body: undefined,
    setHeader(name, value) { this.headers[name] = value; },
    status(code) { this.statusCode = code; return this; },
    json(payload) { this.body = payload; return this; },
  };
}

test('ensure-username returns the registered name for the bearer', async () => {
  const calls = [];
  const handler = loadHandler({
    verify: async () => ({ uid: 'u1' }),
    usernameForRequest: async (args) => { calls.push(args); return 'pokoin'; },
  });
  const res = recorder();
  await handler({ method: 'POST', body: {} }, res);
  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body, { username: 'pokoin' });
  assert.equal(calls[0].decoded.uid, 'u1');
  assert.equal(calls[0].requestedUsername, undefined);
});

test('ensure-username passes the requested name and surfaces 409', async () => {
  const handler = loadHandler({
    verify: async () => ({ uid: 'u1' }),
    usernameForRequest: async ({ requestedUsername }) => {
      assert.equal(requestedUsername, 'luigi');
      throw Object.assign(new Error('Username is already taken.'), { statusCode: 409 });
    },
  });
  const res = recorder();
  await handler({ method: 'POST', body: { username: 'luigi' } }, res);
  assert.equal(res.statusCode, 409);
  assert.equal(res.body.error, 'Username is already taken.');
});

test('ensure-username needs POST and a bearer', async () => {
  const handler = loadHandler({
    verify: async () => { throw Object.assign(new Error('Missing Pokoin bearer token.'), { statusCode: 401 }); },
    usernameForRequest: async () => 'never',
  });
  const get = recorder();
  await handler({ method: 'GET' }, get);
  assert.equal(get.statusCode, 405);
  const anon = recorder();
  await handler({ method: 'POST', body: {} }, anon);
  assert.equal(anon.statusCode, 401);
});
