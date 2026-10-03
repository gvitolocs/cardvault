const assert = require('node:assert/strict');
const test = require('node:test');
const candidateHandler = require('./marketplace-search-candidates');
const { createHandler: createSearchPage } = require('./marketplace-search-page');
const {
  nonNameCategoryPlan,
  buildNonNameContext,
  searchNonNameCategoryWithContext,
  searchNonNameWithDatabase,
  searchVariationReplicaNonNameWithDatabase,
  rowsForSearchTerm,
  searchRowsByCardIdsIdentity,
  searchTerms,
  collectorNumberKey,
  rankRowsByQueryCollectorNumber,
} = require('./marketplace-search-candidates');

function row({ id, name, set = 'Test Set', number = '001/100', rarity = 'Card', rank = 0 }) {
  return {
    card_id: id,
    name,
    set_name: set,
    card_number: number,
    rarity,
    card_type: 'Lightning',
    item_kind: 'single',
    product_type: 'card',
    trainer_name: '',
    search_rank: rank,
  };
}

function responseMock() {
  return {
    headers: {}, statusCode: 200, body: null,
    setHeader(key, value) { this.headers[key] = value; },
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; },
    end() { return this; },
  };
}

test('browser search fallback accepts JSON POST preflight and exposes CORS on responses', async () => {
  const preflight = responseMock();
  await candidateHandler({ method: 'OPTIONS', headers: { origin: 'http://127.0.0.1:5000' } }, preflight);
  assert.equal(preflight.statusCode, 204);
  assert.equal(preflight.headers['Access-Control-Allow-Origin'], '*');
  assert.match(preflight.headers['Access-Control-Allow-Methods'], /POST/);
  assert.match(preflight.headers['Access-Control-Allow-Headers'], /Content-Type/);
  assert.match(preflight.headers['Access-Control-Allow-Headers'], /Authorization/);
  const post = responseMock();
  await candidateHandler({ method: 'POST', body: { search_term: '' } }, post);
  assert.equal(post.statusCode, 200);
  assert.deepEqual(post.body, []);
  assert.equal(post.headers['Access-Control-Allow-Origin'], '*');
});

test('search page serializes hydrated Meili cards after asynchronous theme enrichment', async () => {
  const savedEngine = process.env.MARKETPLACE_SEARCH_ENGINE;
  const modulePaths = ['./_marketplace_db', './_meili_marketplace', './_marketplace_react_sql', './marketplace-search-candidates'].map(require.resolve);
  const savedModules = modulePaths.map((path) => require.cache[path]);
  const card = { ...row({ id: '226324', name: 'Reshiram & Zekrom GX', set: 'Cosmic Eclipse' }), image_url: 'https://cdn.pokoin.com/226324_card.jpg' };
  try {
    process.env.MARKETPLACE_SEARCH_ENGINE = 'meili';
    require.cache[modulePaths[0]] = { exports: { ...savedModules[0].exports, marketplaceQuery: async () => ({ rows: [card] }) } };
    require.cache[modulePaths[1]] = { exports: { ...savedModules[1].exports, meiliMarketplaceCandidates: async () => ({ hits: [{ card_id: '226324' }], estimatedTotalHits: 8 }) } };
    require.cache[modulePaths[2]] = { exports: { ...savedModules[2].exports, readCardThemePacks: async () => { await Promise.resolve(); return new Map(); } } };
    delete require.cache[modulePaths[3]];
    const isolated = require('./marketplace-search-candidates');
    const handler = createSearchPage({
      rowsForCards: ({ query, limit, offset, searchLanguage, ...options }) => isolated.rowsForSearchTerm(query, limit, offset, searchLanguage, null, null, options),
      overlayCheapestOnRows: async (rows) => rows,
      attachTitleLanguageOnRows: null,
      productFacetRows: async () => [],
    });
    const res = responseMock();
    await handler({ method: 'GET', url: '/api/marketplace-search-page?q=Reshiram&includeFacets=0', headers: { host: 'api.pokoin.com' } }, res);
    const json = JSON.parse(JSON.stringify(res.body));
    assert.equal(json.total, 8);
    assert.equal(json.count, 1);
    assert.equal(json.cards[0].name, 'Reshiram & Zekrom GX');
    assert.equal(json.cards[0].set, 'Cosmic Eclipse');
    assert.ok(json.cards[0].imageUrl);
    const legacy = await isolated.rowsForSearchTerm('Reshiram', 20, 0, 'en');
    assert.ok(Array.isArray(legacy));
    assert.equal(legacy[0].card_id, '226324');
  } finally {
    modulePaths.forEach((path, index) => { require.cache[path] = savedModules[index]; });
    if (savedEngine === undefined) delete process.env.MARKETPLACE_SEARCH_ENGINE;
    else process.env.MARKETPLACE_SEARCH_ENGINE = savedEngine;
  }
});

