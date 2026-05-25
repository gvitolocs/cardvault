const assert = require('node:assert/strict');
const test = require('node:test');
const {
  cleanAutocompletePoolLimit,
  autocompleteCandidateIdLadder,
  autocompleteCandidateIdRequestedLimit,
  autocompleteCandidateIdAppliedLimit,
  cleanSearchContext,
  buildSearchContext,
  candidateFanoutPlan,
  filterRowsByStoredStructuredTokens,
  filterRowsByRequiredNameTokens,
  intersectionTokenPlan,
  intersectRows,
  poolSearchTerm,
  rankAutocompleteRows,
  searchFastNamePreviewWithDatabase,
  searchCombinedCardNameWithDatabase,
  searchNameOnlyAutocompleteWithCardNameFanout,
  searchNameOnlyRowsWithDatabase,
  searchNameTokenFallbackWithDatabase,
  searchStructuredAutocompleteWithContext,
  searchStructuredAutocompleteWithCandidateFanout,
  shouldUseSupplementalNameFallback,
  rowMatchesIntersectionToken,
  predictiveChunksForQuery,
  readQueryForAutocomplete,
  genericEnergyExpansionPlan,
  searchGenericEnergyExpansionRowsWithDatabase,
  supabaseNameIndexDecision,
  supabaseNameIndexCandidateRows,
  supabasePredictedNameTokens,
  supabaseRestNameIndexCandidateRows,
  supabaseRestPredictedNameTokens,
  shouldTrySupabaseNameIndex,
  shouldTrySupabaseOneCharNameIndex,
  rowsFromSupabaseNameIndex,
  supabaseOneCharNameTokenRows,
  rowsFromSupabaseOneCharNameIndex,
  resetSupabaseNameIndexCircuitForTest,
  searchPredictiveNgramRowsWithDatabase,
  predictivePoolPlan,
  firstNameAnchorForPredictivePlan,
  cleanPredictionContext,
  predictionSetsFromContext,
  mergePredictivePoolRows,
  predictiveRowsForNamePredictions,
  predictiveNameFragmentCandidates,
  anchoredPredictionSets,
  predictiveVerifiedDimensionRowsWithDatabase,
  buildPredictivePoolWithFanout,
  predictiveDimensionRowsWithDatabase,
  oneCharacterPrefixShardPlan,
  shardedNamePrefixRowsForOneCharacterSearch,
  namePrefixRowsForOneCharacterSearch,
  hotPreviewPoolRowsWithDatabase,
  hotPreviewPool,
  rowsForAutocompleteSearchTermWithQuery,
  analyticsBoostsForRows,
  updateDepthScores,
  rankAutocompleteEntries,
  scoreExplanation,
  candidateLabelsForRows,
  canceledAutocompleteResponse,
  cacheControlForRequest,
  isSearchCanceled,
  setCorsHeaders,
} = require('./marketplace-autocomplete');
const { mergeSearchRows } = require('./marketplace-search-candidates');
const {
  cancelSearchSession,
  clearSearchSessionForTest,
} = require('./_searchbar_session');

function row({
  id,
  name,
  set = 'Test Set',
  number = '001/100',
  rarity = 'Card',
  type = 'Lightning',
  kind = 'single',
  trainer = '',
  rank = 0,
}) {
  return {
    card_id: id,
    name,
    set_name: set,
    card_number: number,
    rarity,
    card_type: type,
    item_kind: kind,
    trainer_name: trainer,
    search_rank: rank,
  };
}

