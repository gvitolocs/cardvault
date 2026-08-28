const assert = require('node:assert/strict');
const test = require('node:test');

const tokenPredict = require('./searchbar-token-predict');
const {
  compact,
  supabasePredictedNameTokens,
} = require('./marketplace-autocomplete');

function tokenRow({
  name,
  compactName,
  tokens,
  language = 'en',
  count = 1,
  confidence,
  score,
}) {
  return {
    canonical_name: name,
    display_name: name,
    compact_name: compactName || compact(name),
    name_tokens: tokens || [compactName || compact(name)],
    language,
    confidence,
    score,
    row_count: count,
    representative_card_ids: Array.from({ length: count }, (_, index) => `${compact(name)}-${index}`),
    card_ids: Array.from({ length: count }, (_, index) => `${compact(name)}-${index}`),
  };
}

test('token predict input accepts GET aliases and trailing token fragment', () => {
  const input = tokenPredict.inputFromRequest({
    method: 'GET',
    query: {
      query: 'mew 232 mewt',
      language: 'FR',
      limit: '3',
      debug: '1',
    },
  });

  assert.equal(input.query, 'mew 232 mewt');
  assert.equal(input.fragment, 'mewt');
  assert.equal(input.predictionFragment, 'mewt');
  assert.equal(input.searchLanguage, 'fr');
  assert.equal(input.limit, 3);
  assert.equal(input.debug, true);
});

test('token predict input keeps simple multi-token name phrase', () => {
  const input = tokenPredict.inputFromRequest({
    method: 'GET',
    query: {
      query: 'tapu l',
    },
  });

  assert.equal(input.fragment, 'l');
  assert.equal(input.predictionFragment, 'tapu l');
});

test('token predict normalization covers punctuation and diacritics', () => {
  assert.equal(compact("Farfetch’d"), 'farfetchd');
  assert.equal(compact('Pikachu & Zekrom-GX'), 'pikachutagteamzekromgx');
  assert.equal(compact("_____'s Pikachu"), 'spikachu');
  assert.equal(compact('Unown [N]'), 'unownn');
  assert.equal(compact('Flabébé'), 'flabebe');
  assert.equal(compact('Pokédex'), 'pokedex');
  assert.equal(compact('Pokémon'), 'pokemon');
});

test('token predict ranks broad p by popularity and par by prefix quality', async () => {
  const predictP = await tokenPredict.predictNameTokens(
    {
      query: 'p',
      fragment: 'p',
      searchLanguage: 'en',
      limit: 5,
    },
    async (_sql, values) => {
      assert.equal(values[0], 'p');
      return {
        rows: [
          tokenRow({ name: 'Paras', compactName: 'paras', count: 2, confidence: 92, score: 120800 }),
          tokenRow({ name: 'Pikachu', compactName: 'pikachu', count: 120, confidence: 91, score: 120800 }),
        ],
      };
    },
  );
  const predictPar = await tokenPredict.predictNameTokens(
    {
      query: 'par',
      fragment: 'par',
      searchLanguage: 'en',
      limit: 5,
    },
    async (_sql, values) => {
      assert.equal(values[0], 'par');
      return {
        rows: [
          tokenRow({ name: 'Pikachu', compactName: 'pikachu', count: 120, confidence: 76, score: 2500 }),
          tokenRow({ name: 'Paras', compactName: 'paras', count: 2, confidence: 93, score: 120800 }),
        ],
      };
    },
  );

  assert.equal(predictP.predictions[0].display_token, 'Pikachu');
  assert.equal(predictP.predictions[0].card_count, 120);
  assert.equal(predictPar.predictions[0].display_token, 'Paras');
});

test('token predict uses accent-folded compact query for Pokédex', async () => {
  const payload = await tokenPredict.predictNameTokens(
    {
      query: 'pokédex',
      fragment: 'pokédex',
      searchLanguage: 'en',
      limit: 5,
    },
    async (_sql, values) => {
      assert.equal(values[0], 'pokedex');
      return {
        rows: [
          tokenRow({
            name: 'Pokédex',
            compactName: 'pokedex',
            tokens: ['pokedex'],
            count: 24,
            confidence: 100,
            score: 240000,
          }),
        ],
      };
    },
  );

  assert.equal(payload.normalized_fragment, 'pokedex');
  assert.equal(payload.predictions[0].display_token, 'Pokédex');
});


