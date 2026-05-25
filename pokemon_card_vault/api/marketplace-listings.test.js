const assert = require('node:assert/strict');
const Module = require('node:module');
const test = require('node:test');

function loadMarketplaceListingsWithStubs(stubs) {
  const target = require.resolve('./marketplace-listings');
  const originalLoad = Module._load;
  delete require.cache[target];
  Module._load = function load(request, parent, isMain) {
    if (request === './_marketplace_db') {
      return { marketplaceQuery: stubs.marketplaceQuery };
    }
    if (request === './_firebase') {
      return {
        getFirebaseAdmin: stubs.getFirebaseAdmin,
        verifyBearerToken: stubs.verifyBearerToken,
      };
    }
    if (request === './_firebase_roles') {
      return { requireReserveAccess: stubs.requireReserveAccess };
    }
    if (request === './cardtrader-live-listings') {
      return {
        readLiveCardTraderListings: stubs.readLiveCardTraderListings || (async () => ({ listings: [] })),
        _test: {
          PKNRESERVE_SELLER_USERNAME: 'pknreserve',
        },
      };
    }
    return originalLoad.apply(this, arguments);
  };
  try {
    return require('./marketplace-listings');
  } finally {
    Module._load = originalLoad;
    delete require.cache[target];
  }
}

function responseRecorder() {
  return {
    statusCode: 200,
    headers: {},
    body: undefined,
    setHeader(name, value) {
      this.headers[name] = value;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.body = payload;
      return this;
    },
  };
}

async function withSilencedConsoleError(callback) {
  const original = console.error;
  console.error = () => {};
  try {
    return await callback();
  } finally {
    console.error = original;
  }
}

function listingRow(overrides = {}) {
  return {
    id: '11111111-1111-4111-8111-111111111111',
    card_id: 'card-1',
    seller_uid: 'seller-uid',
    seller_name: 'Pokoin seller',
    seller_country: 'EU',
    seller_reputation_label: 'New',
    condition: 'NM',
    language: 'EN',
    price_pkn: 100,
    quantity_available: 1,
    signed: false,
    reverse: false,
    first_edition: false,
    foil_state: 'standard',
    variant_state: '',
    sealed: false,
    graded: false,
    grading_company: null,
    grade: null,
    certification_id: null,
    shipping_available: true,
    reserve_available: false,
    nft_available: false,
    seller_comment: '',
    source: 'pokoin_user_listing',
    source_listing_id: '',
    status: 'active',
    card_name: 'Pikachu',
    card_image_url: '',
    set_name: 'Pokemon',
    collector_number: '001',
    created_at: '2026-01-01T00:00:00.000Z',
    updated_at: '2026-01-01T00:00:00.000Z',
    source_metadata: {},
    ...overrides,
  };
}

function validCreateBody(overrides = {}) {
  return {
    cardId: 'card-1',
    sellerName: 'Pokoin seller',
    condition: 'NM',
    language: 'EN',
    pricePkn: 100,
    quantityAvailable: 1,
    shippingAvailable: true,
    reserveAvailable: false,
    nftAvailable: false,
    cardName: 'Pikachu',
    setName: 'Pokemon',
    collectorNumber: '001',
    ...overrides,
  };
}