function fanoutMockQuery({ entities = {}, candidates = [] }) {
  return async (sql, values) => {
    if (/from normalized n\s+join public\.marketplace_card_names_for_language/.test(sql)) {
      return {
        rows: (entities[values[0]] || []).map((name, index) => ({
          name,
          token_score: 1400 - index,
        })),
      };
    }
    if (/where coalesce\(nullif\(c\.canonical_name/.test(sql)) {
      const names = new Set(values[0] || []);
      return { rows: candidates.filter((candidate) => names.has(candidate.canonical_name || candidate.name)) };
    }
    if (/where c\.card_id = any\(\$1::bigint\[\]\)/.test(sql)) {
      const ids = new Set((values[0] || []).map((id) => String(id)));
      return { rows: candidates.filter((candidate) => ids.has(String(candidate.card_id))) };
    }
    return { rows: [] };
  };
}

test('autocomplete CORS helper allows extension preflight headers', () => {
  const headers = {};
  setCorsHeaders({
    setHeader(key, value) {
      headers[key] = value;
    },
  });

  assert.equal(headers['Access-Control-Allow-Origin'], '*');
  assert.equal(headers['Access-Control-Allow-Methods'], 'POST, OPTIONS');
  assert.equal(headers['Access-Control-Allow-Headers'], 'Content-Type, Authorization');
});

test('autocomplete POST search results are not shared-cacheable by URL only', () => {
  assert.equal(cacheControlForRequest({ method: 'POST' }, 'public, max-age=5, s-maxage=30'), 'no-store');
  assert.equal(
    cacheControlForRequest({ method: 'GET' }, 'public, max-age=5, s-maxage=30'),
    'public, max-age=5, s-maxage=30',
  );
});

test('autocomplete fetches the full query for tokenized database search', () => {
  assert.equal(poolSearchTerm('porygon'), 'porygon');
  assert.equal(poolSearchTerm('piachu 151'), 'piachu 151');
  assert.equal(poolSearchTerm('  char ex  '), 'char ex');
});

test('autocomplete pool limit stays bounded for keypress latency', () => {
  assert.equal(cleanAutocompletePoolLimit(undefined), 1000);
  assert.equal(cleanAutocompletePoolLimit(20), 100);
  assert.equal(cleanAutocompletePoolLimit(420), 420);
  assert.equal(cleanAutocompletePoolLimit(1000), 1000);
  assert.equal(cleanAutocompletePoolLimit(2500), 2500);
  assert.equal(cleanAutocompletePoolLimit(10000), 5000);
});

test('canceled search sessions are observable before optional expensive phases', () => {
  const sessionId = 'flutter-autocomplete-cancel-123';
  clearSearchSessionForTest(sessionId);

  assert.equal(isSearchCanceled({ sessionId, clientDisconnected: false }), false);
  cancelSearchSession(sessionId, { query: 'pikachu', reason: 'blur' });
  assert.equal(isSearchCanceled({ sessionId, clientDisconnected: false }), true);
  assert.equal(isSearchCanceled({ sessionId: '', clientDisconnected: true }), true);

  const response = canceledAutocompleteResponse(
    'pikachu',
    'en',
    { sessionId, clientDisconnected: false },
  );
  assert.deepEqual(response.rows, []);
  assert.equal(response.canceled, true);
  assert.equal(response.pool.strategy, 'session_canceled');
  assert.equal(response.debug.searchPath, 'session_canceled');
  clearSearchSessionForTest(sessionId);
});

test('autocomplete ID ladder exposes typed lightweight context caps', () => {
  assert.equal(autocompleteCandidateIdRequestedLimit('p'), 0);
  assert.equal(autocompleteCandidateIdRequestedLimit('pi'), 5000);
  assert.equal(autocompleteCandidateIdRequestedLimit('pik'), 2500);
  assert.equal(autocompleteCandidateIdRequestedLimit('pika'), 1250);
  assert.equal(autocompleteCandidateIdRequestedLimit('pikac'), 500);
  assert.equal(autocompleteCandidateIdRequestedLimit('pikachu'), 500);
  assert.equal(autocompleteCandidateIdAppliedLimit('p'), 500);
  assert.equal(autocompleteCandidateIdAppliedLimit('pi'), 5000);
  assert.equal(autocompleteCandidateIdAppliedLimit('pik'), 2500);
  assert.equal(autocompleteCandidateIdAppliedLimit('pika'), 1250);
  assert.equal(autocompleteCandidateIdAppliedLimit('pikac'), 500);
  assert.deepEqual(autocompleteCandidateIdLadder('pik'), {
    depth: 3,
    requestedLimit: 2500,
    appliedLimit: 2500,
    floor: 500,
    safeCap: 5000,
  });
});

test('predictive chunk extraction uses consecutive compact ngrams across typed input', () => {
  const chunks = predictiveChunksForQuery('Pikchu');

  assert.deepEqual(chunks.slice(0, 6), [
    { chunk: 'pik', position: 1, length: 3, isPrefix: true },
    { chunk: 'pi', position: 1, length: 2, isPrefix: true },
    { chunk: 'ikc', position: 2, length: 3, isPrefix: false },
    { chunk: 'kch', position: 3, length: 3, isPrefix: false },
    { chunk: 'chu', position: 4, length: 3, isPrefix: false },
    { chunk: 'ik', position: 2, length: 2, isPrefix: false },
  ]);
  assert.ok(predictiveChunksForQuery('mew 232').some((entry) => entry.chunk === '232'));
  assert.deepEqual(predictiveChunksForQuery('p'), []);
});

test('Supabase name index is optional and short-prefix focused', () => {
  const original = process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
  try {
    resetSupabaseNameIndexCircuitForTest();
    delete process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
    assert.equal(shouldTrySupabaseNameIndex('pi'), false);

    process.env.SUPABASE_NAME_INDEX_DATABASE_URL = 'postgres://supabase.example/name-index';
    assert.equal(shouldTrySupabaseNameIndex('p'), false);
    assert.equal(shouldTrySupabaseOneCharNameIndex('p'), true);
    assert.equal(shouldTrySupabaseNameIndex('pi'), true);
    assert.equal(shouldTrySupabaseNameIndex('pika'), true);
    assert.equal(shouldTrySupabaseNameIndex('pikac'), true);
    assert.equal(shouldTrySupabaseNameIndex('pikachu'), true);
    assert.equal(shouldTrySupabaseNameIndex('mew 232'), false);
    assert.equal(shouldTrySupabaseNameIndex('mew rare'), false);
    assert.equal(shouldTrySupabaseNameIndex('pi', { query: 'p', strategy: 'supabase_name_index', card_ids: ['25'] }), true);
    assert.equal(shouldTrySupabaseNameIndex('pik', { query: 'pi', strategy: 'supabase_name_index', card_ids: ['25'] }), true);
  } finally {
    resetSupabaseNameIndexCircuitForTest();
    if (original === undefined) delete process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
    else process.env.SUPABASE_NAME_INDEX_DATABASE_URL = original;
  }
});

test('Supabase name index decision explains skipped path', () => {
  const original = process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
  try {
    resetSupabaseNameIndexCircuitForTest();
    delete process.env.SUPABASE_NAME_INDEX_DATABASE_URL;

    assert.deepEqual(supabaseNameIndexDecision('pikac'), {
      configured: false,
      circuitOpen: false,
      depth: 5,
      terms: ['pikac'],
      shortNamePrefix: true,
      previousStrategy: null,
      previousDepth: null,
      shouldTry: false,
    });
  } finally {
    resetSupabaseNameIndexCircuitForTest();
    if (original === undefined) delete process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
    else process.env.SUPABASE_NAME_INDEX_DATABASE_URL = original;
  }
});

test('Supabase name index failure opens short-lived fallback circuit', async () => {
  const original = process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
  try {
    resetSupabaseNameIndexCircuitForTest();
    process.env.SUPABASE_NAME_INDEX_DATABASE_URL = 'postgres://supabase.example/name-index';
    const debug = {};
    const rows = await rowsFromSupabaseNameIndex(
      'pi',
      5000,
      'en',
      debug,
      async () => ({ rows: [] }),
      async () => {
        const error = new Error('relation "public.marketplace_card_name_tokens" does not exist');
        error.code = '42P01';
        throw error;
      },
    );

    assert.equal(rows, null);
    assert.equal(debug.supabaseNameIndex.fallback, true);
    assert.equal(debug.supabaseNameIndex.code, '42P01');
    assert.equal(shouldTrySupabaseNameIndex('pi'), false);
  } finally {
    resetSupabaseNameIndexCircuitForTest();
    if (original === undefined) delete process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
    else process.env.SUPABASE_NAME_INDEX_DATABASE_URL = original;
  }
});

test('Supabase name index query returns compact candidate rows', async () => {
  const calls = [];
  const rows = await supabaseNameIndexCandidateRows(
    'Pi',
    5000,
    'fr',
    async (sql, values) => {
      calls.push({ sql, values });
      assert.match(sql, /public\.marketplace_card_name_tokens/);
      assert.match(sql, /i\.language = input\.language/);
      assert.equal(values[0], 'pi');
      assert.equal(values[1], 'fr');
      assert.equal(values[2], 5000);
      return {
        rows: [
          {
            display_name: 'Pikachu',
            canonical_name: 'Pikachu',
            compact_name: 'pikachu',
            name_tokens: ['pikachu'],
            language: 'fr',
            card_ids: ['25', '26'],
            representative_labels: [],
            search_rank: 3900,
          },
        ],
      };
    },
  );

  assert.equal(calls.length, 1);
  assert.deepEqual(rows.map((candidate) => candidate.card_id), ['25', '26']);
});

test('Supabase predicted name tokens are provisional and pivot with each fragment', async () => {
  const predictedForMe = await supabasePredictedNameTokens(
    'me',
    'en',
    20,
    async (sql, values) => {
      assert.match(sql, /marketplace_card_name_tokens/);
      assert.equal(values[0], 'me');
      assert.equal(values[1], 'en');
      assert.equal(values[2], 20);
      return {
        rows: [
          {
            canonical_name: 'Mew',
            display_name: 'Mew',
            compact_name: 'mew',
            name_tokens: ['mew'],
            language: 'en',
            confidence: 93,
            score: 5000,
            representative_card_ids: ['287350'],
            representative_labels: [{ id: '287350', name: 'Mew' }],
          },
          {
            canonical_name: 'Mewtwo',
            display_name: 'Mewtwo',
            compact_name: 'mewtwo',
            name_tokens: ['mewtwo'],
            language: 'en',
            confidence: 90,
            score: 4800,
            representative_card_ids: ['150'],
            representative_labels: [{ id: '150', name: 'Mewtwo' }],
          },
          {
            canonical_name: 'Meowth',
            display_name: 'Meowth',
            compact_name: 'meowth',
            name_tokens: ['meowth'],
            language: 'en',
            confidence: 88,
            score: 4700,
            representative_card_ids: ['52'],
            representative_labels: [{ id: '52', name: 'Meowth' }],
          },
        ],
      };
    },
  );
  const predictedForMewt = await supabasePredictedNameTokens(
    'mewt',
    'en',
    20,
    async (_sql, values) => {
      assert.equal(values[0], 'mewt');
      return {
        rows: [
          {
            canonical_name: 'Mewtwo',
            display_name: 'Mewtwo',
            compact_name: 'mewtwo',
            name_tokens: ['mewtwo'],
            language: 'en',
            confidence: 94,
            score: 5200,
            representative_card_ids: ['150'],
            representative_labels: [{ id: '150', name: 'Mewtwo' }],
          },
        ],
      };
    },
  );

  assert.deepEqual(predictedForMe.map((prediction) => prediction.display), ['Mew', 'Mewtwo', 'Meowth']);
  assert.deepEqual(predictedForMewt.map((prediction) => prediction.display), ['Mewtwo']);
  assert.equal(predictedForMewt[0].confidence >= 70, true);
});

test('Supabase predicted name tokens boost broad prefixes by popularity', async () => {
  const predictedForP = await supabasePredictedNameTokens(
    'p',
    'en',
    20,
    async (sql, values) => {
      assert.match(sql, /marketplace_card_name_tokens/);
      assert.match(sql, /array_length\(i\.card_ids, 1\)/);
      assert.equal(values[0], 'p');
      return {
        rows: [
          {
            canonical_name: 'Paras',
            display_name: 'Paras',
            compact_name: 'paras',
            name_tokens: ['paras'],
            language: 'en',
            confidence: 92,
            score: 120800,
            representative_card_ids: ['46'],
            card_ids: ['46'],
            row_count: 1,
          },
          {
            canonical_name: 'Pikachu',
            display_name: 'Pikachu',
            compact_name: 'pikachu',
            name_tokens: ['pikachu'],
            language: 'en',
            confidence: 91,
            score: 120800,
            representative_card_ids: Array.from(
              { length: 120 },
              (_, index) => String(index + 1),
            ),
            card_ids: Array.from({ length: 120 }, (_, index) => String(index + 1)),
            row_count: 120,
          },
        ],
      };
    },
  );
  const predictedForPar = await supabasePredictedNameTokens(
    'par',
    'en',
    20,
    async (_sql, values) => {
      assert.equal(values[0], 'par');
      return {
        rows: [
          {
            canonical_name: 'Pikachu',
            display_name: 'Pikachu',
            compact_name: 'pikachu',
            name_tokens: ['pikachu'],
            language: 'en',
            confidence: 76,
            score: 2500,
            card_ids: Array.from({ length: 120 }, (_, index) => String(index + 1)),
            row_count: 120,
          },
          {
            canonical_name: 'Paras',
            display_name: 'Paras',
            compact_name: 'paras',
            name_tokens: ['paras'],
            language: 'en',
            confidence: 93,
            score: 120800,
            card_ids: ['46'],
            row_count: 1,
          },
        ],
      };
    },
  );

  assert.equal(predictedForP[0].display, 'Pikachu');
  assert.equal(predictedForPar[0].display, 'Paras');
});

test('Supabase predicted name tokens aggregate broad token popularity', async () => {
  const predictions = await supabasePredictedNameTokens(
    'p',
    'en',
    20,
    async () => ({
      rows: [
        {
          canonical_name: 'Potion',
          display_name: 'Potion',
          compact_name: 'potion',
          name_tokens: ['potion'],
          language: 'en',
          confidence: 99,
          score: 120900,
          card_ids: Array.from({ length: 8 }, (_, index) => `po${index}`),
          row_count: 8,
        },
        {
          canonical_name: 'Pikachu',
          display_name: 'Pikachu',
          compact_name: 'pikachu',
          name_tokens: ['pikachu'],
          language: 'en',
          confidence: 91,
          score: 120800,
          card_ids: Array.from({ length: 40 }, (_, index) => `pi${index}`),
          row_count: 40,
        },
        {
          canonical_name: "Ash's Pikachu",
          display_name: "Ash's Pikachu",
          compact_name: 'ashspikachu',
          name_tokens: ['ash', 'pikachu'],
          language: 'en',
          confidence: 84,
          score: 60000,
          card_ids: Array.from({ length: 70 }, (_, index) => `ash${index}`),
          row_count: 70,
        },
      ],
    }),
  );

  assert.equal(predictions[0].display, 'Pikachu');
  assert.ok(predictions[0].representative_card_ids.length > 1);
});

test('Supabase predicted name tokens prefer complete shorter token family', async () => {
  const predictions = await supabasePredictedNameTokens(
    'm',
    'en',
    20,
    async () => ({
      rows: [
        {
          canonical_name: 'Mewtwo',
          display_name: 'Mewtwo',
          compact_name: 'mewtwo',
          name_tokens: ['mewtwo'],
          language: 'en',
          confidence: 99,
          score: 180000,
          card_ids: Array.from({ length: 80 }, (_, index) => `two${index}`),
          row_count: 80,
        },
        {
          canonical_name: 'Mew',
          display_name: 'Mew',
          compact_name: 'mew',
          name_tokens: ['mew'],
          language: 'en',
          confidence: 100,
          score: 140000,
          card_ids: Array.from({ length: 20 }, (_, index) => `mew${index}`),
          row_count: 20,
        },
      ],
    }),
  );

  assert.equal(predictions[0].display, 'Mew');
});

test('Supabase one-character name token query matches compact and punctuation-normalized names', async () => {
  const rows = await supabaseOneCharNameTokenRows(
    'p',
    500,
    'en',
    async (sql, values) => {
      assert.match(sql, /public\.marketplace_card_name_tokens/);
      assert.match(sql, /i\.compact_name like input\.compact_q \|\| '%'/);
      assert.match(sql, /i\.normalized_name like input\.normalized_q \|\| '%'/);
      assert.match(sql, /public\.marketplace_search_compact\(token\) like input\.compact_q \|\| '%'/);
      assert.deepEqual(values, ['p', 'en', 1000]);
      return {
        rows: [
          {
            display_name: 'Pikachu',
            canonical_name: 'Pikachu',
            search_name: 'Pikachu',
            compact_name: 'pikachu',
            normalized_name: 'pikachu',
            name_tokens: ['pikachu'],
            language: 'en',
            card_ids: ['25'],
            representative_labels: [{ id: '25', name: 'Pikachu' }],
            row_count: 1,
            confidence: 91,
            score: 125000,
          },
          {
            display_name: "Ash's Pikachu",
            canonical_name: "Ash's Pikachu",
            search_name: "Ash's Pikachu",
            compact_name: 'ashspikachu',
            normalized_name: 'ash s pikachu',
            name_tokens: ['ash', 'pikachu'],
            language: 'en',
            card_ids: ['26'],
            representative_labels: [{ id: '26', name: "Ash's Pikachu", trainer_name: 'Ash' }],
            row_count: 1,
            confidence: 84,
            score: 64000,
          },
          {
            display_name: "_____'s Pikachu",
            canonical_name: "_____'s Pikachu",
            search_name: "_____'s Pikachu",
            compact_name: 'spikachu',
            normalized_name: 's pikachu',
            name_tokens: ['pikachu'],
            language: 'en',
            card_ids: ['27'],
            representative_labels: [{ id: '27', name: "_____'s Pikachu" }],
            row_count: 1,
            confidence: 84,
            score: 63000,
          },
          {
            display_name: 'Pikachu & Zekrom GX',
            canonical_name: 'Pikachu & Zekrom GX',
            search_name: 'Pikachu & Zekrom GX',
            compact_name: 'pikachuzekromgx',
            normalized_name: 'pikachu tagteam zekrom gx',
            name_tokens: ['gx', 'pikachu', 'tagteam', 'zekrom'],
            language: 'en',
            card_ids: ['28'],
            representative_labels: [{ id: '28', name: 'Pikachu & Zekrom GX' }],
            row_count: 1,
            confidence: 81,
            score: 124000,
          },
          {
            display_name: "Lt. Surge's Pikachu",
            canonical_name: "Lt. Surge's Pikachu",
            search_name: "Lt. Surge's Pikachu",
            compact_name: 'ltsurgespikachu',
            normalized_name: 'lt surge s pikachu',
            name_tokens: ['lt', 'surge', 'pikachu'],
            language: 'en',
            card_ids: ['29'],
            representative_labels: [{ id: '29', name: "Lt. Surge's Pikachu", trainer_name: 'Lt. Surge' }],
            row_count: 1,
            confidence: 84,
            score: 62000,
          },
        ],
      };
    },
  );

  assert.deepEqual(rows.map((entry) => entry.display_name), [
    'Pikachu',
    "Ash's Pikachu",
    "_____'s Pikachu",
    'Pikachu & Zekrom GX',
    "Lt. Surge's Pikachu",
  ]);
});

test('Supabase one-character path returns predictions and bounded label context without Oracle shard', async () => {
  const original = process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
  try {
    resetSupabaseNameIndexCircuitForTest();
    process.env.SUPABASE_NAME_INDEX_DATABASE_URL = 'postgres://supabase.example/name-index';
    const debug = {};
    const rows = await rowsFromSupabaseOneCharNameIndex(
      'p',
      3,
      'en',
      debug,
      async () => ({
        rows: [
          {
            display_name: 'Pikachu',
            canonical_name: 'Pikachu',
            search_name: 'Pikachu',
            compact_name: 'pikachu',
            normalized_name: 'pikachu',
            name_tokens: ['pikachu'],
            language: 'en',
            card_ids: ['25', '26'],
            representative_labels: [
              { id: '25', name: 'Pikachu', set_name: 'Base Set', card_number: '58/102' },
              { id: '26', name: 'Pikachu', set_name: 'Jungle', card_number: '60/64' },
            ],
            row_count: 2,
            confidence: 91,
            score: 125000,
            search_weight: 100,
          },
          {
            display_name: 'Porygon',
            canonical_name: 'Porygon',
            search_name: 'Porygon',
            compact_name: 'porygon',
            normalized_name: 'porygon',
            name_tokens: ['porygon'],
            language: 'en',
            card_ids: ['137', '138'],
            representative_labels: [
              { id: '137', name: 'Porygon' },
              { id: '138', name: 'Porygon2' },
            ],
            row_count: 2,
            confidence: 90,
            score: 124000,
            search_weight: 90,
          },
        ],
      }),
    );

    assert.equal(rows.length, 3);
    assert.deepEqual(rows.map((candidate) => candidate.card_id), ['25', '26', '137']);
    assert.equal(rows[0].name, 'Pikachu');
    assert.equal(rows.nonNameContext.predictive_pool.predicted_tokens[0].display, 'Pikachu');
    assert.equal(debug.searchPath, 'supabase_one_char_name_index');
    assert.equal(debug.tokenPlan.strategy, 'supabase_one_char_name_index');
    assert.equal(debug.predictivePool.model, 'supabase_one_char_name_tokens');
  } finally {
    resetSupabaseNameIndexCircuitForTest();
    if (original === undefined) delete process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
    else process.env.SUPABASE_NAME_INDEX_DATABASE_URL = original;
  }
});

test('predictive fragment planner separates likely name and remaining dimension tokens', () => {
  const plan = predictivePoolPlan('lt surge pikachu 025').nameFragmentCandidates;

  assert.ok(plan.some((candidate) =>
    candidate.nameFragment === 'pikachu' &&
    candidate.dimensionTokens.some((token) => token.sourceHint === 'variation_owner' && token.term === 'lt') &&
    candidate.dimensionTokens.some((token) => token.kind === 'number' && token.term === '025')));
  assert.ok(!plan.some((candidate) =>
    candidate.nameFragment === 'surge pikachu'));
  assert.ok(predictiveNameFragmentCandidates([
    { term: 'mew', kind: 'text' },
    { term: '232', kind: 'number' },
  ]).some((candidate) => candidate.nameFragment === 'mew'));
});

test('Supabase name index hydrates capped final-prefix pools fully', async () => {
  const original = process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
  try {
    process.env.SUPABASE_NAME_INDEX_DATABASE_URL = 'postgres://supabase.example/name-index';
    const debug = {};
    const rows = await rowsFromSupabaseNameIndex(
      'pi',
      5000,
      'en',
      debug,
      async (sql, values) => {
        assert.match(sql, /where c\.card_id = any\(\$1::bigint\[\]\)/);
        assert.equal(values[0].length, 120);
        return {
          rows: values[0].map((id, index) =>
            row({
              id: String(id),
              name: index === 0 ? 'Pikachu' : `Pikachu ${id}`,
              rank: 3000 - index,
            })),
        };
      },
      async (sql, values) => {
        assert.match(sql, /public\.marketplace_card_name_tokens/);
        assert.equal(values[2], 5000);
        return {
          rows: [
            {
              display_name: 'Pikachu',
              canonical_name: 'Pikachu',
              compact_name: 'pikachu',
              name_tokens: ['pikachu'],
              language: 'en',
              card_ids: Array.from({ length: 120 }, (_, index) => String(index + 1)),
              representative_labels: [],
              search_rank: 5000,
            },
          ],
        };
      },
    );

    assert.equal(rows.length, 120);
    assert.equal(rows[0].name, 'Pikachu');
    assert.equal(debug.searchPath, 'supabase_name_index');
    assert.equal(debug.supabaseNameIndex.candidateRowCount, 120);
    assert.equal(debug.supabaseNameIndex.hydratedRowCount, 120);
    assert.equal(debug.supabaseNameIndex.visibleHydrationLimit, 120);

    const context = buildSearchContext('pi', 'en', rows, 'supabase_name_index', null, 5000);
    assert.equal(context.card_ids.length, 120);
    assert.equal(context.candidate_labels.length, 120);
  } finally {
    if (original === undefined) delete process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
    else process.env.SUPABASE_NAME_INDEX_DATABASE_URL = original;
  }
});

test('Supabase name index ranks hydrated exact names before suffix variants', async () => {
  const original = process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
  try {
    process.env.SUPABASE_NAME_INDEX_DATABASE_URL = 'postgres://supabase.example/name-index';
    const rows = await rowsFromSupabaseNameIndex(
      'pikachu',
      20,
      'en',
      {},
      async () => ({
        rows: [
          row({ id: '1', name: 'Pikachu GX', rank: 0 }),
          row({ id: '2', name: 'Pikachu', rank: 0 }),
        ],
      }),
      async () => ({
        rows: [
          { card_id: '1', name: 'Pikachu', search_rank: 240000 },
          { card_id: '2', name: 'Pikachu', search_rank: 239999.99 },
        ],
      }),
    );

    assert.equal(rows[0].card_id, '2');
    assert.equal(rows[0].name, 'Pikachu');
  } finally {
    if (original === undefined) delete process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
    else process.env.SUPABASE_NAME_INDEX_DATABASE_URL = original;
  }
});

test('Supabase REST name index fallback ranks compact candidate rows', async () => {
  const originalUrl = process.env.SUPABASE_URL;
  const originalKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const originalFetch = global.fetch;
  try {
    process.env.SUPABASE_URL = 'https://supabase.example';
    process.env.SUPABASE_SERVICE_ROLE_KEY = 'service-role';
    global.fetch = async (url, options) => {
      assert.match(String(url), /marketplace_card_name_tokens/);
      assert.match(String(url), /language=eq\.en/);
      assert.match(String(url), /compact_name\.like\.pik%25/);
      assert.equal(options.headers.apikey, 'service-role');
      return {
        ok: true,
        status: 200,
        async json() {
          return [
            {
              display_name: 'Pikachu',
              canonical_name: 'Pikachu',
              compact_name: 'pikachu',
              name_tokens: ['pikachu'],
              card_ids: ['25'],
              representative_labels: [{ id: '25', name: 'Pikachu', set_name: 'Base Set', card_number: '58/102' }],
              search_weight: 32,
            },
            {
              display_name: 'Pidgeot',
              canonical_name: 'Pidgeot',
              compact_name: 'pidgeot',
              name_tokens: ['pidgeot'],
              card_ids: ['26'],
              representative_labels: [{ id: '26', name: 'Pidgeot', set_name: 'Base Set', card_number: '22/102' }],
              search_weight: 20,
            },
          ];
        },
      };
    };

    const rows = await supabaseRestNameIndexCandidateRows('pik', 20, 'en');

    assert.deepEqual(rows.map((row) => row.card_id), ['25', '26']);
    assert.equal(rows[0].name, 'Pikachu');
    assert.equal(rows[0].search_rank, 220112);
  } finally {
    if (originalUrl === undefined) delete process.env.SUPABASE_URL;
    else process.env.SUPABASE_URL = originalUrl;
    if (originalKey === undefined) delete process.env.SUPABASE_SERVICE_ROLE_KEY;
    else process.env.SUPABASE_SERVICE_ROLE_KEY = originalKey;
    global.fetch = originalFetch;
  }
});

test('Supabase REST name index keeps plain base display names above suffix variants', async () => {
  const originalUrl = process.env.SUPABASE_URL;
  const originalKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const originalFetch = global.fetch;
  try {
    process.env.SUPABASE_URL = 'https://supabase.example';
    process.env.SUPABASE_SERVICE_ROLE_KEY = 'service-role';
    global.fetch = async () => ({
      ok: true,
      status: 200,
      async json() {
        return [
          {
            display_name: 'Pikachu ex',
            canonical_name: 'Pikachu',
            compact_name: 'pikachu',
            name_tokens: ['pikachu'],
            card_ids: ['244074'],
            representative_labels: [{ id: '244074', name: 'Pikachu ex' }],
            search_weight: 50000,
          },
          {
            display_name: 'Pikachu',
            canonical_name: 'Pikachu',
            compact_name: 'pikachu',
            name_tokens: ['pikachu'],
            card_ids: ['317048'],
            representative_labels: [{ id: '317048', name: 'Pikachu' }],
            search_weight: 1,
          },
        ];
      },
    });

    const rows = await supabaseRestNameIndexCandidateRows('pikac', 20, 'en');

    assert.deepEqual(rows.map((candidate) => candidate.name), ['Pikachu', 'Pikachu ex']);
  } finally {
    if (originalUrl === undefined) delete process.env.SUPABASE_URL;
    else process.env.SUPABASE_URL = originalUrl;
    if (originalKey === undefined) delete process.env.SUPABASE_SERVICE_ROLE_KEY;
    else process.env.SUPABASE_SERVICE_ROLE_KEY = originalKey;
    global.fetch = originalFetch;
  }
});

test('Supabase REST name index typo fallback finds near prefixes', async () => {
  const originalUrl = process.env.SUPABASE_URL;
  const originalKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const originalFetch = global.fetch;
  const requestedUrls = [];
  try {
    process.env.SUPABASE_URL = 'https://supabase.example';
    process.env.SUPABASE_SERVICE_ROLE_KEY = 'service-role';
    global.fetch = async (url) => {
      requestedUrls.push(String(url));
      const isFuzzyFallback = String(url).includes('compact_name=like.la%25');
      return {
        ok: true,
        status: 200,
        async json() {
          return isFuzzyFallback
            ? [
                {
                  display_name: 'Lapras',
                  canonical_name: 'Lapras',
                  compact_name: 'lapras',
                  name_tokens: ['lapras'],
                  card_ids: ['116619', '119612'],
                  representative_labels: [
                    { id: '116619', name: 'Lapras', set_name: 'EX Legend Maker' },
                    { id: '119612', name: 'Lapras', set_name: 'Fossil' },
                  ],
                  row_count: 2,
                  search_weight: 22,
                },
              ]
            : [];
        },
      };
    };

    const rows = await supabaseRestNameIndexCandidateRows('laprs', 20, 'en');
    const tokens = await supabaseRestPredictedNameTokens('laprs', 'en', 5);

    assert.deepEqual(rows.map((row) => row.card_id), ['116619', '119612']);
    assert.equal(tokens[0].display, 'Lapras');
    assert.equal(tokens[0].confidence, 76);
    assert.equal(requestedUrls.filter((url) => url.includes('compact_name=like.la%25')).length, 2);
  } finally {
    if (originalUrl === undefined) delete process.env.SUPABASE_URL;
    else process.env.SUPABASE_URL = originalUrl;
    if (originalKey === undefined) delete process.env.SUPABASE_SERVICE_ROLE_KEY;
    else process.env.SUPABASE_SERVICE_ROLE_KEY = originalKey;
    global.fetch = originalFetch;
  }
});

test('Supabase name index uses REST fallback when Postgres fails', async () => {
  const originalUrl = process.env.SUPABASE_URL;
  const originalKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const originalNameIndexUrl = process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
  const originalFetch = global.fetch;
  try {
    process.env.SUPABASE_URL = 'https://supabase.example';
    process.env.SUPABASE_SERVICE_ROLE_KEY = 'service-role';
    process.env.SUPABASE_NAME_INDEX_DATABASE_URL = 'postgres://supabase.example/name-index';
    global.fetch = async () => ({
      ok: true,
      status: 200,
      async json() {
        return Array.from({ length: 2 }, (_, index) => ({
          display_name: index === 0 ? 'Pikachu' : 'Pidgeot',
          canonical_name: index === 0 ? 'Pikachu' : 'Pidgeot',
          compact_name: index === 0 ? 'pikachu' : 'pidgeot',
          name_tokens: [index === 0 ? 'pikachu' : 'pidgeot'],
          card_ids: [String(index + 1)],
          representative_labels: [{ id: String(index + 1), name: index === 0 ? 'Pikachu' : 'Pidgeot' }],
          search_weight: 32 - index,
        }));
      },
    });
    const debug = {};

    const rows = await rowsFromSupabaseNameIndex(
      'pik',
      20,
      'en',
      debug,
      async (sql, values) => ({
        rows: values[0].map((id) => row({ id: String(id), name: `hydrated-${id}`, rank: 0 })),
      }),
      async () => {
        const error = new Error('Tenant or user not found');
        error.code = 'XX000';
        throw error;
      },
    );

    assert.equal(rows.length, 2);
    assert.equal(debug.searchPath, 'supabase_name_index');
    assert.equal(debug.supabaseNameIndex.source, 'rest_fallback');
    assert.equal(debug.supabaseNameIndexPostgresError.code, 'XX000');
  } finally {
    if (originalUrl === undefined) delete process.env.SUPABASE_URL;
    else process.env.SUPABASE_URL = originalUrl;
    if (originalKey === undefined) delete process.env.SUPABASE_SERVICE_ROLE_KEY;
    else process.env.SUPABASE_SERVICE_ROLE_KEY = originalKey;
    if (originalNameIndexUrl === undefined) delete process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
    else process.env.SUPABASE_NAME_INDEX_DATABASE_URL = originalNameIndexUrl;
    global.fetch = originalFetch;
  }
});

test('predictive ngram search queries chunk index and returns backend candidates', async () => {
  const calls = [];
  const debug = {};
  const result = await searchPredictiveNgramRowsWithDatabase(
    'pikchu',
    1000,
    'fr',
    debug,
    async (sql, values) => {
      calls.push({ sql, values });
      assert.deepEqual(values[0].slice(0, 4), ['pik', 'pi', 'ikc', 'kch']);
      assert.equal(values[1], 1000);
      assert.equal(values[2], 'fr');
      assert.match(sql, /marketplace_name_ngrams/);
      assert.match(sql, /marketplace_query_chunk_events/);
      assert.match(sql, /n\.language = \$3::text/);
      assert.match(sql, /e\.language = \$3::text/);
      assert.doesNotMatch(sql, /e\.language = 'en'/);
      return {
        rows: [
          row({ id: '25', name: 'Pikachu', rank: 2500 }),
        ],
      };
    },
  );

  assert.equal(calls.length, 1);
  assert.deepEqual(result.rows.map((candidate) => candidate.name), ['Pikachu']);
  assert.equal(debug.predictiveNgrams.used, true);
  assert.equal(debug.predictiveNgrams.language, 'fr');
  assert.equal(debug.predictiveNgrams.eventLanguage, 'fr');
  assert.equal(debug.predictiveNgrams.languageFallback, 'none');
  assert.equal(debug.predictiveNgrams.candidateRowCount, 1);
});

test('predictive ngram search skips cleanly before schema is applied', async () => {
  const error = new Error('missing relation');
  error.code = '42P01';
  const debug = {};
  const result = await searchPredictiveNgramRowsWithDatabase(
    'charzard',
    1000,
    'en',
    debug,
    async () => {
      throw error;
    },
  );

  assert.equal(result, null);
  assert.equal(debug.predictiveNgrams.used, false);
  assert.equal(debug.predictiveNgrams.reason, 'schema_not_applied');
});

test('predictive ngram query keeps chunk analytics language-local', async () => {
  const calls = [];
  const debug = {};
  const result = await searchPredictiveNgramRowsWithDatabase(
    'charzard',
    1000,
    'de',
    debug,
    async (sql, values) => {
      calls.push({ sql, values });
      assert.equal(values[2], 'de');
      assert.match(sql, /join public\.marketplace_name_ngrams n\s+on n\.language = \$3::text/);
      assert.match(sql, /left join public\.marketplace_query_chunk_events e\s+on e\.language = \$3::text/);
      assert.match(sql, /least\(coalesce\(e\.total_weight, 0\), 250\)/);
      assert.doesNotMatch(sql, /language\s*=\s*'en'/);
      return {
        rows: [
          row({ id: '6', name: 'Glurak', rank: 2500 }),
        ],
      };
    },
  );

  assert.equal(calls.length, 1);
  assert.deepEqual(result.rows.map((candidate) => candidate.name), ['Glurak']);
  assert.equal(result.language, 'de');
  assert.equal(debug.predictiveNgrams.language, 'de');
  assert.equal(debug.predictiveNgrams.eventLanguage, 'de');
  assert.equal(debug.predictiveNgrams.languageFallback, 'none');
});

test('predictive ngram fallback requires substantive name token when mega modifier misses', async () => {
  const calls = [];
  const debug = {};
  const rows = await rowsForAutocompleteSearchTermWithQuery(
    'mega darkrai',
    1000,
    'en',
    debug,
    null,
    async (sql) => {
      calls.push(sql);
      if (/marketplace_name_ngrams/.test(sql)) {
        return {
          rows: [
            row({ id: '1', name: 'Mega Meganium ex', rank: 13000 }),
            row({ id: '2', name: 'Darkrai VSTAR', rank: 12000 }),
            row({ id: '3', name: 'Darkrai ex', rank: 11000 }),
          ],
        };
      }
      if (/where c\.card_id = any\(\$1::bigint\[\]\)/.test(sql)) {
        return { rows: [] };
      }
      return { rows: [] };
    },
  );

  assert.ok(calls.some((sql) => /marketplace_name_ngrams/.test(sql)));
  assert.equal(debug.searchPath, 'typed_predictive_ngrams');
  assert.equal(debug.tokenPlan.requiredNameTokenFilter.applied, true);
  assert.deepEqual(
    rows.map((candidate) => candidate.name),
    ['Darkrai VSTAR', 'Darkrai ex'],
  );
});

test('required name token filter falls back when only mega modifier candidates exist', () => {
  const filtered = filterRowsByRequiredNameTokens(
    [
      row({ id: '1', name: 'Mega Diancie ex' }),
      row({ id: '2', name: 'Mega Dragonite ex' }),
    ],
    'mega d',
  );

  assert.equal(filtered.applied, false);
  assert.deepEqual(
    filtered.rows.map((candidate) => candidate.name),
    ['Mega Diancie ex', 'Mega Dragonite ex'],
  );
});

test('clean single-token prefixes use direct name path before predictive ngrams', async () => {
  const calls = [];
  const debug = {};
  const rows = await rowsForAutocompleteSearchTermWithQuery(
    'pik',
    1000,
    'en',
    debug,
    null,
    async (sql, values) => {
      calls.push({ sql, values });
      assert.doesNotMatch(sql, /marketplace_name_ngrams/);
      if (/marketplace_card_names_for_language/.test(sql) && /join public\.marketplace_search_candidates c/.test(sql)) {
        assert.deepEqual(values, [['pik'], 1000, 'en']);
        return {
          rows: [
            row({ id: '25', name: 'Pikachu', rank: 2500 }),
          ],
        };
      }
      return { rows: [] };
    },
  );

  assert.equal(calls.length, 1);
  assert.deepEqual(rows.map((candidate) => candidate.name), ['Pikachu']);
  assert.equal(debug.tokenPlan.strategy, 'name_table_direct');
  assert.equal(debug.searchPath, undefined);
});

test('direct prefix failure can still fall through to predictive ngrams', async () => {
  const calls = [];
  const debug = {};
  const rows = await rowsForAutocompleteSearchTermWithQuery(
    'pik',
    1000,
    'en',
    debug,
    null,
    async (sql) => {
      calls.push({ sql });
      if (/marketplace_card_names_for_language/.test(sql) && /join public\.marketplace_search_candidates c/.test(sql)) {
        const error = new Error('direct prefix connection failed');
        error.code = 'CONNECTION_TIMEOUT';
        throw error;
      }
      if (/marketplace_name_ngrams/.test(sql)) {
        return {
          rows: [
            row({ id: '25', name: 'Pikachu', rank: 2500 }),
          ],
        };
      }
      return { rows: [] };
    },
  );

  assert.deepEqual(rows.map((candidate) => candidate.name), ['Pikachu']);
  assert.equal(debug.directNamePrefix.fallback, true);
  assert.equal(debug.searchPath, 'typed_predictive_ngrams');
  assert.ok(calls.some((call) => /marketplace_name_ngrams/.test(call.sql)));
});

test('predictive ngram failure falls through to direct name fallback', async () => {
  const calls = [];
  const debug = {};
  const rows = await rowsForAutocompleteSearchTermWithQuery(
    'rocket mewtwo',
    1000,
    'en',
    debug,
    null,
    async (sql, values) => {
      calls.push({ sql, values });
      if (/marketplace_name_ngrams/.test(sql)) {
        const error = new Error('predictive ngram timed out');
        error.code = 'MARKETPLACE_SEARCH_TIMEOUT';
        throw error;
      }
      if (/marketplace_card_names_for_language/.test(sql) && /join public\.marketplace_search_candidates c/.test(sql)) {
        assert.deepEqual(values, [['rocket', 'mewtwo'], 1000, 'en']);
        return {
          rows: [
            row({ id: '25', name: "Rocket's Mewtwo", rank: 2500 }),
          ],
        };
      }
      return { rows: [] };
    },
  );

  assert.ok(calls.some((call) => /marketplace_name_ngrams/.test(call.sql)));
  assert.deepEqual(rows.map((candidate) => candidate.name), ["Rocket's Mewtwo"]);
  assert.equal(debug.predictiveNgrams.used, false);
  assert.equal(debug.predictiveNgrams.reason, 'query_failed');
  assert.equal(debug.tokenPlan.strategy, 'name_table_direct');
});

test('empty autocomplete server pool reads analytics hot blueprints with 1000 cap', async () => {
  const calls = [];
  const rows = await hotPreviewPoolRowsWithDatabase(2500, async (sql, values) => {
    calls.push({ sql, values });
    return {
      rows: [
        row({ id: '1', name: 'Pikachu', rank: 5000 }),
      ],
    };
  });

  assert.deepEqual(rows.map((result) => result.name), ['Pikachu']);
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].values, [1000]);
  assert.match(calls[0].sql, /marketplace_hot_blueprints/);
  assert.match(calls[0].sql, /marketplace_blueprint_price_summary/);
  assert.match(calls[0].sql, /searches_24h/);
});