test('token predict narrows p to pi to pik from previous context top half', async () => {
  const predictP = await tokenPredict.predictNameTokens(
    {
      query: 'p',
      fragment: 'p',
      searchLanguage: 'en',
      limit: 5,
    },
    async (_sql, values) => {
      assert.equal(values[0], 'p');
      return {
        rows: [
          tokenRow({ name: 'Pikachu', compactName: 'pikachu', count: 120, confidence: 91, score: 120800 }),
          tokenRow({ name: 'Piplup', compactName: 'piplup', count: 40, confidence: 90, score: 90000 }),
          tokenRow({ name: 'Pidgey', compactName: 'pidgey', count: 35, confidence: 89, score: 80000 }),
          tokenRow({ name: 'Paras', compactName: 'paras', count: 2, confidence: 86, score: 70000 }),
          tokenRow({ name: 'Porygon', compactName: 'porygon', count: 20, confidence: 84, score: 60000 }),
          tokenRow({ name: 'Psyduck', compactName: 'psyduck', count: 18, confidence: 83, score: 50000 }),
        ],
      };
    },
  );

  let dbCalls = 0;
  const predictPi = await tokenPredict.predictNameTokens(
    {
      query: 'pi',
      fragment: 'pi',
      searchLanguage: 'en',
      limit: 5,
      previousPredictionContext: predictP.prediction_context,
    },
    async () => {
      dbCalls += 1;
      return { rows: [] };
    },
  );
  const predictPik = await tokenPredict.predictNameTokens(
    {
      query: 'pik',
      fragment: 'pik',
      searchLanguage: 'en',
      limit: 5,
      previousPredictionContext: predictPi.prediction_context,
    },
    async () => {
      dbCalls += 1;
      return { rows: [] };
    },
  );

  assert.equal(dbCalls, 0);
  assert.equal(predictPi.meta.source, 'context_prefix_narrow');
  assert.equal(predictPi.meta.context_refinement.searched_candidate_count, 3);
  assert.deepEqual(
    predictPi.predictions.map((prediction) => prediction.display_token),
    ['Pikachu', 'Piplup', 'Pidgey'],
  );
  assert.equal(predictPik.meta.source, 'context_prefix_narrow');
  assert.equal(predictPik.predictions[0].display_token, 'Pikachu');
});

test('token predict caches repeated first-character Supabase lookup', async () => {
  let dbCalls = 0;
  const query = async (_sql, values) => {
    dbCalls += 1;
    assert.equal(values[0], 'p');
    return {
      rows: [
        tokenRow({ name: 'Pikachu', compactName: 'pikachu', count: 120, confidence: 91, score: 120800 }),
      ],
    };
  };
  const input = {
    query: 'p',
    fragment: 'p',
    searchLanguage: 'en',
    limit: 5,
  };

  const first = await tokenPredict.predictNameTokens(input, query);
  const second = await tokenPredict.predictNameTokens(input, query);

  assert.equal(dbCalls, 1);
  assert.equal(first.predictions[0].display_token, 'Pikachu');
  assert.equal(second.predictions[0].display_token, 'Pikachu');
  assert.equal(first.meta.first_char_cache.hit, false);
  assert.equal(second.meta.first_char_cache.hit, true);
});