test('marketplace listings reads public seller inventory by username', async () => {
  const queries = [];
  const handler = loadMarketplaceListingsWithStubs({
    getFirebaseAdmin: () => ({
      firestore: () => ({
        collection: (name) => {
          assert.ok(name === 'usernames' || name === 'users');
          return {
            doc: (username) => {
              if (name === 'usernames') assert.equal(username, 'sellername');
              return {
                get: async () => ({
                  data: () => ({
                    uid: username === 'sellername' ? 'seller-uid' : username,
                    displayName: 'Seller Name',
                    username: 'sellername',
                  }),
                }),
              };
            },
          };
        },
      }),
    }),
    verifyBearerToken: async () => {
      throw new Error('Public username inventory should not require auth.');
    },
    requireReserveAccess: async () => {},
    marketplaceQuery: async (sql, values) => {
      queries.push({ sql: String(sql), values });
      assert.doesNotMatch(String(sql), /cardtrader_blueprint_listing_cache/);
      if (String(sql).includes('marketplace_card_urls')) {
        return {
          rows: [{
            card_id: '316600',
            canonical_path:
              '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions',
            public_number: '633200',
          }],
        };
      }
      return { rows: [listingRow({ card_id: '316600' })] };
    },
  });
  const res = responseRecorder();

  await handler({
    method: 'GET',
    url: '/api/marketplace-listings?sellerUsername=SellerName',
    headers: { host: 'pokoin.test' },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.listings.length, 1);
  assert.equal(res.body.listings[0].sellerName, 'Seller Name');
  assert.equal(res.body.listings[0].sellerDisplayName, 'Seller Name');
  assert.equal(queries.length, 2);
  assert.deepEqual(queries[0].values.slice(0, 2), ['seller-uid', 500]);
  assert.match(queries[0].sql, /seller_uid = \$1/);
  assert.match(queries[0].sql, /status = 'active'/);
  assert.match(queries[0].sql, /quantity_available > 0/);
  assert.match(queries[1].sql, /marketplace_card_urls/);
});

test('marketplace listing rows include canonical card detail path', () => {
  const { _test } = loadMarketplaceListingsWithStubs({});

  const row = _test.listingRow(listingRow({
    card_id: '316600',
    canonical_path:
      '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions',
    public_number: '633200',
  }));

  assert.equal(
    row.canonicalPath,
    '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions',
  );
  assert.equal(row.publicNumber, '633200');
});

test('marketplace listings merges live CardTrader rows on card pages as pknreserve', async () => {
  const queries = [];
  const handler = loadMarketplaceListingsWithStubs({
    getFirebaseAdmin: () => ({
      firestore: () => ({
        collection: (name) => {
          assert.ok(name === 'usernames' || name === 'users');
          return {
            doc: (username) => {
              if (name === 'usernames') assert.equal(username, 'pknreserve');
              return {
                get: async () => ({
                  data: () => ({
                    uid: 'reserve-uid',
                    displayName: 'pknreserve',
                  }),
                }),
              };
            },
          };
        },
      }),
    }),
    verifyBearerToken: async () => {
      throw new Error('Public card listing read should not require auth.');
    },
    requireReserveAccess: async () => {},
    readLiveCardTraderListings: async (request) => {
      assert.equal(request.cardId, 'card-1');
      return {
        listings: [{
          externalListingId: 'ct-live-1',
          externalProductId: 'ct-live-1',
          cardtraderProductId: 'ct-live-1',
          cardtraderBlueprintId: '497712',
          pokoinCardId: 'card-1',
          displayPricePkn: 1000,
          price: 4,
          currency: 'EUR',
          quantity: 1,
          condition: 'GD',
          language: 'it',
          name: 'Magikarp',
          expansion: { name: 'Paldea Evolved' },
          sellerComment: 'tiny whitening',
          shippingMode: 'zero',
          shippingLabel: 'Zero',
          seller: {
            country: 'IT',
            sourceAccountName: 'CardTrader seller',
          },
        }],
      };
    },
    marketplaceQuery: async (sql, values) => {
      queries.push({ sql: String(sql), values });
      assert.doesNotMatch(String(sql), /cardtrader_blueprint_listing_cache/);
      return { rows: [listingRow({ price_pkn: 1200 })] };
    },
  });
  const res = responseRecorder();

  await handler({
    method: 'GET',
    url: '/api/marketplace-listings?cardId=card-1',
    headers: { host: 'pokoin.test' },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.listings.length, 2);
  assert.equal(res.body.listings[0].id, 'cardtrader:live:ct-live-1');
  assert.equal(res.body.listings[0].sellerName, 'pknreserve');
  assert.equal(res.body.listings[0].sellerUid, 'reserve-uid');
  assert.equal(res.body.listings[0].pricePkn, 1000);
  assert.equal(res.body.listings[0].sellerCountry, 'IT');
  assert.equal(res.body.listings[0].sellerComment, 'tiny whitening');
  assert.equal(res.body.listings[0].condition, 'GD');
  assert.equal(res.body.listings[0].source, 'cardtrader_live');
  assert.equal(res.body.listings[0].sourceMetadata.cardtraderProductId, 'ct-live-1');
  assert.equal(res.body.listings[0].sourceMetadata.liveCardTraderApiUsed, undefined);
  assert.equal(queries.length, 1);
  assert.doesNotMatch(queries.map((query) => query.sql).join('\n'), /cardtrader_blueprint_listing_cache/);
});

test('marketplace listings hides promotional seller comments in public output', async () => {
  const handler = loadMarketplaceListingsWithStubs({
    getFirebaseAdmin: () => ({
      firestore: () => ({
        collection: (name) => {
          assert.ok(name === 'users' || name === 'usernames');
          return {
            doc: () => ({
              get: async () => ({
                data: () => name === 'usernames'
                  ? { uid: 'reserve-uid', displayName: 'pknreserve' }
                  : {},
              }),
            }),
          };
        },
      }),
    }),
    verifyBearerToken: async () => {
      throw new Error('Public listing read should not require auth.');
    },
    requireReserveAccess: async () => {},
    readLiveCardTraderListings: async () => ({ listings: [] }),
    marketplaceQuery: async () => ({
      rows: [
        listingRow({
          id: '11111111-1111-4111-8111-111111111111',
          seller_comment: 'Check my store, more cards available! :3',
        }),
        listingRow({
          id: '22222222-2222-4222-8222-222222222222',
          seller_comment: 'Tiny edge whitening',
          price_pkn: 110,
        }),
      ],
    }),
  });
  const res = responseRecorder();

  await handler({
    method: 'GET',
    url: '/api/marketplace-listings?cardId=card-1',
    headers: { host: 'pokoin.test' },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.listings.length, 2);
  assert.equal(res.body.listings[0].sellerComment, '');
  assert.equal(res.body.listings[1].sellerComment, 'Tiny edge whitening');
});

test('synthetic CardTrader rows hide promotional seller comments', () => {
  const { _test } = loadMarketplaceListingsWithStubs({});
  const row = _test.syntheticCardTraderListingRow({
    fallbackCardId: 'card-1',
    seller: { uid: 'reserve-uid' },
    listing: {
      externalProductId: '123',
      displayPricePkn: 250,
      quantity: 1,
      condition: 'NM',
      language: 'en',
      name: 'Pikachu',
      expansion: { name: 'Base' },
      sellerComment: 'Check my store, more cards available! :3',
    },
  });

  assert.equal(row.sellerComment, '');
  assert.equal(row.sourceMetadata.sellerComment, '');
});

test('marketplace listing row prefers current profile seller names except reserve', () => {
  const { _test } = loadMarketplaceListingsWithStubs({
    getFirebaseAdmin: () => ({}),
    verifyBearerToken: async () => ({}),
    requireReserveAccess: async () => {},
    marketplaceQuery: async () => ({ rows: [] }),
  });

  assert.equal(
    _test.displaySellerName({
      seller_name: 'old-name',
      profile_display_name: 'Current Seller',
      profile_username: 'current',
      source: 'pokoin_user_listing',
      source_listing_id: '',
    }),
    'Current Seller',
  );
  assert.equal(
    _test.displaySellerName({
      seller_name: 'old-name',
      profile_display_name: 'Current Seller',
      source: 'cardtrader_live',
      source_listing_id: 'cardtrader:live:1',
      reserve_available: true,
    }, 'cardtrader_live', 'cardtrader:live:1'),
    'pknreserve',
  );
});

test('marketplace listing row emits current seller display name separately', () => {
  const { _test } = loadMarketplaceListingsWithStubs({
    getFirebaseAdmin: () => ({}),
    verifyBearerToken: async () => ({}),
    requireReserveAccess: async () => {},
    marketplaceQuery: async () => ({ rows: [] }),
  });

  const row = _test.listingRow(listingRow({
    seller_name: 'vitologiuseppe17',
    profile_display_name: 'Giuseppe',
    profile_username: 'giuseppe',
  }));

  assert.equal(row.sellerName, 'Giuseppe');
  assert.equal(row.sellerDisplayName, 'Giuseppe');
});

test('marketplace listings rejects reserve create without reserve role', async () => {
  const queries = [];
  let roleChecks = 0;
  const handler = loadMarketplaceListingsWithStubs({
    verifyBearerToken: async () => ({ uid: 'seller-uid' }),
    requireReserveAccess: async () => {
      roleChecks += 1;
      const error = new Error('Reserve listing access required.');
      error.statusCode = 403;
      throw error;
    },
    marketplaceQuery: async (...args) => {
      queries.push(args);
      return { rows: [] };
    },
  });
  const res = responseRecorder();

  await withSilencedConsoleError(() => handler({
    method: 'POST',
    headers: { host: 'pokoin.test', authorization: 'Bearer token' },
    body: validCreateBody({ reserveAvailable: true }),
  }, res));

  assert.equal(roleChecks, 1);
  assert.equal(queries.length, 0);
  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error, 'Reserve listing access required.');
});

test('marketplace listings allows normal create without reserve role lookup', async () => {
  const queries = [];
  let roleChecks = 0;
  const handler = loadMarketplaceListingsWithStubs({
    verifyBearerToken: async () => ({ uid: 'seller-uid' }),
    requireReserveAccess: async () => {
      roleChecks += 1;
    },
    marketplaceQuery: async (sql, values) => {
      queries.push({ sql, values });
      if (String(sql).includes('marketplace_card_versions')) {
        return { rows: [] };
      }
      if (String(sql).includes('refresh_marketplace_blueprint_price_summary')) {
        return { rows: [] };
      }
      return { rows: [listingRow()] };
    },
  });
  const res = responseRecorder();

  await handler({
    method: 'POST',
    headers: { host: 'pokoin.test', authorization: 'Bearer token' },
    body: validCreateBody({ reserveAvailable: false }),
  }, res);

  assert.equal(roleChecks, 0);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.reserveAvailable, false);
  assert.ok(queries.some((query) => String(query.sql).includes('insert into public.marketplace_user_listings')));
});

test('marketplace listings allows reserve create with reserve role', async () => {
  const handler = loadMarketplaceListingsWithStubs({
    verifyBearerToken: async () => ({ uid: 'seller-uid' }),
    requireReserveAccess: async () => {},
    marketplaceQuery: async (sql) => {
      if (String(sql).includes('marketplace_card_versions')) {
        return { rows: [] };
      }
      if (String(sql).includes('refresh_marketplace_blueprint_price_summary')) {
        return { rows: [] };
      }
      return { rows: [listingRow({ reserve_available: true })] };
    },
  });
  const res = responseRecorder();

  await handler({
    method: 'POST',
    headers: { host: 'pokoin.test', authorization: 'Bearer token' },
    body: validCreateBody({ reserveAvailable: true }),
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.reserveAvailable, true);
});

test('marketplace listings accepts NFT listing only for owned NFT item', async () => {
  const handler = loadMarketplaceListingsWithStubs({
    verifyBearerToken: async () => ({ uid: 'seller-uid' }),
    requireReserveAccess: async () => {},
    getFirebaseAdmin: () => ({
      firestore: () => ({
        collection: (name) => {
          assert.equal(name, 'user_card_collections');
          return {
            doc: (id) => {
              assert.equal(id, 'owned-nft-1');
              return {
                get: async () => ({
                  exists: true,
                  data: () => ({
                    uid: 'seller-uid',
                    cardId: 'card-1',
                    ownershipType: 'nft',
                    nftStatus: 'owned',
                  }),
                }),
              };
            },
          };
        },
      }),
    }),
    marketplaceQuery: async (sql) => {
      if (String(sql).includes('marketplace_card_versions')) {
        return { rows: [] };
      }
      if (String(sql).includes('refresh_marketplace_blueprint_price_summary')) {
        return { rows: [] };
      }
      return {
        rows: [listingRow({
          nft_available: true,
          source: 'pokoin_user_nft',
          source_listing_id: 'owned-nft-1',
        })],
      };
    },
  });
  const res = responseRecorder();

  await handler({
    method: 'POST',
    headers: { host: 'pokoin.test', authorization: 'Bearer token' },
    body: validCreateBody({
      nftAvailable: true,
      source: 'pokoin_user_nft',
      sourceListingId: 'owned-nft-1',
      quantityAvailable: 1,
    }),
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.nftAvailable, true);
  assert.equal(res.body.source, 'pokoin_user_nft');
});

test('marketplace listings rejects NFT listing without owned NFT item', async () => {
  const handler = loadMarketplaceListingsWithStubs({
    verifyBearerToken: async () => ({ uid: 'seller-uid' }),
    requireReserveAccess: async () => {},
    getFirebaseAdmin: () => ({
      firestore: () => ({
        collection: () => ({
          doc: () => ({
            get: async () => ({
              exists: false,
              data: () => null,
            }),
          }),
        }),
      }),
    }),
    marketplaceQuery: async () => {
      throw new Error('NFT listing should fail before insert.');
    },
  });
  const res = responseRecorder();

  await withSilencedConsoleError(() => handler({
    method: 'POST',
    headers: { host: 'pokoin.test', authorization: 'Bearer token' },
    body: validCreateBody({
      nftAvailable: true,
      source: 'pokoin_user_nft',
      sourceListingId: 'missing-nft',
      quantityAvailable: 1,
    }),
  }, res));

  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error, 'You can only list NFTs you own for this card.');
});

test('marketplace listings rejects arbitrary user NFT listings', async () => {
  const handler = loadMarketplaceListingsWithStubs({
    verifyBearerToken: async () => ({ uid: 'seller-uid' }),
    requireReserveAccess: async () => {},
    marketplaceQuery: async () => {
      throw new Error('NFT listing should fail before insert.');
    },
  });
  const res = responseRecorder();

  await withSilencedConsoleError(() => handler({
    method: 'POST',
    headers: { host: 'pokoin.test', authorization: 'Bearer token' },
    body: validCreateBody({
      nftAvailable: true,
      source: 'pokoin_user_listing',
      quantityAvailable: 1,
    }),
  }, res));

  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error, 'NFT listings must use an owned NFT.');
});

test('marketplace listings rejects arbitrary NFT listing updates', async () => {
  const listingId = '11111111-1111-4111-8111-111111111111';
  const handler = loadMarketplaceListingsWithStubs({
    verifyBearerToken: async () => ({ uid: 'seller-uid' }),
    requireReserveAccess: async () => {},
    marketplaceQuery: async (sql) => {
      if (String(sql).includes('select seller_uid')) {
        return {
          rows: [{
            seller_uid: 'seller-uid',
            card_id: 'card-1',
            quantity_available: 1,
            reserve_available: false,
            source: 'pokoin_user_listing',
            source_listing_id: '',
          }],
        };
      }
      throw new Error('NFT listing update should fail before update.');
    },
  });
  const res = responseRecorder();

  await withSilencedConsoleError(() => handler({
    method: 'PATCH',
    url: `/api/marketplace-listings?id=${listingId}`,
    headers: { host: 'pokoin.test', authorization: 'Bearer token' },
    body: { nftAvailable: true },
  }, res));

  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error, 'NFT listings must use an owned NFT.');
});