test('empty autocomplete server pool reuses in-process hot cache for primary query', async () => {
  let calls = 0;
  const query = async () => {
    calls += 1;
    return {
      rows: [
        row({ id: '1', name: 'Pikachu', rank: 5000 }),
      ],
    };
  };
  const first = await hotPreviewPool(123, query);
  const second = await hotPreviewPool(123, query);

  assert.equal(calls, 1);
  assert.equal(first.source, 'hot_analytics_server_cache_refresh');
  assert.equal(second.source, 'hot_analytics_server_cache_hit');
  assert.deepEqual(second.rows.map((result) => result.name), ['Pikachu']);
});

test('one-character autocomplete uses bounded name prefix query', async () => {
  const calls = [];
  const debug = {};
  const rows = await namePrefixRowsForOneCharacterSearch('p', 2500, 'en', async (sql, values) => {
    calls.push({ sql, values });
    return {
      rows: [
        row({ id: '1', name: 'Pikachu', rank: 1200 }),
      ],
    };
  }, undefined, debug);

  assert.deepEqual(rows.map((result) => result.name), ['Pikachu']);
  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].values.slice(0, 3), ['p', 500, 'en']);
  assert.deepEqual(JSON.parse(calls[0].values[3]), [
    { kind: 'range', start: 'a', end: 'g' },
    { kind: 'range', start: 'h', end: 'o' },
    { kind: 'range', start: 'p', end: 'u' },
    { kind: 'range', start: 'v', end: 'z' },
    { kind: 'non_alpha' },
  ]);
  assert.match(calls[0].sql, /marketplace_search_candidates/);
  assert.match(calls[0].sql, /marketplace_card_names_for_language/);
  assert.match(calls[0].sql, /left join public\.marketplace_hot_blueprints/);
  assert.equal(debug.prefixPool.path, 'injected_name_prefix');
  assert.equal(debug.prefixPool.fallback, false);
});

test('one-character prefix query skips primary fallback when name peer fails', async () => {
  const calls = [];
  const debug = {};
  const originalError = console.error;
  console.error = () => {};
  try {
    await assert.rejects(
      () => namePrefixRowsForOneCharacterSearch(
        'p',
        1000,
        'en',
        async () => {
          calls.push('name');
          const error = new Error('name peer unavailable');
          error.code = 'ECONNRESET';
          throw error;
        },
        async () => {
          calls.push('primary');
          return { rows: [] };
        },
        debug,
      ),
      /name peer unavailable/,
    );
  } finally {
    console.error = originalError;
  }

  assert.deepEqual(calls, ['name']);
});

test('one-character prefix planner splits p ranges across four DB clients plus special bucket', () => {
  const plan = oneCharacterPrefixShardPlan('p', [
    { role: 'primary', query: async () => ({ rows: [] }) },
    { role: 'name_search', query: async () => ({ rows: [] }) },
    { role: 'variation_search', query: async () => ({ rows: [] }) },
    { role: 'variation_search_2', query: async () => ({ rows: [] }) },
  ]);

  assert.equal(plan.length, 4);
  assert.deepEqual(plan.map((shard) => shard.label), [
    'pa-pg,p+numeric_special_diacritic_apostrophe_hyphen_space',
    'ph-po',
    'pp-pu',
    'pv-pz',
  ]);
  assert.deepEqual(plan.map((shard) => shard.role), [
    'primary',
    'name_search',
    'variation_search',
    'variation_search_2',
  ]);
});

test('one-character prefix planner still works with one configured DB', () => {
  const plan = oneCharacterPrefixShardPlan('p', [
    { role: 'primary', query: async () => ({ rows: [] }) },
  ]);

  assert.equal(plan.length, 1);
  assert.equal(plan[0].label, 'pa-pg,ph-po,pp-pu,pv-pz,p+numeric_special_diacritic_apostrophe_hyphen_space');
});

test('sharded one-character prefix search runs shards in parallel and dedupes strongest rows', async () => {
  const calls = [];
  const debug = {};
  const clients = [
    {
      role: 'primary',
      query: async (_sql, values) => {
        calls.push({ role: 'primary', buckets: JSON.parse(values[3]) });
        return { rows: [row({ id: '1', name: 'Pikachu', rank: 10 })] };
      },
    },
    {
      role: 'name_search',
      query: async (_sql, values) => {
        calls.push({ role: 'name_search', buckets: JSON.parse(values[3]) });
        return {
          rows: [
            row({ id: '1', name: 'Pikachu', rank: 50 }),
            row({ id: '2', name: 'Porygon', rank: 40 }),
          ],
        };
      },
    },
  ];

  const rows = await shardedNamePrefixRowsForOneCharacterSearch('p', 1000, 'en', debug, clients);

  assert.equal(calls.length, 2);
  assert.deepEqual(rows.map((result) => `${result.card_id}:${result.search_rank}`), ['1:50', '2:40']);
  assert.equal(debug.prefixPool.path, 'typed_one_character_sharded_prefix');
  assert.equal(debug.prefixPool.shardCount, 2);
  assert.deepEqual(debug.prefixPool.shardRanges, [
    'pa-pg,pp-pu,p+numeric_special_diacritic_apostrophe_hyphen_space',
    'ph-po,pv-pz',
  ]);
});

test('sharded one-character prefix search does not fall failed replicas back to primary', async () => {
  const calls = [];
  const debug = {};
  const clients = [
    {
      role: 'primary',
      query: async (_sql, values) => {
        calls.push({ role: 'primary', buckets: JSON.parse(values[3]) });
        return { rows: [row({ id: '1', name: 'Pikachu', rank: 100 })] };
      },
    },
    {
      role: 'name_search',
      query: async () => {
        calls.push({ role: 'name_search' });
        throw new Error('replica unavailable');
      },
    },
  ];
  const originalError = console.error;
  console.error = () => {};
  try {
    const rows = await shardedNamePrefixRowsForOneCharacterSearch('p', 1000, 'en', debug, clients);
    assert.deepEqual(rows.map((result) => result.name), ['Pikachu']);
  } finally {
    console.error = originalError;
  }

  assert.equal(calls.length, 2);
  assert.equal(debug.prefixPool.fallback, false);
  assert.equal(debug.prefixPool.shards[1].fallback, false);
  assert.equal(debug.prefixPool.shards[1].failed, true);
  assert.equal(debug.prefixPool.shards[1].rowCount, 0);
});

test('typed one-character autocomplete returns prefix rows without generic hot fallback', async () => {
  const original = process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
  delete process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
  resetSupabaseNameIndexCircuitForTest();
  let calls = 0;
  const debug = {};
  let rows;
  try {
    rows = await rowsForAutocompleteSearchTermWithQuery(
      'p',
      500,
      'en',
      debug,
      null,
      async (sql, values) => {
        calls += 1;
        assert.deepEqual(values.slice(0, 3), ['p', 500, 'en']);
        assert.doesNotMatch(sql, /from public\.marketplace_hot_blueprints h\s+join public\.marketplace_search_candidates/);
        return {
          rows: [
            row({ id: '1', name: 'Pikachu', rank: 1200 }),
            row({ id: '2', name: 'Porygon', rank: 900 }),
          ],
        };
      },
    );
  } finally {
    resetSupabaseNameIndexCircuitForTest();
    if (original === undefined) delete process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
    else process.env.SUPABASE_NAME_INDEX_DATABASE_URL = original;
  }

  assert.deepEqual(rows.map((result) => result.name), ['Pikachu', 'Porygon']);
  assert.equal(calls, 1);
  assert.equal(debug.searchPath, 'typed_one_character_sharded_prefix');
  assert.equal(debug.tokenPlan.strategy, 'typed_one_character_sharded_prefix');
  assert.equal(debug.tokenPlan.shardCount, 1);
  assert.equal(debug.tokenPlan.candidateRowCount, 2);
  assert.equal(debug.tokenPlan.matchedRowCount, 2);
});

