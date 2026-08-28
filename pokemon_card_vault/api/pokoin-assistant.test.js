const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const Module = require('node:module');
const test = require('node:test');

function loadAssistantWithStubs(stubs) {
  const target = require.resolve('./pokoin-assistant');
  const originalEnv = { ...process.env };
  delete require.cache[target];
  for (const key of ['POKONTACT_SERVICE_URL', 'POKONTACT_SERVICE_TOKEN', 'POKONTACT_SERVICE_TIMEOUT_MS']) {
    delete process.env[key];
  }
  Object.assign(process.env, stubs.env || {});
  try {
    const assistant = require('./pokoin-assistant');
    assistant._test.setTestHelperOverrides({
      _marketplace_db: { marketplaceQuery: stubs.marketplaceQuery || (async () => ({ rows: [] })) },
      _firebase: { getFirebaseAdmin: () => ({}), verifyBearerToken: async () => ({ uid: 'user' }) },
      _email: { sendEmail: async () => ({ ok: true }) },
    });
    return assistant;
  } finally {
    process.env = originalEnv;
  }
}

function createResponse() {
  const response = {
    statusCode: 200,
    headers: {},
    body: null,
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
  return response;
}

const UNSUPPORTED_POKO_EMOJI = /[🃏🫧🫠⛓🦊📒✅🐣🔑💪💕😌📨💌🧭⚠🟢🟡⚡💗]/u;

function copyApiFile(name, targetDir) {
  fs.copyFileSync(
    path.join(__dirname, `${name}.js`),
    path.join(targetDir, `${name}.js`),
  );
}

function withStubbedExternalPackages(fn) {
  const originalLoad = Module._load;
  Module._load = function load(request, parent, isMain) {
    if (request === 'firebase-admin') {
      return { apps: [] };
    }
    if (request === 'pg') {
      return { Pool: class Pool {} };
    }
    return originalLoad.apply(this, arguments);
  };
  try {
    return fn();
  } finally {
    Module._load = originalLoad;
  }
}

test('Pokontact helpers module-load in deploy-pokoin-web output layout', () => {
  const deployDir = fs.mkdtempSync(path.join(os.tmpdir(), 'pokontact-deploy-'));
  try {
    const deployApiDir = path.join(deployDir, 'api');
    const deployServerDir = path.join(deployDir, 'server');
    fs.mkdirSync(deployApiDir);
    fs.mkdirSync(deployServerDir);

    copyApiFile('pokoin-assistant', deployApiDir);
    for (const helper of ['_firebase', '_email', '_marketplace_db', '_slug']) {
      copyApiFile(helper, deployServerDir);
    }

    withStubbedExternalPackages(() => {
      const handler = require(path.join(deployApiDir, 'pokoin-assistant.js'));

      assert.equal(typeof handler, 'function');
      assert.equal(typeof handler._test.loadFirebaseHelper().getFirebaseAdmin, 'function');
      assert.equal(typeof handler._test.loadEmailHelper().sendEmail, 'function');
      assert.equal(typeof handler._test.loadMarketplaceDbHelper().marketplaceQuery, 'function');
    });
  } finally {
    fs.rmSync(deployDir, { force: true, recursive: true });
  }
});

test('most expensive card tool returns a navigation action', async () => {
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async (sql, values) => {
      assert.match(String(sql), /marketplace_user_listings/);
      assert.deepEqual(values, ['%charizard%', '', 'desc']);
      return {
        rows: [{
          listing_id: 'listing-1',
          card_id: '123',
          card_name: 'Charizard ex',
          price_pkn: 9999,
          quantity_available: 1,
          set_name: 'Test Set',
          collector_number: '001/100',
          rarity: 'Rare',
          canonical_path: '/marketplace/en/cards/246/rare-charizard-ex-001-100-test-set',
        }],
      };
    },
  });

  const result = await assistant._test.mostExpensiveCardTool({
    message: 'show the most expensive charizard card',
    page: 'https://pokoin.com/marketplace/en',
  });

  assert.equal(result.intent, 'marketplace');
  assert.match(result.reply, /Charizard ex/);
  assert.match(result.reply, /active Pokoin marketplace listings/);
  assert.equal(result.actions[0].type, 'navigate');
  assert.equal(result.actions[0].path, '/marketplace/en/cards/246/rare-charizard-ex-001-100-test-set');
  assert.equal(result.actions[0].data.pricePkn, 9999);
});

test('marketplace follow-up reuses previous expensive-card intent', async () => {
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async (sql, values) => {
      assert.match(String(sql), /marketplace_user_listings/);
      assert.deepEqual(values, ['%leafeon%', '', 'desc']);
      return {
        rows: [{
          listing_id: 'listing-2',
          card_id: '316600',
          card_name: 'Leafeon',
          price_pkn: 4500,
          quantity_available: 1,
          set_name: 'Prismatic Evolutions',
          collector_number: '005/131',
          rarity: 'Rare',
          canonical_path: '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions',
        }],
      };
    },
  });

  const result = await assistant._test.marketplaceGroundedDelivery({
    message: 'leafeon?',
    chatRecord: [{ role: 'user', text: 'what is the most expensive charizard card?' }],
    page: 'https://pokoin.com/marketplace/en',
    pageContext: {},
  });

  assert.equal(result.intent, 'marketplace');
  assert.match(result.reply, /Leafeon/);
  assert.equal(
    result.actions[0].path,
    '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions',
  );
});

test('Italian most expensive Leafeon query uses active marketplace listings', async () => {
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async (sql, values) => {
      assert.match(String(sql), /marketplace_user_listings/);
      assert.deepEqual(values, ['%leafeon%', '', 'desc']);
      return {
        rows: [{
          listing_id: 'listing-leafeon-38',
          card_id: '316600',
          card_name: 'Leafeon',
          price_pkn: 38,
          quantity_available: 1,
          set_name: 'Prismatic Evolutions',
          collector_number: '005/131',
          rarity: 'Rare',
          canonical_path: '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions',
        }],
      };
    },
  });

  const request = assistant._test.marketplaceRequestFromMessage({
    message: 'mostrami la carta di leafeon più costosa',
    chatRecord: [],
    page: 'https://pokoin.com/marketplace/en',
    pageContext: {},
  });
  assert.equal(request.query, 'leafeon');

  const result = await assistant._test.marketplaceGroundedDelivery({
    message: 'fammi vedere la carta di leafeon più costosa',
    chatRecord: [],
    page: 'https://pokoin.com/marketplace/en',
    pageContext: {},
  });

  assert.equal(result.intent, 'marketplace');
  assert.match(result.reply, /Leafeon/);
  assert.doesNotMatch(result.reply, /vedere leafeon/i);
  assert.match(result.reply, /38 PKN/);
  assert.equal(result.actions[0].type, 'navigate');
  assert.equal(
    result.actions[0].path,
    '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions',
  );
  assert.equal(result.actions[0].data.pricePkn, 38);
});