function categoryQueryMock(fixtures) {
  return async (sql, values) => {
    const token = values[0];
    if (/where c\.card_id = any\(\$1::bigint\[\]\)/.test(sql)) {
      const ids = new Set((values[0] || []).map((id) => String(id)));
      return {
        rows: (fixtures.byId || []).filter((candidate) =>
          ids.has(String(candidate.card_id))),
      };
    }
    if (/marketplace_expansion_numbers/.test(sql)) {
      return { rows: fixtures.number?.[token] || [] };
    }
    if (/marketplace_card_variations/.test(sql)) {
      return { rows: fixtures.variation?.[token] || [] };
    }
    if (/pokoin_pokemon_expansions|marketplace_expansion_aliases/.test(sql)) {
      return { rows: fixtures.expansion?.[token] || [] };
    }
    if (/marketplace_rarities/.test(sql)) {
      return { rows: fixtures.rarity?.[token] || [] };
    }
    if (/trainer_name|product_variant/.test(sql)) {
      return { rows: fixtures.trainer_or_variant?.[token] || [] };
    }
    return { rows: [] };
  };
}

test('non-name category planner targets only relevant token families', () => {
  assert.deepEqual(nonNameCategoryPlan('pikachu 151').tokens, [
    {
      term: 'pikachu',
      categories: ['trainer_or_variant'],
    },
    {
      term: '151',
      categories: ['number', 'expansion'],
    },
  ]);
  assert.deepEqual(nonNameCategoryPlan('manaphy ex').tokens, [
    {
      term: 'manaphy',
      categories: ['trainer_or_variant'],
    },
    {
      term: 'ex',
      categories: ['variation'],
    },
  ]);
  assert.deepEqual(nonNameCategoryPlan('mew 232').tokens[1], {
    term: '232',
    categories: ['number', 'expansion'],
  });
});

test('non-name category planner recognizes HGSS era expansion aliases', () => {
  assert.deepEqual(nonNameCategoryPlan('rare candy hgss').tokens, [
    {
      term: 'rare',
      categories: ['rarity'],
    },
    {
      term: 'candy',
      categories: ['expansion', 'trainer_or_variant'],
    },
    {
      term: 'hgss',
      categories: ['expansion', 'trainer_or_variant'],
    },
  ]);
  assert(nonNameCategoryPlan('rare candy heartgold').tokens.some((token) =>
    token.term === 'heartgold' && token.categories.includes('expansion')));
  assert(nonNameCategoryPlan('rare candy soulsilver').tokens.some((token) =>
    token.term === 'soulsilver' && token.categories.includes('expansion')));
});

test('meili-only candidate fetch returns empty without legacy split fallback', async () => {
  const originalEngine = process.env.MARKETPLACE_SEARCH_ENGINE;
  const originalHost = process.env.MEILI_HOST;
  const originalFetch = global.fetch;
  try {
    process.env.MARKETPLACE_SEARCH_ENGINE = 'meili';
    process.env.MEILI_HOST = 'http://meili.test';
    global.fetch = async () => ({
      ok: true,
      text: async () => JSON.stringify({ hits: [] }),
    });
    const debug = {};
    const rows = await rowsForSearchTerm('p', 20, 0, 'en', debug, null, { meiliOnly: true });

    assert.deepEqual(rows, []);
    assert.equal(debug.searchPath, 'meili_en_candidates');
    assert.equal(debug.searchEngine.mode, 'meili');
    assert.equal(debug.searchEngine.candidateCount, 0);
  } finally {
    if (originalEngine === undefined) delete process.env.MARKETPLACE_SEARCH_ENGINE;
    else process.env.MARKETPLACE_SEARCH_ENGINE = originalEngine;
    if (originalHost === undefined) delete process.env.MEILI_HOST;
    else process.env.MEILI_HOST = originalHost;
    global.fetch = originalFetch;
  }
});