test('typed one-character autocomplete prefers Supabase token table over Oracle shard', async () => {
  const original = process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
  try {
    resetSupabaseNameIndexCircuitForTest();
    process.env.SUPABASE_NAME_INDEX_DATABASE_URL = 'postgres://supabase.example/name-index';
    const debug = {};
    let oracleShardCalls = 0;
    const rows = await rowsForAutocompleteSearchTermWithQuery(
      'p',
      500,
      'en',
      debug,
      null,
      async () => {
        oracleShardCalls += 1;
        return { rows: [] };
      },
      async (sql, values) => {
        assert.match(sql, /public\.marketplace_card_name_tokens/);
        assert.equal(values[0], 'p');
        return {
          rows: [
            {
              display_name: 'Pikachu',
              canonical_name: 'Pikachu',
              search_name: 'Pikachu',
              compact_name: 'pikachu',
              normalized_name: 'pikachu',
              name_tokens: ['pikachu'],
              language: 'en',
              card_ids: ['25'],
              representative_labels: [{ id: '25', name: 'Pikachu' }],
              row_count: 1,
              confidence: 91,
              score: 125000,
            },
            {
            display_name: 'Pikachu & Zekrom GX',
            canonical_name: 'Pikachu & Zekrom GX',
            search_name: 'Pikachu & Zekrom GX',
            compact_name: 'pikachuzekromgx',
            normalized_name: 'pikachu tagteam zekrom gx',
            name_tokens: ['gx', 'pikachu', 'tagteam', 'zekrom'],
              language: 'en',
              card_ids: ['201'],
            representative_labels: [{ id: '201', name: 'Pikachu & Zekrom GX' }],
              row_count: 1,
              confidence: 84,
              score: 64000,
            },
          ],
        };
      },
    );

    assert.deepEqual(rows.map((result) => result.name), ['Pikachu', 'Pikachu & Zekrom GX']);
    assert.equal(oracleShardCalls, 0);
    assert.equal(debug.searchPath, 'supabase_one_char_name_index');
    assert.equal(debug.tokenPlan.strategy, 'supabase_one_char_name_index');
    assert.notEqual(debug.searchPath, 'typed_one_character_sharded_prefix');
  } finally {
    resetSupabaseNameIndexCircuitForTest();
    if (original === undefined) delete process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
    else process.env.SUPABASE_NAME_INDEX_DATABASE_URL = original;
  }
});

test('typed one-character ranking keeps only matching prefix rows and honors limit', () => {
  const ranked = rankAutocompleteRows(
    [
      row({ id: '1', name: "Ash's Pikachu", rank: 10000 }),
      row({ id: '2', name: 'Porygon', rank: 500 }),
      row({ id: '3', name: 'Pikachu', rank: 100 }),
      row({ id: '4', name: 'Persian', rank: 900 }),
    ].filter((candidate) => candidate.name.startsWith('P')),
    'p',
    2,
    new Map([
      ['3', 800],
      ['2', 200],
      ['4', 50],
    ]),
  );

  assert.deepEqual(ranked.map((result) => result.name), ['Pikachu', 'Porygon']);
});

test('depth weighted context accumulates only over current matching candidates', () => {
  const firstRows = [
    row({ id: '1', name: 'Pikachu', rank: 100 }),
    row({ id: '2', name: 'Pichu', rank: 900 }),
    row({ id: '3', name: "Ash's Pikachu", rank: 850 }),
  ];
  const firstContext = buildSearchContext('p', 'en', firstRows, 'typed_one_character_sharded_prefix');
  const secondRows = [
    row({ id: '1', name: 'Pikachu', rank: 100 }),
    row({ id: '2', name: 'Pichu', rank: 900 }),
  ];
  const secondContext = buildSearchContext('pi', 'en', secondRows, 'name_table_direct', firstContext);
  const depthScores = secondContext.non_name_context.depth_scores;

  assert.equal(depthScores['1'], 3);
  assert.equal(depthScores['2'], 3);
  assert.equal(depthScores['3'], undefined);

  const rankedEntries = rankAutocompleteEntries(
    [
      row({ id: '2', name: 'Pichu', rank: 900 }),
      row({ id: '1', name: 'Pikachu', rank: 100 }),
      row({ id: '3', name: 'Charizard', rank: 20000 }),
    ],
    'pik',
    10,
    new Map(),
    { depthScores: { ...depthScores, 1: depthScores['1'] + 3 } },
  );
  const pikachu = rankedEntries.find((entry) => entry.row.name === 'Pikachu');
  const pichu = rankedEntries.find((entry) => entry.row.name === 'Pichu');
  const charizard = rankedEntries.find((entry) => entry.row.name === 'Charizard');

  assert.equal(pikachu.depthWeight, 6);
  assert.equal(pichu.depthWeight, 3);
  assert.equal(charizard.depthWeight, 0);
  assert.equal(charizard.depthBoost, 0);
});

test('structured autocomplete plans token intersections', () => {
  assert.deepEqual(intersectionTokenPlan('flareon ex'), {
    strategy: 'intersection',
    tokens: [
      { term: 'flareon', kind: 'text' },
      { term: 'ex', kind: 'variation' },
    ],
    skippedTokens: [],
  });
  assert.deepEqual(intersectionTokenPlan('manaphy ex'), {
    strategy: 'intersection',
    tokens: [
      { term: 'manaphy', kind: 'text' },
      { term: 'ex', kind: 'variation' },
    ],
    skippedTokens: [],
  });
  assert.deepEqual(intersectionTokenPlan('mapahy ex'), {
    strategy: 'intersection',
    tokens: [
      { term: 'mapahy', kind: 'text' },
      { term: 'ex', kind: 'variation' },
    ],
    skippedTokens: [],
  });
  assert.deepEqual(intersectionTokenPlan('manaphy gx'), {
    strategy: 'intersection',
    tokens: [
      { term: 'manaphy', kind: 'text' },
      { term: 'gx', kind: 'variation' },
    ],
    skippedTokens: [],
  });
  assert.deepEqual(intersectionTokenPlan('charizard 199'), {
    strategy: 'intersection',
    tokens: [
      { term: 'charizard', kind: 'text' },
      { term: '199', kind: 'number' },
    ],
    skippedTokens: [],
  });
  assert.equal(intersectionTokenPlan('flareon'), null);
  assert.equal(intersectionTokenPlan('mew special illustration rare'), null);
});

test('candidate fanout planner keeps name probe tokens separate from fields', () => {
  assert.deepEqual(candidateFanoutPlan('pikachu surgin'), {
    strategy: 'candidate_fanout',
    tokens: [
      { term: 'pikachu', kind: 'text' },
      { term: 'surgin', kind: 'text' },
    ],
    nameProbeTokens: [
      { term: 'pikachu', kind: 'text' },
      { term: 'surgin', kind: 'text' },
    ],
  });
  assert.equal(candidateFanoutPlan('ex'), null);
});

test('candidate fanout treats variation prefixes as structured fields', () => {
  assert.deepEqual(candidateFanoutPlan('mimikyu g'), {
    strategy: 'candidate_fanout',
    tokens: [
      { term: 'mimikyu', kind: 'text' },
      { term: 'g', kind: 'variation' },
    ],
    nameProbeTokens: [
      { term: 'mimikyu', kind: 'text' },
    ],
  });
  assert.deepEqual(candidateFanoutPlan('pikachu vm'), {
    strategy: 'candidate_fanout',
    tokens: [
      { term: 'pikachu', kind: 'text' },
      { term: 'vm', kind: 'variation' },
    ],
    nameProbeTokens: [
      { term: 'pikachu', kind: 'text' },
    ],
  });
});

test('candidate fanout treats HGSS era terms as expansion fields', () => {
  assert.deepEqual(candidateFanoutPlan('rare candy hgss'), {
    strategy: 'candidate_fanout',
    tokens: [
      { term: 'rare', kind: 'rarity' },
      { term: 'candy', kind: 'text' },
      { term: 'hgs', kind: 'expansion' },
    ],
    nameProbeTokens: [
      { term: 'candy', kind: 'text' },
    ],
  });
  assert.equal(intersectionTokenPlan('candy heartgold').tokens[1].kind, 'expansion');
  assert.equal(intersectionTokenPlan('candy soulsilver').tokens[1].kind, 'expansion');
  assert.equal(intersectionTokenPlan('umbreon unleashed').tokens[1].kind, 'expansion');
});

test('HGSS set punctuation does not become tag team intent', () => {
  assert.deepEqual(candidateFanoutPlan('energy HeartGold & SoulSilver'), {
    strategy: 'candidate_fanout',
    tokens: [
      { term: 'energy', kind: 'text' },
      { term: 'heartgoldsoulsilver', kind: 'expansion' },
    ],
    nameProbeTokens: [
      { term: 'energy', kind: 'text' },
    ],
  });
});

test('generic energy expansion planner targets broad energy intent only', () => {
  assert.deepEqual(genericEnergyExpansionPlan('energy HeartGold & SoulSilver'), {
    strategy: 'generic_energy_expansion',
    tokens: [
      { term: 'energy', kind: 'text' },
      { term: 'heartgoldsoulsilver', kind: 'expansion' },
    ],
    expansionTokens: [
      { term: 'heartgoldsoulsilver', kind: 'expansion' },
    ],
  });
  assert.equal(genericEnergyExpansionPlan('basic energy heartgold').strategy, 'generic_energy_expansion');
  assert.equal(genericEnergyExpansionPlan('fire energy heartgold'), null);
});

test('generic energy expansion search keeps all matching energy-name candidates', async () => {
  const debug = {};
  const rows = await searchGenericEnergyExpansionRowsWithDatabase(
    'energy HeartGold & SoulSilver',
    20,
    debug,
    async (sql, values) => {
      assert.match(sql, /like '%energy'/);
      assert.deepEqual(values[0], [
        'heartgoldsoulsilver',
        'unleashed',
        'undaunted',
        'triumphant',
        'calloflegends',
      ]);
      return {
        rows: [
          row({ id: '1', name: 'Fire Energy', set: 'HeartGold & SoulSilver', rank: 8814 }),
          row({ id: '2', name: 'Energy Returner', set: 'Unleashed', rank: 6514 }),
          row({ id: '3', name: 'Energy Exchanger', set: 'Undaunted', rank: 6514 }),
        ],
      };
    },
  );

  assert.deepEqual(rows.map((result) => result.name), ['Fire Energy', 'Energy Returner', 'Energy Exchanger']);
  assert.equal(debug.genericEnergyExpansion.candidateRowCount, 3);
});

test('intersection keeps only rows shared by all token result sets', () => {
  const flareonRows = [
    row({ id: '1', name: 'Flareon' }),
    row({ id: '2', name: 'Flareon ex' }),
    row({ id: '3', name: 'Flareon VMAX' }),
  ];
  const exRows = [
    row({ id: '4', name: 'Absol ex' }),
    row({ id: '2', name: 'Flareon ex' }),
  ];

  assert.deepEqual(
    intersectRows([flareonRows, exRows], 20).map((result) => result.name),
    ['Flareon ex'],
  );
});

test('stored variation filtering keeps name candidates that have the requested variation', async () => {
  const rows = [
    row({ id: '110433', name: 'Manaphy ex' }),
    row({ id: '113676', name: 'Manaphy' }),
  ];
  const filtered = await filterRowsByStoredStructuredTokens(
    rows,
    [{ term: 'ex', kind: 'variation' }],
    async () => ({
      rows: [
        {
          card_id: '110433',
          variation_keys: ['ex'],
          compact_number: '32122',
          compact_set: 'breakpoint',
        },
        {
          card_id: '113676',
          variation_keys: [],
          compact_number: 'holotrainerkit412',
          compact_set: 'dptrainerkitmanaphy',
        },
      ],
    }),
  );

  assert.deepEqual(filtered.map((result) => result.name), ['Manaphy ex']);
});

test('required predictive tokens include leading variation modifiers', () => {
  const filtered = filterRowsByRequiredNameTokens(
    [
      row({ id: '1', name: 'Darkrai EX', set: 'Dark Rush', type: 'Darkness' }),
      row({ id: '2', name: 'Mega Darkrai ex', set: 'Abyss Eye', type: 'Darkness' }),
    ],
    'mega darkrai ex',
  );

  assert.equal(filtered.applied, true);
  assert.deepEqual(filtered.rows.map((result) => result.name), ['Mega Darkrai ex']);
});

test('stored variation filtering expands short variation prefixes', async () => {
  const rows = [
    row({ id: '1', name: 'Mimikyu', set: 'GX Battle Boost' }),
    row({ id: '2', name: 'Mimikyu GX' }),
  ];
  const filtered = await filterRowsByStoredStructuredTokens(
    rows,
    [{ term: 'g', kind: 'variation' }],
    async () => ({
      rows: [
        {
          card_id: '1',
          variation_keys: [],
          compact_number: '001100',
          compact_set: 'gxbattleboost',
        },
        {
          card_id: '2',
          variation_keys: ['gx'],
          compact_number: '002100',
          compact_set: 'lostthunder',
        },
      ],
    }),
  );

  assert.deepEqual(filtered.map((result) => result.name), ['Mimikyu GX']);
});

test('stored number filtering matches collector numbers after rarity text', async () => {
  const rows = [
    row({
      id: '274416',
      name: 'Mew ex',
      number: 'Special Illustration Rare | 232/091',
    }),
    row({ id: '287350', name: 'Mew', number: '005/016' }),
  ];
  const filtered = await filterRowsByStoredStructuredTokens(
    rows,
    [{ term: '232', kind: 'number' }],
    async () => ({
      rows: [
        {
          card_id: '274416',
          variation_keys: ['ex'],
          normalized_number: 'special illustration rare 232 091',
          compact_number: 'specialillustrationrare232091',
          compact_set: 'paldeanfates',
        },
        {
          card_id: '287350',
          variation_keys: [],
          normalized_number: '005 016',
          compact_number: '005016',
          compact_set: 'miragesmewconstructedstarterdeck',
        },
      ],
    }),
  );

  assert.deepEqual(filtered.map((result) => result.name), ['Mew ex']);
});

test('stored number filtering falls back to card version collector text', async () => {
  const rows = [
    row({
      id: '274416',
      name: 'Mew ex',
      number: '',
    }),
    row({ id: '287350', name: 'Mew', number: '' }),
  ];
  const filtered = await filterRowsByStoredStructuredTokens(
    rows,
    [{ term: '232', kind: 'number' }],
    async (sql, values) => {
      assert.match(sql, /marketplace_cards mc/);
      assert.match(sql, /cardtrader_pokemon_blueprints b/);
      assert.deepEqual(values[0], [274416, 287350]);
      return {
        rows: [
          {
            card_id: '274416',
            variation_keys: ['ex'],
            normalized_number: 'special illustration rare 232 091',
            compact_number: 'specialillustrationrare232091',
            compact_set: 'paldeanfates',
          },
          {
            card_id: '287350',
            variation_keys: [],
            normalized_number: '',
            compact_number: '',
            compact_set: 'miragesmewconstructedstarterdeck',
          },
        ],
      };
    },
  );

  assert.deepEqual(filtered.map((result) => result.name), ['Mew ex']);
});

test('name token fallback asks for exact and prefix compact card names only as a safety net', async () => {
  const calls = [];
  await searchNameTokenFallbackWithDatabase('manaphy', 20, 0, 'fr', async (sql, values) => {
    calls.push({ sql, values });
    return { rows: [] };
  });

  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].values, ['manaphy', 20, 0, 'fr']);
  assert.match(calls[0].sql, /marketplace_search_candidates/);
  assert.match(calls[0].sql, /marketplace_card_names_for_language/);
  assert.match(calls[0].sql, /canonical_name/);
  assert.match(calls[0].sql, /like n\.compact_q \|\| '%'/);
  assert.match(calls[0].sql, /marketplace_edit_distance/);
});

test('name token fallback documents the expansion-alias collision regression', async () => {
  const rows = await searchNameTokenFallbackWithDatabase('manaphy', 20, 0, 'en', async () => ({
    rows: [
      row({ id: '110433', name: 'Manaphy ex' }),
      row({ id: '113676', name: 'Manaphy' }),
    ],
  }));

  assert.deepEqual(rows.map((result) => result.name), ['Manaphy ex', 'Manaphy']);
});

test('fast name preview queries canonical name tokens before intersections', async () => {
  const rows = await searchFastNamePreviewWithDatabase(
    'pikachu surgin',
    20,
    'en',
    async (sql, values) => ({
      rows: values[0] === 'pikachu'
        ? [
            row({ id: '306126', name: 'Pikachu ex', set: 'Surging Sparks' }),
            row({ id: '171164', name: 'Surfing Pikachu', set: 'Pikachu World Collection' }),
          ]
        : [],
    }),
  );

  assert.deepEqual(
    rows.map((result) => result.name),
    ['Pikachu ex', 'Surfing Pikachu'],
  );
});

test('fast name preview keeps plain-name candidates within requested limit', async () => {
  const calls = [];
  const rows = await searchFastNamePreviewWithDatabase(
    'pikachu',
    10,
    'en',
    async (sql, values) => {
      calls.push({ sql, values });
      return {
        rows: [
          { ...row({ id: '165', name: 'Pikachu & Zekrom GX', rank: 3300 }), canonical_name: 'Pikachu & Zekrom GX' },
          { ...row({ id: '317048', name: 'Pikachu', rank: 3300 }), canonical_name: 'Pikachu' },
        ],
      };
    },
  );

  assert.equal(calls[0].values[1], 10);
  assert.deepEqual(
    new Set(rows.map((result) => result.name)),
    new Set(['Pikachu', 'Pikachu & Zekrom GX']),
  );
});

test('fast name preview filters variation prefixes before set-name matches', async () => {
  const rows = await searchFastNamePreviewWithDatabase(
    'mimikyu g',
    8,
    'en',
    async (sql, values) => {
      if (/where c\.card_id = any\(\$1::bigint\[\]\)/.test(sql)) {
        return {
          rows: [
            { card_id: '1', variation_keys: [], compact_number: '043114', compact_set: 'gxbattleboost' },
            { card_id: '2', variation_keys: ['gx'], compact_number: '149214', compact_set: 'lostthunder' },
          ],
        };
      }
      return {
        rows: [
          row({ id: '1', name: 'Mimikyu', set: 'GX Battle Boost', rank: 3000 }),
          row({ id: '2', name: 'Mimikyu GX', set: 'Lost Thunder', rank: 1000 }),
        ],
      };
    },
  );

  assert.deepEqual(rows.map((result) => result.name), ['Mimikyu GX']);
});