test('English show-me most expensive Leafeon query opens direct card page', async () => {
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async (sql, values) => {
      assert.match(String(sql), /marketplace_user_listings/);
      assert.deepEqual(values, ['%leafeon%', '', 'desc']);
      return {
        rows: [{
          listing_id: 'listing-leafeon-english',
          card_id: '316600',
          card_name: 'Leafeon',
          price_pkn: 42,
          quantity_available: 1,
          set_name: 'Prismatic Evolutions',
          collector_number: '005/131',
          rarity: 'Rare',
          canonical_path: '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions',
        }],
      };
    },
  });

  const request = assistant._test.marketplaceRequestFromMessage({
    message: 'show me the most expensive Leafeon card',
    chatRecord: [],
    page: 'https://pokoin.com/marketplace/en',
    pageContext: {},
  });
  assert.equal(request.query, 'leafeon');

  const result = await assistant._test.marketplaceGroundedDelivery({
    message: 'show me the most expensive Leafeon card',
    chatRecord: [],
    page: 'https://pokoin.com/marketplace/en',
    pageContext: {},
  });

  assert.equal(result.intent, 'marketplace');
  assert.doesNotMatch(result.reply, /show me leafeon/i);
  assert.equal(result.actions[0].type, 'navigate');
  assert.equal(
    result.actions[0].path,
    '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions',
  );
  assert.equal(result.actions[0].data.pricePkn, 42);
});

test('missing active listing response is grounded and sane', async () => {
  let callCount = 0;
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async (sql, values) => {
      callCount += 1;
      if (callCount === 1) {
        assert.match(String(sql), /marketplace_user_listings/);
        assert.deepEqual(values, ['%leafeon%', '', 'desc']);
        return { rows: [] };
      }
      assert.match(String(sql), /marketplace_search_candidates/);
      return {
        rows: [{
          card_id: '316600',
          card_name: 'Leafeon',
          name: 'Leafeon',
          set_name: 'Prismatic Evolutions',
          card_number: '005/131',
          rarity: 'Rare',
          canonical_path: '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions',
          active_listing_count: 0,
          listed_quantity: 0,
        }],
      };
    },
  });

  const result = await assistant._test.marketplaceGroundedDelivery({
    message: 'fammi vedere la carta di leafeon più costosa',
    chatRecord: [],
    page: 'https://pokoin.com/marketplace/en',
    pageContext: {},
  });

  assert.match(result.reply, /could not find any active listing/i);
  assert.doesNotMatch(result.reply, /vedere leafeon/i);
  assert.match(result.reply, /marketplace_user_listings/);
  assert.equal(result.actions[0].path, '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions');
});

test('marketplace current-card follow-up uses pageContext card id', async () => {
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async (sql, values) => {
      assert.match(String(sql), /marketplace_user_listings/);
      assert.deepEqual(values, ['%Magikarp%', '248856', 'asc']);
      return {
        rows: [{
          listing_id: 'listing-magikarp-floor',
          card_id: '248856',
          card_name: 'Magikarp',
          price_pkn: 120,
          quantity_available: 1,
          set_name: 'Paldea Evolved',
          collector_number: '203/193',
          rarity: 'Illustration Rare',
          canonical_path: '/marketplace/en/cards/497712/card-magikarp-203-193-paldea-evolved',
        }],
      };
    },
  });

  const result = await assistant._test.marketplaceGroundedDelivery({
    message: 'floor price for this card',
    chatRecord: [],
    page: 'https://pokoin.com/marketplace/en/cards/497712/card-magikarp-203-193-paldea-evolved',
    pageContext: assistant._test.cleanPageContext({
      kind: 'card',
      path: '/marketplace/en/cards/497712/card-magikarp-203-193-paldea-evolved',
      activeCard: {
        id: '248856',
        name: 'Magikarp',
        set: 'Paldea Evolved',
        number: '203/193',
      },
    }),
  });

  assert.equal(result.intent, 'marketplace');
  assert.match(result.reply, /Magikarp/);
  assert.equal(
    result.actions[0].path,
    '/marketplace/en/cards/497712/card-magikarp-203-193-paldea-evolved',
  );
});

test('Italian current-card investment question uses contextual card answer', async () => {
  const originalFetch = global.fetch;
  let peerServiceCalled = false;
  global.fetch = async (url) => {
    const textUrl = String(url);
    if (textUrl.includes('reddit.com/search.json')) {
      return {
        ok: true,
        status: 200,
        json: async () => ({
          data: {
            children: [
              { data: { title: 'Poliwhirl 151 illustration rare artwork is beautiful and underrated' } },
              { data: { title: 'Poliwhirl IR is one of my favorite cozy binder cards' } },
            ],
          },
        }),
      };
    }
    peerServiceCalled = true;
    return {
      ok: true,
      status: 200,
      json: async () => ({
        reply: 'Per domande tecniche ti mando alla documentazione ufficiale. Node docs.',
        intent: 'project',
      }),
    };
  };
  try {
    const assistant = loadAssistantWithStubs({
      env: {
        POKONTACT_SERVICE_TOKEN: 'secret',
      },
      marketplaceQuery: async (sql, values) => {
        assert.match(String(sql), /marketplace_search_candidates/);
        assert.deepEqual(values, ['Poliwhirl', '316262', 1]);
        return {
          rows: [{
            card_id: '316262',
            card_name: 'Poliwhirl',
            name: 'Poliwhirl',
            set_name: 'Scarlet & Violet 151',
            card_number: '176/165',
            rarity: 'Illustration Rare',
            canonical_path: '/marketplace/it/cards/632524/illustration-rare-poliwhirl-176-165-scarlet-violet-151',
            lowest_ask_pkn: 420,
            active_listing_count: 2,
            listed_quantity: 2,
          }],
        };
      },
    });
    const res = createResponse();

    await assistant({
      method: 'POST',
      headers: {},
      body: {
        message: 'come lo vedi come investimento questo?',
        messages: [],
        page: 'https://pokoin.com/marketplace/it/cards/632524/illustration-rare-poliwhirl-176-165-scarlet-violet-151',
        pageContext: assistant._test.cleanPageContext({
          kind: 'card',
          path: '/marketplace/it/cards/632524/illustration-rare-poliwhirl-176-165-scarlet-violet-151',
          activeCard: {
            id: '316262',
            name: 'Poliwhirl',
            set: 'Scarlet & Violet 151',
            number: '176/165',
            rarity: 'Illustration Rare',
            artist: 'Gemi',
          },
        }),
        username: 'guest',
      },
    }, res);

    assert.equal(res.statusCode, 200);
    assert.equal(peerServiceCalled, false);
    assert.equal(res.body.intent, 'card-context-opinion');
    assert.match(res.body.reply, /Poliwhirl/);
    assert.match(res.body.reply, /151/);
    assert.match(res.body.reply, /176\/165/);
    assert.match(res.body.reply, /Illustration Rare/);
    assert.match(res.body.reply, /Non è consulenza finanziaria/i);
    assert.match(res.body.reply, /sentiment collezionistico online|Tra i collezionisti/i);
    assert.doesNotMatch(res.body.reply, /Reddit/i);
    assert.doesNotMatch(res.body.reply, /la gente su reddit/i);
    assert.doesNotMatch(res.body.reply, /docs|node|documentazione ufficiale/i);
    assert.equal(res.body.serviceDelivery.provider, 'pokoin-current-card-context');
  } finally {
    global.fetch = originalFetch;
  }
});

