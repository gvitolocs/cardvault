const { cleanLanguage, cleanLimit, cleanSearchTerm } = require('./marketplace-search-candidates');
const { isSearchSessionCancelled, cleanSearchSessionId } = require('./_searchbar_session');

const DEFAULT_MODE = 'autocomplete';
const SEARCHBAR_ENDPOINT = '/api/searchbar-cards';

function headersObject(headers) {
  if (!headers) return {};
  if (typeof headers.entries === 'function') {
    return Object.fromEntries([...headers.entries()].map(([key, value]) => [
      String(key).toLowerCase(),
      value,
    ]));
  }
  return Object.fromEntries(Object.entries(headers).map(([key, value]) => [
    String(key).toLowerCase(),
    Array.isArray(value) ? value[0] || '' : value,
  ]));
}

function booleanParam(value) {
  return value === true || value === 'true' || value === '1' || value === 1;
}

function cleanMode(value) {
  const mode = cleanSearchTerm(value || DEFAULT_MODE);
  if (mode === 'full' || mode === 'benchmark_step') return mode;
  return DEFAULT_MODE;
}

function cacheControlForInput(input) {
  return input?.method === 'POST'
    ? 'no-store'
    : input.query
      ? 'public, max-age=5, s-maxage=30'
      : 'public, max-age=10, s-maxage=60, stale-while-revalidate=120';
}

function parseContext(value) {
  if (!value) return null;
  if (typeof value === 'object') return value;
  try {
    return JSON.parse(String(value));
  } catch {
    return null;
  }
}

function requestInput(req) {
  const source = req.method === 'GET' ? req.query || {} : req.body || {};
  const query = cleanSearchTerm(source.query ?? source.search_term ?? source.searchTerm);
  const searchLanguage = cleanLanguage(source.search_language ?? source.language);
  const limit = cleanLimit(source.limit ?? source.result_limit ?? 20);
  const poolLimit = cleanLimit(source.pool_limit ?? source.poolLimit ?? 1000);
  const mode = cleanMode(source.mode);
  return {
    method: req.method,
    query,
    searchLanguage,
    limit,
    poolLimit,
    mode,
    previousSearchContext: parseContext(
      source.previous_search_context ?? source.previousSearchContext,
    ),
    predictionContext: parseContext(
      source.prediction_context ??
        source.predictionContext ??
        source.previous_prediction_context ??
        source.previousPredictionContext,
    ),
    debug: booleanParam(source.debug),
    debugSessionId: cleanSearchTerm(source.debug_session_id ?? source.debugSessionId),
    searchSessionId: cleanSearchSessionId(
      source.search_session_id ?? source.searchSessionId ?? source.session_id ?? source.sessionId,
    ),
  };
}

