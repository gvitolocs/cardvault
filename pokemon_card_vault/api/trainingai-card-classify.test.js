const assert = require('node:assert/strict');
const test = require('node:test');

const handler = require('./trainingai-card-classify');

function mockResponse() {
  const headers = {};
  return {
    statusCode: 200,
    body: undefined,
    headers,
    setHeader(key, value) {
      headers[key.toLowerCase()] = value;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
    end(payload = '') {
      this.body = payload;
      return this;
    },
  };
}

async function withEnv(values, callback) {
  const previous = {};
  for (const key of Object.keys(values)) {
    previous[key] = process.env[key];
    if (values[key] == null) {
      delete process.env[key];
    } else {
      process.env[key] = values[key];
    }
  }
  try {
    return await callback();
  } finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value == null) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  }
}

test('trainingai classifier route rejects missing image data', async () => {
  await withEnv({ TRAININGAI_HF_SPACE_URL: 'https://example.hf.space' }, async () => {
    const res = mockResponse();
    await handler({ method: 'POST', body: {} }, res);

    assert.equal(res.statusCode, 400);
    assert.equal(res.body.ok, false);
    assert.match(res.body.error, /imageBase64/);
  });
});

test('trainingai classifier route reports missing space config', async () => {
  await withEnv({ TRAININGAI_HF_SPACE_URL: '' }, async () => {
    const res = mockResponse();
    await handler({
      method: 'POST',
      body: {
        imageBase64: Buffer.from('not really an image').toString('base64'),
      },
    }, res);

    assert.equal(res.statusCode, 503);
    assert.equal(res.body.setupRequired, true);
  });
});

test('trainingai classifier route proxies base64 payload to space', async () => {
  await withEnv({
    TRAININGAI_HF_SPACE_URL: 'https://classifier.example',
    TRAININGAI_HF_TOKEN: 'secret',
  }, async () => {
    const previousFetch = global.fetch;
    try {
      global.fetch = async (url, options) => {
        assert.equal(url, 'https://classifier.example/classify/base64');
        assert.equal(options.method, 'POST');
        assert.equal(options.headers.Authorization, 'Bearer secret');
        const body = JSON.parse(options.body);
        assert.equal(body.topK, 2);
        assert.equal(body.imageBase64, Buffer.from('image').toString('base64'));
        return {
          ok: true,
          status: 200,
          async text() {
            return JSON.stringify({
              ok: true,
              results: [{ rank: 1, score: 0.9, cardPath: 'cards/base1/4.png' }],
            });
          },
        };
      };

      const res = mockResponse();
      await handler({
        method: 'POST',
        body: {
          imageBase64: `data:image/png;base64,${Buffer.from('image').toString('base64')}`,
          topK: 2,
        },
      }, res);

      assert.equal(res.statusCode, 200);
      assert.equal(res.body.ok, true);
      assert.equal(res.body.results[0].cardPath, 'cards/base1/4.png');
    } finally {
      global.fetch = previousFetch;
    }
  });
});

test('trainingai classifier route proxies multipart payload to space', async () => {
  await withEnv({
    TRAININGAI_HF_SPACE_URL: 'https://classifier.example',
  }, async () => {
    const previousFetch = global.fetch;
    try {
      const body = Buffer.from('multipart-body');
      global.fetch = async (url, options) => {
        assert.equal(url, 'https://classifier.example/classify');
        assert.equal(options.method, 'POST');
        assert.equal(options.headers['Content-Type'], 'multipart/form-data; boundary=x');
        assert.deepEqual(options.body, body);
        return {
          ok: true,
          status: 200,
          async text() {
            return JSON.stringify({ ok: true, results: [] });
          },
        };
      };

      const res = mockResponse();
      await handler({
        method: 'POST',
        headers: { 'content-type': 'multipart/form-data; boundary=x' },
        body,
      }, res);

      assert.equal(res.statusCode, 200);
      assert.equal(res.body.ok, true);
    } finally {
      global.fetch = previousFetch;
    }
  });
});