test('card suggestion resolves to direct card navigation action', async () => {
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async (sql, values) => {
      assert.match(String(sql), /marketplace_search_candidates/);
      assert.match(String(sql), /marketplace_card_urls/);
      assert.equal(values[0], 'Mew ex');
      assert.equal(values[1], '232/091');
      return {
        rows: [{
          card_id: '274416',
          card_name: 'Mew ex',
          collector_number: '232/091',
          set_name: 'Paldean Fates',
          rarity: 'Special Illustration Rare',
          canonical_path: '/marketplace/en/cards/548832/stored-mew-ex-path',
        }],
      };
    },
  });

  const path = await assistant._test.resolveCardQueryPath('Mew ex 232/091', 'en');

  assert.equal(
    path,
    '/marketplace/en/cards/548832/stored-mew-ex-path',
  );
});

test('card suggestion resolves by specific card id first', async () => {
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async (sql, values) => {
      assert.match(String(sql), /marketplace_search_candidates/);
      assert.match(String(sql), /marketplace_card_urls/);
      assert.equal(values[0], '166430');
      assert.equal(values[1], 'en');
      return {
        rows: [{
          card_id: '166430',
          card_name: 'Dragonite V',
          collector_number: 'Ultra Rare | 192/203',
          set_name: 'Evolving Skies',
          rarity: 'Card',
          canonical_path: '/marketplace/en/cards/332860/card-dragonite-v-192-203-evolving-skies',
        }],
      };
    },
  });

  const path = await assistant._test.resolveCardQueryPath({
    name: 'Dragonite V',
    query: 'Dragonite V 192/203',
    cardId: '166430',
    setName: 'Evolving Skies',
    artist: 'Atsushi Furusawa',
  }, 'en');

  assert.equal(
    path,
    '/marketplace/en/cards/332860/card-dragonite-v-192-203-evolving-skies',
  );
});

test('card suggestion resolver falls back when collector number has rarity prefix', async () => {
  let callCount = 0;
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async (sql, values) => {
      callCount += 1;
      assert.match(String(sql), /marketplace_search_candidates/);
      if (callCount === 1) {
        assert.equal(values[0], '248856');
        assert.equal(values[1], 'en');
        return { rows: [] };
      }
      if (callCount === 2) {
        assert.equal(values[0], 'Magikarp');
        assert.equal(values[1], '203/193');
        return { rows: [] };
      }
      if (callCount === 3) {
        assert.equal(values[0], 'Magikarp');
        assert.equal(values[1], '203/193');
        return { rows: [] };
      }
      assert.match(String(sql), /regexp_replace/);
      assert.equal(values[0], 'Magikarp');
      assert.equal(values[1], '203/193');
      return {
        rows: [{
          card_id: '248856',
          card_name: 'Magikarp',
          collector_number: 'Illustration Rare | 203/193',
          set_name: 'Paldea Evolved',
          rarity: 'Card',
          canonical_path: '/marketplace/en/cards/497712/card-magikarp-203-193-paldea-evolved',
        }],
      };
    },
  });

  const path = await assistant._test.resolveCardQueryPath({
    name: 'Magikarp',
    query: 'Magikarp 203/193',
    cardId: '248856',
    setName: 'Paldea Evolved',
  }, 'en');

  assert.equal(
    path,
    '/marketplace/en/cards/497712/card-magikarp-203-193-paldea-evolved',
  );
});

test('curated card suggestion response includes navigate action for current tab', async () => {
  const originalRandom = Math.random;
  Math.random = () => 0.6;
  try {
    const assistant = loadAssistantWithStubs({
      marketplaceQuery: async (sql, values) => {
        assert.match(String(sql), /marketplace_search_candidates/);
        assert.match(String(sql), /marketplace_card_urls/);
        assert.equal(values[0], '274416');
        assert.equal(values[1], 'en');
        return {
          rows: [{
            card_id: '274416',
            card_name: 'Mew ex',
            collector_number: '232/091',
            set_name: 'Paldean Fates',
            rarity: 'Special Illustration Rare',
            canonical_path: '/marketplace/en/cards/548832/stored-mew-ex-path',
          }],
        };
      },
    });
    const res = createResponse();

    await assistant({
      method: 'POST',
      headers: {},
      body: {
        message: 'Suggest a cute card',
        messages: [],
        page: 'https://pokoin.com/marketplace/en',
        username: 'guest',
      },
    }, res);

    assert.equal(res.statusCode, 200);
    assert.equal(res.body.actions[0].type, 'navigate');
    assert.equal(res.body.actions[0].path, '/marketplace/en/cards/548832/stored-mew-ex-path');
    assert.match(res.body.reply, /https:\/\/pokoin\.com\/marketplace\/en\/cards\/548832\/stored-mew-ex-path/);
    assert.doesNotMatch(res.body.reply, /marketplace\/search/);
  } finally {
    Math.random = originalRandom;
  }
});

test('curated Dragonite suggestion opens direct card page instead of search', async () => {
  const originalRandom = Math.random;
  Math.random = () => 0.25;
  try {
    const assistant = loadAssistantWithStubs({
      marketplaceQuery: async (sql, values) => {
        assert.match(String(sql), /marketplace_search_candidates/);
        assert.match(String(sql), /marketplace_card_urls/);
        assert.equal(values[0], '166430');
        assert.equal(values[1], 'en');
        return {
          rows: [{
            card_id: '166430',
            card_name: 'Dragonite V',
            collector_number: 'Ultra Rare | 192/203',
            set_name: 'Evolving Skies',
            rarity: 'Card',
            canonical_path: '/marketplace/en/cards/332860/card-dragonite-v-192-203-evolving-skies',
          }],
        };
      },
    });
    const res = createResponse();

    await assistant({
      method: 'POST',
      headers: {},
      body: {
        message: 'Suggest a cute card',
        messages: [],
        page: 'https://pokoin.com/marketplace/en',
        username: 'guest',
      },
    }, res);

    assert.equal(res.statusCode, 200);
    assert.equal(res.body.actions[0].type, 'navigate');
    assert.equal(
      res.body.actions[0].path,
      '/marketplace/en/cards/332860/card-dragonite-v-192-203-evolving-skies',
    );
    assert.match(res.body.reply, /Dragonite V/);
    assert.match(res.body.reply, /https:\/\/pokoin\.com\/marketplace\/en\/cards\/332860\/card-dragonite-v-192-203-evolving-skies/);
    assert.doesNotMatch(res.body.reply, /marketplace\/search/);
  } finally {
    Math.random = originalRandom;
  }
});

