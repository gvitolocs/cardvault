const assert = require('node:assert/strict');
const test = require('node:test');

const {
  canonicalPathForCardId,
  canonicalPathForShortlinkPath,
  canonicalPathForRow,
  canonicalSlugForRow,
  cleanCollectorNumber,
  cleanCardId,
  createHandler,
} = require('./marketplace-card-shortlink')._test;

test('shortlink canonical slug keeps real collector number', () => {
  assert.equal(
    canonicalSlugForRow({
      card_id: '316600',
      name: 'Leafeon',
      set_name: 'Prismatic Evolutions',
      card_number: '005/131',
      rarity: 'Rare',
    }),
    'rare-leafeon-005-131-prismatic-evolutions',
  );
});

test('shortlink canonical slug folds Pokémon accents', () => {
  assert.equal(
    canonicalSlugForRow({
      card_id: '251432',
      name: 'Poliwhirl',
      set_name: 'Pokémon Card 151',
      card_number: '176/165',
      rarity: 'Card',
    }),
    'card-poliwhirl-176-165-pokemon-card-151',
  );
});

test('shortlink canonical path redirects to our-id marketplace URL', () => {
  assert.equal(
    canonicalPathForRow({
      card_id: '633200',
      name: 'Leafeon',
      set_name: 'Prismatic Evolutions',
      card_number: '005/131',
      rarity: 'Rare',
    }),
    '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions',
  );
});

test('shortlink canonical slug omits blueprint id masquerading as number', () => {
  assert.equal(cleanCollectorNumber('139056', '139056'), '');
  assert.equal(
    canonicalSlugForRow({
      card_id: '139056',
      name: 'Super Rod',
      set_name: 'Gold, Silver, to a New World...',
      card_number: '139056',
      rarity: 'Card',
    }),
    'card-super-rod-gold-silver-to-a-new-world',
  );
});

test('shortlink id cleaner only accepts positive safe integers', () => {
  assert.equal(cleanCardId('139056'), 139056);
  assert.equal(cleanCardId('0'), 0);
  assert.equal(cleanCardId('not-a-card'), 0);
});

test('shortlink query resolves leftover ct_id to our-id path', async () => {
  let callCount = 0;
  const path = await canonicalPathForCardId('124384', async (sql, values) => {
    callCount += 1;
    if (callCount === 1) {
      assert.match(sql, /marketplace_card_urls/);
      assert.deepEqual(values, [[124384], 'en', '']);
      return { rows: [] };
    }
    assert.match(sql, /marketplace_card_urls/);
    assert.deepEqual(values, [124384]);
    return {
      rows: [{
        card_id: '248768',
        canonical_path: '/marketplace/en/cards/248768/uncommon-drifloon-lv-17-non-holo-promo-6-17-pop-series-6',
        name: 'Drifloon Lv.17',
        set_name: 'POP Series 6',
        card_number: '6/17',
        rarity: 'Card',
      }],
    };
  });

  assert.equal(
    path,
    '/marketplace/en/cards/248768/uncommon-drifloon-lv-17-non-holo-promo-6-17-pop-series-6',
  );
  assert.equal(callCount, 2);
});

test('shortlink query looks up Drifloon by our id', async () => {
  const path = await canonicalPathForCardId('248768', async (sql, values) => {
    assert.match(sql, /marketplace_card_urls/);
    assert.deepEqual(values, [[248768, 124384], 'en', '']);
    return {
      rows: [{
        card_id: '248768',
        ct_id: '124384',
        canonical_path:
          '/marketplace/en/cards/248768/uncommon-drifloon-lv-17-non-holo-promo-6-17-pop-series-6',
        language: 'en',
      }],
    };
  });

  assert.equal(
    path,
    '/marketplace/en/cards/248768/uncommon-drifloon-lv-17-non-holo-promo-6-17-pop-series-6',
  );
});

test('shortlink handler treats root detail path id as a public number', async () => {
  const headers = {};
  const handler = createHandler({
    query: async (sql, values) => {
      assert.match(sql, /marketplace_card_urls/);
      assert.deepEqual(values, [[220962, 110481], 'en', '220962']);
      return {
        rows: [{
          card_id: '220962',
          canonical_path: '/marketplace/en/cards/220962/card-espurr-58-122-breakpoint',
          language: 'en',
          public_number: '220962',
        }],
      };
    },
  });
  const res = {
    setHeader(name, value) {
      headers[name.toLowerCase()] = value;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    end() {
      this.ended = true;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };

  await handler({
    method: 'GET',
    url: '/api/marketplace-card-shortlink.js?path=%2F220962%2Fsome-slug',
    headers: { host: 'pokoin.com' },
  }, res);

  assert.equal(res.statusCode, 302);
  assert.equal(headers.location, '/marketplace/en/cards/220962/card-espurr-58-122-breakpoint');
});

test('shortlink path resolves public-number routes on the first lookup', async () => {
  let callCount = 0;
  const path = await canonicalPathForShortlinkPath(
    '/275598/card-exeggutor-2-078-emerald-break',
    'en',
    async (sql, values) => {
      callCount += 1;
      assert.match(sql, /marketplace_card_urls/);
      assert.deepEqual(values, [[275598, 137799], 'en', '275598']);
      return {
        rows: [{
          card_id: '275598',
          language: 'en',
          canonical_path:
            '/marketplace/en/cards/275598/card-exeggutor-2-078-emerald-break',
          public_number: '275598',
        }],
      };
    },
  );

  assert.equal(
    path,
    '/marketplace/en/cards/275598/card-exeggutor-2-078-emerald-break',
  );
  assert.equal(callCount, 1);
});

test('shortlink handler redirects browser requests to canonical card path', async () => {
  const headers = {};
  const handler = createHandler({
    query: async (sql, values) => {
      if (Array.isArray(values?.[0])) {
        return { rows: [] };
      }
      return {
        rows: [{
          card_id: '633200',
          name: 'Leafeon',
          set_name: 'Prismatic Evolutions',
          card_number: '005/131',
          rarity: 'Rare',
        }],
      };
    },
  });
  const res = {
    setHeader(name, value) {
      headers[name.toLowerCase()] = value;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    end() {
      this.ended = true;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };

  await handler({
    method: 'GET',
    url: '/api/marketplace-card-shortlink.js?cardId=633200',
    headers: { host: 'pokoin.com' },
  }, res);

  assert.equal(res.statusCode, 302);
  assert.equal(headers.location, '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions');
  assert.match(headers['cache-control'], /s-maxage=300/);
  assert.equal(res.ended, true);
});