test('candidate fanout filters expansion typo within canonical name candidates', async () => {
  const rows = await searchStructuredAutocompleteWithCandidateFanout(
    'pikachu surgin',
    20,
    'en',
    {},
    fanoutMockQuery({
      entities: { pikachu: ['Pikachu'] },
      candidates: [
        {
          ...row({ id: '1', name: 'Pikachu ex', set: 'Surging Sparks', rank: 20 }),
          canonical_name: 'Pikachu',
          normalized_set: 'surging sparks',
          compact_set: 'surgingsparks',
          variation_keys: ['ex'],
        },
        {
          ...row({ id: '2', name: 'Surfing Pikachu', set: 'Celebrations', rank: 200 }),
          canonical_name: 'Pikachu',
          normalized_set: 'celebrations',
          compact_set: 'celebrations',
          variation_keys: ['surfing'],
        },
      ],
    }),
  );

  assert.deepEqual(rows.map((result) => result.name), ['Pikachu ex']);
});

test('candidate fanout applies variation and collector number fields to name candidates', async () => {
  const rows = await searchStructuredAutocompleteWithCandidateFanout(
    'mew ex 232',
    20,
    'en',
    {},
    fanoutMockQuery({
      entities: { mew: ['Mew'] },
      candidates: [
        {
          ...row({ id: '1', name: 'Mew ex', number: 'Special Illustration Rare | 232/091', rank: 20 }),
          canonical_name: 'Mew',
          normalized_number: 'special illustration rare 232 091',
          compact_number: 'specialillustrationrare232091',
          variation_keys: ['ex'],
        },
        {
          ...row({ id: '2', name: 'Mew', number: '005/016', rank: 200 }),
          canonical_name: 'Mew',
          normalized_number: '005 016',
          compact_number: '005016',
          variation_keys: [],
        },
      ],
    }),
  );

  assert.deepEqual(rows.map((result) => result.name), ['Mew ex']);
});

test('candidate fanout treats expansion as field after card-name anchor', async () => {
  const rows = await searchStructuredAutocompleteWithCandidateFanout(
    'umbreon unleashed',
    20,
    'en',
    {},
    fanoutMockQuery({
      entities: { umbreon: ['Umbreon'] },
      candidates: [
        {
          ...row({ id: '1', name: 'Umbreon VMAX', set: 'Evolving Skies', rank: 30000 }),
          canonical_name: 'Umbreon',
          normalized_set: 'evolving skies',
          compact_set: 'evolvingskies',
        },
        {
          ...row({ id: '2', name: 'Umbreon', set: 'Unleashed', number: '10/90', rank: 100 }),
          canonical_name: 'Umbreon',
          normalized_set: 'unleashed',
          compact_set: 'unleashed',
        },
      ],
    }),
  );

  assert.deepEqual(rows.map((result) => result.card_id), ['2']);
});

test('candidate fanout resolves short typo name before collector number filter', async () => {
  const debug = {};
  const rows = await searchStructuredAutocompleteWithCandidateFanout(
    'mee 232',
    20,
    'en',
    debug,
    fanoutMockQuery({
      entities: { mee: ['Mew'] },
      candidates: [
        {
          ...row({ id: '274416', name: 'Mew ex', number: 'Special Illustration Rare | 232/091', rank: 20 }),
          canonical_name: 'Mew',
          normalized_number: 'special illustration rare 232 091',
          compact_number: 'specialillustrationrare232091',
          variation_keys: ['ex'],
        },
        {
          ...row({ id: '287350', name: 'Mew', number: '005/016', rank: 200 }),
          canonical_name: 'Mew',
          normalized_number: '005 016',
          compact_number: '005016',
          variation_keys: [],
        },
      ],
    }),
  );

  assert.deepEqual(rows.map((result) => result.card_id), ['274416']);
  assert.equal(debug.tokenPlan.strategy, 'candidate_fanout');
  assert.deepEqual(debug.tokenPlan.fieldTokens, [{ term: '232', kind: 'number' }]);
});

test('candidate fanout does not invent arbitrary rows for unrelated typo plus number', async () => {
  const rows = await searchStructuredAutocompleteWithCandidateFanout(
    'zzz 232',
    20,
    'en',
    {},
    fanoutMockQuery({
      entities: { zzz: [] },
      candidates: [
        {
          ...row({ id: '274416', name: 'Mew ex', number: 'Special Illustration Rare | 232/091', rank: 20 }),
          canonical_name: 'Mew',
          normalized_number: 'special illustration rare 232 091',
          compact_number: 'specialillustrationrare232091',
          variation_keys: ['ex'],
        },
      ],
    }),
  );

  assert.equal(rows, null);
});

test('candidate fanout applies trainer fields to trainer-owned pokemon', async () => {
  const rows = await searchStructuredAutocompleteWithCandidateFanout(
    'lt surge pikachu',
    20,
    'en',
    {},
    fanoutMockQuery({
      entities: { pikachu: ['Pikachu'] },
      candidates: [
        {
          ...row({ id: '1', name: "Lt. Surge's Pikachu", trainer: 'Lt. Surge', rank: 20 }),
          canonical_name: 'Pikachu',
          normalized_trainer: 'lt surge',
          compact_trainer: 'ltsurge',
        },
        {
          ...row({ id: '2', name: 'Pikachu', trainer: '', rank: 200 }),
          canonical_name: 'Pikachu',
          normalized_trainer: '',
          compact_trainer: '',
        },
      ],
    }),
  );

  assert.deepEqual(rows.map((result) => result.name), ["Lt. Surge's Pikachu"]);
});

test('predictive pool planner keeps name and dimension tokens separate', () => {
  assert.deepEqual(predictivePoolPlan('mew ex 232').tokens, [
    { term: 'mew', kind: 'text' },
    { term: 'ex', kind: 'variation' },
    { term: '232', kind: 'number' },
  ]);
  assert.deepEqual(predictivePoolPlan('mew ex 232').dimensionTokens, [
    { term: 'ex', kind: 'variation' },
    { term: '232', kind: 'number' },
  ]);
});

test('predictive pool planner keeps only leading text as anchored name candidate', () => {
  const rareCandyPlan = predictiveNameFragmentCandidates([
    { term: 'rare', kind: 'rarity' },
    { term: 'candy', kind: 'text' },
    { term: 'heartgold', kind: 'expansion' },
  ]);
  assert.equal(rareCandyPlan.some((candidate) =>
    candidate.nameFragment === 'heartgold' ||
    candidate.nameFragment === 'candy heartgold'), false);

  const megaPlan = predictiveNameFragmentCandidates([
    { term: 'mega', kind: 'variation' },
    { term: 'd', kind: 'text' },
  ]);
  assert.deepEqual(megaPlan.map((candidate) => candidate.nameFragment), ['d']);
});

test('prediction context supplies predicted names for dimension verification', () => {
  const plan = predictivePoolPlan('pikachu 025');
  const context = {
    query: 'pik',
    fragment: 'pik',
    normalized_fragment: 'pik',
    language: 'en',
    created_at_ms: Date.now(),
    candidates: [
      {
        display_token: 'Pikachu',
        normalized_token: 'pikachu',
        confidence: 96,
        score: 200000,
        representative_card_ids: ['25'],
      },
    ],
  };
  const debug = {};
  const cleaned = cleanPredictionContext(context, 'pikachu 025', 'en');
  const sets = predictionSetsFromContext(plan, context, 'pikachu 025', 'en', debug);

  assert.equal(cleaned.valid, true);
  assert.equal(sets.length, 1);
  assert.equal(sets[0].predictions[0].display, 'Pikachu');
  assert.equal(sets[0].dimensionTokens.some((token) => token.kind === 'number'), true);
  assert.equal(debug.predictionContext.used, true);
});

test('first-name anchor turns trailing text into dimension tokens', async () => {
  const plan = predictivePoolPlan('rare candy heartgold');
  const anchor = await firstNameAnchorForPredictivePlan(
    plan,
    'en',
    {},
    async (_sql, values) => {
      if (values[0] !== 'rarecandy') return { rows: [] };
      return {
        rows: [
          {
            canonical_name: 'Rare Candy',
            display_name: 'Rare Candy',
            compact_name: 'rarecandy',
            name_tokens: ['rare', 'candy'],
            language: 'en',
            confidence: 100,
            score: 240000,
            card_ids: ['1', '2', '3'],
            row_count: 3,
          },
        ],
      };
    },
    null,
  );
  const sets = anchoredPredictionSets(anchor, plan.tokens);

  assert.ok(anchor);
  assert.ok(sets);
  assert.equal(anchor.nameFragment, 'rare candy');
  assert.equal(sets.length, 1);
  assert.deepEqual(sets[0].nameTerms, ['rare', 'candy']);
  assert.deepEqual(sets[0].dimensionTokens, [
    { term: 'heartgold', kind: 'expansion', sourceHint: undefined },
  ]);
  assert.equal(sets[0].predictions[0].display, 'Rare Candy');
});

test('prediction context invalidates on branch or language mismatch', () => {
  const context = {
    normalized_fragment: 'pi',
    language: 'en',
    created_at_ms: Date.now(),
    candidates: [{ display_token: 'Pikachu', normalized_token: 'pikachu' }],
  };

  assert.equal(cleanPredictionContext(context, 'paras', 'en').valid, false);
  assert.equal(cleanPredictionContext(context, 'pikachu', 'fr').reason, 'language_changed');
});

test('mega darkrai does not anchor on Mega as the first card name', async () => {
  const plan = predictivePoolPlan('mega darkrai');
  const calls = [];
  const anchor = await firstNameAnchorForPredictivePlan(
    plan,
    'en',
    {},
    async (_sql, values) => {
      calls.push(values[0]);
      return {
        rows: [
          {
            canonical_name: 'Mega',
            display_name: 'Mega',
            compact_name: 'mega',
            name_tokens: ['mega'],
            language: 'en',
            confidence: 100,
            score: 240000,
            card_ids: ['1'],
            row_count: 1,
          },
        ],
      };
    },
    null,
  );

  assert.equal(anchor, null);
  assert.deepEqual(calls, []);
});

test('predictive pool merge honors source hierarchy and exposes source flags', () => {
  const rows = mergePredictivePoolRows([
    {
      source: 'rarity',
      status: 'fulfilled',
      rows: [row({ id: '3', name: 'Energy Switch', rarity: 'Special Illustration Rare', rank: 5000 })],
    },
    {
      source: 'number',
      status: 'fulfilled',
      rows: [row({ id: '2', name: 'Mewtwo ex', number: '232/091', rank: 9000 })],
    },
    {
      source: 'variation_owner',
      status: 'fulfilled',
      rows: [row({ id: '1', name: 'Mew ex', number: '232/091', rank: 100 })],
    },
    {
      source: 'name',
      status: 'fulfilled',
      rows: [row({ id: '1', name: 'Mew ex', number: '232/091', rank: 100 })],
    },
  ], 'mew ex 232', 20);

  assert.equal(rows[0].card_id, '1');
  assert.deepEqual(rows[0].predictive_source_flags.sort(), ['name', 'variation_owner']);
  assert.ok(rows[0].predictive_score_components.name > rows[0].predictive_score_components.variation_owner);
});

test('predicted-name confidence boosts but does not lock stale candidates', () => {
  const rows = mergePredictivePoolRows([
    {
      source: 'name',
      status: 'fulfilled',
      query: 'mewt',
      rows: [
        {
          ...row({ id: '1', name: 'Mew', rank: 50000 }),
          predicted_name_confidence: 72,
          predicted_name: { normalized: 'mew', display: 'Mew', confidence: 72 },
          predictive_source_flags: ['name'],
        },
        {
          ...row({ id: '2', name: 'Mewtwo', rank: 100 }),
          predicted_name_confidence: 94,
          predicted_name: { normalized: 'mewtwo', display: 'Mewtwo', confidence: 94 },
          predictive_source_flags: ['name'],
        },
      ],
    },
  ], 'mewt', 20);

  assert.equal(rows[0].name, 'Mewtwo');
  assert.equal(rows[0].predicted_name_confidence, 94);
});

test('predicted-name rows verify remaining dimensions before ranking', async () => {
  const rows = await predictiveRowsForNamePredictions([
    {
      nameFragment: 'mee',
      dimensionTokens: [{ term: '232', kind: 'number' }],
      predictions: [
        {
          normalized: 'mew',
          display: 'Mew',
          confidence: 76,
          score: 5000,
          source_rank: 1,
          language: 'en',
          representative_card_ids: ['274416'],
          representative_labels: [{ id: '274416', name: 'Mew ex' }],
        },
      ],
    },
  ], 5000, async () => ({
    rows: [
      {
        ...row({
          id: '274416',
          name: 'Mew ex',
          number: 'Special Illustration Rare | 232/091',
          rank: 20,
        }),
        canonical_name: 'Mew',
        normalized_number: 'special illustration rare 232 091',
        compact_number: 'specialillustrationrare232091',
        variation_keys: ['ex'],
      },
      {
        ...row({ id: '287350', name: 'Mew', number: '005/016', rank: 9000 }),
        canonical_name: 'Mew',
        normalized_number: '005 016',
        compact_number: '005016',
        variation_keys: [],
      },
    ],
  }));

  assert.deepEqual(rows.map((result) => result.card_id), ['274416']);
  assert.ok(rows[0].predictive_source_flags.includes('number'));
  assert.equal(rows[0].predicted_name.display, 'Mew');
});

test('predicted-name dimension verification queries canonical names and source dimensions', async () => {
  const calls = [];
  const rows = await predictiveVerifiedDimensionRowsWithDatabase(
    'number',
    [
      {
        nameFragment: 'mee',
        dimensionTokens: [{ term: '232', kind: 'number' }],
        predictions: [
          {
            normalized: 'mew',
            display: 'Mew',
            confidence: 76,
            score: 5000,
            source_rank: 1,
            language: 'en',
          },
        ],
      },
    ],
    5000,
    async (sql, values) => {
      calls.push({ sql, values });
      assert.match(sql, /coalesce\(nullif\(c\.canonical_name, ''\), c\.name\) = any\(input\.canonical_names\)/);
      assert.match(sql, /candidate_number\.card_number/);
      assert.deepEqual(values[0], ['Mew']);
      assert.equal(values[5], 'number');
      return {
        rows: [
          {
            ...row({ id: '274416', name: 'Mew ex', number: '232/091' }),
            canonical_name: 'Mew',
          },
        ],
      };
    },
  );

  assert.equal(calls.length, 1);
  assert.deepEqual(rows.map((result) => result.card_id), ['274416']);
  assert.deepEqual(rows[0].predictive_source_flags.sort(), ['name', 'number']);
});

test('predicted-name dimension verification prefers bounded candidate card IDs', async () => {
  const calls = [];
  const rows = await predictiveVerifiedDimensionRowsWithDatabase(
    'number',
    [
      {
        nameFragment: 'laprs',
        dimensionTokens: [{ term: '045', kind: 'number' }],
        predictions: [
          {
            normalized: 'lapras',
            display: 'Lapras',
            confidence: 76,
            score: 90000,
            source_rank: 1,
            language: 'en',
            representative_card_ids: ['131'],
            candidate_card_ids: ['131', '132'],
          },
        ],
      },
    ],
    5000,
    async (sql, values) => {
      calls.push({ sql, values });
      assert.match(sql, /candidate_card_ids/);
      assert.match(sql, /c\.card_id = any\(input\.candidate_card_ids\)/);
      assert.deepEqual(values[0], ['Lapras']);
      assert.deepEqual(values[7], ['131', '132']);
      return {
        rows: [
          {
            ...row({ id: '131', name: 'Lapras', number: '045/165' }),
            canonical_name: 'Lapras',
          },
        ],
      };
    },
  );

  assert.equal(calls.length, 1);
  assert.equal(rows[0].card_id, '131');
  assert.equal(rows[0].predicted_name.display, 'Lapras');
  assert.deepEqual(rows[0].predicted_name.candidate_card_ids, ['131', '132']);
  assert.deepEqual(rows[0].predictive_source_flags.sort(), ['name', 'number']);
});

test('predictive dimension query targets collector number source', async () => {
  const calls = [];
  const rows = await predictiveDimensionRowsWithDatabase(
    'number',
    [{ term: '232', kind: 'number' }],
    5000,
    async (sql, values) => {
      calls.push({ sql, values });
      assert.match(sql, /candidate_number\.card_number/);
      assert.equal(values[4], 'number');
      return {
        rows: [
          row({ id: '274416', name: 'Mew ex', number: 'Special Illustration Rare | 232/091' }),
        ],
      };
    },
  );

  assert.equal(calls.length, 1);
  assert.equal(rows[0].card_id, '274416');
});