test('Italian explicit Rayquaza card prompt opens Rayquaza direct card page', async () => {
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async (sql, values) => {
      assert.match(String(sql), /marketplace_search_candidates/);
      assert.match(String(sql), /marketplace_card_urls/);
      assert.deepEqual(values, ['rayquaza', '', 5]);
      return {
        rows: [{
          card_id: '123456',
          card_name: 'Rayquaza VMAX',
          name: 'Rayquaza VMAX',
          collector_number: '111/203',
          set_name: 'Evolving Skies',
          rarity: 'Ultra Rare',
          canonical_path: '/marketplace/en/cards/246912/ultra-rare-rayquaza-vmax-111-203-evolving-skies',
          lowest_ask_pkn: 125,
          active_listing_count: 2,
        }],
      };
    },
  });
  const res = createResponse();

  assert.equal(assistant._test.classifyIntent('fammi vedere una carta di rayquaza'), 'marketplace');
  assert.equal(assistant._test.explicitCardSubjectFromMessage('fammi vedere una carta di rayquaza'), 'rayquaza');
  await assistant({
    method: 'POST',
    headers: {},
    body: {
      message: 'fammi vedere una carta di rayquaza',
      messages: [],
      page: 'https://pokoin.com/marketplace/en',
      username: 'guest',
    },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.intent, 'marketplace');
  assert.equal(res.body.serviceDelivery.provider, 'pokoin-marketplace-tool');
  assert.equal(res.body.actions[0].type, 'navigate');
  assert.equal(
    res.body.actions[0].path,
    '/marketplace/en/cards/246912/ultra-rare-rayquaza-vmax-111-203-evolving-skies',
  );
  assert.match(res.body.reply, /Rayquaza VMAX/i);
  assert.match(res.body.reply, /Direct card page/i);
  assert.doesNotMatch(res.body.reply, /Mew ex|Poko card taste mode|My illustration pick/i);
});

test('English explicit Rayquaza card prompt opens Rayquaza direct card page', async () => {
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async (sql, values) => {
      assert.match(String(sql), /marketplace_search_candidates/);
      assert.match(String(sql), /marketplace_card_urls/);
      assert.deepEqual(values, ['rayquaza', '', 5]);
      return {
        rows: [{
          card_id: '98765',
          card_name: 'Rayquaza ex',
          name: 'Rayquaza ex',
          collector_number: '102/107',
          set_name: 'Deoxys',
          rarity: 'Ultra Rare',
          canonical_path: '/marketplace/en/cards/197530/ultra-rare-rayquaza-ex-102-107-deoxys',
        }],
      };
    },
  });
  const res = createResponse();

  assert.equal(assistant._test.classifyIntent('show me a Rayquaza card'), 'marketplace');
  assert.equal(assistant._test.explicitCardSubjectFromMessage('show me a Rayquaza card'), 'rayquaza');
  await assistant({
    method: 'POST',
    headers: {},
    body: {
      message: 'show me a Rayquaza card',
      messages: [],
      page: 'https://pokoin.com/marketplace/en',
      username: 'guest',
    },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.intent, 'marketplace');
  assert.equal(res.body.actions[0].type, 'navigate');
  assert.equal(
    res.body.actions[0].path,
    '/marketplace/en/cards/197530/ultra-rare-rayquaza-ex-102-107-deoxys',
  );
  assert.match(res.body.reply, /Rayquaza ex/i);
  assert.doesNotMatch(res.body.reply, /Mew ex|Poko card taste mode|My illustration pick/i);
});

test('casual gelato chat is not forced to docs, marketplace, or navigation', async () => {
  const originalFetch = global.fetch;
  let peerServiceCalled = false;
  global.fetch = async () => {
    peerServiceCalled = true;
    return {
      ok: true,
      status: 200,
      json: async () => ({
        reply: 'Per domande tecniche ti mando alla documentazione ufficiale.',
        intent: 'project',
        actions: [{ type: 'navigate', path: '/docs' }],
      }),
    };
  };
  try {
    const assistant = loadAssistantWithStubs({
      env: {
        POKONTACT_SERVICE_TOKEN: 'secret',
      },
      marketplaceQuery: async () => {
        throw new Error('marketplace should not be queried for casual chat');
      },
    });
    const res = createResponse();

    await assistant({
      method: 'POST',
      headers: {},
      body: {
        message: 'ti piace il gelato?',
        messages: [],
        page: 'https://pokoin.com/marketplace/en',
        username: 'guest',
      },
    }, res);

    assert.equal(res.statusCode, 200);
    assert.equal(peerServiceCalled, false);
    assert.equal(res.body.intent, 'casual');
    assert.match(res.body.reply, /gelato/i);
    assert.match(res.body.reply, /Vanillite/i);
    assert.doesNotMatch(res.body.reply, /docs|documentazione ufficiale|marketplace_search_candidates/i);
    assert.deepEqual(res.body.actions, []);
    assert.equal(res.body.serviceDelivery.reason, 'local_casual');
  } finally {
    global.fetch = originalFetch;
  }
});

test('pokemon gelato suggestion resolves to coherent Vanillite card navigation', async () => {
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async (sql, values) => {
      assert.match(String(sql), /marketplace_search_candidates/);
      assert.match(String(sql), /marketplace_card_urls/);
      assert.equal(values[0], 'Vanillite');
      assert.equal(values[1], '');
      return {
        rows: [{
          card_id: '555',
          card_name: 'Vanillite',
          name: 'Vanillite',
          collector_number: '043/198',
          set_name: 'Scarlet & Violet',
          rarity: 'Illustration Rare',
          canonical_path: '/marketplace/en/cards/1110/illustration-rare-vanillite-043-198-scarlet-violet',
        }],
      };
    },
  });
  const res = createResponse();

  await assistant({
    method: 'POST',
    headers: {},
    body: {
      message: 'consigliami un pokemon gelato',
      messages: [],
      page: 'https://pokoin.com/marketplace/en',
      username: 'guest',
    },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.intent, 'card');
  assert.match(res.body.reply, /ice cream|gelato/i);
  assert.match(res.body.reply, /Vanillite/);
  assert.doesNotMatch(res.body.reply, /Dragonite|Mew ex|Magikarp/);
    assert.equal(res.body.serviceDelivery.reason, 'local_card');
  assert.equal(res.body.actions[0].type, 'navigate');
  assert.equal(
    res.body.actions[0].path,
    '/marketplace/en/cards/1110/illustration-rare-vanillite-043-198-scarlet-violet',
  );
  assert.match(res.body.actions[0].path, /^\/marketplace\/en\/cards\/\d+\//);
});