test('marketplace listings marks synthetic CardTrader reserve rows as NFT', () => {
  const { _test } = loadMarketplaceListingsWithStubs({});
  const row = _test.syntheticCardTraderListingRow({
    fallbackCardId: 'card-1',
    seller: { uid: 'reserve-uid' },
    listing: {
      externalProductId: '123',
      displayPricePkn: 250,
      quantity: 1,
      condition: 'NM',
      language: 'en',
      name: 'Pikachu',
      expansion: { name: 'Base' },
    },
  });

  assert.equal(row.reserveAvailable, true);
  assert.equal(row.nftAvailable, true);
  assert.equal(row.source, 'cardtrader_live');
});

test('marketplace listings does not turn CardTrader shipping labels into comments', () => {
  const { _test } = loadMarketplaceListingsWithStubs({});
  const row = _test.syntheticCardTraderListingRow({
    fallbackCardId: 'card-1',
    seller: { uid: 'reserve-uid' },
    listing: {
      externalProductId: '123',
      displayPricePkn: 250,
      quantity: 1,
      condition: 'NM',
      language: 'en',
      name: 'Pikachu',
      expansion: { name: 'Base' },
      sellerComment: '',
      shippingMode: 'zero',
      shippingLabel: 'Zero',
    },
  });

  assert.equal(row.sellerComment, '');
  assert.equal(row.sourceMetadata.sellerComment, '');
  assert.equal(row.sourceMetadata.shippingMode, 'zero');
  assert.equal(row.sourceMetadata.shippingLabel, 'Zero');
});