test('token predict uses Meili only for english language', async () => {
  const originalEngine = process.env.MARKETPLACE_SEARCH_ENGINE;
  const originalHost = process.env.MEILI_HOST;
  const originalIndex = process.env.MEILI_NAME_TOKEN_INDEX;
  const originalFetch = global.fetch;
  process.env.MARKETPLACE_SEARCH_ENGINE = 'meili';
  process.env.MEILI_HOST = 'http://127.0.0.1:7700';
  process.env.MEILI_NAME_TOKEN_INDEX = 'marketplace_name_tokens';
  let fetchCalls = 0;
  global.fetch = async () => {
    fetchCalls += 1;
    return {
      ok: true,
      status: 200,
      async text() {
        return JSON.stringify({
          hits: [{
            display_token: 'Pikachu',
            normalized_token: 'pikachu',
            card_count: 100,
            candidate_card_ids: ['25'],
            _rankingScore: 0.98,
          }],
        });
      },
    };
  };
  try {
    const englishPayload = await tokenPredict.predictNameTokens(
      {
        query: 'pik',
        fragment: 'pik',
        searchLanguage: 'en',
        limit: 5,
      },
      async () => {
        throw new Error('legacy token query must not run for english meili mode');
      },
    );
    assert.equal(englishPayload.predictions[0].display_token, 'Pikachu');
    assert.equal(fetchCalls > 0, true);

    let legacyCalls = 0;
    fetchCalls = 0;
    const frenchPayload = await tokenPredict.predictNameTokens(
      {
        query: 'pik',
        fragment: 'pik',
        searchLanguage: 'fr',
        limit: 5,
      },
      async () => {
        legacyCalls += 1;
        return {
          rows: [
            tokenRow({ name: 'Pikachu', compactName: 'pikachu', count: 100, confidence: 90, score: 100000 }),
          ],
        };
      },
    );
    assert.equal(frenchPayload.predictions[0].display_token, 'Pikachu');
    assert.equal(legacyCalls > 0, true);
    assert.equal(fetchCalls, 0);
  } finally {
    global.fetch = originalFetch;
    if (originalEngine === undefined) delete process.env.MARKETPLACE_SEARCH_ENGINE;
    else process.env.MARKETPLACE_SEARCH_ENGINE = originalEngine;
    if (originalHost === undefined) delete process.env.MEILI_HOST;
    else process.env.MEILI_HOST = originalHost;
    if (originalIndex === undefined) delete process.env.MEILI_NAME_TOKEN_INDEX;
    else process.env.MEILI_NAME_TOKEN_INDEX = originalIndex;
  }
});

test('token predict warmup returns top first-character suggestions and caches them', async () => {
  tokenPredict.clearFirstCharWarmupCacheForTest();
  let dbCalls = 0;
  const query = async (sql, values) => {
    dbCalls += 1;
    assert.match(sql, /public\.marketplace_card_name_tokens/);
    assert.equal(values[0], 'en');
    assert.equal(values[1], 1);
    return {
      rows: [
        {
          letter: 'm',
          canonical_name: 'Mew',
          display_name: 'Mew',
          compact_name: 'mew',
          language: 'en',
          confidence: 100,
          score: 260000,
          source_rank: 1,
          card_count: 155,
          ids_count: 155,
        },
        {
          letter: 'p',
          canonical_name: 'Pikachu',
          display_name: 'Pikachu',
          compact_name: 'pikachu',
          language: 'en',
          confidence: 98,
          score: 620000,
          source_rank: 1,
          card_count: 550,
          ids_count: 550,
        },
      ],
    };
  };

  const first = await tokenPredict.firstCharWarmupSuggestions(
    { searchLanguage: 'en', limit: 1 },
    query,
  );
  const second = await tokenPredict.firstCharWarmupSuggestions(
    { searchLanguage: 'en', limit: 1 },
    query,
  );

  assert.equal(dbCalls, 1);
  assert.equal(first.language, 'en');
  assert.equal(first.suggestions.p.display_token, 'Pikachu');
  assert.equal(first.suggestions.m.display_token, 'Mew');
  assert.equal(first.suggestions.p.source, 'first_char_warmup');
  assert.equal(first.meta.cache.hit, false);
  assert.equal(second.meta.cache.hit, true);
  assert.equal(second.suggestions.p.display_token, 'Pikachu');
});

test('token predict warmup does not fall back to English for selected language', async () => {
  tokenPredict.clearFirstCharWarmupCacheForTest();
  const languages = [];
  const payload = await tokenPredict.firstCharWarmupSuggestions(
    { searchLanguage: 'it', limit: 1 },
    async (_sql, values) => {
      languages.push(values[0]);
      return {
        rows: [],
      };
    },
  );

  assert.deepEqual(languages, ['it']);
  assert.equal(payload.language, 'it');
  assert.equal(payload.source_language, 'it');
  assert.deepEqual(payload.suggestions, {});
  assert.equal(payload.meta.fallback_to_english, false);
});