test('cute Rayquaza recommendation uses analytics-backed direct card navigation', async () => {
  const queries = [];
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async (sql, values) => {
      queries.push(String(sql));
      assert.match(String(sql), /marketplace_search_candidates/);
      assert.match(String(sql), /marketplace_hot_blueprints/);
      assert.match(String(sql), /marketplace_blueprint_price_summary/);
      assert.match(String(sql), /cardtrader_blueprint_listing_cache/);
      assert.match(String(sql), /marketplace_blueprint_artists/);
      assert.deepEqual(values.slice(0, 5), [
        'rayquaza',
        '',
        ['cute'],
        '',
        ['rayquaza'],
      ]);
      return {
        rows: [{
          card_id: '123456',
          card_name: 'Rayquaza VMAX',
          name: 'Rayquaza VMAX',
          set_name: 'Evolving Skies',
          card_number: '111/203',
          rarity: 'Illustration Rare',
          canonical_path: '/marketplace/en/cards/246912/illustration-rare-rayquaza-vmax-111-203-evolving-skies',
          lowest_ask_pkn: 300,
          active_listing_count: 3,
          listed_quantity: 4,
          views_24h: 42,
          searches_24h: 12,
          clicks_24h: 5,
          sales_24h: 1,
          hot_score_24h: 88,
          recommendation_score: 1450,
          artist: 'Atsushi Furusawa',
        }],
      };
    },
  });
  const res = createResponse();

  await assistant({
    method: 'POST',
    headers: {},
    body: {
      message: 'fammi vedere una cute card di rayquaza',
      messages: [],
      page: 'https://pokoin.com/marketplace/en',
      sessionId: 'session-1',
      username: 'guest',
    },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.intent, 'card-recommendation');
  assert.equal(res.body.serviceDelivery.provider, 'pokoin-card-recommendation');
  assert.equal(res.body.actions[0].type, 'navigate');
  assert.equal(
    res.body.actions[0].path,
    '/marketplace/en/cards/246912/illustration-rare-rayquaza-vmax-111-203-evolving-skies',
  );
  assert.match(res.body.reply, /Rayquaza VMAX/);
  assert.match(res.body.reply, /Signals used|Segnali letti/i);
  assert.match(res.body.reply, /peer4\/read-only/i);
  assert.ok(queries.every((sql) => !/\b(insert|update|delete|drop|alter|truncate)\b/i.test(sql)));
});

test('personalized cute recommendation biases toward prior Rayquaza preference', async () => {
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async (sql, values) => {
      if (!String(sql).includes('input.favorite')) {
        return { rows: [] };
      }
      assert.equal(values[0], '');
      assert.deepEqual(values[2], ['cute']);
      assert.equal(values[5], 'rayquaza');
      return {
        rows: [{
          card_id: '123456',
          card_name: 'Rayquaza VMAX',
          name: 'Rayquaza VMAX',
          set_name: 'Evolving Skies',
          card_number: '111/203',
          rarity: 'Illustration Rare',
          canonical_path: '/marketplace/en/cards/246912/illustration-rare-rayquaza-vmax-111-203-evolving-skies',
          active_listing_count: 1,
          hot_score_24h: 10,
          recommendation_score: 700,
        }],
      };
    },
  });
  const res = createResponse();

  await assistant({
    method: 'POST',
    headers: {},
    body: {
      message: 'suggest a cute card',
      messages: [
        { role: 'user', text: 'I love Rayquaza and ice cards' },
        { role: 'assistant', text: 'Nice taste.' },
      ],
      page: 'https://pokoin.com/marketplace/en',
      sessionId: 'session-rayquaza',
      username: 'guest',
    },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.intent, 'card-recommendation');
  assert.match(res.body.reply, /Rayquaza VMAX/);
  assert.match(res.body.reply, /recent taste/i);
  assert.equal(res.body.userMemory.favoritePokemon[0], 'rayquaza');
  assert.equal(
    res.body.actions[0].path,
    '/marketplace/en/cards/246912/illustration-rare-rayquaza-vmax-111-203-evolving-skies',
  );
});

test('ice theme recommendation resolves Vanillite through read-only planner', async () => {
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async (sql, values) => {
      assert.match(String(sql), /seed_terms/);
      assert.equal(values[1], 'ice_cream');
      assert.deepEqual(values[4].slice(0, 3), ['Vanillite', 'Vanillish', 'Vanilluxe']);
      return {
        rows: [{
          card_id: '555',
          card_name: 'Vanillite',
          name: 'Vanillite',
          set_name: 'Scarlet & Violet',
          card_number: '043/198',
          rarity: 'Illustration Rare',
          canonical_path: '/marketplace/en/cards/1110/illustration-rare-vanillite-043-198-scarlet-violet',
          lowest_ask_pkn: 80,
          active_listing_count: 2,
          hot_score_24h: 12,
          recommendation_score: 900,
        }],
      };
    },
  });
  const res = createResponse();

  await assistant({
    method: 'POST',
    headers: {},
    body: {
      message: 'show me a cute ice card',
      messages: [],
      page: 'https://pokoin.com/marketplace/en',
      username: 'guest',
    },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.intent, 'card-recommendation');
  assert.match(res.body.reply, /Vanillite/);
  assert.equal(
    res.body.actions[0].path,
    '/marketplace/en/cards/1110/illustration-rare-vanillite-043-198-scarlet-violet',
  );
});

test('pokemon gelato suggestion avoids generic fallback when first ice match resolves', async () => {
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async (sql, values) => {
      assert.match(String(sql), /marketplace_search_candidates/);
      assert.equal(values[0], 'Vanillite');
      return {
        rows: [{
          card_id: '777',
          card_name: 'Vanillite',
          name: 'Vanillite',
          collector_number: '044/162',
          set_name: 'Temporal Forces',
          rarity: 'Common',
          canonical_path: '/marketplace/en/cards/1554/common-vanillite-044-162-temporal-forces',
        }],
      };
    },
  });

  const suggestion = await assistant._test.cardSuggestion({
    page: 'https://pokoin.com/marketplace/en',
    message: 'pokemon gelato',
    chatRecord: [],
  });

  assert.match(suggestion.reply, /Vanillite/);
  assert.doesNotMatch(suggestion.reply, /\b(Dragonite|Mew ex)\b/);
  assert.equal(suggestion.actions[0].type, 'navigate');
  assert.equal(
    suggestion.actions[0].path,
    '/marketplace/en/cards/1554/common-vanillite-044-162-temporal-forces',
  );
});

test('navigate actions are sanitized to safe internal direct card paths', () => {
  const assistant = loadAssistantWithStubs({});

  const actions = assistant._test.safeAssistantActions([
    { type: 'navigate', path: 'https://evil.example/cards/1' },
    { type: 'open_url', path: '/marketplace/en/cards/1110/vanillite' },
    { type: 'navigate', path: '//pokoin.com/marketplace/en/cards/1110/vanillite' },
    {
      type: 'navigate',
      data: {
        canonicalPath:
          '/marketplace/en/cards/1110/illustration-rare-vanillite-043-198-scarlet-violet',
      },
    },
  ]);

  assert.deepEqual(actions, [{
    type: 'navigate',
    data: {
      canonicalPath:
        '/marketplace/en/cards/1110/illustration-rare-vanillite-043-198-scarlet-violet',
    },
    path: '/marketplace/en/cards/1110/illustration-rare-vanillite-043-198-scarlet-violet',
  }]);
  assert.equal(assistant._test.isDirectMarketplaceCardPath(actions[0].path), true);
});