test('meili-only candidate fetch delegates unavailable fallback to caller', async () => {
  const originalEngine = process.env.MARKETPLACE_SEARCH_ENGINE;
  const originalHost = process.env.MEILI_HOST;
  const originalFetch = global.fetch;
  const originalError = console.error;
  try {
    process.env.MARKETPLACE_SEARCH_ENGINE = 'meili';
    process.env.MEILI_HOST = 'http://meili.test';
    global.fetch = async () => {
      throw new Error('meili down');
    };
    console.error = () => {};
    const debug = {};
    const rows = await rowsForSearchTerm('p', 20, 0, 'en', debug, null, { meiliOnly: true });

    assert.deepEqual(rows, []);
    assert.equal(debug.searchPath, 'meili_en_unavailable');
    assert.equal(debug.searchEngine.fallback, 'caller');
    assert.match(debug.searchEngine.reason, /meili down/);
  } finally {
    if (originalEngine === undefined) delete process.env.MARKETPLACE_SEARCH_ENGINE;
    else process.env.MARKETPLACE_SEARCH_ENGINE = originalEngine;
    if (originalHost === undefined) delete process.env.MEILI_HOST;
    else process.env.MEILI_HOST = originalHost;
    global.fetch = originalFetch;
    console.error = originalError;
  }
});

test('non-name category planner preserves short variation prefixes', () => {
  assert.deepEqual(searchTerms('mimikyu g'), ['mimikyu', 'g']);
  assert.deepEqual(nonNameCategoryPlan('mimikyu g').tokens, [
    {
      term: 'mimikyu',
      categories: ['trainer_or_variant'],
    },
    {
      term: 'g',
      categories: ['variation'],
    },
  ]);
  assert.deepEqual(nonNameCategoryPlan('pikachu vm').tokens[1], {
    term: 'vm',
    categories: ['variation'],
  });
});

test('non-name fanout runs number and expansion categories for collector set queries', async () => {
  const debug = {};
  const rows = await searchNonNameWithDatabase(
    'pikachu 151',
    20,
    0,
    'en',
    debug,
    categoryQueryMock({
      number: {
        151: [row({ id: '1', name: 'Pikachu', set: 'Collect 151', number: '170/151', rank: 2000 })],
      },
      expansion: {
        151: [row({ id: '2', name: 'Charmander', set: 'Collect 151', number: '004/151', rank: 1000 })],
      },
    }),
  );

  assert.equal(debug.nonNameCategoryFanout.used, true);
  assert(debug.nonNameCategoryFanout.steps.some((step) => step.category === 'number' && step.term === '151'));
  assert(debug.nonNameCategoryFanout.steps.some((step) => step.category === 'expansion' && step.term === '151'));
  assert.equal(rows[0].name, 'Pikachu');
});

test('non-name fanout keeps variation matches blueprint-ranked', async () => {
  const rows = await searchNonNameWithDatabase(
    'manaphy ex',
    20,
    0,
    'en',
    {},
    categoryQueryMock({
      variation: {
        ex: [
          row({ id: '110433', name: 'Manaphy ex', rank: 5000 }),
          row({ id: '9', name: 'Absol ex', rank: 1000 }),
        ],
      },
    }),
  );

  assert.deepEqual(rows.map((result) => result.name), ['Manaphy ex', 'Absol ex']);
});

test('non-name fanout treats variation prefixes before expansion/set matches', async () => {
  const rows = await searchNonNameWithDatabase(
    'mimikyu g',
    20,
    0,
    'en',
    {},
    categoryQueryMock({
      variation: {
        g: [
          row({ id: '2', name: 'Mimikyu GX', set: 'Lost Thunder', rank: 5000 }),
        ],
      },
    }),
  );

  assert.deepEqual(rows.map((result) => result.name), ['Mimikyu GX']);
});

