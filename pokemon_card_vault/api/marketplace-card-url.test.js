const assert = require('node:assert/strict');
const test = require('node:test');

const {
  candidateCardIdsForLookup,
  canonicalSlugFromPath,
  canonicalCardUrlForLookup,
  createHandler,
  parseMarketplaceCardPath,
  parseRootCardPath,
  slugsEquivalent,
} = require('./marketplace-card-url')._test;

test('canonical URL lookup uses our id from the path, plus ct_id', () => {
  assert.deepEqual(
    candidateCardIdsForLookup({ path: '/220962/some-slug' }),
    ['220962', '110481'],
  );
});

test('canonical URL lookup keeps normal direct cardId queries direct', async () => {
  const lookup = await canonicalCardUrlForLookup({
    cardId: '633200',
  }, async (sql, values) => {
    assert.match(sql, /marketplace_card_urls/);
    assert.deepEqual(values, [[633200], 'en', '']);
    return {
      rows: [{
        card_id: '633200',
        language: 'en',
        canonical_path:
          '/marketplace/en/cards/633200/card-leafeon-005-131-prismatic-evolutions',
      }],
    };
  });

  assert.deepEqual(lookup, {
    cardId: '633200',
    language: 'en',
    canonicalPath:
      '/marketplace/en/cards/633200/card-leafeon-005-131-prismatic-evolutions',
    publicNumber: '633200',
  });
});

test('canonical URL lookup treats 248768 as Drifloon our id', async () => {
  const lookup = await canonicalCardUrlForLookup({
    cardId: '248768',
  }, async (sql, values) => {
    assert.match(sql, /marketplace_card_urls/);
    assert.deepEqual(values, [[248768, 124384], 'en', '']);
    return {
      rows: [{
        card_id: '248768',
        ct_id: '124384',
        language: 'en',
        canonical_path:
          '/marketplace/en/cards/248768/uncommon-drifloon-lv-17-non-holo-promo-6-17-pop-series-6',
      }],
    };
  });

  assert.deepEqual(lookup, {
    cardId: '248768',
    language: 'en',
    canonicalPath:
      '/marketplace/en/cards/248768/uncommon-drifloon-lv-17-non-holo-promo-6-17-pop-series-6',
    publicNumber: '248768',
  });
});

test('canonical URL lookup keeps our id on /marketplace/{ourId} short path', () => {
  assert.deepEqual(
    candidateCardIdsForLookup({ path: '/marketplace/220962' }),
    ['220962', '110481'],
  );
});