test('deck advisor gives beginner deck options from Limitless read-only data', async () => {
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async (sql, values) => {
      assert.match(String(sql), /limitless_public_decks/);
      assert.match(String(sql), /limitless_public_deck_core_cards/);
      assert.match(String(sql), /limitless_public_deck_results/);
      assert.deepEqual(values, ['', true, false, 'beginner']);
      return {
        rows: [{
          deck_id: 'charizard-ex',
          name: 'Charizard ex',
          format: 'STANDARD',
          format_label: 'Standard',
          rank: 1,
          points: 1200,
          share: 12.5,
          source_url: 'https://limitlesstcg.com/decks/charizard-ex',
          featured_decklist_id: '123',
          featured_tournament_name: 'Regional Championship',
          featured_tournament_date: '2026-05-01',
          core_cards: [
            { name: 'Charizard ex', count: 3, inclusionShare: 0.98 },
            { name: 'Pidgeot ex', count: 2, inclusionShare: 0.9 },
          ],
          recent_results: [
            {
              tournamentName: 'Regional Championship',
              tournamentDate: '2026-05-01',
              placing: 2,
              playerName: 'Test Player',
              decklistId: '123',
            },
          ],
        }],
      };
    },
  });
  const res = createResponse();

  await assistant({
    method: 'POST',
    headers: {},
    body: {
      message: 'best deck for beginners',
      messages: [],
      page: 'https://pokoin.com/marketplace/en',
      username: 'guest',
    },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.intent, 'deck-advisor');
  assert.equal(res.body.serviceDelivery.provider, 'pokoin-deck-advisor');
  assert.match(res.body.reply, /Charizard ex/);
  assert.match(res.body.reply, /How it works/);
  assert.match(res.body.reply, /Strengths/);
  assert.match(res.body.reply, /Weaknesses/);
  assert.match(res.body.reply, /Limitless/);
  assert.deepEqual(res.body.actions, []);
  assert.equal(res.body.marketplaceContext.readOnly, true);
});

test('deck advisor explains a named deck without claiming exact live win rates', async () => {
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async (sql, values) => {
      assert.match(String(sql), /limitless_public_decks/);
      assert.equal(values[0], 'gardevoir');
      return {
        rows: [{
          deck_id: 'gardevoir-ex',
          name: 'Gardevoir ex',
          format: 'STANDARD',
          format_label: 'Standard',
          rank: 4,
          points: 700,
          share: 6.2,
          source_url: 'https://limitlesstcg.com/decks/gardevoir-ex',
          core_cards: [
            { name: 'Gardevoir ex', count: 2, inclusionShare: 0.96 },
            { name: 'Kirlia', count: 4, inclusionShare: 0.94 },
          ],
          recent_results: [],
        }],
      };
    },
  });
  const res = createResponse();

  await assistant({
    method: 'POST',
    headers: {},
    body: {
      message: 'come funziona gardevoir ex deck?',
      messages: [],
      page: 'https://pokoin.com/marketplace/en',
      username: 'guest',
    },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.intent, 'deck-advisor');
  assert.match(res.body.reply, /Gardevoir ex/);
  assert.match(res.body.reply, /energy from the discard pile/i);
  assert.match(res.body.reply, /Weaknesses/);
  assert.doesNotMatch(res.body.reply, /\b\d+(\.\d+)?% win rate/i);
});

test('card lookup returns canonical public-number card URL', async () => {
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async (sql, values) => {
      assert.match(String(sql), /marketplace_search_candidates/);
      assert.equal(values[0], 'mew ex 232/091');
      return {
        rows: [{
          card_id: '274416',
          card_name: 'Mew ex',
          name: 'Mew ex',
          set_name: 'Paldean Fates',
          card_number: '232/091',
          rarity: 'Special Illustration Rare',
          canonical_path: '/marketplace/en/cards/548832/special-illustration-rare-mew-ex-232-091-paldean-fates',
          lowest_ask_pkn: 1200,
          active_listing_count: 2,
          listed_quantity: 3,
        }],
      };
    },
  });

  const result = await assistant._test.marketplaceGroundedDelivery({
    message: 'find card mew ex 232/091',
    chatRecord: [],
    page: 'https://pokoin.com/marketplace/en',
    pageContext: {},
  });

  assert.match(result.reply, /Direct card page/);
  assert.doesNotMatch(result.reply, /marketplace\/search/);
  assert.equal(
    result.actions[0].path,
    '/marketplace/en/cards/548832/special-illustration-rare-mew-ex-232-091-paldean-fates',
  );
});

test('peer service card search links are rewritten to direct card URLs', async () => {
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async (sql, values) => {
      assert.match(String(sql), /marketplace_search_candidates/);
      assert.equal(values[0], 'Drowzee');
      assert.equal(values[1], '10/198');
      return {
        rows: [{
          card_id: '12345',
          card_name: 'Drowzee',
          collector_number: '010/198',
          set_name: 'Scarlet & Violet',
          rarity: 'Illustration Rare',
        }],
      };
    },
  });

  const rewritten = await assistant._test.rewriteCardSuggestionLinks({
    reply: 'Search it on Pokoin: https://pokoin.com/marketplace/search?q=Drowzee%2010%2F198',
    intent: 'card',
    actions: [{
      type: 'navigate',
      path: '/marketplace/search?q=Drowzee%2010%2F198',
      label: 'Search Drowzee',
      data: { query: 'Drowzee 10/198' },
    }],
  }, 'https://pokoin.com/marketplace/en');

  assert.doesNotMatch(rewritten.reply, /(?:Open|Search) it on Pokoin/);
  assert.equal(
    rewritten.reply,
    'https://pokoin.com/marketplace/en/cards/24690/illustration-rare-drowzee-010-198-scarlet-violet',
  );
  assert.equal(
    rewritten.actions[0].path,
    '/marketplace/en/cards/24690/illustration-rare-drowzee-010-198-scarlet-violet',
  );
  assert.equal(rewritten.actions[0].label, 'Open Drowzee');
});

test('peer service card link rewrite adds navigate action when service omits actions', async () => {
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async (sql, values) => {
      assert.match(String(sql), /marketplace_search_candidates/);
      assert.match(String(sql), /marketplace_card_urls/);
      assert.equal(values[0], 'Drowzee');
      assert.equal(values[1], '10/198');
      return {
        rows: [{
          card_id: '12345',
          card_name: 'Drowzee',
          collector_number: '010/198',
          set_name: 'Scarlet & Violet',
          rarity: 'Illustration Rare',
          canonical_path: '/marketplace/en/cards/24690/stored-drowzee-path',
        }],
      };
    },
  });

  const rewritten = await assistant._test.rewriteCardSuggestionLinks({
    reply: 'Search it on Pokoin: https://pokoin.com/marketplace/search?q=Drowzee%2010%2F198',
    intent: 'card',
  }, 'https://pokoin.com/marketplace/en');

  assert.equal(rewritten.actions[0].type, 'navigate');
  assert.equal(
    rewritten.actions[0].path,
    '/marketplace/en/cards/24690/stored-drowzee-path',
  );
});