test('non-name fanout uses expansion/set category for typo set tokens', async () => {
  const rows = await searchNonNameWithDatabase(
    'pikachu surgin',
    20,
    0,
    'en',
    {},
    categoryQueryMock({
      expansion: {
        surgin: [
          row({ id: '1', name: 'Pikachu ex', set: 'Surging Sparks', rank: 4000 }),
          row({ id: '2', name: 'Surfing Pikachu', set: 'Celebrations', rank: 1000 }),
        ],
      },
    }),
  );

  assert.equal(rows[0].set_name, 'Surging Sparks');
});

test('non-name context builder keeps bounded per-category ids', () => {
  const context = buildNonNameContext('en', [
    {
      category: 'expansion',
      term: 'surg',
      strategy: 'category_sql',
      cardIds: ['1', '2'],
    },
  ]);

  assert.deepEqual(context.expansion.card_ids, ['1', '2']);
  assert.equal(context.expansion.query, 'surg');
  assert.equal(context.expansion.language, 'en');
});

test('non-name category context refines extended category tokens', async () => {
  const result = await searchNonNameCategoryWithContext(
    'expansion',
    { term: 'surgin' },
    20,
    'en',
    {
      non_name_context: {
        expansion: {
          query: 'surg',
          language: 'en',
          card_ids: ['1', '2'],
          created_at_ms: Date.now(),
        },
      },
    },
    async () => ({
      rows: [
        row({ id: '1', name: 'Pikachu ex', set: 'Surging Sparks', rank: 2000 }),
        row({ id: '2', name: 'Surfing Pikachu', set: 'Celebrations', rank: 1000 }),
        row({ id: '3', name: 'Pikachu', set: 'Base Set', rank: 9000 }),
      ],
    }),
  );

  assert.equal(result.strategy, 'category_context_refine');
  assert.deepEqual(result.rows.map((item) => item.card_id), ['1']);
});

test('non-name fanout uses category context before SQL helper', async () => {
  const debug = {};
  const rows = await searchNonNameWithDatabase(
    'pikachu surgin',
    20,
    0,
    'en',
    debug,
    categoryQueryMock({
      byId: [
        row({ id: '1', name: 'Pikachu ex', set: 'Surging Sparks', rank: 2000 }),
        row({ id: '2', name: 'Surfing Pikachu', set: 'Celebrations', rank: 1000 }),
      ],
      expansion: {
        surgin: [row({ id: '9', name: 'Fallback Pikachu', set: 'Surging Sparks', rank: 1 })],
      },
    }),
    {
      non_name_context: {
        expansion: {
          query: 'surg',
          language: 'en',
          card_ids: ['1', '2'],
          created_at_ms: Date.now(),
        },
      },
    },
  );

  assert.equal(rows[0].card_id, '1');
  assert(
    debug.nonNameCategoryFanout.steps.some((step) =>
      step.category === 'expansion' &&
      step.term === 'surgin' &&
      step.strategy === 'category_context_refine'),
  );
});

test('variation replica timeout opens primary fallback path', async () => {
  const originalTimeout = process.env.MARKETPLACE_VARIATION_SEARCH_TIMEOUT_MS;
  const originalCircuit = process.env.MARKETPLACE_VARIATION_SEARCH_CIRCUIT_MS;
  process.env.MARKETPLACE_VARIATION_SEARCH_TIMEOUT_MS = '250';
  process.env.MARKETPLACE_VARIATION_SEARCH_CIRCUIT_MS = '5000';
  try {
    const debug = {};
    const rows = await searchVariationReplicaNonNameWithDatabase(
      'ex',
      20,
      0,
      'en',
      debug,
      null,
      async (sql, values) => {
        assert.match(sql, /marketplace_card_variations|search_marketplace_blueprint_non_name_candidates/);
        assert.equal(values[0], 'ex');
        return {
          rows: [
            row({ id: '110433', name: 'Manaphy ex', rank: 5000 }),
          ],
        };
      },
      async () => new Promise(() => {}),
    );

    assert.equal(debug.variationSearch.path, 'primary_fallback');
    assert.equal(debug.variationSearch.code, 'MARKETPLACE_SEARCH_TIMEOUT');
    assert.deepEqual(rows.map((result) => result.name), ['Manaphy ex']);
  } finally {
    if (originalTimeout === undefined) {
      delete process.env.MARKETPLACE_VARIATION_SEARCH_TIMEOUT_MS;
    } else {
      process.env.MARKETPLACE_VARIATION_SEARCH_TIMEOUT_MS = originalTimeout;
    }
    if (originalCircuit === undefined) {
      delete process.env.MARKETPLACE_VARIATION_SEARCH_CIRCUIT_MS;
    } else {
      process.env.MARKETPLACE_VARIATION_SEARCH_CIRCUIT_MS = originalCircuit;
    }
  }
});