test('token predict debug exposes selected Italian language and token language', async () => {
  const payload = await tokenPredict.predictNameTokens(
    {
      query: 'camilla',
      fragment: 'camilla',
      searchLanguage: 'it',
      limit: 5,
    },
    async (_sql, values) => {
      assert.equal(values[1], 'it');
      return {
        rows: [
          tokenRow({
            name: 'Camilla',
            compactName: 'camilla',
            tokens: ['camilla'],
            language: 'it',
            count: 4,
            confidence: 100,
            score: 240000,
          }),
        ],
      };
    },
  );

  assert.equal(payload.search_language, 'it');
  assert.equal(payload.predictions[0].display_token, 'Camilla');
  assert.equal(payload.predictions[0].language, 'it');
  assert.equal(payload.prediction_context.language, 'it');
});

test('token predict fuzzy mode after three chars keeps girati on Giratina', async () => {
  const context = {
    query: 'girat',
    fragment: 'girat',
    prediction_fragment: 'girat',
    normalized_fragment: 'girat',
    language: 'en',
    created_at_ms: Date.now(),
    candidates: [
      {
        display_token: 'Giratina',
        normalized_token: 'giratina',
        confidence: 94,
        score: 140000,
        source_rank: 1,
        language: 'en',
        representative_card_ids: ['487'],
      },
      {
        display_token: 'Giraffe',
        normalized_token: 'giraffe',
        confidence: 80,
        score: 10000,
        source_rank: 2,
        language: 'en',
      },
    ],
  };
  let dbCalls = 0;
  const predictGirati = await tokenPredict.predictNameTokens(
    {
      query: 'girati',
      fragment: 'girati',
      searchLanguage: 'en',
      limit: 5,
      previousPredictionContext: context,
    },
    async () => {
      dbCalls += 1;
      return { rows: [] };
    },
  );

  assert.equal(dbCalls, 0);
  assert.equal(predictGirati.meta.source, 'context_fuzzy');
  assert.equal(predictGirati.predictions[0].display_token, 'Giratina');
});

test('token predict falls back to full Supabase table when context misses laprs', async () => {
  const context = {
    query: 'lap',
    fragment: 'lap',
    prediction_fragment: 'lap',
    normalized_fragment: 'lap',
    language: 'en',
    created_at_ms: Date.now(),
    candidates: [
      {
        display_token: 'Lapurdi',
        normalized_token: 'lapurdi',
        confidence: 82,
        score: 3000,
        source_rank: 1,
      },
      {
        display_token: 'Lappy',
        normalized_token: 'lappy',
        confidence: 80,
        score: 2000,
        source_rank: 2,
      },
    ],
  };
  let dbCalls = 0;
  const predictLaprs = await tokenPredict.predictNameTokens(
    {
      query: 'laprs',
      fragment: 'laprs',
      searchLanguage: 'en',
      limit: 5,
      previousPredictionContext: context,
    },
    async (sql, values) => {
      dbCalls += 1;
      assert.match(sql, /public\.marketplace_card_name_tokens/);
      assert.match(sql, /marketplace_edit_distance/);
      assert.equal(values[0], 'laprs');
      return {
        rows: [
          tokenRow({
            name: 'Lapras',
            compactName: 'lapras',
            count: 12,
            confidence: 76,
            score: 90000,
          }),
        ],
      };
    },
  );

  assert.equal(dbCalls, 1);
  assert.equal(predictLaprs.predictions[0].display_token, 'Lapras');
  assert.equal(predictLaprs.meta.context_refinement.matched_candidate_count, 0);
  assert.equal(predictLaprs.meta.full_table_fallback.used, true);
  assert.equal(predictLaprs.meta.full_table_fallback.reason, 'no_context_matches');
  assert.match(predictLaprs.meta.source, /supabase_postgres_fallback/);
});

test('token predict exposes bounded candidate card IDs for backend subset verification', async () => {
  const payload = await tokenPredict.predictNameTokens(
    {
      query: 'laprs',
      fragment: 'laprs',
      searchLanguage: 'en',
      limit: 5,
    },
    async () => ({
      rows: [
        tokenRow({
          name: 'Lapras',
          compactName: 'lapras',
          count: 40,
          confidence: 76,
          score: 90000,
        }),
      ],
    }),
  );

  assert.equal(payload.predictions[0].display_token, 'Lapras');
  assert.equal(payload.predictions[0].representative_card_ids.length, 3);
  assert.equal(payload.predictions[0].candidate_card_ids.length, 24);
  assert.equal(payload.prediction_context.candidates[0].candidate_card_ids.length, 32);
});

