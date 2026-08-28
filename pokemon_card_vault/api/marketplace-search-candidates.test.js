const assert = require('node:assert/strict');
const test = require('node:test');
const {
  nonNameCategoryPlan,
  buildNonNameContext,
  searchNonNameCategoryWithContext,
  searchNonNameWithDatabase,
  searchVariationReplicaNonNameWithDatabase,
  rowsForSearchTerm,
  searchTerms,
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
    if (/cardtrader_pokemon_expansions|marketplace_expansion_aliases/.test(sql)) {
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