test('strict predictive pool exposes required source failure instead of broad fallback', async () => {
  const originalEnabled = process.env.MARKETPLACE_PREDICTIVE_POOL_ENABLED;
  const originalStrict = process.env.MARKETPLACE_PREDICTIVE_POOL_STRICT;
  const originalPrimary = process.env.MARKETPLACE_DATABASE_URL;
  const originalName = process.env.MARKETPLACE_NAME_SEARCH_DATABASE_URL;
  const originalSupabase = process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
  const originalPeer1 = process.env.MARKETPLACE_PEER1_DATABASE_URL;
  const originalPeer2 = process.env.MARKETPLACE_PEER2_DATABASE_URL;
  const originalPeer3 = process.env.MARKETPLACE_PEER3_DATABASE_URL;
  const originalVariationList = process.env.MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS;
  const originalVariation = process.env.MARKETPLACE_VARIATION_SEARCH_DATABASE_URL;
  const originalNumber = process.env.MARKETPLACE_NUMBER_SEARCH_DATABASE_URL;
  const originalExpansion = process.env.MARKETPLACE_EXPANSION_SEARCH_DATABASE_URL;
  const originalRarity = process.env.MARKETPLACE_RARITY_SEARCH_DATABASE_URL;
  const originalOwner = process.env.MARKETPLACE_VARIATION_OWNER_SEARCH_DATABASE_URL;
  try {
    process.env.MARKETPLACE_PREDICTIVE_POOL_ENABLED = '1';
    process.env.MARKETPLACE_PREDICTIVE_POOL_STRICT = '1';
    process.env.MARKETPLACE_DATABASE_URL = 'postgres://peer4.example/db';
    delete process.env.MARKETPLACE_NAME_SEARCH_DATABASE_URL;
    delete process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
    delete process.env.MARKETPLACE_PEER1_DATABASE_URL;
    delete process.env.MARKETPLACE_PEER2_DATABASE_URL;
    delete process.env.MARKETPLACE_PEER3_DATABASE_URL;
    delete process.env.MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS;
    delete process.env.MARKETPLACE_VARIATION_SEARCH_DATABASE_URL;
    delete process.env.MARKETPLACE_NUMBER_SEARCH_DATABASE_URL;
    delete process.env.MARKETPLACE_EXPANSION_SEARCH_DATABASE_URL;
    delete process.env.MARKETPLACE_RARITY_SEARCH_DATABASE_URL;
    delete process.env.MARKETPLACE_VARIATION_OWNER_SEARCH_DATABASE_URL;

    const debug = {};
    let queryCalled = false;
    await assert.rejects(
      () => buildPredictivePoolWithFanout('mew 232', 5000, 'en', null, debug, async () => {
        queryCalled = true;
        return { rows: [] };
      }),
      (error) => {
        assert.equal(error.code, 'PREDICTIVE_POOL_SOURCE_FAILED');
        assert.ok(error.predictivePool.failedSources.some((source) => source.source === 'number'));
        return true;
      },
    );
    assert.equal(queryCalled, true);
    assert.equal(debug.predictivePool.strict, true);
    assert.ok(debug.predictivePool.sources.some((source) =>
      source.status === 'failed' &&
      source.reason === 'source_not_configured_no_primary_fallback'));
  } finally {
    if (originalEnabled === undefined) delete process.env.MARKETPLACE_PREDICTIVE_POOL_ENABLED;
    else process.env.MARKETPLACE_PREDICTIVE_POOL_ENABLED = originalEnabled;
    if (originalStrict === undefined) delete process.env.MARKETPLACE_PREDICTIVE_POOL_STRICT;
    else process.env.MARKETPLACE_PREDICTIVE_POOL_STRICT = originalStrict;
    if (originalPrimary === undefined) delete process.env.MARKETPLACE_DATABASE_URL;
    else process.env.MARKETPLACE_DATABASE_URL = originalPrimary;
    if (originalName === undefined) delete process.env.MARKETPLACE_NAME_SEARCH_DATABASE_URL;
    else process.env.MARKETPLACE_NAME_SEARCH_DATABASE_URL = originalName;
    if (originalSupabase === undefined) delete process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
    else process.env.SUPABASE_NAME_INDEX_DATABASE_URL = originalSupabase;
    if (originalPeer1 === undefined) delete process.env.MARKETPLACE_PEER1_DATABASE_URL;
    else process.env.MARKETPLACE_PEER1_DATABASE_URL = originalPeer1;
    if (originalPeer2 === undefined) delete process.env.MARKETPLACE_PEER2_DATABASE_URL;
    else process.env.MARKETPLACE_PEER2_DATABASE_URL = originalPeer2;
    if (originalPeer3 === undefined) delete process.env.MARKETPLACE_PEER3_DATABASE_URL;
    else process.env.MARKETPLACE_PEER3_DATABASE_URL = originalPeer3;
    if (originalVariationList === undefined) delete process.env.MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS;
    else process.env.MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS = originalVariationList;
    if (originalVariation === undefined) delete process.env.MARKETPLACE_VARIATION_SEARCH_DATABASE_URL;
    else process.env.MARKETPLACE_VARIATION_SEARCH_DATABASE_URL = originalVariation;
    if (originalNumber === undefined) delete process.env.MARKETPLACE_NUMBER_SEARCH_DATABASE_URL;
    else process.env.MARKETPLACE_NUMBER_SEARCH_DATABASE_URL = originalNumber;
    if (originalExpansion === undefined) delete process.env.MARKETPLACE_EXPANSION_SEARCH_DATABASE_URL;
    else process.env.MARKETPLACE_EXPANSION_SEARCH_DATABASE_URL = originalExpansion;
    if (originalRarity === undefined) delete process.env.MARKETPLACE_RARITY_SEARCH_DATABASE_URL;
    else process.env.MARKETPLACE_RARITY_SEARCH_DATABASE_URL = originalRarity;
    if (originalOwner === undefined) delete process.env.MARKETPLACE_VARIATION_OWNER_SEARCH_DATABASE_URL;
    else process.env.MARKETPLACE_VARIATION_OWNER_SEARCH_DATABASE_URL = originalOwner;
  }
});

test('name-only fanout uses card-name table for trainer cards', async () => {
  const debug = {};
  const rows = await searchNameOnlyAutocompleteWithCardNameFanout(
    'cynthia',
    20,
    'en',
    debug,
    fanoutMockQuery({
      entities: { cynthia: ['Cynthia'] },
      candidates: [
        {
          ...row({ id: '1', name: 'Cynthia', set: 'Hidden Fates', rank: 20 }),
          canonical_name: 'Cynthia',
        },
        {
          ...row({ id: '2', name: "Cynthia's Ambition", set: 'Crown Zenith', rank: 200 }),
          canonical_name: "Cynthia's Ambition",
        },
      ],
    }),
  );

  assert.equal(debug.tokenPlan.strategy, 'name_table_fanout');
  assert.deepEqual(rows.map((result) => result.name), ['Cynthia']);
});

test('direct name-only query joins card-name table to candidates in one request', async () => {
  const calls = [];
  const rows = await searchNameOnlyRowsWithDatabase(
    ['cynthia'],
    20,
    'en',
    async (sql, values) => {
      calls.push({ sql, values });
      return {
        rows: [
          row({ id: '1', name: 'Cynthia', set: 'Hidden Fates' }),
        ],
      };
    },
  );

  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].values, [['cynthia'], 20, 'en']);
  assert.match(calls[0].sql, /marketplace_card_names_for_language/);
  assert.match(calls[0].sql, /marketplace_search_candidates/);
  assert.doesNotMatch(calls[0].sql, /marketplace_edit_distance/);
  assert.deepEqual(rows.map((result) => result.name), ['Cynthia']);
});

test('combined card-name search matches trainer owned pokemon before broad fanout', async () => {
  const calls = [];
  const rows = await searchCombinedCardNameWithDatabase(
    ['cynthia', 'garchomp'],
    20,
    async (sql, values) => {
      calls.push({ sql, values });
      return {
        rows: [
          row({ id: '1', name: "Cynthia's Garchomp ex", set: 'Heat Wave Arena' }),
        ],
      };
    },
  );

  assert.equal(calls.length, 1);
  assert.deepEqual(calls[0].values, [['cynthia', 'garchomp'], 20]);
  assert.match(calls[0].sql, /source_name/);
  assert.deepEqual(rows.map((result) => result.name), ["Cynthia's Garchomp ex"]);
});

test('name-only fanout handles possessive queries through card names', async () => {
  const rows = await searchNameOnlyAutocompleteWithCardNameFanout(
    'rockets mewtwo',
    20,
    'en',
    {},
    fanoutMockQuery({
      entities: {
        rocket: ["Rocket's Mewtwo"],
        mewtwo: ["Rocket's Mewtwo", 'Mewtwo'],
      },
      candidates: [
        {
          ...row({ id: '1', name: "Rocket's Mewtwo", set: 'Gym Challenge', rank: 20 }),
          canonical_name: "Rocket's Mewtwo",
        },
        {
          ...row({ id: '2', name: 'Mewtwo', set: 'Base Set', rank: 200 }),
          canonical_name: 'Mewtwo',
        },
      ],
    }),
  );

  assert.deepEqual(rows.map((result) => result.name), ["Rocket's Mewtwo"]);
});

test('search context validation accepts only query extensions in the same language', () => {
  const context = {
    query: 'mew',
    language: 'en',
    card_ids: ['1', '2'],
    created_at_ms: Date.now(),
    non_name_context: {
      depth_scores: {
        1: 3,
        2: 3,
        999: 99,
      },
    },
  };

  const cleaned = cleanSearchContext(context, 'mew 232', 'en');
  assert.equal(cleaned.valid, true);
  assert.deepEqual(cleaned.depthScores, { 1: 3, 2: 3 });
  assert.equal(cleanSearchContext(context, 'mew', 'en').reason, 'query_not_extended');
  assert.equal(cleanSearchContext(context, 'pikachu', 'en').reason, 'query_not_extended');
  assert.equal(cleanSearchContext(context, 'mew 232', 'fr').reason, 'language_changed');
});

test('previous depth context is ignored on shortening language mismatch and unrelated query', () => {
  const context = {
    query: 'pika',
    language: 'en',
    card_ids: ['1'],
    created_at_ms: Date.now(),
    non_name_context: { depth_scores: { 1: 10 } },
  };

  assert.deepEqual(updateDepthScores(context, 'pik', 'en', [row({ id: '1', name: 'Pikachu' })]), { 1: 3 });
  assert.deepEqual(updateDepthScores(context, 'pikac', 'fr', [row({ id: '1', name: 'Pikachu' })]), { 1: 5 });
  assert.deepEqual(updateDepthScores(context, 'charizard', 'en', [row({ id: '1', name: 'Pikachu' })]), { 1: 9 });
});

test('candidate context refine filters collector number over previous ids only', async () => {
  const debug = {};
  const rows = await searchStructuredAutocompleteWithContext(
    'mew 232',
    20,
    'en',
    {
      query: 'mew',
      language: 'en',
      card_ids: ['1', '2'],
      created_at_ms: Date.now(),
    },
    debug,
    fanoutMockQuery({
      candidates: [
        {
          ...row({ id: '1', name: 'Mew ex', number: 'Special Illustration Rare | 232/091', rank: 20 }),
          canonical_name: 'Mew',
          normalized_number: 'special illustration rare 232 091',
          compact_number: 'specialillustrationrare232091',
          variation_keys: ['ex'],
        },
        {
          ...row({ id: '2', name: 'Mew', number: '005/016', rank: 200 }),
          canonical_name: 'Mew',
          normalized_number: '005 016',
          compact_number: '005016',
          variation_keys: [],
        },
        {
          ...row({ id: '3', name: 'Mew ex', number: '232/091', rank: 1000 }),
          canonical_name: 'Mew',
          normalized_number: '232 091',
          compact_number: '232091',
          variation_keys: ['ex'],
        },
      ],
    }),
  );

  assert.deepEqual(rows.map((result) => result.card_id), ['1']);
  assert.equal(debug.tokenPlan.strategy, 'candidate_context_refine');
});

test('context refine keeps depth boosted ids inside the matched subset', async () => {
  const previousContext = {
    query: 'p',
    language: 'en',
    card_ids: ['1', '2', '3'],
    created_at_ms: Date.now(),
    non_name_context: {
      depth_scores: {
        1: 1,
        2: 1,
        3: 1,
      },
    },
  };
  const rows = await searchStructuredAutocompleteWithContext(
    'pika 025',
    20,
    'en',
    previousContext,
    {},
    fanoutMockQuery({
      candidates: [
        {
          ...row({ id: '1', name: 'Pikachu', number: '025/165', rank: 20 }),
          canonical_name: 'Pikachu',
          normalized_number: '025 165',
          compact_number: '025165',
        },
        {
          ...row({ id: '2', name: 'Pichu', number: '025/100', rank: 8000 }),
          canonical_name: 'Pichu',
          normalized_number: '025 100',
          compact_number: '025100',
        },
        {
          ...row({ id: '3', name: "Ash's Pikachu", number: '001/100', rank: 9000 }),
          canonical_name: "Ash's Pikachu",
          normalized_number: '001 100',
          compact_number: '001100',
        },
      ],
    }),
  );
  const context = buildSearchContext('pika 025', 'en', rows, 'candidate_context_refine', previousContext);

  assert.deepEqual(rows.map((result) => result.card_id), ['1']);
  assert.deepEqual(context.card_ids, ['1']);
  assert.equal(context.non_name_context.depth_scores['1'], 8);
  assert.equal(context.non_name_context.depth_scores['2'], undefined);
  assert.equal(context.non_name_context.depth_scores['3'], undefined);
});

test('candidate context refine applies variation over previous ids', async () => {
  const rows = await searchStructuredAutocompleteWithContext(
    'manaphy ex',
    20,
    'en',
    {
      query: 'manaphy',
      language: 'en',
      card_ids: ['110433', '113676'],
      created_at_ms: Date.now(),
    },
    {},
    fanoutMockQuery({
      candidates: [
        {
          ...row({ id: '110433', name: 'Manaphy ex' }),
          canonical_name: 'Manaphy',
          variation_keys: ['ex'],
        },
        {
          ...row({ id: '113676', name: 'Manaphy' }),
          canonical_name: 'Manaphy',
          variation_keys: [],
        },
      ],
    }),
  );

  assert.deepEqual(rows.map((result) => result.name), ['Manaphy ex']);
});

test('candidate context refine returns null for empty subset so callers can fan out', async () => {
  const debug = {};
  const rows = await searchStructuredAutocompleteWithContext(
    'mew 999',
    20,
    'en',
    {
      query: 'mew',
      language: 'en',
      card_ids: ['1'],
      created_at_ms: Date.now(),
    },
    debug,
    fanoutMockQuery({
      candidates: [
        {
          ...row({ id: '1', name: 'Mew ex', number: '232/091' }),
          canonical_name: 'Mew',
          normalized_number: '232 091',
          compact_number: '232091',
          variation_keys: ['ex'],
        },
      ],
    }),
  );

  assert.equal(rows, null);
  assert.equal(debug.contextRefine.fallbackReason, 'empty_context_refine');
});

test('search context validation accepts a bounded 10000 candidate ID pool', () => {
  const context = {
    query: 'mew',
    language: 'en',
    card_ids: Array.from({ length: 10000 }, (_, index) => `${index + 1}`),
    created_at_ms: Date.now(),
  };

  assert.equal(cleanSearchContext(context, 'mew 232', 'en').valid, true);
  assert.equal(
    cleanSearchContext(
      { ...context, card_ids: [...context.card_ids, '10001'] },
      'mew 232',
      'en',
    ).reason,
    'too_many_card_ids',
  );
});

test('short typo name tokens use supplemental fallback for structured searches', () => {
  assert.equal(
    shouldUseSupplementalNameFallback(
      { term: 'mee', kind: 'text' },
      [row({ id: '287350', name: 'Mew' })],
    ),
    true,
  );
  assert.equal(
    shouldUseSupplementalNameFallback(
      { term: 'mew', kind: 'text' },
      [row({ id: '287350', name: 'Mew' })],
    ),
    false,
  );
});

test('intersection token filtering rejects set-name flare noise', () => {
  assert.equal(
    rowMatchesIntersectionToken(
      row({ id: '1', name: 'Bouffalant ex', set: 'White Flare' }),
      { term: 'flareon', kind: 'text' },
    ),
    false,
  );
  assert.equal(
    rowMatchesIntersectionToken(
      row({ id: '2', name: 'Flareon ex', set: 'Prismatic Evolutions' }),
      { term: 'flareon', kind: 'text' },
    ),
    true,
  );
});

test('debug score explanation exposes score and matched terms', () => {
  const explanation = scoreExplanation(
    row({ id: '25', name: 'Pikachu ex', set: 'Journey Together', rarity: 'Double Rare' }),
    'pikachu ex',
  );

  assert.equal(explanation.card_id, '25');
  assert.equal(explanation.name, 'Pikachu ex');
  assert.ok(explanation.score > 0);
  assert.ok(explanation.matchedTerms.includes('pikachu'));
  assert.ok(explanation.matchedTerms.includes('ex'));
});

test('autocomplete can return a large ranked background pool', () => {
  const cards = Array.from({ length: 1200 }, (_, index) =>
    row({
      id: `${index}`,
      name: `Miraidon ${index}`,
      number: `${index + 1}/100`,
    }),
  );

  assert.equal(rankAutocompleteRows(cards, 'mir', 1000).length, 1000);
});

test('search context can expose more IDs than full preview rows', () => {
  const rows = Array.from({ length: 5000 }, (_, index) =>
    row({
      id: `${index + 1}`,
      name: `Pikachu ${index + 1}`,
      number: `${index + 1}/100`,
    }),
  );
  const context = buildSearchContext(
    'pi',
    'en',
    rows,
    'name_table_direct',
    null,
    5000,
  );
  const visible = rankAutocompleteRows(rows, 'pi', 20);

  assert.equal(context.card_ids.length, 5000);
  assert.equal(visible.length, 20);
  assert.equal(context.candidate_labels.length, 5000);
  assert.deepEqual(context.candidate_labels[0], {
    id: '1',
    name: 'Pikachu 1',
    item_kind: 'single',
    product_type: 'card',
    set_name: 'Test Set',
    card_number: '1/100',
    trainer_name: '',
  });
  assert.equal(context.candidate_id_ladder.requestedLimit, 5000);
  assert.equal(context.candidate_id_ladder.appliedLimit, 5000);
});

test('search context suppresses one-character Flutter candidate pool', () => {
  const rows = Array.from({ length: 1200 }, (_, index) =>
    row({
      id: `${index + 1}`,
      name: `Pikachu ${index + 1}`,
      number: `${index + 1}/100`,
    }),
  );
  const context = buildSearchContext(
    'p',
    'en',
    rows,
    'typed_one_character_sharded_prefix',
    null,
    0,
  );

  assert.equal(context.card_ids.length, 0);
  assert.equal(context.candidate_labels, undefined);
  assert.equal(context.candidate_id_ladder.requestedLimit, 0);
  assert.equal(context.candidate_id_ladder.appliedLimit, 500);
});