function responseRecorder(parentRes) {
  return {
    statusCode: 200,
    headers: {},
    body: undefined,
    setHeader(name, value) {
      this.headers[String(name).toLowerCase()] = value;
      if (String(name).toLowerCase() === 'server-timing') {
        parentRes.setHeader('Server-Timing', value);
      }
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

async function runAutocomplete(req, input, res) {
  if (typeof req._searchbarAutocompleteResponse === 'function') {
    return req._searchbarAutocompleteResponse(input, res);
  }
  const autocomplete = require('./marketplace-autocomplete');
  const innerReq = {
    ...req,
    method: 'POST',
    headers: headersObject(req.headers),
    body: {
      search_term: input.query,
      result_limit: input.limit,
      pool_limit: input.poolLimit,
      search_language: input.searchLanguage,
      previous_search_context: input.previousSearchContext,
      prediction_context: input.predictionContext,
      debug: input.debug,
      debug_session_id: input.debugSessionId,
      search_session_id: input.searchSessionId,
    },
  };
  const innerRes = responseRecorder(res);
  await autocomplete(innerReq, innerRes);
  return innerRes;
}

function wrapAutocompleteBody(body, input, innerRes) {
  const rows = Array.isArray(body) ? body : body?.rows || [];
  const searchContext = Array.isArray(body) ? null : body?.search_context || null;
  const debug = Array.isArray(body) ? null : body?.debug || null;
  const pool = Array.isArray(body) ? null : body?.pool || null;
  const candidateLadder = searchContext?.candidate_id_ladder ||
    debug?.candidateIdLadder ||
    (pool
      ? {
          requestedLimit: pool.candidateIdLimit,
          appliedLimit: pool.appliedCandidateIdLimit,
        }
      : null);
  const predictivePool =
    debug?.candidateDebug?.predictivePool ||
    debug?.predictivePool ||
    searchContext?.non_name_context?.predictive_pool ||
    searchContext?.nonNameContext?.predictivePool ||
    null;
  const predictedTokens = predictivePool?.predictedTokens ||
    predictivePool?.predicted_tokens ||
    [];

  return {
    ok: true,
    endpoint: SEARCHBAR_ENDPOINT,
    mode: input.mode,
    query: input.query,
    search_language: input.searchLanguage,
    search_session_id: input.searchSessionId,
    limit: input.limit,
    pool_limit: input.poolLimit,
    rows,
    search_context: searchContext,
    meta: {
      visible_row_count: rows.length,
      rows_capped_by_limit: rows.length <= input.limit,
      rows_capped_by_preview_limit: rows.length <= 20,
      pool,
      candidate_id_ladder: candidateLadder,
      candidate_counts: {
        visible_rows: rows.length,
        pool_size: pool?.size ?? debug?.poolSize ?? null,
        context_card_ids: searchContext?.card_ids?.length || 0,
        context_candidate_labels: searchContext?.candidate_labels?.length || 0,
      },
      prediction_context: input.predictionContext
        ? {
            candidate_count: Array.isArray(input.predictionContext.candidates)
              ? input.predictionContext.candidates.length
              : 0,
            normalized_fragment: input.predictionContext.normalized_fragment ||
              input.predictionContext.normalizedFragment ||
              null,
          }
        : null,
      search_path: debug?.searchPath || pool?.strategy || null,
      predictive: predictivePool
        ? {
            model: predictivePool.model || predictivePool.strategy,
            predicted_tokens: predictedTokens,
            sources: predictivePool.sources || [],
            failed_source_count: predictivePool.failedSourceCount || 0,
          }
        : null,
      timings: {
        server_timing: innerRes.headers['server-timing'] || null,
        duration_ms: debug?.durationMs ?? null,
        candidate_ms: debug?.candidateDurationMs ?? null,
        analytics_ms: debug?.analyticsDurationMs ?? null,
        rank_ms: debug?.rankDurationMs ?? null,
      },
    },
    ...(input.debug && debug ? { debug } : {}),
  };
}

async function handler(req, res) {
  if (req.method !== 'POST' && req.method !== 'GET') {
    res.setHeader('Allow', 'GET, POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  const input = requestInput(req);
  try {
    if (isSearchSessionCancelled(input.searchSessionId)) {
      res.setHeader('Cache-Control', 'no-store');
      return res.status(200).json({
        ok: true,
        endpoint: SEARCHBAR_ENDPOINT,
        canceled: true,
        query: input.query,
        search_session_id: input.searchSessionId,
        rows: [],
        search_context: null,
        meta: {
          visible_row_count: 0,
          search_path: 'session_canceled',
        },
      });
    }
    const innerRes = await runAutocomplete(req, input, res);
    if (innerRes.statusCode >= 400) {
      return res.status(innerRes.statusCode).json(innerRes.body);
    }
    res.setHeader('Cache-Control', cacheControlForInput(input));
    return res.status(200).json(wrapAutocompleteBody(innerRes.body, input, innerRes));
  } catch (error) {
    console.error('searchbar cards failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Searchbar cards failed.',
    });
  }
}

module.exports = handler;
module.exports.requestInput = requestInput;
module.exports.wrapAutocompleteBody = wrapAutocompleteBody;
module.exports.cleanMode = cleanMode;
module.exports.cacheControlForInput = cacheControlForInput;