test('token predict invalidates previous context on branch and language mismatch', async () => {
  const context = {
    query: 'pi',
    fragment: 'pi',
    normalized_fragment: 'pi',
    language: 'en',
    created_at_ms: Date.now(),
    candidates: [
      { display_token: 'Pikachu', normalized_token: 'pikachu', confidence: 95 },
    ],
  };
  const branch = tokenPredict.cleanPreviousPredictionContext(
    context,
    { searchLanguage: 'en' },
    'pa',
  );
  const language = tokenPredict.cleanPreviousPredictionContext(
    context,
    { searchLanguage: 'fr' },
    'pik',
  );

  assert.equal(branch.valid, false);
  assert.equal(branch.reason, 'fragment_not_extended');
  assert.equal(language.valid, false);
  assert.equal(language.reason, 'language_changed');
});

test('token predict completes two-token names from compact phrase prefixes', async () => {
  const predictTapuL = await tokenPredict.predictNameTokens(
    {
      query: 'tapu l',
      fragment: 'l',
      predictionFragment: 'tapu l',
      searchLanguage: 'en',
      limit: 5,
    },
    async (sql, values) => {
      assert.match(sql, /i\.compact_name like input\.compact_q \|\| '%'/);
      assert.equal(values[0], 'tapul');
      return {
        rows: [
          tokenRow({
            name: 'Tapu Lele',
            compactName: 'tapulele',
            tokens: ['tapu', 'lele'],
            count: 6,
            confidence: 0,
            score: 0,
          }),
        ],
      };
    },
  );
  const predictTapuK = await tokenPredict.predictNameTokens(
    {
      query: 'tapu k',
      fragment: 'k',
      predictionFragment: 'tapu k',
      searchLanguage: 'en',
      limit: 5,
    },
    async (_sql, values) => {
      assert.equal(values[0], 'tapuk');
      return {
        rows: [
          tokenRow({
            name: 'Tapu Koko',
            compactName: 'tapukoko',
            tokens: ['tapu', 'koko'],
            count: 20,
            confidence: 0,
            score: 0,
          }),
        ],
      };
    },
  );

  assert.equal(predictTapuL.predictions[0].display_token, 'Tapu Lele');
  assert.equal(predictTapuL.predictions[0].matched_prefix, 'tapul');
  assert.equal(predictTapuK.predictions[0].display_token, 'Tapu Koko');
});

test('token predict falls back to substantive token when mega phrase has no exact name', async () => {
  const calls = [];
  const payload = await tokenPredict.predictNameTokens(
    {
      query: 'mega darkrai',
      fragment: 'darkrai',
      predictionFragment: 'mega darkrai',
      searchLanguage: 'en',
      limit: 5,
    },
    async (sql, values) => {
      calls.push({ sql, values });
      assert.match(sql, /public\.marketplace_card_name_tokens/);
      if (values[0] === 'megadarkrai') {
        return { rows: [] };
      }
      assert.equal(values[0], 'darkrai');
      return {
        rows: [
          tokenRow({
            name: 'Darkrai',
            compactName: 'darkrai',
            tokens: ['darkrai'],
            count: 34,
            confidence: 100,
            score: 120000,
          }),
        ],
      };
    },
  );

  assert.deepEqual(calls.map((call) => call.values[0]), ['megadarkrai', 'darkrai']);
  assert.equal(payload.meta.source, 'supabase_postgres_alternate_fragment');
  assert.equal(payload.predictions[0].display_token, 'Darkrai');
  assert.equal(payload.meta.full_table_fallback.reason, 'primary_fragment_empty');
});

test('token predict tries trailing phrase before generic suffix token', async () => {
  const calls = [];
  const payload = await tokenPredict.predictNameTokens(
    {
      query: 'mega darkrai ex',
      fragment: 'ex',
      predictionFragment: 'mega darkrai ex',
      searchLanguage: 'en',
      limit: 5,
    },
    async (_sql, values) => {
      calls.push(values[0]);
      if (values[0] === 'darkraiex') {
        return {
          rows: [
            tokenRow({
              name: 'Darkrai EX',
              compactName: 'darkraiex',
              tokens: ['darkrai', 'ex'],
              count: 19,
              confidence: 100,
              score: 180000,
            }),
          ],
        };
      }
      return { rows: [] };
    },
  );

  assert.deepEqual(calls, ['megadarkraiex', 'darkraiex']);
  assert.equal(payload.predictions[0].display_token, 'Darkrai EX');
});

