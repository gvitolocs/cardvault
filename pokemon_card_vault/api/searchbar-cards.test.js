const assert = require('node:assert/strict');
const test = require('node:test');

const searchbar = require('./searchbar-cards');
const autocomplete = require('./marketplace-autocomplete');
const cancelEndpoint = require('./searchbar-cancel');
const {
  clearSearchSessionForTest,
  isSearchSessionCancelled,
} = require('./_searchbar_session');

function responseRecorder() {
  return {
    statusCode: 200,
    headers: {},
    body: undefined,
    setHeader(name, value) {
      this.headers[String(name).toLowerCase()] = value;
      return this;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(value) {
      this.body = value;
      return this;
    },
    end(value) {
      this.body = value;
      return this;
    },
  };
}

function row(id, name) {
  return {
    card_id: String(id),
    name,
    set_name: 'Test Set',
    card_number: `${id}/100`,
    item_kind: 'single',
    product_type: 'card',
    trainer_name: '',
  };
}

test('searchbar request input accepts stable POST and GET contract fields', () => {
  const previous = { query: 'pi', language: 'en', card_ids: ['1'], created_at_ms: Date.now() };
  const predictionContext = { normalized_fragment: 'pi', language: 'en', candidates: [] };

  assert.deepEqual(searchbar.requestInput({
    method: 'POST',
    body: {
      query: ' pikachu ',
      search_language: 'EN',
      limit: 8,
      pool_limit: 2500,
      previous_search_context: previous,
      prediction_context: predictionContext,
      debug: '1',
      mode: 'benchmark_step',
    },
  }), {
    method: 'POST',
    query: 'pikachu',
    searchLanguage: 'en',
    limit: 8,
    poolLimit: 2500,
    mode: 'benchmark_step',
    previousSearchContext: previous,
    predictionContext,
    debug: true,
    debugSessionId: '',
    searchSessionId: '',
  });

  assert.equal(searchbar.requestInput({
    method: 'GET',
    query: {
      query: 'charizard',
      previous_search_context: JSON.stringify(previous),
    },
  }).previousSearchContext.query, 'pi');
});

test('searchbar POST wrapper responses are not shared-cacheable by URL only', () => {
  assert.equal(searchbar.cacheControlForInput({ method: 'POST', query: 'rare candy heartgold' }), 'no-store');
  assert.equal(
    searchbar.cacheControlForInput({ method: 'GET', query: 'rare candy heartgold' }),
    'public, max-age=5, s-maxage=30',
  );
  assert.equal(
    searchbar.cacheControlForInput({ method: 'GET', query: '' }),
    'public, max-age=10, s-maxage=60, stale-while-revalidate=120',
  );
});

test('searchbar cancel endpoint is anonymous-safe and marks session canceled', async () => {
  const sessionId = 'flutter-test-session-123';
  clearSearchSessionForTest(sessionId);
  const res = responseRecorder();

  await cancelEndpoint({
    method: 'POST',
    body: {
      search_session_id: sessionId,
      last_query: 'pikachu',
      reason: 'blur',
    },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.ok, true);
  assert.equal(res.body.canceled, true);
  assert.equal(res.body.session_id, sessionId);
  assert.equal(isSearchSessionCancelled(sessionId), true);
  clearSearchSessionForTest(sessionId);
});

test('canceled searchbar session short-circuits before autocomplete work', async () => {
  const sessionId = 'flutter-test-session-456';
  clearSearchSessionForTest(sessionId);
  await cancelEndpoint({
    method: 'POST',
    body: { search_session_id: sessionId, last_query: 'mew', reason: 'clear' },
  }, responseRecorder());
  const res = responseRecorder();
  let autocompleteCalled = false;

  await searchbar({
    method: 'POST',
    body: {
      query: 'mew',
      search_session_id: sessionId,
    },
    _searchbarAutocompleteResponse: async () => {
      autocompleteCalled = true;
      return { statusCode: 200, headers: {}, body: { rows: [] } };
    },
  }, res);

  assert.equal(autocompleteCalled, false);
  assert.equal(res.statusCode, 200);
  assert.equal(res.body.canceled, true);
  assert.deepEqual(res.body.rows, []);
  assert.equal(res.body.meta.search_path, 'session_canceled');
  clearSearchSessionForTest(sessionId);
});

test('searchbar response wrapper exposes rows, context, counts, path, and timings', () => {
  const context = autocomplete.buildSearchContext(
    'pikachu',
    'en',
    [row(1, 'Pikachu'), row(2, 'Pikachu ex'), row(3, 'Pikachu V')],
    'name_table_direct',
    null,
    500,
  );

  const body = searchbar.wrapAutocompleteBody({
    rows: [row(1, 'Pikachu'), row(2, 'Pikachu ex')],
    pool: {
      source: 'search_pipeline',
      size: 3,
      limit: 500,
      candidateIdLimit: 500,
      appliedCandidateIdLimit: 500,
      strategy: 'name_table_direct',
    },
    search_context: context,
    debug: {
      searchPath: 'name_table_direct',
      durationMs: 42,
      candidateDurationMs: 30,
      analyticsDurationMs: 5,
      rankDurationMs: 7,
    },
  }, {
    query: 'pikachu',
    searchLanguage: 'en',
    limit: 2,
    poolLimit: 500,
    mode: 'benchmark_step',
    debug: true,
  }, {
    headers: { 'server-timing': 'autocomplete;dur=42' },
  });

  assert.equal(body.ok, true);
  assert.equal(body.endpoint, '/api/searchbar-cards');
  assert.equal(body.rows.length, 2);
  assert.equal(body.search_context.card_ids.length, 3);
  assert.equal(body.search_context.candidate_labels.length, 3);
  assert.equal(body.meta.candidate_counts.visible_rows, 2);
  assert.equal(body.meta.candidate_counts.pool_size, 3);
  assert.equal(body.meta.candidate_counts.context_card_ids, 3);
  assert.equal(body.meta.search_path, 'name_table_direct');
  assert.equal(body.meta.timings.duration_ms, 42);
  assert.equal(body.debug.searchPath, 'name_table_direct');
});

test('searchbar response wrapper exposes predictive debug metadata', () => {
  const body = searchbar.wrapAutocompleteBody({
    rows: [row(150, 'Mewtwo')],
    pool: {
      source: 'search_pipeline',
      size: 1,
      strategy: 'predictive_dimension_pool',
    },
    search_context: autocomplete.buildSearchContext(
      'mewt',
      'en',
      [row(150, 'Mewtwo')],
      'predictive_dimension_pool',
      null,
      5000,
    ),
    debug: {
      searchPath: 'predictive_dimension_pool',
      candidateDebug: {
        predictivePool: {
          model: 'dynamic_supabase_predicted_tokens',
          predictedTokens: [
            {
              normalized: 'mewtwo',
              display: 'Mewtwo',
              confidence: 94,
              source_rank: 1,
              language: 'en',
            },
          ],
          sources: [
            { source: 'supabase_predicted_names', status: 'fulfilled', rowCount: 1 },
            { source: 'name', status: 'fulfilled', rowCount: 1 },
          ],
          failedSourceCount: 0,
        },
      },
    },
  }, {
    query: 'mewt',
    searchLanguage: 'en',
    limit: 20,
    poolLimit: 5000,
    mode: 'benchmark_step',
    debug: true,
  }, {
    headers: {},
  });

  assert.equal(body.meta.predictive.model, 'dynamic_supabase_predicted_tokens');
  assert.equal(body.meta.predictive.predicted_tokens[0].display, 'Mewtwo');
  assert.equal(body.meta.predictive.sources.length, 2);
});

test('searchbar response wrapper exposes one-character Supabase context predictions', () => {
  const rows = [row(25, 'Pikachu')];
  rows.nonNameContext = {
    predictive_pool: {
      strategy: 'supabase_one_char_name_index',
      predicted_tokens: [
        {
          normalized: 'pikachu',
          display: 'Pikachu',
          confidence: 91,
          source_rank: 1,
          language: 'en',
        },
      ],
      sources: [{ source: 'supabase_predicted_names', status: 'fulfilled', row_count: 1 }],
    },
  };
  const body = searchbar.wrapAutocompleteBody({
    rows,
    pool: {
      source: 'search_pipeline',
      size: 1,
      strategy: 'supabase_one_char_name_index',
    },
    search_context: autocomplete.buildSearchContext(
      'p',
      'en',
      rows,
      'supabase_one_char_name_index',
      null,
      500,
    ),
    debug: {
      searchPath: 'supabase_one_char_name_index',
    },
  }, {
    query: 'p',
    searchLanguage: 'en',
    limit: 20,
    poolLimit: 500,
    mode: 'benchmark_step',
    debug: true,
  }, {
    headers: {},
  });

  assert.equal(body.meta.search_path, 'supabase_one_char_name_index');
  assert.equal(body.meta.predictive.model, 'supabase_one_char_name_index');
  assert.equal(body.meta.predictive.predicted_tokens[0].display, 'Pikachu');
});

test('searchbar endpoint supports anonymous POST without authorization headers', async () => {
  const autocompletePath = require.resolve('./marketplace-autocomplete');
  const originalAutocomplete = require.cache[autocompletePath].exports;
  require.cache[autocompletePath].exports = async (req, res) => {
    assert.deepEqual(req.headers, {});
    assert.equal(req.headers.authorization, undefined);
    res.setHeader('Server-Timing', 'autocomplete;dur=12, candidate;dur=8, rank;dur=1');
    return res.status(200).json({
      rows: [row(25, 'Pikachu')],
      pool: {
        source: 'search_pipeline',
        size: 1,
        limit: 500,
        candidateIdLimit: 500,
        appliedCandidateIdLimit: 500,
        strategy: 'name_table_direct',
      },
      search_context: autocomplete.buildSearchContext(
        'pikachu',
        'en',
        [row(25, 'Pikachu')],
        'name_table_direct',
        null,
        500,
      ),
      debug: {
        searchPath: 'name_table_direct',
        durationMs: 12,
        candidateDurationMs: 8,
        rankDurationMs: 1,
      },
    });
  };

  try {
    const res = responseRecorder();
    await searchbar({
      method: 'POST',
      body: {
        query: 'pikachu',
        search_language: 'en',
        limit: 20,
        debug: true,
      },
    }, res);

    assert.equal(res.statusCode, 200);
    assert.equal(res.body.ok, true);
    assert.equal(res.body.rows.length, 1);
    assert.equal(res.body.rows[0].name, 'Pikachu');
    assert.equal(res.body.meta.search_path, 'name_table_direct');
    assert.equal(res.body.meta.timings.duration_ms, 12);
  } finally {
    require.cache[autocompletePath].exports = originalAutocomplete;
  }
});

test('searchbar endpoint supports anonymous GET without authorization headers', async () => {
  const res = responseRecorder();
  await searchbar({
    method: 'GET',
    query: {
      query: 'mimikyu',
      search_language: 'en',
      limit: 5,
      debug: '1',
    },
    _searchbarAutocompleteResponse: async (input, innerRes) => {
      assert.equal(input.query, 'mimikyu');
      assert.equal(input.limit, 5);
      innerRes.setHeader('Server-Timing', 'autocomplete;dur=9');
      return {
        statusCode: 200,
        headers: { 'server-timing': 'autocomplete;dur=9' },
        body: {
          rows: [row(778, 'Mimikyu')],
          pool: {
            source: 'search_pipeline',
            size: 1,
            strategy: 'name_table_direct',
          },
          search_context: autocomplete.buildSearchContext(
            'mimikyu',
            'en',
            [row(778, 'Mimikyu')],
            'name_table_direct',
            null,
            500,
          ),
          debug: {
            searchPath: 'name_table_direct',
            durationMs: 9,
          },
        },
      };
    },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.ok, true);
  assert.equal(res.body.rows.length, 1);
  assert.equal(res.body.rows[0].name, 'Mimikyu');
  assert.equal(res.body.search_context.query, 'mimikyu');
});

test('searchbar endpoint forwards char-by-char context and caps visible rows', async () => {
  const calls = [];
  let previousSearchContext = null;
  for (const query of ['p', 'pi', 'pik', 'pika']) {
    const req = {
      method: 'POST',
      headers: {},
      body: {
        query,
        search_language: 'en',
        limit: 20,
        pool_limit: 5000,
        previous_search_context: previousSearchContext,
        debug: true,
        mode: 'benchmark_step',
      },
      _searchbarAutocompleteResponse: async (input, res) => {
        const appliedLimit = autocomplete.autocompleteCandidateIdAppliedLimit(input.query);
        const rows = Array.from({ length: appliedLimit }, (_, index) =>
          row(index + 1, `${input.query} ${index + 1}`));
        const searchContext = autocomplete.buildSearchContext(
          input.query,
          input.searchLanguage,
          rows,
          input.previousSearchContext ? 'candidate_context_refine' : 'name_table_direct',
          input.previousSearchContext,
          appliedLimit,
        );
        calls.push({
          searchTerm: input.query,
          poolLimit: appliedLimit,
          searchLanguage: input.searchLanguage,
          previousSearchContext: input.previousSearchContext,
        });
        res.setHeader('Server-Timing', 'autocomplete;dur=10, candidate;dur=7, rank;dur=1');
        return {
          statusCode: 200,
          headers: { 'server-timing': 'autocomplete;dur=10, candidate;dur=7, rank;dur=1' },
          body: {
            rows: rows.slice(0, input.limit),
            pool: {
              source: input.previousSearchContext ? 'context_or_search_pipeline' : 'search_pipeline',
              size: rows.length,
              limit: appliedLimit,
              candidateIdLimit: autocomplete.autocompleteCandidateIdRequestedLimit(input.query),
              appliedCandidateIdLimit: appliedLimit,
              strategy: searchContext.strategy,
            },
            search_context: searchContext,
            debug: {
              searchPath: searchContext.strategy,
              durationMs: 10,
              candidateDurationMs: 7,
              rankDurationMs: 1,
            },
          },
        };
      },
    };
    const res = responseRecorder();
    await searchbar(req, res);
    assert.equal(res.statusCode, 200);
    assert.equal(res.body.rows.length, 20);
    assert.equal(res.body.search_context.query, query);
    assert.equal(res.body.search_context.card_ids.length, res.body.meta.candidate_id_ladder.appliedLimit);
    previousSearchContext = res.body.search_context;
  }

  assert.equal(calls[0].previousSearchContext, null);
  assert.equal(calls[1].previousSearchContext.query, 'p');
  assert.equal(calls[2].previousSearchContext.query, 'pi');
  assert.equal(calls[3].previousSearchContext.query, 'pik');
  assert.deepEqual(calls.map((call) => call.poolLimit), [500, 5000, 2500, 1250]);
});

test('searchbar endpoint forwards prediction context to autocomplete', async () => {
  const predictionContext = {
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
        representative_card_ids: ['25'],
      },
    ],
  };
  const res = responseRecorder();

  await searchbar({
    method: 'POST',
    body: {
      query: 'pikachu 025',
      search_language: 'en',
      prediction_context: predictionContext,
      debug: true,
    },
    _searchbarAutocompleteResponse: async (input, innerRes) => {
      assert.equal(input.predictionContext, predictionContext);
      innerRes.setHeader('Server-Timing', 'autocomplete;dur=9');
      return {
        statusCode: 200,
        headers: { 'server-timing': 'autocomplete;dur=9' },
        body: {
          rows: [row(25, 'Pikachu')],
          pool: { source: 'search_pipeline', size: 1, strategy: 'predictive_dimension_pool' },
          search_context: autocomplete.buildSearchContext(
            'pikachu 025',
            'en',
            [row(25, 'Pikachu')],
            'predictive_dimension_pool',
            null,
            500,
          ),
          debug: { searchPath: 'predictive_dimension_pool' },
        },
      };
    },
  }, res);

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.meta.prediction_context.candidate_count, 1);
  assert.equal(res.body.meta.prediction_context.normalized_fragment, 'pik');
});

test('searchbar quality examples rank exact and typo query fixtures', () => {
  const fixtures = [
    row(1, 'Pikachu'),
    row(2, 'Mew ex'),
    row(3, 'Mimikyu'),
    row(4, 'Charizard ex'),
    row(5, 'Charmander'),
    row(6, 'Energy Switch'),
  ].map((item) => ({
    ...item,
    set_name: item.name === 'Mew ex' ? 'Paldean Fates' : item.set_name,
    card_number: item.name === 'Mew ex' ? 'Special Illustration Rare | 216/091' : item.card_number,
  }));

  const examples = [
    ['pikachu', 'Pikachu'],
    ['mew ex 216', 'Mew ex'],
    ['mimikyu', 'Mimikyu'],
    ['charizard', 'Charizard ex'],
    ['pikchu', 'Pikachu'],
    ['charzard', 'Charizard ex'],
  ];

  for (const [query, expectedName] of examples) {
    assert.equal(autocomplete.rankAutocompleteRows(fixtures, query, 20)[0].name, expectedName);
  }
});