test('later depth context outranks broader earlier context', () => {
  const previousContext = buildSearchContext(
    'pi',
    'en',
    [
      row({ id: '1', name: 'Pikachu Broad', rank: 9000 }),
      row({ id: '2', name: 'Pikachu Exact', rank: 100 }),
    ],
    'name_table_direct',
    null,
    5000,
  );
  const rows = [
    row({ id: '1', name: 'Pikachu Broad', rank: 9000 }),
    row({ id: '2', name: 'Pikachu Exact', rank: 100 }),
  ];
  const depthScores = updateDepthScores(previousContext, 'pik', 'en', [
    rows[1],
  ]);
  const context = buildSearchContext('pik', 'en', [rows[1]], 'ranked_pool', previousContext, 2500);
  const ranked = rankAutocompleteEntries(rows, 'pikachu', 20, new Map(), {
    depthScores,
    depthMetadata: {
      latestDepths: context.non_name_context.latest_depths,
      latestOrders: context.non_name_context.latest_orders,
    },
  });

  assert.equal(ranked[0].row.card_id, '2');
  assert.equal(ranked[0].latestDepth, 3);
});

test('candidate labels are bounded lightweight id and name context', () => {
  const labels = candidateLabelsForRows(
    Array.from({ length: 150 }, (_, index) =>
      row({
        id: `${index + 1}`,
        name: `Pikachu ${index + 1}`,
      }),
    ),
  );

  assert.equal(labels.length, 100);
  assert.equal(labels[0].id, '1');
  assert.equal(labels[99].id, '100');
  assert.equal(labels[0].cdn_image_url, undefined);
});

test('split search merge keeps the strongest candidate per blueprint id', () => {
  const results = mergeSearchRows(
    [
      [
        row({ id: '1', name: 'Mew', rank: 100 }),
        row({ id: '2', name: 'Mew ex', rank: 80 }),
      ],
      [
        row({ id: '1', name: 'Mew', rank: 250 }),
        row({ id: '3', name: 'Mewtwo', rank: 120 }),
      ],
    ],
    10,
  );

  assert.deepEqual(
    results.map((result) => `${result.card_id}:${result.search_rank}`),
    ['1:250', '3:120', '2:80'],
  );
});

test('analytics boost reorders equally relevant hot cards', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'Pikachu', set: 'Base Set', rank: 100 }),
      row({ id: '2', name: 'Pikachu', set: 'Surging Sparks', rank: 100 }),
    ],
    'pikachu',
    20,
    new Map([
      ['2', 1200],
    ]),
  );

  assert.equal(results[0].set_name, 'Surging Sparks');
});

test('analytics boost can reorder similarly relevant name matches', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'Mew', rank: 100 }),
      row({ id: '2', name: 'Mewtwo', rank: 100 }),
    ],
    'mew',
    20,
    new Map([
      ['2', 2500],
    ]),
  );

  assert.equal(results[0].name, 'Mewtwo');
});

test('analytics boosts combine site and user signals inside matching candidates only', async () => {
  const boosts = await analyticsBoostsForRows(
    [
      row({ id: '1', name: 'Pikachu', rank: 100 }),
      row({ id: '2', name: 'Pidgey', rank: 100 }),
    ],
    async (sql, values) => {
      if (/from public\.marketplace_hot_blueprints h/.test(sql)) {
        assert.deepEqual(values, [[1, 2]]);
        return {
          rows: [
            { card_id: '1', analytics_boost: 200 },
            { card_id: '2', analytics_boost: 20 },
          ],
        };
      }
      if (/from public\.marketplace_card_events e/.test(sql)) {
        assert.deepEqual(values, [[1, 2], 'uid-1']);
        return {
          rows: [
            { card_id: '2', user_boost: 180 },
          ],
        };
      }
      return { rows: [] };
    },
    'uid-1',
  );

  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'Pikachu', rank: 100 }),
      row({ id: '2', name: 'Pidgey', rank: 100 }),
      row({ id: '3', name: "Ash's Pikachu", rank: 10000 }),
    ].filter((candidate) => candidate.name.toLowerCase().startsWith('pi')),
    'pi',
    20,
    boosts,
  );

  assert.equal(boosts.get('2'), 200);
  assert.deepEqual(results.map((result) => result.name), ['Pidgey', 'Pikachu']);
  assert.ok(!results.some((result) => result.name === "Ash's Pikachu"));
  assert.equal(boosts.sources.user, 'marketplace_card_events:user_uid');
});

test('typed one-character autocomplete skips analytics after prefix candidates', async () => {
  const autocomplete = require('./marketplace-autocomplete');
  const originalMaxDepth = process.env.MARKETPLACE_SHORT_PREFIX_ANALYTICS_MAX_DEPTH;
  try {
    delete process.env.MARKETPLACE_SHORT_PREFIX_ANALYTICS_MAX_DEPTH;
    assert.equal(autocomplete.shouldSkipAnalyticsForSearchTerm('p'), true);
    assert.equal(autocomplete.shouldSkipAnalyticsForSearchTerm('pi'), false);
    process.env.MARKETPLACE_SHORT_PREFIX_ANALYTICS_MAX_DEPTH = '2';
    assert.equal(autocomplete.shouldSkipAnalyticsForSearchTerm('pi'), true);
  } finally {
    if (originalMaxDepth === undefined) delete process.env.MARKETPLACE_SHORT_PREFIX_ANALYTICS_MAX_DEPTH;
    else process.env.MARKETPLACE_SHORT_PREFIX_ANALYTICS_MAX_DEPTH = originalMaxDepth;
  }
});

test('predictive ngram short-prefix failure skips primary fallback', async () => {
  const debug = {};
  const rows = await searchPredictiveNgramRowsWithDatabase(
    'pi',
    1000,
    'en',
    debug,
    async () => {
      throw new Error('peer3 unavailable');
    },
    async () => {
      throw new Error('primary should not be used');
    },
  );

  assert.equal(rows, null);
  assert.equal(debug.predictiveNgrams.reason, 'primary_fallback_skipped_short_prefix');
});

test('autocomplete default read query keeps short text prefixes on name replica', () => {
  const db = require('./_marketplace_db');
  assert.equal(readQueryForAutocomplete('pi'), db.marketplaceNameSearchQuery);
  assert.equal(readQueryForAutocomplete('pikachu'), db.marketplaceNameSearchQuery);
  assert.equal(readQueryForAutocomplete('pikachu ex'), db.marketplaceVariationSearchQuery);
});

test('optional personalization treats missing authorization as anonymous', async () => {
  assert.deepEqual(await require('./marketplace-autocomplete').optionalPersonalizationUser({}), {
    uid: null,
    error: null,
  });
  assert.deepEqual(await require('./marketplace-autocomplete').optionalPersonalizationUser({
    headers: {},
  }), {
    uid: null,
    error: null,
  });
});

test('google-style typed prefixes filter a 100-card pool before popularity ranking', () => {
  const pool = Array.from({ length: 100 }, (_, index) => {
    if (index < 40) return row({ id: `${index + 1}`, name: `Pikachu ${index + 1}`, rank: 100 + index });
    if (index < 70) return row({ id: `${index + 1}`, name: `Pidgey ${index + 1}`, rank: 5000 - index });
    if (index < 90) return row({ id: `${index + 1}`, name: `Charizard ${index + 1}`, rank: 9000 });
    return row({ id: `${index + 1}`, name: `Mew ${index + 1}`, rank: 12000 });
  });
  const boosts = new Map([
    ['95', 5000],
    ['75', 4000],
    ['5', 900],
    ['45', 800],
  ]);

  for (const query of ['p', 'pi', 'pik', 'pika']) {
    const candidates = pool.filter((candidate) =>
      candidate.name.toLowerCase().startsWith(query));
    const results = rankAutocompleteRows(candidates, query, 20, boosts);

    assert.equal(results.length, 20);
    assert.ok(results.every((result) => result.name.toLowerCase().startsWith(query)));
    assert.ok(!results.some((result) => result.name.startsWith('Charizard')));
    assert.ok(!results.some((result) => result.name.startsWith('Mew')));
  }
});

test('structured exact name plus collector number beats generic popular cards', () => {
  const pool = [
    row({ id: '1', name: 'Mew ex', set: 'Paldean Fates', number: '232/091', rarity: 'Special Illustration Rare', rank: 400 }),
    row({ id: '2', name: 'Mewtwo ex', set: 'Promo', number: '150/165', rank: 12000 }),
    row({ id: '3', name: 'Mew', set: 'Pokemon Card 151', number: '151/165', rank: 9000 }),
    row({ id: '4', name: 'Pikachu', set: 'Hot Set', number: '232/999', rank: 20000 }),
  ];
  const boosts = new Map([
    ['2', 5000],
    ['4', 8000],
  ]);

  const exact = rankAutocompleteRows(pool, 'mew 232', 20, boosts);
  const typo = rankAutocompleteRows(pool, 'mee 232', 20, boosts);

  assert.equal(exact[0].name, 'Mew ex');
  assert.equal(exact[0].card_number, '232/091');
  assert.equal(typo[0].name, 'Mew ex');
  assert.equal(typo[0].card_number, '232/091');
});

test('HGSS era alias ranks matching Rare Candy set above generic name matches', () => {
  const pool = [
    row({ id: '1', name: 'Rare Candy', set: 'Scarlet & Violet JP: Premium Trainer Box ex', number: '003/028', rank: 20000 }),
    row({ id: '2', name: 'Rare Candy', set: 'Metagross Expert Deck', number: '009/014', rank: 20000 }),
    row({ id: '3', name: 'Rare Candy', set: 'Unleashed', number: '82/95', rank: 100 }),
  ];

  const results = rankAutocompleteRows(pool, 'rare candy hgss', 20);

  assert.equal(results[0].card_id, '3');
  assert.equal(results[0].set_name, 'Unleashed');
});

test('HGSS era alias filters completed trailing tokens to matching Rare Candy rows', () => {
  const pool = [
    row({ id: '1', name: 'Rare Candy', set: 'Scarlet & Violet JP: Premium Trainer Box ex', number: '003/028', rank: 20000 }),
    row({ id: '2', name: 'Rare Candy', set: 'Metagross Expert Deck', number: '009/014', rank: 20000 }),
    row({ id: '3', name: 'Rare Candy', set: 'Unleashed', number: '82/95', rank: 100 }),
    row({ id: '4', name: 'Hearthflame Mask Ogerpon ex', set: 'Twilight Masquerade', number: '212/167', rank: 50000 }),
  ];

  for (const query of ['rare candy hgss', 'rare candy heartgold', 'rare candy heart gold', 'rare candy hearth gold']) {
    const filtered = filterRowsByRequiredNameTokens(pool, query);
    assert.equal(filtered.applied, true, query);
    assert.deepEqual(filtered.rows.map((result) => result.card_id), ['3'], query);
    const results = rankAutocompleteRows(filtered.rows, query, 20);
    assert.equal(results[0].name, 'Rare Candy', query);
    assert.equal(results[0].set_name, 'Unleashed', query);
    assert.equal(results[0].card_number, '82/95', query);
  }
});

test('HGSS heart gold aliases rank matching Rare Candy set above generic rows', () => {
  const pool = [
    row({ id: '1', name: 'Rare Candy', set: 'Scarlet & Violet JP: Premium Trainer Box ex', number: '003/028', rank: 20000 }),
    row({ id: '2', name: 'Rare Candy', set: 'Metagross Expert Deck', number: '009/014', rank: 20000 }),
    row({ id: '3', name: 'Rare Candy', set: 'Unleashed', number: '82/95', rank: 100 }),
    row({ id: '4', name: 'Hearthflame Mask Ogerpon ex', set: 'Twilight Masquerade', number: '212/167', rank: 50000 }),
  ];

  for (const query of ['rare candy heartgold', 'rare candy heart gold', 'rare candy hearth gold']) {
    const results = rankAutocompleteRows(pool, query, 20);
    assert.equal(results[0].card_id, '3', query);
    assert.equal(results[0].set_name, 'Unleashed', query);
  }
});

test('generic energy HGSS query ranks elemental energy over trainer energy names', () => {
  const pool = [
    row({ id: '1', name: 'Energy Switch', set: 'HeartGold & SoulSilver', number: '091/123', rank: 9000 }),
    row({ id: '2', name: 'Fire Energy', set: 'HeartGold & SoulSilver', number: '116/123', rank: 100 }),
    row({ id: '3', name: 'Energy Returner', set: 'Unleashed', number: '74/95', rank: 9000 }),
  ];

  const results = rankAutocompleteRows(pool, 'energy HeartGold & SoulSilver', 20);

  assert.equal(results[0].name, 'Fire Energy');
});

test('generic energy HGSS pool keeps broad elemental energy context before preview cap', () => {
  const pool = [
    row({ id: 'trainer-1', name: 'Energy Returner', set: 'Unleashed', number: '74/95', rank: 9000 }),
    row({ id: 'trainer-2', name: 'Energy Exchanger', set: 'Undaunted', number: '73/90', rank: 9000 }),
    row({ id: '1', name: 'Darkness Energy', set: 'HeartGold & SoulSilver', number: '121/123', rank: 100 }),
    row({ id: '2', name: 'Fighting Energy', set: 'HeartGold & SoulSilver', number: '120/123', rank: 100 }),
    row({ id: '3', name: 'Fire Energy', set: 'HeartGold & SoulSilver', number: '116/123', rank: 100 }),
    row({ id: '4', name: 'Grass Energy', set: 'HeartGold & SoulSilver', number: '115/123', rank: 100 }),
    row({ id: '5', name: 'Lightning Energy', set: 'HeartGold & SoulSilver', number: '118/123', rank: 100 }),
    row({ id: '6', name: 'Metal Energy', set: 'HeartGold & SoulSilver', number: '122/123', rank: 100 }),
    row({ id: '7', name: 'Psychic Energy', set: 'HeartGold & SoulSilver', number: '119/123', rank: 100 }),
    row({ id: '8', name: 'Water Energy', set: 'HeartGold & SoulSilver', number: '117/123', rank: 100 }),
    row({ id: '9', name: 'Darkness Energy', set: 'Call of Legends', number: '86/95', rank: 100 }),
    row({ id: '10', name: 'Fire Energy', set: 'Call of Legends', number: '89/95', rank: 100 }),
  ];

  const context = buildSearchContext(
    'energy HeartGold & SoulSilver',
    'en',
    pool,
    'generic_energy_expansion',
    null,
    500,
  );
  const visible = rankAutocompleteRows(pool, 'energy HeartGold & SoulSilver', 20);

  assert.ok(context.card_ids.length > 2);
  assert.equal(context.card_ids.length, pool.length);
  assert.ok(context.candidate_labels.length > 2);
  assert.equal(visible.length, pool.length);
  assert.deepEqual(
    visible.slice(0, 8).map((result) => result.name),
    [
      'Darkness Energy',
      'Fighting Energy',
      'Fire Energy',
      'Grass Energy',
      'Lightning Energy',
      'Metal Energy',
      'Psychic Energy',
      'Water Energy',
    ],
  );
  assert.ok(visible.findIndex((result) => result.name === 'Energy Returner') > 7);
  assert.ok(visible.findIndex((result) => result.name === 'Energy Exchanger') > 7);
});

test('explicit energy returner HGSS query can rank the trainer card', () => {
  const pool = [
    row({ id: '1', name: 'Fire Energy', set: 'HeartGold & SoulSilver', number: '116/123', rank: 9000 }),
    row({ id: '2', name: 'Energy Returner', set: 'Unleashed', number: '74/95', rank: 100 }),
    row({ id: '3', name: 'Energy Exchanger', set: 'Undaunted', number: '73/90', rank: 9000 }),
  ];

  const results = rankAutocompleteRows(pool, 'energy returner hgss', 20);

  assert.equal(results[0].name, 'Energy Returner');
});

test('explicit energy exchanger HGSS query can rank the trainer card', () => {
  const pool = [
    row({ id: '1', name: 'Fire Energy', set: 'HeartGold & SoulSilver', number: '116/123', rank: 9000 }),
    row({ id: '2', name: 'Energy Returner', set: 'Unleashed', number: '74/95', rank: 9000 }),
    row({ id: '3', name: 'Energy Exchanger', set: 'Undaunted', number: '73/90', rank: 100 }),
  ];

  const results = rankAutocompleteRows(pool, 'energy exchanger hgss', 20);

  assert.equal(results[0].name, 'Energy Exchanger');
});

test('direct unleashed alias filters Umbreon set candidates out of ngram pools', () => {
  const pool = [
    row({ id: '1', name: 'Umbreon VMAX', set: 'Evolving Skies', rank: 30000 }),
    row({ id: '2', name: 'Umbreon', set: 'Unleashed', number: '10/90', rank: 100 }),
  ];
  const filtered = filterRowsByRequiredNameTokens(pool, 'umbreon unleashed');

  assert.equal(filtered.applied, true);
  assert.deepEqual(filtered.rows.map((result) => result.card_id), ['2']);
  assert.equal(rankAutocompleteRows(filtered.rows, 'umbreon unleashed', 20)[0].set_name, 'Unleashed');
});

test('standalone name intent ranks Umbreon above untyped tag-team partners', () => {
  const pool = [
    row({ id: '1', name: 'Umbreon & Darkrai GX', set: 'Unified Minds', rank: 27092 }),
    row({ id: '2', name: 'Umbreon', set: 'Unleashed', number: '10/90', rank: 6000 }),
    row({ id: '3', name: 'Umbreon VMAX', set: 'Evolving Skies', rank: 12722 }),
  ];

  assert.equal(rankAutocompleteRows(pool, 'umbreon', 20)[0].name, 'Umbreon');

  const unleashed = rankAutocompleteRows(pool, 'umbreon unleashed', 20);
  assert.equal(unleashed[0].name, 'Umbreon');
  assert.equal(unleashed[0].set_name, 'Unleashed');
  assert.notEqual(unleashed[0].name, 'Umbreon & Darkrai GX');
});