test('token predict keeps variation prefix completion after first-name anchor', async () => {
  const calls = [];
  const payload = await tokenPredict.predictNameTokens(
    {
      query: 'mimikyu g',
      fragment: 'g',
      predictionFragment: 'mimikyu g',
      searchLanguage: 'en',
      limit: 5,
    },
    async (_sql, values) => {
      calls.push(values[0]);
      if (values[0] === 'mimikyu') {
        return {
          rows: [
            tokenRow({
              name: 'Mimikyu',
              compactName: 'mimikyu',
              tokens: ['mimikyu'],
              count: 60,
              confidence: 100,
              score: 140000,
            }),
          ],
        };
      }
      if (values[0] === 'mimikyug') {
        return {
          rows: [
            tokenRow({
              name: 'Mimikyu GX',
              compactName: 'mimikyugx',
              tokens: ['mimikyu', 'gx'],
              count: 7,
              confidence: 100,
              score: 180000,
            }),
          ],
        };
      }
      return { rows: [] };
    },
  );

  assert.deepEqual(calls, ['mimikyu', 'mimikyug']);
  assert.equal(payload.predictions[0].display_token, 'Mimikyu GX');
  assert.equal(payload.meta.source, 'supabase_postgres');
});

test('token predict suppresses unrelated Hearthflame card after Rare Candy anchor', async () => {
  const calls = [];
  const payload = await tokenPredict.predictNameTokens(
    {
      query: 'rare candy hearth',
      fragment: 'hearth',
      predictionFragment: 'rare candy hearth',
      searchLanguage: 'en',
      limit: 5,
      previousPredictionContext: {
        query: 'rare candy heart',
        fragment: 'heart',
        prediction_fragment: 'rare candy heart',
        normalized_fragment: 'rarecandyheart',
        language: 'en',
        created_at_ms: Date.now(),
        candidates: [
          {
            display_token: 'Hearthflame Mask Ogerpon',
            normalized_token: 'hearthflamemaskogerpon',
            confidence: 79,
            score: 120000,
            source_rank: 1,
          },
        ],
      },
    },
    async (_sql, values) => {
      calls.push(values[0]);
      if (values[0] === 'rarecandy' || values[0] === 'rarecandyhearth') {
        return {
          rows: [
            tokenRow({
              name: 'Rare Candy',
              compactName: 'rarecandy',
              tokens: ['rare', 'candy'],
              count: 50,
              confidence: 100,
              score: 240000,
            }),
          ],
        };
      }
      if (values[0] === 'hearth') {
        return {
          rows: [
            tokenRow({
              name: 'Hearthflame Mask Ogerpon',
              compactName: 'hearthflamemaskogerpon',
              tokens: ['hearthflame', 'mask', 'ogerpon'],
              count: 17,
              confidence: 80,
              score: 150000,
            }),
          ],
        };
      }
      return { rows: [] };
    },
  );

  assert.deepEqual(calls, ['rarecandy']);
  assert.equal(payload.predictions[0].display_token, 'HeartGold & SoulSilver');
  assert.equal(payload.predictions[0].normalized_token, 'heartgoldsoulsilver');
  assert.equal(payload.predictions.some((prediction) =>
    prediction.display_token === 'Hearthflame Mask Ogerpon'), false);
  assert.equal(payload.meta.source, 'anchored_dimension_alias');
  assert.equal(payload.meta.full_table_fallback.reason, 'first_name_anchor_established');
  assert.equal(
    payload.meta.full_table_fallback.anchor.normalized,
    'rarecandy',
  );
});