test('rankRowsByQueryCollectorNumber prefers the matching set number', () => {
  assert.equal(collectorNumberKey('Illustration Rare | 210/198'), '210/198');
  const ranked = rankRowsByQueryCollectorNumber([
    { card_id: '220438', name: 'Drowzee', card_number: '74a/147' },
    { card_id: '483348', name: 'Drowzee', card_number: 'Illustration Rare | 210/198' },
  ], 'Drowzee 210/198');
  assert.equal(ranked[0].card_id, '483348');
});

test('identity hydrate skips cheapest listing cache', async () => {
  let sql = '';
  const rows = await searchRowsByCardIdsIdentity(['220962'], async (queryText, values) => {
    sql = queryText;
    assert.deepEqual(values, [['220962']]);
    return {
      rows: [{
        card_id: '220962',
        name: 'Espurr',
        card_number: '42/146',
        set_name: 'XY',
      }],
    };
  });
  assert.equal(rows.length, 1);
  assert.doesNotMatch(sql, /cheapest_homepage_cache_blueprint/);
  assert.match(sql, /marketplace_search_candidates/);
});

test('Meili search page requests pageSize hits, not a numbered over-fetch', async () => {
  const originalEngine = process.env.MARKETPLACE_SEARCH_ENGINE;
  const originalHost = process.env.MEILI_HOST;
  const originalFetch = global.fetch;
  let capturedLimit = null;
  try {
    process.env.MARKETPLACE_SEARCH_ENGINE = 'meili';
    process.env.MEILI_HOST = 'http://meili.test';
    global.fetch = async (_url, options) => {
      const body = JSON.parse(options.body);
      capturedLimit = body.limit;
      return {
        ok: true,
        text: async () => JSON.stringify({ hits: [] }),
      };
    };
    await rowsForSearchTerm('Drowzee 210/198', 24, 0, 'en', {}, null, { lightHydrate: true });
    assert.equal(capturedLimit, 24);
  } finally {
    if (originalEngine === undefined) delete process.env.MARKETPLACE_SEARCH_ENGINE;
    else process.env.MARKETPLACE_SEARCH_ENGINE = originalEngine;
    if (originalHost === undefined) delete process.env.MEILI_HOST;
    else process.env.MEILI_HOST = originalHost;
    global.fetch = originalFetch;
  }
});

test('attachThemePacks adds vt and never fails search', async () => {
  process.env.MEILI_HOST = '';
  const { attachThemePacks } = require('./marketplace-search-candidates');
  const PACKED = 'v1'
    + '1c0705' + '2c1512' + '3d211c' + '8a3a28' + '7a463a' + '452a24' + '8a3f2c';
  const rows = [
    { card_id: 251820, name: 'Torchic' },
    { card_id: 251822, name: 'Mudkip' },
  ];
  const packs = new Map([['251820', PACKED]]);
  const themed = await attachThemePacks(rows, { readCardThemePacks: async () => packs });
  assert.equal(themed[0].vt, PACKED);
  assert.equal(themed[1].vt, undefined);
  // Lookup failure returns the rows untouched.
  const safe = await attachThemePacks(rows, {
    readCardThemePacks: async () => {
      throw new Error('db down');
    },
  });
  assert.deepEqual(safe, rows);
  assert.deepEqual(await attachThemePacks([], { readCardThemePacks: async () => packs }), []);
});