test('marketplace listings rejects reserve-enabling update without reserve role', async () => {
  const listingId = '11111111-1111-4111-8111-111111111111';
  const handler = loadMarketplaceListingsWithStubs({
    verifyBearerToken: async () => ({ uid: 'seller-uid' }),
    requireReserveAccess: async () => {
      const error = new Error('Reserve listing access required.');
      error.statusCode = 403;
      throw error;
    },
    marketplaceQuery: async (sql) => {
      if (String(sql).includes('select seller_uid')) {
        return {
          rows: [{
            seller_uid: 'seller-uid',
            reserve_available: false,
            source: 'pokoin_user_listing',
            source_listing_id: '',
          }],
        };
      }
      throw new Error('Update should not run without reserve access.');
    },
  });
  const res = responseRecorder();

  await withSilencedConsoleError(() => handler({
    method: 'PATCH',
    url: `/api/marketplace-listings?id=${listingId}`,
    headers: { host: 'pokoin.test', authorization: 'Bearer token' },
    body: { reserveAvailable: true },
  }, res));

  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error, 'Reserve listing access required.');
});

test('marketplace listings rejects updates to existing reserve listing without reserve role', async () => {
  const listingId = '11111111-1111-4111-8111-111111111111';
  const handler = loadMarketplaceListingsWithStubs({
    verifyBearerToken: async () => ({ uid: 'seller-uid' }),
    requireReserveAccess: async () => {
      const error = new Error('Reserve listing access required.');
      error.statusCode = 403;
      throw error;
    },
    marketplaceQuery: async (sql) => {
      if (String(sql).includes('select seller_uid')) {
        return {
          rows: [{
            seller_uid: 'seller-uid',
            reserve_available: true,
            source: 'pokoin_user_listing',
            source_listing_id: '',
          }],
        };
      }
      throw new Error('Update should not run without reserve access.');
    },
  });
  const res = responseRecorder();

  await withSilencedConsoleError(() => handler({
    method: 'PATCH',
    url: `/api/marketplace-listings?id=${listingId}`,
    headers: { host: 'pokoin.test', authorization: 'Bearer token' },
    body: { pricePkn: 120 },
  }, res));

  assert.equal(res.statusCode, 403);
  assert.equal(res.body.error, 'Reserve listing access required.');
});