test('token predict returns no second-card completion for unrecognized trailing text after anchor', async () => {
  const calls = [];
  const payload = await tokenPredict.predictNameTokens(
    {
      query: 'rare candy twi',
      fragment: 'twi',
      predictionFragment: 'rare candy twi',
      searchLanguage: 'en',
      limit: 5,
    },
    async (_sql, values) => {
      calls.push(values[0]);
      if (values[0] === 'rarecandy') {
        return {
          rows: [
            tokenRow({
              name: 'Rare Candy',
              compactName: 'rarecandy',
              tokens: ['rare', 'candy'],
              count: 50,
              confidence: 100,
              score: 240000,
            }),
          ],
        };
      }
      return {
        rows: [
          tokenRow({
            name: 'Twilight Masquerade',
            compactName: 'twilightmasquerade',
            tokens: ['twilight', 'masquerade'],
            count: 20,
            confidence: 84,
            score: 120000,
          }),
        ],
      };
    },
  );

  assert.deepEqual(calls, ['rarecandy']);
  assert.deepEqual(payload.predictions, []);
  assert.equal(payload.meta.source, 'anchored_first_name');
});

test('token predict does not require hardcoded Rare Candy alias to anchor first card name', async () => {
  const payload = await tokenPredict.predictNameTokens(
    {
      query: 'ultra ball heart',
      fragment: 'heart',
      predictionFragment: 'ultra ball heart',
      searchLanguage: 'en',
      limit: 5,
    },
    async (_sql, values) => {
      assert.equal(values[0], 'ultraball');
      return {
        rows: [
          tokenRow({
            name: 'Ultra Ball',
            compactName: 'ultraball',
            tokens: ['ultra', 'ball'],
            count: 60,
            confidence: 100,
            score: 240000,
          }),
        ],
      };
    },
  );

  assert.equal(payload.predictions[0].display_token, 'HeartGold & SoulSilver');
  assert.equal(payload.predictions[0].anchor, 'Ultra Ball');
  assert.equal(
    payload.meta.full_table_fallback.anchor.normalized,
    'ultraball',
  );
  assert.equal(
    payload.meta.full_table_fallback.reason,
    'first_name_anchor_established',
  );
  assert.equal(
    payload.predictions[0].alias,
    'heartgold',
  );
});

test('token predict recognizes heart gold and hearth gold HGSS alias fragments', async () => {
  for (const query of ['rare candy heart g', 'rare candy hearth g']) {
    const payload = await tokenPredict.predictNameTokens(
      {
        query,
        fragment: 'g',
        predictionFragment: query,
        searchLanguage: 'en',
        limit: 5,
      },
      async (_sql, values) => {
        if (values[0] !== 'rarecandy') return { rows: [] };
        return {
          rows: [
            tokenRow({
              name: 'Rare Candy',
              compactName: 'rarecandy',
              tokens: ['rare', 'candy'],
              count: 50,
              confidence: 100,
              score: 240000,
            }),
          ],
        };
      },
    );

    assert.equal(payload.predictions[0].display_token, 'HeartGold & SoulSilver');
    assert.equal(payload.predictions[0].normalized_token, 'heartgoldsoulsilver');
  }
});

test('token predict returns token-only tiny payload without rows or context labels', async () => {
  const payload = await tokenPredict.predictNameTokens(
    {
      query: 'mewt',
      fragment: 'mewt',
      searchLanguage: 'en',
      limit: 5,
    },
    async () => ({
      rows: [
        tokenRow({ name: 'Mewtwo', compactName: 'mewtwo', count: 24, confidence: 94, score: 140000 }),
      ],
    }),
  );
  const encoded = JSON.stringify(payload);

  assert.equal(payload.predictions[0].display_token, 'Mewtwo');
  assert.equal(Object.hasOwn(payload, 'rows'), false);
  assert.equal(Object.hasOwn(payload, 'search_context'), false);
  assert.equal(encoded.includes('representative_labels'), false);
  assert.ok(Buffer.byteLength(encoded) < 2000);
});

test('token predict forwards requested language to Supabase token query', async () => {
  const predictions = await supabasePredictedNameTokens(
    'pika',
    'fr',
    5,
    async (sql, values) => {
      assert.match(sql, /i\.language = input\.language/);
      assert.equal(values[1], 'fr');
      return {
        rows: [
          tokenRow({ name: 'Pikachu', compactName: 'pikachu', language: 'fr', count: 10, confidence: 95, score: 150000 }),
        ],
      };
    },
  );

  assert.equal(predictions[0].language, 'fr');
});
