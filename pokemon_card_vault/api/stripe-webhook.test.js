const assert = require('node:assert/strict');
const Module = require('node:module');
const test = require('node:test');
const { Readable } = require('node:stream');

function loadWebhookWithStubs({ constructEvent, handleCompletedCheckout }) {
  const originalLoad = Module._load;
  const resolvedWebhook = require.resolve('./stripe-webhook.js');
  const resolvedPurchase = require.resolve('./_pkn_purchase.js');
  const resolvedFirebase = require.resolve('./_firebase.js');

  delete require.cache[resolvedWebhook];
  delete require.cache[resolvedPurchase];
  delete require.cache[resolvedFirebase];

  Module._load = function load(request, parent, isMain) {
    if (request === 'stripe') {
      return function Stripe() {
        return {
          webhooks: {
            constructEvent,
          },
        };
      };
    }
    if (request === resolvedPurchase || request.endsWith('/_pkn_purchase') || request.endsWith('/_pkn_purchase.js')) {
      return { handleCompletedCheckout };
    }
    if (request === resolvedFirebase || request.endsWith('/_firebase') || request.endsWith('/_firebase.js')) {
      return {
        getFirebaseAdmin: () => ({ firestore: () => ({}) }),
      };
    }
    // server re-exports
    if (String(request).includes('server/_pkn_purchase')) {
      return { handleCompletedCheckout };
    }
    if (String(request).includes('server/_firebase')) {
      return {
        getFirebaseAdmin: () => ({ firestore: () => ({}) }),
      };
    }
    return originalLoad.apply(this, arguments);
  };

  try {
    return require('./stripe-webhook.js');
  } finally {
    Module._load = originalLoad;
  }
}

function mockRes() {
  return {
    statusCode: 200,
    headers: {},
    body: null,
    writableEnded: false,
    setHeader(key, value) {
      this.headers[key] = value;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      this.writableEnded = true;
      return this;
    },
    send(payload) {
      this.body = payload;
      this.writableEnded = true;
      return this;
    },
    end(payload) {
      if (payload !== undefined) this.body = payload;
      this.writableEnded = true;
      return this;
    },
  };
}

test('stripe-webhook exports Vercel bodyParser:false config', () => {
  const previousSecret = process.env.STRIPE_SECRET_KEY;
  const previousWebhook = process.env.STRIPE_WEBHOOK_SECRET;
  process.env.STRIPE_SECRET_KEY = 'sk_test';
  process.env.STRIPE_WEBHOOK_SECRET = 'whsec_test';
  try {
    const handler = loadWebhookWithStubs({
      constructEvent: () => ({ type: 'ping', data: { object: {} } }),
      handleCompletedCheckout: async () => ({}),
    });
    assert.equal(handler.config.api.bodyParser, false);
  } finally {
    process.env.STRIPE_SECRET_KEY = previousSecret;
    process.env.STRIPE_WEBHOOK_SECRET = previousWebhook;
    delete require.cache[require.resolve('./stripe-webhook.js')];
  }
});

test('stripe-webhook prefers req.rawBody when present', async () => {
  const previousSecret = process.env.STRIPE_SECRET_KEY;
  const previousWebhook = process.env.STRIPE_WEBHOOK_SECRET;
  process.env.STRIPE_SECRET_KEY = 'sk_test';
  process.env.STRIPE_WEBHOOK_SECRET = 'whsec_test';

  const seen = [];
  const handler = loadWebhookWithStubs({
    constructEvent: (rawBody) => {
      seen.push(Buffer.isBuffer(rawBody) ? rawBody.toString('utf8') : String(rawBody));
      return {
        type: 'checkout.session.completed',
        data: { object: { id: 'cs_1', metadata: { uid: 'u', pknAmount: '1000' } } },
      };
    },
    handleCompletedCheckout: async () => ({ amountPkn: 1000 }),
  });

  const req = Readable.from([]);
  req.method = 'POST';
  req.headers = { 'stripe-signature': 'sig' };
  req.rawBody = Buffer.from('{"id":"evt_raw"}');
  const res = mockRes();

  try {
    await handler(req, res);
    assert.equal(res.statusCode, 200);
    assert.deepEqual(res.body, { received: true });
    assert.deepEqual(seen, ['{"id":"evt_raw"}']);
  } finally {
    process.env.STRIPE_SECRET_KEY = previousSecret;
    process.env.STRIPE_WEBHOOK_SECRET = previousWebhook;
    delete require.cache[require.resolve('./stripe-webhook.js')];
  }
});