test('peer illustration pick with search action is rewritten to direct card URL', async () => {
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async (sql, values) => {
      assert.match(String(sql), /marketplace_search_candidates/);
      assert.match(String(sql), /marketplace_card_urls/);
      assert.equal(values[0], 'Dragonite V');
      assert.equal(values[1], '192/203');
      return {
        rows: [{
          card_id: '166430',
          card_name: 'Dragonite V',
          collector_number: 'Ultra Rare | 192/203',
          set_name: 'Evolving Skies',
          rarity: 'Card',
          canonical_path: '/marketplace/en/cards/332860/card-dragonite-v-192-203-evolving-skies',
        }],
      };
    },
  });

  const rewritten = await assistant._test.rewriteCardSuggestionLinks({
    reply: 'My illustration pick: Dragonite V by Atsushi Furusawa.\n\nSearch it on Pokoin: https://pokoin.com/marketplace/search?q=Dragonite%20V%20192%2F203',
    intent: 'general',
    actions: [{
      type: 'navigate',
      path: '/marketplace/search?q=Dragonite%20V%20192%2F203',
      label: 'Search Dragonite V',
      reason: 'cute_card_suggestion',
      data: { query: 'Dragonite V 192/203' },
    }],
  }, 'https://pokoin.com/marketplace/en');

  assert.doesNotMatch(rewritten.reply, /(?:Open|Search) it on Pokoin/);
  assert.doesNotMatch(rewritten.reply, /marketplace\/search/);
  assert.equal(
    rewritten.actions[0].path,
    '/marketplace/en/cards/332860/card-dragonite-v-192-203-evolving-skies',
  );
});

test('peer card reply with direct URL removes open-it phrasing', async () => {
  const assistant = loadAssistantWithStubs({});

  const rewritten = await assistant._test.rewriteCardSuggestionLinks({
    reply: 'Open it on Pokoin: https://pokoin.com/marketplace/en/cards/548832/special-illustration-rare-mew-ex-232-091-paldean-fates',
    intent: 'card',
    actions: [{
      type: 'navigate',
      path: '/marketplace/en/cards/548832/special-illustration-rare-mew-ex-232-091-paldean-fates',
      label: 'Open Mew ex',
      reason: 'cute_card_suggestion',
    }],
  }, 'https://pokoin.com/marketplace/en');

  assert.equal(
    rewritten.reply,
    'https://pokoin.com/marketplace/en/cards/548832/special-illustration-rare-mew-ex-232-091-paldean-fates',
  );
  assert.equal(
    rewritten.actions[0].path,
    '/marketplace/en/cards/548832/special-illustration-rare-mew-ex-232-091-paldean-fates',
  );
});

test('greeting returns JSON fallback when peer service is not configured', async () => {
  const assistant = loadAssistantWithStubs({});
  const res = createResponse();

  await assistant({
    method: 'POST',
    headers: {},
    body: {
      message: 'ciao',
      messages: [],
      page: 'https://pokoin.com/marketplace',
      username: 'guest',
    },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.assistant, 'Pokontact');
  assert.equal(res.body.intent, 'greeting');
  assert.match(res.body.reply, /^Ciao! Sono Poko/);
  assert.deepEqual(res.body.actions, []);
  assert.equal(res.body.serviceDelivery.ok, false);
  assert.equal(res.body.serviceDelivery.skipped, true);
  assert.equal(res.body.serviceDelivery.reason, 'local_greeting');
});

test('assistant sanitizes and returns structured page context on greeting', async () => {
  const assistant = loadAssistantWithStubs({});
  const res = createResponse();

  await assistant({
    method: 'POST',
    headers: {},
    body: {
      message: 'ciao',
      messages: [],
      page: 'https://pokoin.com/marketplace/search?q=Magikarp%20203%2F193&token=secret',
      pageContext: {
        url: 'https://pokoin.com/marketplace/search?q=Magikarp%20203%2F193&token=secret',
        internalUri: '/marketplace/search?q=Magikarp%20203%2F193',
        path: '/marketplace/search',
        kind: 'search',
        searchQuery: 'Magikarp 203/193',
        queryParameters: { q: 'Magikarp 203/193', token: 'secret' },
        filters: { productType: 'card', authToken: 'secret' },
        visibleCards: [{
          id: '248856',
          name: 'Magikarp',
          set: 'Paldea Evolved',
          number: '203/193',
          canonicalPath: '/marketplace/en/cards/497712/card-magikarp-203-193-paldea-evolved',
          token: 'secret',
        }],
      },
      username: 'guest',
    },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.intent, 'greeting');
  assert.equal(res.body.pageContext.kind, 'search');
  assert.doesNotMatch(res.body.pageContext.url, /token=secret/);
  assert.equal(res.body.pageContext.searchQuery, 'Magikarp 203/193');
  assert.equal(res.body.pageContext.filters.productType, 'card');
  assert.equal(res.body.pageContext.filters.authToken, undefined);
  assert.equal(res.body.pageContext.queryParameters.token, undefined);
  assert.equal(res.body.pageContext.visibleCards[0].cardId, '248856');
  assert.equal(res.body.pageContext.visibleCards[0].collectorNumber, '203/193');
});

test('greeting bypasses peer service even when configured', async () => {
  const originalFetch = global.fetch;
  let fetchCalled = false;
  global.fetch = async () => {
    fetchCalled = true;
    return {
      ok: true,
      status: 200,
      json: async () => ({
        reply: 'Opening a card unexpectedly',
        intent: 'card',
        actions: [{ type: 'navigate', path: '/marketplace/search?q=Mew' }],
      }),
    };
  };
  try {
    const assistant = loadAssistantWithStubs({
      env: {
        POKONTACT_SERVICE_TOKEN: 'secret',
      },
    });
    const res = createResponse();

    await assistant({
      method: 'POST',
      headers: {},
      body: {
        message: 'ciao',
        messages: [],
        page: 'https://pokoin.com/marketplace/search?q=Magikarp%20203%2F193',
        username: 'guest',
      },
    }, res);

    assert.equal(res.statusCode, 200);
    assert.equal(fetchCalled, false);
    assert.equal(res.body.intent, 'greeting');
    assert.deepEqual(res.body.actions, []);
    assert.equal(res.body.serviceDelivery.skipped, true);
    assert.equal(res.body.serviceDelivery.reason, 'local_greeting');
  } finally {
    global.fetch = originalFetch;
  }
});

test('quick project prompt returns local Poko explanation, not card lookup failure', async () => {
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async () => {
      throw new Error('marketplace should not be queried for project prompt');
    },
  });
  const res = createResponse();

  await assistant({
    method: 'POST',
    headers: {},
    body: {
      message: 'Explain Pokoin simply',
      messages: [],
      page: 'https://pokoin.com/marketplace',
      username: 'guest',
    },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.intent, 'project');
  assert.match(res.body.reply, /I am Poko/);
  assert.match(res.body.reply, /Pokoin is a collector project/);
  assert.match(res.body.reply, /marketplace.*cart.*checkout.*orders/i);
  assert.match(res.body.reply, /sharded into PKN value/i);
  assert.match(res.body.reply, /marketplace flows|order flows/i);
  assert.doesNotMatch(res.body.reply, /CardTrader/i);
  assert.doesNotMatch(res.body.reply, /could not resolve a direct card page/i);
});

test('shard question explains Earn PKN review flow without forbidden provider name', async () => {
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async () => {
      throw new Error('marketplace should not be queried for shard explanation');
    },
  });
  const res = createResponse();

  await assistant({
    method: 'POST',
    headers: {},
    body: {
      message: 'how do shards work?',
      messages: [],
      page: 'https://pokoin.com/earn',
      username: 'guest',
    },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.intent, 'earn');
  assert.match(res.body.reply, /Earn PKN \/ PKN Shard Review/i);
  assert.match(res.body.reply, /card list or full decklist/i);
  assert.match(res.body.reply, /eligible.*sharded into PKN value/i);
  assert.match(res.body.reply, /not an instant guaranteed disenchant button/i);
  assert.doesNotMatch(res.body.reply, /CardTrader/i);
});