test('canonical URL lookup uses our id from canonical marketplace path', () => {
  assert.deepEqual(
    candidateCardIdsForLookup({
      path: '/marketplace/en/cards/220962/card-espurr-58-122-breakpoint',
    }),
    ['220962', '110481'],
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

test('canonical URL slug matcher folds Pokémon accent legacy route', () => {
  assert.equal(
    canonicalSlugFromPath('/marketplace/en/cards/502864/card-poliwhirl-176-165-pok-mon-card-151'),
    'card-poliwhirl-176-165-pok-mon-card-151',
  );
  assert.equal(
    slugsEquivalent(
      'card-poliwhirl-176-165-pok-mon-card-151',
      'card-poliwhirl-176-165-pokemon-card-151',
    ),
    true,
  );
});

test('canonical URL lookup returns stored database canonical path', async () => {
  const lookup = await canonicalCardUrlForLookup({
    path: '/marketplace/en/cards/220962/card-espurr-58-122-breakpoint',
  }, async (sql, values) => {
    assert.match(sql, /marketplace_card_urls/);
    assert.deepEqual(values, [[220962, 110481], 'en', '220962']);
    return {
      rows: [{
        card_id: '220962',
        language: 'en',
        canonical_path: '/marketplace/en/cards/220962/card-espurr-58-122-breakpoint',
        public_number: '220962',
      }],
    };
  });

  assert.deepEqual(lookup, {
    cardId: '220962',
    language: 'en',
    canonicalPath: '/marketplace/en/cards/220962/card-espurr-58-122-breakpoint',
    publicNumber: '220962',
  });
});

test('canonical URL lookup prefers the path our-id when rows collide', async () => {
  const lookup = await canonicalCardUrlForLookup({
    path: '/marketplace/en/cards/502864/card-poliwhirl-176-165-pok-mon-card-151',
  }, async (sql, values) => {
    assert.match(sql, /marketplace_card_urls/);
    assert.deepEqual(values, [[502864, 251432], 'en', '502864']);
    return {
      rows: [
        {
          card_id: '1005728',
          language: 'en',
          canonical_path: '/marketplace/en/cards/1005728/card-some-other-card',
        },
        {
          card_id: '502864',
          language: 'en',
          canonical_path:
            '/marketplace/en/cards/502864/card-poliwhirl-176-165-pokemon-card-151',
        },
      ],
    };
  });

  assert.deepEqual(lookup, {
    cardId: '502864',
    language: 'en',
    canonicalPath:
      '/marketplace/en/cards/502864/card-poliwhirl-176-165-pokemon-card-151',
    publicNumber: '502864',
  });
});

test('canonical URL lookup still finds leftover odd ct_id queries', async () => {
  const lookup = await canonicalCardUrlForLookup({
    cardId: '122739',
    language: 'en',
  }, async (sql, values) => {
    assert.match(sql, /marketplace_card_urls/);
    assert.deepEqual(values, [[122739], 'en', '']);
    return {
      rows: [{
        card_id: '245478',
        ct_id: '122739',
        language: 'en',
        canonical_path:
          '/marketplace/en/cards/245478/card-cresselia-lv-43-2-100-majestic-dawn',
      }],
    };
  });

  assert.deepEqual(lookup, {
    cardId: '245478',
    language: 'en',
    canonicalPath:
      '/marketplace/en/cards/245478/card-cresselia-lv-43-2-100-majestic-dawn',
    publicNumber: '245478',
  });
});

test('canonical URL lookup resolves Cresselia our-id route to DB path', async () => {
  const lookup = await canonicalCardUrlForLookup({
    path:
      '/marketplace/en/cards/245478/card-cresselia-lv-43-holo-rare-2-100-majestic-dawn',
  }, async (sql, values) => {
    assert.match(sql, /marketplace_card_urls/);
    assert.deepEqual(values, [[245478, 122739], 'en', '245478']);
    return {
      rows: [{
        card_id: '245478',
        language: 'en',
        canonical_path:
          '/marketplace/en/cards/245478/card-cresselia-lv-43-2-100-majestic-dawn',
      }],
    };
  });

  assert.deepEqual(lookup, {
    cardId: '245478',
    language: 'en',
    canonicalPath:
      '/marketplace/en/cards/245478/card-cresselia-lv-43-2-100-majestic-dawn',
    publicNumber: '245478',
  });
});

test('canonical URL lookup resolves /marketplace/{ourId} without doubling again', async () => {
  const lookup = await canonicalCardUrlForLookup({
    path: '/marketplace/220962',
  }, async (sql, values) => {
    assert.match(sql, /public_number/);
    assert.deepEqual(values, [[220962, 110481], 'en', '220962']);
    return {
      rows: [{
        card_id: '220962',
        language: 'en',
        canonical_path:
          '/marketplace/en/cards/220962/card-espurr-58-122-breakpoint',
        public_number: '220962',
      }],
    };
  });

  assert.deepEqual(lookup, {
    cardId: '220962',
    language: 'en',
    canonicalPath:
      '/marketplace/en/cards/220962/card-espurr-58-122-breakpoint',
    publicNumber: '220962',
  });
});

test('canonical URL handler responds with canonicalPath JSON', async () => {
  const headers = {};
  const handler = createHandler({
    query: async () => ({
      rows: [{
        card_id: '220962',
        language: 'en',
        canonical_path: '/marketplace/en/cards/220962/card-espurr-58-122-breakpoint',
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
    url: '/api/marketplace-card-url?path=%2Fmarketplace%2Fen%2Fcards%2F220962%2Fcard-espurr-58-122-breakpoint',
    headers: { host: 'pokoin.com' },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(
    res.body.canonicalPath,
    '/marketplace/en/cards/220962/card-espurr-58-122-breakpoint',
  );
  assert.equal(res.body.publicNumber, '220962');
  assert.match(headers['cache-control'], /s-maxage=300/);
});
