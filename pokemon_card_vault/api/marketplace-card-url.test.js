const assert = require('node:assert/strict');
const test = require('node:test');

const {
  candidateCardIdsForLookup,
  canonicalCardUrlForLookup,
  createHandler,
  parseMarketplaceCardPath,
  parseRootCardPath,
} = require('./marketplace-card-url')._test;

test('canonical URL lookup keeps direct root card id only', () => {
  assert.deepEqual(
    candidateCardIdsForLookup({ path: '/497536/some-slug' }),
    ['497536'],
  );
});

test('canonical URL lookup keeps normal direct cardId queries direct', async () => {
  const lookup = await canonicalCardUrlForLookup({
    cardId: '316600',
  }, async (sql, values) => {
    assert.match(sql, /marketplace_card_urls/);
    assert.deepEqual(values, [[316600], 'en', '']);
    return {
      rows: [{
        card_id: '316600',
        language: 'en',
        canonical_path:
          '/marketplace/en/cards/633200/card-leafeon-005-131-prismatic-evolutions',
      }],
    };
  });

  assert.deepEqual(lookup, {
    cardId: '316600',
    language: 'en',
    canonicalPath:
      '/marketplace/en/cards/633200/card-leafeon-005-131-prismatic-evolutions',
    publicNumber: '633200',
  });
});

test('canonical URL lookup uses legacy override for colliding Drifloon public number', async () => {
  const lookup = await canonicalCardUrlForLookup({
    cardId: '248768',
  }, async (sql, values) => {
    assert.match(sql, /marketplace_card_urls/);
    assert.deepEqual(values, [[124384], 'en', '']);
    return {
      rows: [{
        card_id: '124384',
        language: 'en',
        canonical_path:
          '/marketplace/en/cards/248768/uncommon-drifloon-lv-17-non-holo-promo-6-17-pop-series-6',
      }],
    };
  });

  assert.deepEqual(lookup, {
    cardId: '124384',
    language: 'en',
    canonicalPath:
      '/marketplace/en/cards/248768/uncommon-drifloon-lv-17-non-holo-promo-6-17-pop-series-6',
    publicNumber: '248768',
  });
});

test('canonical URL lookup decodes public number for canonical marketplace path', () => {
  assert.deepEqual(
    candidateCardIdsForLookup({
      path: '/marketplace/en/cards/497536/card-drifloon-6-17-pop-series-6',
    }),
    ['248768'],
  );
});

test('root card path parser extracts id and slug from path', () => {
  assert.deepEqual(parseRootCardPath('/497536/some-slug?utm=1'), {
    cardId: '497536',
    cardSlug: 'some-slug',
  });
});

test('marketplace card path parser extracts language and public number field', () => {
  assert.deepEqual(
    parseMarketplaceCardPath('/marketplace/en/cards/497536/some-slug?utm=1'),
    {
      language: 'en',
      doubledCardId: '497536',
      cardSlug: 'some-slug',
    },
  );
});

test('canonical URL lookup returns stored database canonical path', async () => {
  const lookup = await canonicalCardUrlForLookup({
    path: '/marketplace/en/cards/497536/card-drifloon-6-17-pop-series-6',
  }, async (sql, values) => {
    assert.match(sql, /marketplace_card_urls/);
    assert.deepEqual(values, [[248768], 'en', '497536']);
    return {
      rows: [{
        card_id: '248768',
        language: 'en',
        canonical_path: '/marketplace/en/cards/497536/db-backed-drifloon',
      }],
    };
  });

  assert.deepEqual(lookup, {
    cardId: '248768',
    language: 'en',
    canonicalPath: '/marketplace/en/cards/497536/db-backed-drifloon',
    publicNumber: '497536',
  });
});

test('canonical URL lookup returns Cresselia DB path without rarity slug', async () => {
  const lookup = await canonicalCardUrlForLookup({
    cardId: '122739',
    language: 'en',
  }, async (sql, values) => {
    assert.match(sql, /marketplace_card_urls/);
    assert.deepEqual(values, [[122739], 'en', '']);
    return {
      rows: [{
        card_id: '122739',
        language: 'en',
        canonical_path:
          '/marketplace/en/cards/245478/card-cresselia-lv-43-2-100-majestic-dawn',
      }],
    };
  });

  assert.deepEqual(lookup, {
    cardId: '122739',
    language: 'en',
    canonicalPath:
      '/marketplace/en/cards/245478/card-cresselia-lv-43-2-100-majestic-dawn',
    publicNumber: '245478',
  });
});

test('canonical URL lookup resolves Cresselia public number route to DB path', async () => {
  const lookup = await canonicalCardUrlForLookup({
    path:
      '/marketplace/en/cards/245478/card-cresselia-lv-43-holo-rare-2-100-majestic-dawn',
  }, async (sql, values) => {
    assert.match(sql, /marketplace_card_urls/);
    assert.deepEqual(values, [[122739], 'en', '245478']);
    return {
      rows: [{
        card_id: '122739',
        language: 'en',
        canonical_path:
          '/marketplace/en/cards/245478/card-cresselia-lv-43-2-100-majestic-dawn',
      }],
    };
  });

  assert.deepEqual(lookup, {
    cardId: '122739',
    language: 'en',
    canonicalPath:
      '/marketplace/en/cards/245478/card-cresselia-lv-43-2-100-majestic-dawn',
    publicNumber: '245478',
  });
});

test('canonical URL handler responds with canonicalPath JSON', async () => {
  const headers = {};
  const handler = createHandler({
    query: async () => ({
      rows: [{
        card_id: '248768',
        language: 'en',
        canonical_path: '/marketplace/en/cards/497536/db-backed-drifloon',
      }],
    }),
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
    url: '/api/marketplace-card-url?path=%2Fmarketplace%2Fen%2Fcards%2F497536%2Fcard-drifloon-6-17-pop-series-6',
    headers: { host: 'pokoin.com' },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(
    res.body.canonicalPath,
    '/marketplace/en/cards/497536/db-backed-drifloon',
  );
  assert.equal(res.body.publicNumber, '497536');
  assert.match(headers['cache-control'], /s-maxage=300/);
});