test('turn cards into new cards prompt includes shard and order concept', async () => {
  const assistant = loadAssistantWithStubs({});
  const res = createResponse();

  await assistant({
    method: 'POST',
    headers: {},
    body: {
      message: 'can I turn cards into new cards?',
      messages: [],
      page: 'https://pokoin.com/marketplace',
      username: 'guest',
    },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.intent, 'earn');
  assert.match(res.body.reply, /eligible.*sharded into PKN value/i);
  assert.match(res.body.reply, /used toward cards you actually want/i);
  assert.match(res.body.reply, /marketplace\/order flows/i);
  assert.doesNotMatch(res.body.reply, /CardTrader/i);
});

test('Italian videogame shard prompt gets Italian review-flow answer', async () => {
  const assistant = loadAssistantWithStubs({});
  const res = createResponse();

  await assistant({
    method: 'POST',
    headers: {},
    body: {
      message: 'come funziona il sistema tipo videogame?',
      messages: [],
      page: 'https://pokoin.com/shard-review',
      username: 'guest',
    },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.intent, 'earn');
  assert.match(res.body.reply, /Sì: su Pokoin esiste il flusso Earn PKN/i);
  assert.match(res.body.reply, /lista di carte o un decklist/i);
  assert.match(res.body.reply, /sharded into PKN/i);
  assert.match(res.body.reply, /non è un pulsante automatico garantito/i);
  assert.doesNotMatch(res.body.reply, /CardTrader/i);
});

test('quick cute-card prompt returns curated card suggestion action', async () => {
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async () => ({ rows: [] }),
  });
  const res = createResponse();

  await assistant({
    method: 'POST',
    headers: {},
    body: {
      message: 'Suggest a cute card',
      messages: [],
      page: 'https://pokoin.com/marketplace/en',
      username: 'guest',
    },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.intent, 'card');
  assert.match(res.body.reply, /Poko card taste mode activated/);
  assert.doesNotMatch(res.body.reply, UNSUPPORTED_POKO_EMOJI);
  assert.doesNotMatch(res.body.reply, /could not resolve a direct card page/i);
  assert.equal(res.body.actions[0].type, 'navigate');
});

test('local Poko replies avoid unsupported emoji glyphs', async () => {
  const assistant = loadAssistantWithStubs({
    marketplaceQuery: async () => ({ rows: [] }),
  });

  const sanitized = assistant._test.sanitizePokoEmoji('fun card suggestions! 🃏🫧��');
  assert.doesNotMatch(sanitized, UNSUPPORTED_POKO_EMOJI);
  assert.doesNotMatch(sanitized, /\uFFFD/);

  for (const message of [
    'Explain Pokoin simply',
    'Explain PKN and wallets',
    'Suggest a cute card',
  ]) {
    const res = createResponse();
    await assistant({
      method: 'POST',
      headers: {},
      body: {
        message,
        messages: [],
        page: 'https://pokoin.com/marketplace/en',
        username: 'guest',
      },
    }, res);

    assert.equal(res.statusCode, 200);
    assert.doesNotMatch(res.body.reply, UNSUPPORTED_POKO_EMOJI);
  }
});

test('service URL resolves to documented Oracle peer2 endpoint by default', () => {
  const assistant = loadAssistantWithStubs({});

  assert.equal(
    assistant._test.resolvePokontactServiceUrl({}),
    assistant._test.DEFAULT_POKONTACT_SERVICE_URL,
  );
  assert.equal(
    assistant._test.resolvePokontactServiceUrl({ POKONTACT_SERVICE_URL: 'https://pokontact.example/' }),
    'https://pokontact.example',
  );
});

test('token-only configuration calls documented Oracle peer2 endpoint', async () => {
  const originalFetch = global.fetch;
  let requestedUrl = '';
  let requestBody = null;
  global.fetch = async (url, options) => {
    requestedUrl = String(url);
    requestBody = JSON.parse(options.body);
    return {
      ok: true,
      status: 200,
      json: async () => ({
        reply: 'Oracle Poko is awake ✨',
        intent: 'general',
        provider: 'local-ollama',
        model: 'qwen2.5:0.5b',
        source: 'peer2-service',
      }),
    };
  };
  try {
    const assistant = loadAssistantWithStubs({
      env: {
        POKONTACT_SERVICE_TOKEN: 'secret',
      },
    });
    const res = createResponse();

    await assistant({
      method: 'POST',
      headers: {},
      body: {
        message: 'tell me something',
        messages: [],
        page: 'https://pokoin.com/marketplace',
        pageContext: {
          kind: 'search',
          internalUri: '/marketplace/search?q=Magikarp',
          searchQuery: 'Magikarp',
          visibleCards: [{ id: '248856', name: 'Magikarp' }],
        },
        username: 'guest',
      },
    }, res);

    assert.equal(res.statusCode, 200);
    assert.equal(requestedUrl, `${assistant._test.DEFAULT_POKONTACT_SERVICE_URL}/chat`);
    assert.equal(requestBody.pageContext.kind, 'search');
    assert.match(requestBody.context, /Current page kind: search/);
    assert.match(requestBody.context, /Current search query: Magikarp/);
    assert.match(requestBody.context, /Visible cards/);
    assert.equal(res.body.reply, 'Oracle Poko is awake ✨');
    assert.equal(res.body.serviceDelivery.ok, true);
    assert.equal(res.body.serviceDelivery.source, 'peer2-service');
  } finally {
    global.fetch = originalFetch;
  }
});

test('peer service failures fall back to local JSON reply', async () => {
  const originalFetch = global.fetch;
  global.fetch = async () => ({
    ok: false,
    status: 503,
    json: async () => ({ error: 'peer2 down' }),
  });
  try {
    const assistant = loadAssistantWithStubs({
      env: {
        POKONTACT_SERVICE_URL: 'https://pokontact.example',
        POKONTACT_SERVICE_TOKEN: 'secret',
      },
    });
    const res = createResponse();

    await assistant({
      method: 'POST',
      headers: {},
      body: {
        message: 'what is pokoin',
        messages: [],
        page: 'https://pokoin.com/marketplace',
        username: 'guest',
      },
    }, res);

    assert.equal(res.statusCode, 200);
    assert.equal(res.body.intent, 'project');
    assert.match(res.body.reply, /Pokoin is a collector project/);
    assert.equal(res.body.serviceDelivery.ok, false);
    assert.match(res.body.serviceDelivery.error, /peer2 down/);
  } finally {
    global.fetch = originalFetch;
  }
});