test('typed second root preserves tag-team ranking intent', () => {
  const pool = [
    row({ id: '1', name: 'Umbreon', set: 'Unleashed', number: '10/90', rank: 6000 }),
    row({ id: '2', name: 'Umbreon & Darkrai GX', set: 'Unified Minds', rank: 27092 }),
    row({ id: '3', name: 'Darkrai & Cresselia LEGEND', set: 'Triumphant', rank: 20000 }),
    row({ id: '5', name: 'Pikachu', set: 'Base Set', rank: 6000 }),
  ];

  assert.equal(rankAutocompleteRows(pool, 'umbreon darkrai', 20)[0].name, 'Umbreon & Darkrai GX');
  assert.equal(rankAutocompleteRows(pool, 'umbreon & darkrai', 20)[0].name, 'Umbreon & Darkrai GX');
  assert.equal(rankAutocompleteRows(pool, 'darkrai cresselia', 20)[0].name, 'Darkrai & Cresselia LEGEND');
  assert.equal(rankAutocompleteRows([
    row({ id: '4', name: 'Pikachu & Zekrom GX', set: 'Team Up', rank: 6000 }),
    row({ id: '5', name: 'Pikachu', set: 'Base Set', rank: 6000 }),
  ], 'pikachu zekrom', 20)[0].name, 'Pikachu & Zekrom GX');
});

test("non-matching typed prefixes do not show Ash's Pikachu as hot fallback", () => {
  const pool = [
    row({ id: '1', name: "Ash's Pikachu", rank: 20000 }),
    row({ id: '2', name: 'Charizard ex', rank: 100 }),
    row({ id: '3', name: 'Charmander', rank: 90 }),
    row({ id: '4', name: 'Charcadet', rank: 80 }),
  ];
  const candidates = pool.filter((candidate) =>
    candidate.name.toLowerCase().startsWith('char'));
  const results = rankAutocompleteRows(candidates, 'char', 20, new Map([['1', 9999]]));

  assert.deepEqual(new Set(results.map((result) => result.name)), new Set([
    'Charizard ex',
    'Charmander',
    'Charcadet',
  ]));
  assert.ok(!results.some((result) => result.name === "Ash's Pikachu"));
});

test('common misspells rank intended candidates from a fixture pool', () => {
  const pool = [
    row({ id: '1', name: 'Pikachu', set: 'Surging Sparks', number: '057/191' }),
    row({ id: '2', name: 'Charizard ex', set: 'Obsidian Flames', number: '223/197' }),
    row({ id: '3', name: 'Charmander', set: '151', number: '004/165' }),
    row({ id: '4', name: 'Energy Switch', set: 'Charizard Deck' }),
    row({ id: '5', name: 'Surging Sparks Booster Box', set: 'Surging Sparks', kind: 'product' }),
  ];

  assert.equal(rankAutocompleteRows(pool, 'pikchu', 20)[0].name, 'Pikachu');
  assert.equal(rankAutocompleteRows(pool, 'charzard', 20)[0].name, 'Charizard ex');
  assert.equal(rankAutocompleteRows(pool, 'pikachu surgin', 20)[0].name, 'Pikachu');
});

test('exact static catalog query keeps Porygon variants and rejects prefix noise', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'Porygon', set: '151', number: '137/165' }),
      row({ id: '2', name: 'Porygon2', set: 'Stellar Crown' }),
      row({ id: '3', name: 'Porygon-Z', set: 'Unbroken Bonds' }),
      row({ id: '4', name: 'Vaporeon', set: 'Display Set Gift Box' }),
      row({ id: '5', name: 'Pokemon Communication' }),
    ],
    'porygon',
    20,
  );

  assert.deepEqual(
    results.map((result) => result.name),
    ['Porygon', 'Porygon-Z', 'Porygon2'],
  );
});

test('common misspells still resolve to the intended blueprint names', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'Pikachu ex' }),
      row({ id: '2', name: 'Pidgeot ex' }),
      row({ id: '3', name: 'Gardevoir ex' }),
      row({ id: '4', name: 'Energy Switch', set: 'Gardevoir Deck' }),
    ],
    'gardevior',
    20,
  );

  assert.equal(results[0].name, 'Gardevoir ex');
});

test('collector abbreviations rank shorthand names before unrelated matches', () => {
  const cards = [
    row({ id: '1', name: 'Charizard ex', set: '151' }),
    row({ id: '2', name: 'Charmander', set: '151' }),
    row({ id: '3', name: 'Venusaur ex', set: '151' }),
    row({ id: '4', name: 'Blastoise ex', set: '151' }),
  ];

  assert.equal(rankAutocompleteRows(cards, 'char ex', 20)[0].name, 'Charizard ex');
  assert.equal(rankAutocompleteRows(cards, 'venu ex', 20)[0].name, 'Venusaur ex');
  assert.equal(rankAutocompleteRows(cards, 'blast ex', 20)[0].name, 'Blastoise ex');
});

test('products are shown after matching single-card blueprints', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'Eevee', kind: 'single' }),
      row({ id: '2', name: 'Eevee Display Set Gift Box', kind: 'product' }),
    ],
    'eevee',
    20,
  );

  assert.deepEqual(
    results.map((result) => result.item_kind),
    ['single', 'product'],
  );
});

test('single-token card name intent outranks loaded product and set noise', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'Paldea Partners Tins | Skeledirge ex Tin', set: 'Scarlet & Violet Products', kind: 'product' }),
      row({ id: '2', name: 'Lapras', set: 'Raging Surf', number: '002/062', type: 'Water' }),
      row({ id: '3', name: 'EX Crystal Guardians | Tauros Blister', set: 'EX Crystal Guardians', kind: 'product' }),
      row({ id: '4', name: 'Lapras ex', set: 'Stellar Miracle', number: '117/102', type: 'Water' }),
    ],
    'lapras',
    20,
  );

  assert.deepEqual(
    results.slice(0, 2).map((result) => result.item_kind),
    ['single', 'single'],
  );
  assert.equal(results[0].name, 'Lapras');
});

test('trainer card names rank as first-class single-card names', () => {
  const results = rankAutocompleteRows(
    [
      row({
        id: '1',
        name: 'Misty',
        set: 'Gym Heroes',
        number: '102/132',
        type: 'Trainer',
      }),
      row({
        id: '2',
        name: 'Staryu',
        set: "Misty's Trainer Deck",
        number: '001/018',
      }),
      row({
        id: '3',
        name: "Misty's Determination",
        set: 'Evolutions',
        number: '80/108',
        type: 'Supporter',
      }),
      row({
        id: '4',
        name: 'Misty Gift Box',
        kind: 'product',
        type: 'Product',
      }),
    ],
    'misty',
    20,
  );

  assert.equal(results[0].name, 'Misty');
  assert.equal(results[0].item_kind, 'single');
});

test('multi-token number searches rank matching name and set-number rows first', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'Pikachu', set: '151', number: '025/165' }),
      row({ id: '2', name: 'Pikachu ex', set: 'Journey Together', number: '179/159' }),
      row({ id: '3', name: 'Charmander', set: '151', number: '004/165' }),
    ],
    'pikachu 151',
    20,
  );

  assert.equal(results[0].name, 'Pikachu');
  assert.equal(results[0].set_name, '151');
});

test('multi-token rarity searches keep the named card above rarity-only rows', () => {
  const results = rankAutocompleteRows(
    [
      row({
        id: '1',
        name: 'Mew ex',
        set: 'Paldean Fates',
        number: '232/091',
        rarity: 'Special Illustration Rare',
      }),
      row({
        id: '2',
        name: 'Mewtwo ex',
        set: 'Paradox Rift',
        number: '058/182',
        rarity: 'Double Rare',
      }),
      row({
        id: '3',
        name: 'Energy Switch',
        set: 'Deck',
        rarity: 'Special Illustration Rare',
      }),
    ],
    'mew special illustration rare',
    20,
  );

  assert.equal(results[0].name, 'Mew ex');
});

test('ill keyword behaves as illustration rare intent', () => {
  const results = rankAutocompleteRows(
    [
      row({
        id: '1',
        name: 'Mesprit',
        set: 'Surging Sparks',
        number: 'Illustration Rare | 204/191',
        rarity: 'Illustration Rare',
      }),
      row({
        id: '2',
        name: 'Mesprit',
        set: 'Triumphant',
        number: '003/102',
        rarity: 'Rare',
      }),
      row({
        id: '3',
        name: 'Energy Switch',
        set: 'Deck',
        rarity: 'Illustration Rare',
      }),
    ],
    'mescript ill',
    20,
  );

  assert.equal(results[0].name, 'Mesprit');
  assert.equal(results[0].rarity, 'Illustration Rare');
});

test('remote tokenized rank keeps typo plus expansion candidates visible', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'Pikachu', set: '151', number: '025/165', rank: 9000 }),
      row({ id: '2', name: 'Charmander', set: '151', number: '004/165', rank: 2400 }),
    ],
    'piachu 151',
    20,
  );

  assert.equal(results[0].name, 'Pikachu');
  assert.equal(results[0].set_name, '151');
});

test('short name typo plus collector number beats expansion-code noise', () => {
  const results = rankAutocompleteRows(
    [
      row({
        id: '1',
        name: 'Mew ex',
        set: 'Paldean Fates',
        number: 'Special Illustration Rare | 232/091',
      }),
      row({
        id: '2',
        name: 'Basic Darkness Energy',
        set: 'Mega Evolution Energies',
        number: 'MEE 007',
        type: 'Energy',
        rank: 2640,
      }),
      row({
        id: '3',
        name: 'Basic Fire Energy',
        set: 'Mega Evolution Energies',
        number: 'MEE 002',
        type: 'Energy',
        rank: 2640,
      }),
    ],
    'mee 232',
    20,
  );

  assert.equal(results[0].name, 'Mew ex');
});

test('short name typo plus variation keeps intended pokemon visible', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'Mew ex', set: 'Paldean Fates', number: '232/091' }),
      row({ id: '2', name: 'Meowth', set: 'EX Team Rocket Returns' }),
    ],
    'mee ex',
    20,
  );

  assert.equal(results[0].name, 'Mew ex');
});

test('expansion typo prefers set intent over surfing variant noise', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'Pikachu', set: 'Surging Sparks', number: '057/191', rank: 7800 }),
      row({ id: '2', name: 'Pikachu ex', set: 'Surging Sparks', number: '247/191', rank: 7600 }),
      row({ id: '3', name: 'Surfing Pikachu', set: 'Celebrations', number: '008/025', rank: 2100 }),
    ],
    'pikachu surgin',
    20,
  );

  assert.deepEqual(
    results.slice(0, 2).map((result) => result.set_name),
    ['Surging Sparks', 'Surging Sparks'],
  );
});

test('trainer owned pokemon search keeps owner and pokemon intent together', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: "Lt. Surge's Pikachu", trainer: 'Lt. Surge', rank: 7200 }),
      row({ id: '2', name: 'Pikachu', set: 'Base Set', rank: 3200 }),
      row({ id: '3', name: "Lt. Surge's Strategy", type: 'Trainer', rank: 2400 }),
    ],
    'lt surge pikachu',
    20,
  );

  assert.equal(results[0].name, "Lt. Surge's Pikachu");
});

test('short name typo plus variation rejects compact cross-word noise', () => {
  const results = rankAutocompleteRows(
    [
      row({
        id: '1',
        name: 'Mew',
        set: 'Expedition Base Set',
        number: '055/165',
        rank: 5548,
      }),
      row({
        id: '2',
        name: "Erika's Vileplume ex",
        set: 'Ascended Heroes',
        number: 'Ultra Rare | 003/217',
        rank: 2944,
      }),
    ],
    'mee ex',
    20,
  );

  assert.equal(results[0].name, 'Mew');
});

test('name and suffix token matches beat set-only product noise', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'Charizard ex', set: '151' }),
      row({ id: '2', name: 'Charcadet', set: 'ex Premium Collection' }),
      row({ id: '3', name: 'Charizard', set: 'EX Dragon' }),
    ],
    'char ex',
    20,
  );

  assert.equal(results[0].name, 'Charizard ex');
});

test('single v keyword filters immediately to pokemon V cards', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'Venusaur', set: 'Base Set', type: 'Grass' }),
      row({ id: '2', name: 'Vaporeon', set: 'Jungle', type: 'Water' }),
      row({ id: '3', name: 'Charizard V', set: 'Brilliant Stars', type: 'Fire' }),
      row({ id: '4', name: 'Pikachu VMAX', set: 'Vivid Voltage', type: 'Lightning' }),
    ],
    'v',
    20,
  );

  assert.deepEqual(
    results.map((result) => result.name),
    ['Charizard V'],
  );
});

test('standalone n is preserved as one-character name intent', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'N', set: 'Promo', type: 'Trainer' }),
      row({ id: '2', name: 'Ninetales', set: '151', type: 'Fire' }),
      row({ id: '3', name: 'Nest Ball', set: 'Scarlet & Violet', type: 'Trainer' }),
      row({ id: '4', name: 'Charizard ex', set: '151', type: 'Fire' }),
    ],
    'n',
    10,
  );

  assert.equal(results[0].name, 'N');
  assert(results.some((result) => result.name === 'Ninetales'));
  assert(results.some((result) => result.name === 'Nest Ball'));
  assert(!results.some((result) => result.name === 'Charizard ex'));
});

test('single variation keywords filter immediately to matching card variants', () => {
  const rows = [
    row({ id: '1', name: 'Charizard ex', set: '151', type: 'Fire' }),
    row({ id: '2', name: 'Pikachu VMAX', set: 'Vivid Voltage', type: 'Lightning' }),
    row({ id: '3', name: 'Mewtwo GX', set: 'Hidden Fates', type: 'Psychic' }),
    row({ id: '4', name: 'Shining Magikarp', set: 'Celebrations', type: 'Water' }),
    row({ id: '7', name: 'Arceus VSTAR', set: 'Brilliant Stars', type: 'Colorless' }),
    row({ id: '5', name: 'Exeggutor', set: 'Base Set', type: 'Grass' }),
    row({ id: '6', name: 'Voltorb', set: 'VMAX Climax', type: 'Lightning' }),
    row({ id: '8', name: 'Mew', set: 'VSTAR Universe', type: 'Psychic' }),
  ];

  assert.deepEqual(
    rankAutocompleteRows(rows, 'ex', 20).map((result) => result.name),
    ['Charizard ex'],
  );
  assert.deepEqual(
    rankAutocompleteRows(rows, 'vmax', 20).map((result) => result.name),
    ['Pikachu VMAX'],
  );
  assert.deepEqual(
    rankAutocompleteRows(rows, 'gx', 20).map((result) => result.name),
    ['Mewtwo GX'],
  );
  assert.deepEqual(
    rankAutocompleteRows(rows, 'shining', 20).map((result) => result.name),
    ['Shining Magikarp'],
  );
  assert.deepEqual(
    rankAutocompleteRows(rows, 'vstar', 20).map((result) => result.name),
    ['Arceus VSTAR', 'Mew'],
  );
});

test('mega keyword recognizes legacy M-prefixed mega card names', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'M Charizard EX', set: 'Generations', type: 'Fire' }),
      row({ id: '2', name: 'Charizard EX', set: 'Mega Evolution', type: 'Fire' }),
      row({ id: '3', name: 'Charmander', set: 'Mega Evolution', type: 'Fire' }),
    ],
    'mega charizard',
    20,
  );

  assert.equal(results[0].name, 'M Charizard EX');
});

test('mega keyword does not consume the pokemon name token', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'M Venusaur EX', set: 'XY Promos', type: 'Grass' }),
      row({ id: '2', name: 'Venusaur ex', set: 'Scarlet & Violet 151', type: 'Grass' }),
      row({ id: '3', name: 'Meganium', set: 'Neo Genesis', type: 'Grass' }),
    ],
    'mega venusaur',
    20,
  );

  assert.deepEqual(
    results.map((result) => result.name).slice(0, 2),
    ['M Venusaur EX', 'Venusaur ex'],
  );
});

test('confident pokemon name token keeps suffix tokens out of name fuzzy matching', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'Vaporeon ex', set: 'Prismatic Evolutions' }),
      row({ id: '2', name: 'Espeon ex', set: 'Prismatic Evolutions' }),
      row({ id: '3', name: 'Vaporeon', set: 'EX Sandstorm' }),
      row({ id: '4', name: 'Exploud', set: 'Ruby & Sapphire' }),
    ],
    'vaporeon ex',
    20,
  );

  assert.equal(results[0].name, 'Vaporeon ex');
});

test('ampersand query is treated as tag team variation intent', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'Mewtwo & Mew-GX', set: 'Unified Minds', type: 'Psychic' }),
      row({ id: '2', name: 'Mewtwo GX', set: 'Shining Legends', type: 'Psychic' }),
      row({ id: '3', name: 'Mew ex', set: 'Paldean Fates', type: 'Psychic' }),
    ],
    'mewtwo & mew',
    20,
  );

  assert.equal(results[0].name, 'Mewtwo & Mew-GX');
});

test('pokemon name prefixes beat expansion and set-name pool noise', () => {
  const results = rankAutocompleteRows(
    [
      row({ id: '1', name: 'Miraidon', set: 'Scarlet & Violet Promos' }),
      row({ id: '2', name: 'Miracle Berry', set: 'Neo Genesis', type: 'Item' }),
      row({ id: '3', name: 'Jirachi EX', set: 'Miracle Crystal' }),
      row({ id: '4', name: 'Girafarig', set: 'Mirage Forest' }),
    ],
    'mir',
    20,
  );

  assert.equal(results[0].name, 'Miraidon');
});
