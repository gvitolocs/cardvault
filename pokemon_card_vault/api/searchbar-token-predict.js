const {
  cleanLanguage,
  cleanLimit,
  cleanSearchTerm,
} = require('./marketplace-search-candidates');
const { useMeiliSearchForLanguage } = require('./_marketplace_search_engine');
const { meiliPredictedNameTokens } = require('./_meili_marketplace');
const {
  compact,
  supabasePredictedNameTokens,
  supabaseRestPredictedNameTokens,
} = require('./marketplace-autocomplete');
const {
  supabaseNameIndexDatabaseUrl,
  supabaseNameIndexConfigured,
  supabaseNameIndexQuery,
} = require('./_marketplace_db');

const ENDPOINT = '/api/searchbar-token-predict';
const DEFAULT_LIMIT = 5;
const MAX_LIMIT = 20;
const PREDICTION_CONTEXT_MAX_CANDIDATES = 20;
const PUBLIC_PREDICTION_CANDIDATE_ID_LIMIT = 24;
const PREDICTION_CONTEXT_CANDIDATE_ID_LIMIT = 32;
const CONTEXT_WEAK_MATCH_CONFIDENCE = 75;
const PREDICTION_CONTEXT_TTL_MS = 60_000;
const FIRST_CHAR_PREDICTION_CACHE_TTL_MS = 5 * 60_000;
const FIRST_CHAR_WARMUP_CACHE_TTL_MS = 5 * 60_000;
const DEFAULT_WARMUP_LIMIT = 1;
const MAX_WARMUP_LIMIT = 5;
const FIRST_CHAR_WARMUP_LETTERS = 'abcdefghijklmnopqrstuvwxyz'.split('');
const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Access-Control-Max-Age': '86400',
};
const firstCharPredictionCachesByQuery = new WeakMap();
const firstCharWarmupCachesByQuery = new WeakMap();
const EXPANSION_ALIAS_COMPLETIONS = [
  {
    display_token: 'HeartGold & SoulSilver',
    normalized_token: 'heartgoldsoulsilver',
    alias: 'heartgold',
    prefixes: ['h', 'he', 'hea', 'hear', 'heart', 'hearth', 'heartg', 'heartgo', 'heartgol', 'heartgold'],
  },
  {
    display_token: 'HeartGold & SoulSilver',
    normalized_token: 'heartgoldsoulsilver',
    alias: 'heart gold',
    prefixes: ['heart g', 'heart go', 'heart gol', 'heart gold'],
  },
  {
    display_token: 'HeartGold & SoulSilver',
    normalized_token: 'heartgoldsoulsilver',
    alias: 'hearth gold',
    prefixes: ['hearth g', 'hearth go', 'hearth gol', 'hearth gold'],
  },
  {
    display_token: 'HGSS',
    normalized_token: 'hgss',
    alias: 'hgss',
    prefixes: ['hg', 'hgs', 'hgss'],
  },
];
const WORD_PATTERN = /[A-Za-z0-9À-ÿ][A-Za-z0-9À-ÿ'’_.&()[\]\-]*/g;
const ANCHOR_MIN_CONFIDENCE = 60;
const anchorCachesByQuery = new WeakMap();
const MODIFIER_ONLY_ANCHOR_WORDS = new Set([
  'ex',
  'v',
  'vmax',
  'vstar',
  'gx',
  'lvx',
  'lv',
  'mega',
  'break',
  'radiant',
  'shining',
  'shiny',
  'prime',
  'tagteam',
]);

function setCorsHeaders(res) {
  for (const [key, value] of Object.entries(CORS_HEADERS)) {
    res.setHeader(key, value);
  }
}

function cleanTokenPredictLimit(value) {
  const cleaned = value === undefined || value === null || value === ''
    ? DEFAULT_LIMIT
    : cleanLimit(value);
  return Math.min(Math.max(cleaned, 1), MAX_LIMIT);
}

function cleanWarmupLimit(value) {
  const cleaned = value === undefined || value === null || value === ''
    ? DEFAULT_WARMUP_LIMIT
    : cleanLimit(value);
  return Math.min(Math.max(cleaned, 1), MAX_WARMUP_LIMIT);
}

function inputFromRequest(req) {
  const source = req.method === 'GET' ? req.query || {} : req.body || {};
  const rawQuery = source.fragment ??
    source.query ??
    source.search_term ??
    source.searchTerm ??
    source.current_token ??
    source.currentToken;
  const query = cleanSearchTerm(rawQuery);
  return {
    query,
    fragment: trailingTokenFragment(query),
    predictionFragment: predictionFragmentForQuery(query),
    searchLanguage: cleanLanguage(source.search_language ?? source.language ?? source.lang),
    limit: cleanTokenPredictLimit(source.limit ?? source.result_limit ?? source.resultLimit),
    previousPredictionContext: parsePredictionContext(
      source.previous_prediction_context ??
      source.previousPredictionContext ??
      source.prediction_context ??
      source.predictionContext,
    ),
    debug: source.debug === true || source.debug === 'true' || source.debug === '1' || source.debug === 1,
  };
}

function requestWantsWarmup(req) {
  const source = req.method === 'GET' ? req.query || {} : req.body || {};
  const mode = String(source.mode || source.intent || '').trim().toLowerCase();
  return mode === 'warmup' ||
    mode === 'first_char_warmup' ||
    source.warmup === true ||
    source.warmup === 'true' ||
    source.warmup === '1' ||
    source.first_char_warmup === true ||
    source.first_char_warmup === 'true' ||
    source.first_char_warmup === '1' ||
    source.firstCharWarmup === true ||
    source.firstCharWarmup === 'true' ||
    source.firstCharWarmup === '1';
}

function warmupInputFromRequest(req) {
  const source = req.method === 'GET' ? req.query || {} : req.body || {};
  return {
    searchLanguage: cleanLanguage(source.search_language ?? source.language ?? source.lang),
    limit: cleanWarmupLimit(source.limit ?? source.result_limit ?? source.resultLimit),
    debug: source.debug === true || source.debug === 'true' || source.debug === '1' || source.debug === 1,
  };
}

function parsePredictionContext(value) {
  if (!value) return null;
  if (typeof value === 'object' && !Array.isArray(value)) return value;
  try {
    const parsed = JSON.parse(String(value));
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed)
      ? parsed
      : null;
  } catch {
    return null;
  }
}

function trailingTokenFragment(value) {
  const text = cleanSearchTerm(value);
  const match = /([A-Za-z0-9À-ÿ][A-Za-z0-9À-ÿ'’_.&()[\]\-]*)\s*$/.exec(text);
  return cleanSearchTerm(match?.[1] || text);
}

function queryWords(value) {
  return cleanSearchTerm(value).match(WORD_PATTERN) || [];
}

function isAnchorPrefixCandidate(words) {
  if (words?.length === 1 && MODIFIER_ONLY_ANCHOR_WORDS.has(compact(words[0]))) {
    return false;
  }
  return (words || []).every((word) => {
    const normalized = compact(word);
    return normalized && !/^[0-9]+$/.test(normalized);
  });
}

function isModifierOnlyTrailingWords(words) {
  return Array.isArray(words) &&
    words.length > 0 &&
    words.every((word) => MODIFIER_ONLY_ANCHOR_WORDS.has(compact(word)));
}

function isVariationPrefixTrailingWords(words) {
  return Array.isArray(words) &&
    words.length > 0 &&
    words.every((word) => {
      const normalized = compact(word);
      if (!normalized) return false;
      if (normalized === 'g' || normalized === 'e') return true;
      if (MODIFIER_ONLY_ANCHOR_WORDS.has(normalized)) return true;
      return normalized.length >= 2 &&
        [...MODIFIER_ONLY_ANCHOR_WORDS].some((modifier) => modifier.startsWith(normalized));
    });
}

function predictionFragmentForQuery(value) {
  const text = cleanSearchTerm(value);
  const words = queryWords(text);
  if (words.length <= 1) {
    return trailingTokenFragment(text);
  }
  const nameWords = words.filter((word) => !/^[0-9]+$/.test(word));
  if (nameWords.length !== words.length || nameWords.length <= 1) {
    return trailingTokenFragment(text);
  }
  return cleanSearchTerm(nameWords.join(' '));
}

function anchoredAliasPredictionForQuery(value, anchor) {
  const words = queryWords(value);
  if (!anchor || words.length < 2) return null;
  const trailingWords = anchor.trailingWords || words.slice(anchor.prefixWordCount);
  for (let length = Math.min(2, trailingWords.length); length >= 1; length -= 1) {
    const fragment = cleanSearchTerm(trailingWords.slice(0, length).join(' '));
    const normalizedFragment = compact(fragment);
    if (!normalizedFragment) continue;
    const completion = EXPANSION_ALIAS_COMPLETIONS.find((entry) =>
      entry.prefixes.some((prefix) => compact(prefix) === normalizedFragment));
    if (!completion) continue;
    return {
      ...completion,
      anchor: anchor.display,
      fragment,
      normalizedFragment,
      confidence: normalizedFragment === compact(completion.alias) ? 100 : 96,
    };
  }
  return null;
}

function predictionFromExpansionAlias(aliasPrediction) {
  if (!aliasPrediction) return null;
  const score = 600000 + aliasPrediction.normalizedFragment.length * 1000;
  return {
    display_token: aliasPrediction.display_token,
    display: aliasPrediction.display_token,
    normalized_token: aliasPrediction.normalized_token,
    normalized: aliasPrediction.normalized_token,
    confidence: aliasPrediction.confidence,
    score,
    source_rank: 1,
    language: 'en',
    matched_prefix: aliasPrediction.normalizedFragment,
    card_count: 0,
    ids_count: 0,
    alias: aliasPrediction.alias,
    anchor: aliasPrediction.anchor,
    source: 'oracle_dimension_alias',
    token_type: 'dimension_alias',
    dimension: 'expansion',
  };
}

function predictionFragmentAlternates(value, primaryFragment) {
  const primary = cleanSearchTerm(primaryFragment);
  const words = queryWords(value);
  if (words.length <= 1) return [];
  const alternates = [];
  const seen = new Set([compact(primary)]);
  const wordEntries = words
    .map((word) => cleanSearchTerm(word))
    .filter((word) => word && !/^[0-9]+$/.test(word));
  for (let start = Math.max(0, wordEntries.length - 2); start < wordEntries.length; start += 1) {
    const fragment = cleanSearchTerm(wordEntries.slice(start).join(' '));
    const normalized = compact(fragment);
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    alternates.push(fragment);
  }
  for (const word of [...wordEntries].reverse()) {
    const normalized = compact(word);
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    alternates.push(word);
  }
  return alternates.slice(0, 3);
}

function candidateCardIdsFromPrediction(prediction, limit) {
  const ids = Array.isArray(prediction?.candidate_card_ids)
    ? prediction.candidate_card_ids
    : Array.isArray(prediction?.candidateCardIds)
      ? prediction.candidateCardIds
      : Array.isArray(prediction?.representative_card_ids)
        ? prediction.representative_card_ids
        : [];
  const cleanIds = [];
  const seen = new Set();
  for (const rawId of ids) {
    const id = String(rawId || '').trim();
    if (!id || seen.has(id)) continue;
    seen.add(id);
    cleanIds.push(id);
    if (cleanIds.length >= limit) break;
  }
  return cleanIds;
}

function publicPrediction(prediction, fallbackFragment) {
  const candidateIds = candidateCardIdsFromPrediction(
    prediction,
    PUBLIC_PREDICTION_CANDIDATE_ID_LIMIT,
  );
  const representativeIds = candidateIds.slice(0, 3);
  return {
    display_token: prediction.display_token || prediction.display || '',
    normalized_token: prediction.normalized_token || prediction.normalized || '',
    confidence: Number(prediction.confidence || 0),
    score: Number(prediction.score || 0),
    source_rank: Number(prediction.source_rank || 0),
    language: prediction.language || '',
    matched_prefix: prediction.matched_prefix || compact(fallbackFragment),
    card_count: Number(prediction.card_count || prediction.ids_count || candidateIds.length || representativeIds.length || 0),
    ids_count: Number(prediction.ids_count || candidateIds.length || representativeIds.length || 0),
    ...(prediction.source ? { source: prediction.source } : {}),
    ...(prediction.token_type ? { token_type: prediction.token_type } : {}),
    ...(prediction.dimension ? { dimension: prediction.dimension } : {}),
    ...(prediction.alias ? { alias: prediction.alias } : {}),
    ...(prediction.anchor ? { anchor: prediction.anchor } : {}),
    ...(representativeIds.length > 0 ? { representative_card_ids: representativeIds } : {}),
    ...(candidateIds.length > 0 ? { candidate_card_ids: candidateIds } : {}),
  };
}

function contextRepresentativeIds(prediction) {
  return candidateCardIdsFromPrediction(prediction, 8);
}

function publicContextCandidate(prediction, fallbackFragment, order) {
  if (prediction?.token_type === 'dimension_alias') return null;
  const candidateIds = candidateCardIdsFromPrediction(
    prediction,
    PREDICTION_CONTEXT_CANDIDATE_ID_LIMIT,
  );
  const representativeIds = contextRepresentativeIds(prediction);
  return {
    display_token: prediction.display_token || prediction.display || '',
    normalized_token: prediction.normalized_token || prediction.normalized || '',
    confidence: Number(prediction.confidence || 0),
    score: Number(prediction.score || 0),
    source_rank: Number(prediction.source_rank || order + 1),
    order,
    language: prediction.language || '',
    matched_prefix: prediction.matched_prefix || compact(fallbackFragment),
    card_count: Number(prediction.card_count || prediction.ids_count || candidateIds.length || representativeIds.length || 0),
    ids_count: Number(prediction.ids_count || candidateIds.length || representativeIds.length || 0),
    ...(representativeIds.length > 0 ? { representative_card_ids: representativeIds } : {}),
    ...(candidateIds.length > 0 ? { candidate_card_ids: candidateIds } : {}),
  };
}

function predictionContextFromTokens(input, predictionFragment, normalizedFragment, tokens, source) {
  const candidates = (tokens || [])
    .slice(0, PREDICTION_CONTEXT_MAX_CANDIDATES)
    .map((prediction, index) => publicContextCandidate(prediction, predictionFragment, index))
    .filter((candidate) => candidate?.display_token && candidate.normalized_token);
  return {
    query: input.query,
    fragment: input.fragment,
    prediction_fragment: predictionFragment,
    normalized_fragment: normalizedFragment,
    language: input.searchLanguage,
    depth: normalizedFragment.length,
    created_at_ms: Date.now(),
    source,
    candidates,
  };
}

function predictionContextCandidateFromJson(value, index) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const display = String(value.display_token ?? value.display ?? '').trim();
  const normalized = compact(value.normalized_token ?? value.normalized ?? display);
  if (!display || !normalized) return null;
  const candidateIds = Array.isArray(value.candidate_card_ids)
    ? value.candidate_card_ids.map((id) => String(id || '').trim()).filter(Boolean).slice(0, PREDICTION_CONTEXT_CANDIDATE_ID_LIMIT)
    : Array.isArray(value.candidateCardIds)
      ? value.candidateCardIds.map((id) => String(id || '').trim()).filter(Boolean).slice(0, PREDICTION_CONTEXT_CANDIDATE_ID_LIMIT)
      : [];
  const representativeIds = Array.isArray(value.representative_card_ids)
    ? value.representative_card_ids.map((id) => String(id || '').trim()).filter(Boolean).slice(0, 8)
    : candidateIds.slice(0, 8);
  return {
    display_token: display,
    display,
    normalized_token: normalized,
    normalized,
    confidence: Number(value.confidence || 0),
    score: Number(value.score || 0),
    source_rank: Number(value.source_rank || value.sourceRank || index + 1),
    order: Number(value.order ?? index),
    language: String(value.language || '').trim(),
    matched_prefix: String(value.matched_prefix || value.matchedPrefix || '').trim(),
    card_count: Number(value.card_count || value.cardCount || value.ids_count || value.idsCount || candidateIds.length || representativeIds.length || 0),
    ids_count: Number(value.ids_count || value.idsCount || candidateIds.length || representativeIds.length || 0),
    representative_card_ids: representativeIds,
    candidate_card_ids: candidateIds.length > 0 ? candidateIds : representativeIds,
  };
}

function cleanPreviousPredictionContext(value, input, normalizedFragment) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return { valid: false, reason: 'missing_context' };
  }
  const previousLanguage = cleanLanguage(value.language ?? value.search_language);
  if (previousLanguage !== input.searchLanguage) {
    return { valid: false, reason: 'language_changed' };
  }
  const previousFragment = compact(
    value.normalized_fragment ??
    value.normalizedFragment ??
    value.prediction_fragment ??
    value.predictionFragment ??
    value.fragment ??
    value.query,
  );
  if (!previousFragment || !normalizedFragment.startsWith(previousFragment) || normalizedFragment === previousFragment) {
    return { valid: false, reason: 'fragment_not_extended' };
  }
  const createdAtMs = Number(value.created_at_ms ?? value.createdAtMs ?? 0);
  if (!Number.isFinite(createdAtMs) || createdAtMs <= 0 || Date.now() - createdAtMs > PREDICTION_CONTEXT_TTL_MS) {
    return { valid: false, reason: 'context_expired' };
  }
  const rawCandidates = Array.isArray(value.candidates)
    ? value.candidates
    : Array.isArray(value.predictions)
      ? value.predictions
      : [];
  const candidates = rawCandidates
    .map(predictionContextCandidateFromJson)
    .filter(Boolean)
    .slice(0, PREDICTION_CONTEXT_MAX_CANDIDATES);
  if (candidates.length === 0) {
    return { valid: false, reason: 'empty_candidates' };
  }
  return {
    valid: true,
    previousFragment,
    candidates,
  };
}

function boundedDistance(left, right, maxDistance) {
  const a = String(left || '');
  const b = String(right || '');
  if (Math.abs(a.length - b.length) > maxDistance) return maxDistance + 1;
  let previous = Array.from({ length: b.length + 1 }, (_, index) => index);
  for (let i = 1; i <= a.length; i += 1) {
    const current = [i];
    let rowMin = current[0];
    for (let j = 1; j <= b.length; j += 1) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      const value = Math.min(
        current[j - 1] + 1,
        previous[j] + 1,
        previous[j - 1] + cost,
      );
      current[j] = value;
      rowMin = Math.min(rowMin, value);
    }
    if (rowMin > maxDistance) return maxDistance + 1;
    previous = current;
  }
  return previous[b.length];
}

function fuzzyDistanceLimit(normalizedFragment) {
  if (normalizedFragment.length <= 3) return 0;
  return normalizedFragment.length >= 6 ? 2 : 1;
}

function nearPrefixDistance(normalizedToken, normalizedFragment, maxDistance) {
  const lengths = new Set([
    normalizedFragment.length,
    normalizedFragment.length - 1,
    normalizedFragment.length + 1,
  ]);
  let best = maxDistance + 1;
  for (const length of lengths) {
    if (length <= 0) continue;
    best = Math.min(
      best,
      boundedDistance(
        normalizedToken.slice(0, Math.min(normalizedToken.length, length)),
        normalizedFragment,
        maxDistance,
      ),
    );
  }
  return best;
}

function rescoreContextCandidate(candidate, normalizedFragment) {
  const normalizedToken = candidate.normalized_token || candidate.normalized || compact(candidate.display_token);
  if (!normalizedToken || !normalizedFragment) return null;
  const baseScore = Number(candidate.score || 0);
  const sourceRank = Number(candidate.source_rank || candidate.order || 0);
  if (normalizedToken === normalizedFragment) {
    return {
      ...candidate,
      confidence: Math.max(Number(candidate.confidence || 0), 100),
      score: baseScore + 500000,
      matched_prefix: normalizedFragment,
    };
  }
  if (normalizedToken.startsWith(normalizedFragment)) {
    const confidence = Math.max(
      Number(candidate.confidence || 0),
      Math.max(76, 98 - Math.max(0, normalizedToken.length - normalizedFragment.length)),
    );
    return {
      ...candidate,
      confidence,
      score: baseScore + 300000 - sourceRank,
      matched_prefix: normalizedFragment,
    };
  }
  const maxDistance = fuzzyDistanceLimit(normalizedFragment);
  if (maxDistance > 0 && normalizedToken.startsWith(normalizedFragment.slice(0, 2))) {
    const distance = nearPrefixDistance(normalizedToken, normalizedFragment, maxDistance);
    if (distance <= maxDistance) {
      return {
        ...candidate,
        confidence: Math.max(Number(candidate.confidence || 0), 86 - distance * 7),
        score: baseScore + 160000 - distance * 25000 - sourceRank,
        matched_prefix: normalizedFragment,
        fuzzy_distance: distance,
      };
    }
  }
  return null;
}

function refineTokensFromPreviousContext(input, normalizedFragment) {
  const previous = cleanPreviousPredictionContext(
    input.previousPredictionContext,
    input,
    normalizedFragment,
  );
  if (!previous.valid) {
    return {
      tokens: null,
      meta: {
        used: false,
        reason: previous.reason,
      },
    };
  }
  const searchCount = normalizedFragment.length <= 3
    ? Math.max(1, Math.ceil(previous.candidates.length / 2))
    : previous.candidates.length;
  const searchedCandidates = previous.candidates.slice(0, searchCount);
  const refined = searchedCandidates
    .map((candidate) => rescoreContextCandidate(candidate, normalizedFragment))
    .filter(Boolean)
    .sort((left, right) =>
      Number(right.confidence || 0) - Number(left.confidence || 0) ||
      Number(right.score || 0) - Number(left.score || 0) ||
      Number(left.order || 0) - Number(right.order || 0) ||
      String(left.display_token || left.display).localeCompare(String(right.display_token || right.display)))
    .slice(0, PREDICTION_CONTEXT_MAX_CANDIDATES)
    .map((candidate, index) => ({
      ...candidate,
      display: candidate.display_token,
      normalized: candidate.normalized_token,
      source_rank: index + 1,
    }));
  return {
    tokens: refined,
    meta: {
      used: true,
      previous_candidate_count: previous.candidates.length,
      searched_candidate_count: searchedCandidates.length,
      matched_candidate_count: refined.length,
      mode: normalizedFragment.length > 3 ? 'context_fuzzy' : 'context_prefix_narrow',
    },
  };
}

function contextFallbackReason(contextRefinement) {
  if (!contextRefinement.tokens) return null;
  if (contextRefinement.tokens.length === 0) return 'no_context_matches';
  const topConfidence = Math.max(
    ...contextRefinement.tokens.map((token) => Number(token.confidence || 0)),
  );
  return topConfidence < CONTEXT_WEAK_MATCH_CONFIDENCE
    ? 'weak_context_matches'
    : null;
}

function predictionTokenKey(prediction) {
  return compact(
    prediction?.normalized_token ??
    prediction?.normalized ??
    prediction?.display_token ??
    prediction?.display,
  );
}

function firstCharCacheEntry(query, key) {
  const cache = firstCharPredictionCachesByQuery.get(query);
  if (!cache) return null;
  const entry = cache.get(key);
  if (!entry) return null;
  if (Date.now() - entry.createdAtMs > FIRST_CHAR_PREDICTION_CACHE_TTL_MS) {
    cache.delete(key);
    return null;
  }
  return entry;
}

function rememberFirstCharCacheEntry(query, key, result) {
  let cache = firstCharPredictionCachesByQuery.get(query);
  if (!cache) {
    cache = new Map();
    firstCharPredictionCachesByQuery.set(query, cache);
  }
  cache.set(key, {
    createdAtMs: Date.now(),
    source: result.source,
    tokens: (result.tokens || []).map((token) => ({
      ...token,
      representative_card_ids: Array.isArray(token.representative_card_ids)
        ? [...token.representative_card_ids]
        : undefined,
      candidate_card_ids: Array.isArray(token.candidate_card_ids)
        ? [...token.candidate_card_ids]
        : undefined,
    })),
  });
}

function firstCharWarmupCacheEntry(query, key) {
  const cache = firstCharWarmupCachesByQuery.get(query);
  if (!cache) return null;
  const entry = cache.get(key);
  if (!entry) return null;
  if (Date.now() - entry.createdAtMs > FIRST_CHAR_WARMUP_CACHE_TTL_MS) {
    cache.delete(key);
    return null;
  }
  return entry.payload;
}

function rememberFirstCharWarmupCacheEntry(query, key, payload) {
  let cache = firstCharWarmupCachesByQuery.get(query);
  if (!cache) {
    cache = new Map();
    firstCharWarmupCachesByQuery.set(query, cache);
  }
  cache.set(key, {
    createdAtMs: Date.now(),
    payload,
  });
}

function firstCharCacheKey(input, normalizedFragment) {
  if (normalizedFragment.length !== 1) return '';
  if (input.previousPredictionContext) return '';
  return `${input.searchLanguage || 'en'}:${normalizedFragment}`;
}

function clearFirstCharPredictionCacheForTest() {
  firstCharPredictionCachesByQuery.delete(supabaseNameIndexQuery);
  anchorCachesByQuery.delete(supabaseNameIndexQuery);
  firstCharWarmupCachesByQuery.delete(supabaseNameIndexQuery);
}

function clearFirstCharWarmupCacheForTest(query = supabaseNameIndexQuery) {
  firstCharWarmupCachesByQuery.delete(query);
}

async function firstCharWarmupRows(searchLanguage, perLetterLimit, query) {
  const result = await query(
    `
      with input as (
        select
          $1::text as language,
          least(greatest($2::integer, 1), 5) as per_letter_limit
      ),
      ranked as (
        select
          lower(substr(i.compact_name, 1, 1)) as letter,
          i.display_name,
          i.canonical_name,
          i.compact_name,
          i.language,
          greatest(
            coalesce(i.row_count, 0),
            coalesce(array_length(i.card_ids, 1), 0)
          )::integer as card_count,
          coalesce(array_length(i.card_ids, 1), 0)::integer as ids_count,
          least(
            100,
            greatest(72, 96 - greatest(length(i.compact_name) - 1, 0)) +
              least(
                8,
                case
                  when greatest(coalesce(i.row_count, 0), coalesce(array_length(i.card_ids, 1), 0)) > 1
                    then ln(greatest(coalesce(i.row_count, 0), coalesce(array_length(i.card_ids, 1), 0)) + 1) / ln(2) * 1.2
                  else 0
                end
              )
          )::real as confidence,
          (
            120000 +
            case when i.display_name = i.canonical_name then 800 else 0 end +
            least(greatest(i.search_weight, 0), 5000) +
            least(
              greatest(
                greatest(
                  coalesce(i.row_count, 0),
                  coalesce(array_length(i.card_ids, 1), 0)
                ),
                0
              ),
              1000
            ) * 900
          )::real as score,
          row_number() over (
            partition by lower(substr(i.compact_name, 1, 1))
            order by
              (
                120000 +
                case when i.display_name = i.canonical_name then 800 else 0 end +
                least(greatest(i.search_weight, 0), 5000) +
                least(
                  greatest(
                    greatest(
                      coalesce(i.row_count, 0),
                      coalesce(array_length(i.card_ids, 1), 0)
                    ),
                    0
                  ),
                  1000
                ) * 900
              ) desc,
              length(i.compact_name),
              i.display_name
          )::integer as source_rank
        from input
        join public.marketplace_card_name_tokens i
          on i.language = input.language
        where i.compact_name ~ '^[a-z]'
      )
      select *
      from ranked, input
      where ranked.source_rank <= input.per_letter_limit
      order by ranked.letter, ranked.source_rank
    `,
    [searchLanguage, perLetterLimit],
  );
  return result.rows || [];
}

async function firstCharWarmupRestRows(searchLanguage, perLetterLimit) {
  const rows = [];
  for (const letter of FIRST_CHAR_WARMUP_LETTERS) {
    const predictions = await supabaseRestPredictedNameTokens(
      letter,
      searchLanguage,
      perLetterLimit,
    );
    predictions.forEach((prediction, index) => {
      rows.push({
        ...prediction,
        letter,
        source_rank: index + 1,
      });
    });
  }
  return rows;
}

function firstCharWarmupSuggestionFromRow(row, requestedLanguage, sourceLanguage) {
  const display = String(
    row.canonical_name ||
    row.display_name ||
    row.display_token ||
    row.display ||
    '',
  ).trim();
  const normalized = compact(row.normalized_token || row.normalized || display) || compact(row.compact_name);
  const letter = compact(row.letter || row.matched_prefix || normalized.slice(0, 1));
  if (!display || !normalized || letter.length !== 1) return null;
  return {
    display_token: display,
    normalized_token: normalized,
    confidence: Number(row.confidence || 0),
    score: Number(row.score || 0),
    source_rank: Number(row.source_rank || 0),
    language: requestedLanguage,
    matched_prefix: letter,
    card_count: Number(row.card_count || row.ids_count || 0),
    ids_count: Number(row.ids_count || row.card_count || 0),
    source: 'first_char_warmup',
    ...(sourceLanguage !== requestedLanguage ? { source_language: sourceLanguage } : {}),
  };
}

function firstCharWarmupPayload(rows, input, sourceLanguage, meta = {}) {
  const byLetter = {};
  for (const row of rows || []) {
    const suggestion = firstCharWarmupSuggestionFromRow(row, input.searchLanguage, sourceLanguage);
    if (!suggestion) continue;
    const letter = suggestion.matched_prefix;
    if (!FIRST_CHAR_WARMUP_LETTERS.includes(letter)) continue;
    if (!byLetter[letter]) byLetter[letter] = [];
    if (byLetter[letter].length < input.limit) {
      byLetter[letter].push(suggestion);
    }
  }
  const suggestions = {};
  for (const letter of Object.keys(byLetter).sort()) {
    if (byLetter[letter].length > 0) {
      suggestions[letter] = byLetter[letter][0];
    }
  }
  return {
    ok: true,
    endpoint: ENDPOINT,
    mode: 'first_char_warmup',
    language: input.searchLanguage,
    source_language: sourceLanguage,
    generated_at_ms: Date.now(),
    limit: input.limit,
    suggestions,
    ...(input.limit > 1 ? { suggestion_lists: byLetter } : {}),
    meta: {
      source: 'supabase_postgres',
      model: 'marketplace_card_name_tokens',
      cache: { hit: false, ttl_ms: FIRST_CHAR_WARMUP_CACHE_TTL_MS },
      ...meta,
    },
  };
}

async function firstCharWarmupSuggestions(input, query = supabaseNameIndexQuery) {
  const normalizedLanguage = cleanLanguage(input.searchLanguage);
  const cleanInput = {
    searchLanguage: normalizedLanguage,
    limit: cleanWarmupLimit(input.limit),
  };
  const cacheKey = `${cleanInput.searchLanguage}:${cleanInput.limit}`;
  const cached = firstCharWarmupCacheEntry(query, cacheKey);
  if (cached) {
    return {
      ...cached,
      meta: {
        ...cached.meta,
        cache: { hit: true, ttl_ms: FIRST_CHAR_WARMUP_CACHE_TTL_MS },
      },
    };
  }
  const hasPostgresConfig = Boolean(supabaseNameIndexDatabaseUrl());
  const hasRestConfig = Boolean(process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY);
  if (query === supabaseNameIndexQuery && !hasPostgresConfig && !hasRestConfig) {
    const error = new Error('Supabase name-token index is not configured for first-char warmup.');
    error.statusCode = 503;
    error.code = 'SUPABASE_NAME_INDEX_NOT_CONFIGURED';
    throw error;
  }
  const loadRows = async (language) => {
    try {
      if (query !== supabaseNameIndexQuery || hasPostgresConfig) {
        return {
          source: 'supabase_postgres',
          rows: await firstCharWarmupRows(language, cleanInput.limit, query),
        };
      }
    } catch (error) {
      if (!hasRestConfig) throw error;
    }
    return {
      source: 'supabase_rest',
      rows: await firstCharWarmupRestRows(language, cleanInput.limit),
    };
  };
  const started = Date.now();
  const sourceLanguage = cleanInput.searchLanguage;
  const loaded = await loadRows(sourceLanguage);
  const rows = loaded.rows;
  const payload = firstCharWarmupPayload(rows, cleanInput, sourceLanguage, {
    source: loaded.source,
    duration_ms: Date.now() - started,
    row_count: rows.length,
    fallback_to_english: false,
  });
  rememberFirstCharWarmupCacheEntry(query, cacheKey, payload);
  return payload;
}

function anchorFromPrediction(prediction, words, prefixWordCount, source) {
  if (!prediction) return null;
  const prefix = cleanSearchTerm(words.slice(0, prefixWordCount).join(' '));
  const normalizedPrefix = compact(prefix);
  const normalizedPrediction = predictionTokenKey(prediction);
  const confidence = Number(prediction.confidence || 0);
  const matchedPrefix = compact(prediction.matched_prefix || prediction.matchedPrefix || '');
  if (
    !normalizedPrefix ||
    (
      normalizedPrediction !== normalizedPrefix &&
      !normalizedPrediction.startsWith(normalizedPrefix)
    ) ||
    (matchedPrefix && matchedPrefix !== normalizedPrefix) ||
    confidence < ANCHOR_MIN_CONFIDENCE
  ) {
    return null;
  }
  return {
    display: prediction.display_token || prediction.display || prefix,
    normalized: normalizedPrediction,
    confidence,
    prefix,
    prefixWordCount,
    trailingWords: words.slice(prefixWordCount),
    source,
  };
}

function anchorFromPreviousPredictionContext(input) {
  const words = queryWords(input.query);
  if (words.length < 2) return null;
  const candidates = Array.isArray(input.previousPredictionContext?.candidates)
    ? input.previousPredictionContext.candidates
    : [];
  for (let prefixWordCount = words.length - 1; prefixWordCount >= 1; prefixWordCount -= 1) {
    if (!isAnchorPrefixCandidate(words.slice(0, prefixWordCount))) continue;
    if (isModifierOnlyTrailingWords(words.slice(prefixWordCount))) continue;
    for (const candidate of candidates) {
      const anchor = anchorFromPrediction(
        predictionContextCandidateFromJson(candidate, 0),
        words,
        prefixWordCount,
        'previous_prediction_context',
      );
      if (anchor) return anchor;
    }
  }
  return null;
}

async function anchorFromSupabaseNamePrefixes(input, query) {
  const words = queryWords(input.query);
  if (words.length < 2) return null;
  for (let prefixWordCount = words.length - 1; prefixWordCount >= 1; prefixWordCount -= 1) {
    if (!isAnchorPrefixCandidate(words.slice(0, prefixWordCount))) continue;
    if (isModifierOnlyTrailingWords(words.slice(prefixWordCount))) continue;
    const prefix = cleanSearchTerm(words.slice(0, prefixWordCount).join(' '));
    const normalizedPrefix = compact(prefix);
    if (!normalizedPrefix) continue;
    let result;
    try {
      result = await fetchSupabasePredictionTokens(input, prefix, query);
    } catch {
      continue;
    }
    for (const prediction of result.tokens || []) {
      const anchor = anchorFromPrediction(
        prediction,
        words,
        prefixWordCount,
        'supabase_name_prefix',
      );
      if (anchor) return anchor;
    }
  }
  return null;
}

async function firstNameAnchorForQuery(input, query) {
  const cacheKey = `${input.searchLanguage || 'en'}:${compact(input.query)}`;
  let cache = anchorCachesByQuery.get(query);
  if (cache?.has(cacheKey)) {
    return cache.get(cacheKey);
  }
  const previousAnchor = anchorFromPreviousPredictionContext(input);
  const anchor = previousAnchor || await anchorFromSupabaseNamePrefixes(input, query);
  if (!cache) {
    cache = new Map();
    anchorCachesByQuery.set(query, cache);
  }
  cache.set(cacheKey, anchor);
  return anchor;
}

function mergePredictionTokens(primaryTokens, fallbackTokens) {
  const byToken = new Map();
  const add = (prediction) => {
    const key = predictionTokenKey(prediction);
    if (!key) return;
    const existing = byToken.get(key);
    if (
      !existing ||
      Number(prediction.confidence || 0) > Number(existing.confidence || 0) ||
      (
        Number(prediction.confidence || 0) === Number(existing.confidence || 0) &&
        Number(prediction.score || 0) > Number(existing.score || 0)
      )
    ) {
      byToken.set(key, prediction);
    }
  };
  (primaryTokens || []).forEach(add);
  (fallbackTokens || []).forEach(add);
  return [...byToken.values()]
    .sort((left, right) =>
      Number(right.confidence || 0) - Number(left.confidence || 0) ||
      Number(right.score || 0) - Number(left.score || 0) ||
      Number(left.source_rank || 0) - Number(right.source_rank || 0) ||
      String(left.display_token || left.display).localeCompare(String(right.display_token || right.display)))
    .slice(0, PREDICTION_CONTEXT_MAX_CANDIDATES)
    .map((prediction, index) => ({
      ...prediction,
      source_rank: index + 1,
    }));
}

async function fetchSupabasePredictionTokens(input, predictionFragment, query) {
  const normalizedFragment = compact(predictionFragment);
  const cacheKey = firstCharCacheKey(input, normalizedFragment);
  if (cacheKey) {
    const cached = firstCharCacheEntry(query, cacheKey);
    if (cached) {
      return {
        source: cached.source,
        tokens: cached.tokens,
        firstCharCache: {
          used: true,
          hit: true,
          ttl_ms: FIRST_CHAR_PREDICTION_CACHE_TTL_MS,
        },
      };
    }
  }
  const hasPostgresConfig = Boolean(supabaseNameIndexDatabaseUrl());
  const hasRestConfig = Boolean(process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY);
  if (query === supabaseNameIndexQuery && !hasPostgresConfig && !hasRestConfig) {
    const error = new Error('Supabase name-token index is not configured for token prediction.');
    error.statusCode = 503;
    error.code = 'SUPABASE_NAME_INDEX_NOT_CONFIGURED';
    throw error;
  }
  try {
    if (useMeiliSearchForLanguage(input.searchLanguage)) {
      try {
        const result = {
          source: 'meili_name_tokens',
          tokens: await meiliPredictedNameTokens(
            predictionFragment,
            input.searchLanguage,
            PREDICTION_CONTEXT_MAX_CANDIDATES,
          ),
        };
        if (cacheKey) rememberFirstCharCacheEntry(query, cacheKey, result);
        return {
          ...result,
          firstCharCache: cacheKey
            ? {
                used: true,
                hit: false,
                ttl_ms: FIRST_CHAR_PREDICTION_CACHE_TTL_MS,
              }
            : { used: false },
        };
      } catch (error) {
        console.error('meili token prediction failed, falling back to legacy token index', {
          message: error.message,
          code: error.code,
        });
      }
    }
    const result = {
      source: 'supabase_postgres',
      tokens: await supabasePredictedNameTokens(
        predictionFragment,
        input.searchLanguage,
        PREDICTION_CONTEXT_MAX_CANDIDATES,
        query,
      ),
    };
    if (cacheKey) rememberFirstCharCacheEntry(query, cacheKey, result);
    return {
      ...result,
      firstCharCache: cacheKey
        ? {
            used: true,
            hit: false,
            ttl_ms: FIRST_CHAR_PREDICTION_CACHE_TTL_MS,
          }
        : { used: false },
    };
  } catch (error) {
    if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_ROLE_KEY) {
      error.statusCode = error.statusCode || 503;
      throw error;
    }
    const result = {
      source: 'supabase_rest',
      tokens: await supabaseRestPredictedNameTokens(
        predictionFragment,
        input.searchLanguage,
        PREDICTION_CONTEXT_MAX_CANDIDATES,
      ),
    };
    if (cacheKey) rememberFirstCharCacheEntry(query, cacheKey, result);
    return {
      ...result,
      firstCharCache: cacheKey
        ? {
            used: true,
            hit: false,
            ttl_ms: FIRST_CHAR_PREDICTION_CACHE_TTL_MS,
          }
        : { used: false },
    };
  }
}

async function fetchSupabasePredictionTokensWithAlternates(input, predictionFragment, query) {
  const primaryResult = await fetchSupabasePredictionTokens(input, predictionFragment, query);
  if (primaryResult.tokens.length > 0) {
    return {
      ...primaryResult,
      alternateFragments: [],
    };
  }
  const alternates = predictionFragmentAlternates(input.query, predictionFragment);
  for (const alternateFragment of alternates) {
    const alternateResult = await fetchSupabasePredictionTokens(input, alternateFragment, query);
    if (alternateResult.tokens.length > 0) {
      return {
        ...alternateResult,
        source: `${alternateResult.source}_alternate_fragment`,
        firstCharCache: primaryResult.firstCharCache || alternateResult.firstCharCache,
        alternateFragments: [{
          fragment: alternateFragment,
          normalized_fragment: compact(alternateFragment),
          returned_candidate_count: alternateResult.tokens.length,
        }],
      };
    }
  }
  return {
    ...primaryResult,
    alternateFragments: alternates.map((fragment) => ({
      fragment,
      normalized_fragment: compact(fragment),
      returned_candidate_count: 0,
    })),
  };
}

async function predictNameTokens(input, query = supabaseNameIndexQuery) {
  const predictionFragment = cleanSearchTerm(input.predictionFragment || input.fragment);
  if (!predictionFragment || !compact(predictionFragment)) {
    return {
      ok: true,
      endpoint: ENDPOINT,
      query: input.query,
      fragment: input.fragment,
      normalized_fragment: '',
      search_language: input.searchLanguage,
      limit: input.limit,
      predictions: [],
      meta: { source: 'empty_fragment' },
    };
  }

  const normalizedFragment = compact(predictionFragment);
  const firstNameAnchor = await firstNameAnchorForQuery(input, query);
  const aliasPrediction = anchoredAliasPredictionForQuery(input.query, firstNameAnchor);
  const aliasToken = predictionFromExpansionAlias(aliasPrediction);
  const suppressTrailingNamePrediction = Boolean(firstNameAnchor?.trailingWords?.length) &&
    !isVariationPrefixTrailingWords(firstNameAnchor.trailingWords);
  const started = Date.now();
  let source = 'supabase_postgres';
  let tokens;
  let fullTableFallback = {
    used: false,
  };
  let firstCharCache = {
    used: false,
  };
  const contextRefinement = refineTokensFromPreviousContext(input, normalizedFragment);
  const fallbackReason = contextFallbackReason(contextRefinement);
  if (suppressTrailingNamePrediction) {
    tokens = aliasToken ? [aliasToken] : [];
    source = aliasToken ? 'anchored_dimension_alias' : 'anchored_first_name';
    fullTableFallback = {
      used: false,
      reason: 'first_name_anchor_established',
      anchor: {
        display: firstNameAnchor.display,
        normalized: firstNameAnchor.normalized,
        confidence: firstNameAnchor.confidence,
        source: firstNameAnchor.source,
      },
    };
  } else if (contextRefinement.tokens && !fallbackReason) {
    tokens = contextRefinement.tokens;
    source = contextRefinement.meta.mode;
  }
  if ((!tokens || fallbackReason) && !suppressTrailingNamePrediction) {
    const supabaseResult = await fetchSupabasePredictionTokensWithAlternates(input, predictionFragment, query);
    firstCharCache = supabaseResult.firstCharCache || firstCharCache;
    if (contextRefinement.tokens) {
      tokens = supabaseResult.tokens.length > 0
        ? mergePredictionTokens(supabaseResult.tokens, contextRefinement.tokens)
        : contextRefinement.tokens;
      source = `${contextRefinement.meta.mode}_with_${supabaseResult.source}_fallback`;
      fullTableFallback = {
        used: true,
        reason: fallbackReason,
        source: supabaseResult.source,
        returned_candidate_count: supabaseResult.tokens.length,
        alternate_fragments: supabaseResult.alternateFragments || [],
      };
    } else {
      tokens = supabaseResult.tokens;
      source = supabaseResult.source;
      fullTableFallback = {
        used: (supabaseResult.alternateFragments || []).length > 0,
        reason: supabaseResult.tokens.length > 0 ? 'primary_fragment_empty' : 'empty_primary_and_alternate_fragments',
        source: supabaseResult.source,
        returned_candidate_count: supabaseResult.tokens.length,
        alternate_fragments: supabaseResult.alternateFragments || [],
      };
    }
  }
  if (aliasToken && !suppressTrailingNamePrediction) {
    tokens = mergePredictionTokens([aliasToken], tokens || []);
    source = `anchored_expansion_alias_with_${source}`;
    fullTableFallback = {
      ...fullTableFallback,
      anchored_expansion_alias: {
        anchor: aliasPrediction.anchor,
        alias: aliasPrediction.alias,
        fragment: aliasPrediction.fragment,
        normalized_fragment: aliasPrediction.normalizedFragment,
      },
    };
  }
  const durationMs = Date.now() - started;
  const visibleTokens = tokens.slice(0, input.limit);
  const predictionContext = predictionContextFromTokens(
    input,
    predictionFragment,
    normalizedFragment,
    tokens,
    source,
  );
  return {
    ok: true,
    endpoint: ENDPOINT,
    query: input.query,
    fragment: input.fragment,
    prediction_fragment: predictionFragment,
    normalized_fragment: normalizedFragment,
    search_language: input.searchLanguage,
    limit: input.limit,
    predictions: visibleTokens.map((prediction) => publicPrediction(prediction, predictionFragment)),
    prediction_context: predictionContext,
    meta: {
      source,
      model: 'marketplace_card_name_tokens',
      duration_ms: durationMs,
      row_payload: 'tokens_only',
      context_refinement: contextRefinement.meta,
      full_table_fallback: fullTableFallback,
      first_char_cache: firstCharCache,
    },
  };
}

async function handler(req, res) {
  setCorsHeaders(res);
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }
  if (req.method !== 'GET' && req.method !== 'POST') {
    res.setHeader('Allow', 'GET, POST, OPTIONS');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  const input = inputFromRequest(req);
  try {
    if (requestWantsWarmup(req)) {
      const warmupInput = warmupInputFromRequest(req);
      const payload = await firstCharWarmupSuggestions(warmupInput);
      res.setHeader('Cache-Control', req.method === 'POST'
        ? 'no-store'
        : 'public, max-age=30, s-maxage=300');
      res.setHeader('Server-Timing', `first-char-warmup;dur=${payload.meta.duration_ms || 0}`);
      return res.status(200).json(warmupInput.debug ? payload : {
        ...payload,
        meta: {
          source: payload.meta.source,
          model: payload.meta.model,
          duration_ms: payload.meta.duration_ms,
          cache: payload.meta.cache,
        },
      });
    }
    const payload = await predictNameTokens(input);
    res.setHeader('Cache-Control', req.method === 'POST'
      ? 'no-store'
      : input.fragment
        ? 'public, max-age=5, s-maxage=30'
        : 'public, max-age=10, s-maxage=60');
    res.setHeader('Server-Timing', `token-predict;dur=${payload.meta.duration_ms || 0}`);
    return res.status(200).json(input.debug ? payload : {
      ...payload,
      meta: {
        source: payload.meta.source,
        model: payload.meta.model,
        duration_ms: payload.meta.duration_ms,
      },
    });
  } catch (error) {
    console.error('searchbar token predict failed', {
      message: error.message,
      code: error.code,
    });
    return res.status(error.statusCode || 500).json({
      ok: false,
      endpoint: ENDPOINT,
      query: input.query,
      fragment: input.fragment,
      normalized_fragment: compact(input.fragment),
      search_language: input.searchLanguage,
      predictions: [],
      error: error.code || 'TOKEN_PREDICT_FAILED',
      message: error.message || 'Token prediction failed.',
      ...(input.debug ? { debug: { code: error.code, reason: error.message } } : {}),
    });
  }
}

module.exports = handler;
module.exports.cleanTokenPredictLimit = cleanTokenPredictLimit;
module.exports.cleanWarmupLimit = cleanWarmupLimit;
module.exports.inputFromRequest = inputFromRequest;
module.exports.warmupInputFromRequest = warmupInputFromRequest;
module.exports.requestWantsWarmup = requestWantsWarmup;
module.exports.predictNameTokens = predictNameTokens;
module.exports.firstCharWarmupSuggestions = firstCharWarmupSuggestions;
module.exports.predictionFragmentForQuery = predictionFragmentForQuery;
module.exports.predictionFragmentAlternates = predictionFragmentAlternates;
module.exports.anchoredAliasPredictionForQuery = anchoredAliasPredictionForQuery;
module.exports.firstNameAnchorForQuery = firstNameAnchorForQuery;
module.exports.publicPrediction = publicPrediction;
module.exports.refineTokensFromPreviousContext = refineTokensFromPreviousContext;
module.exports.cleanPreviousPredictionContext = cleanPreviousPredictionContext;
module.exports.trailingTokenFragment = trailingTokenFragment;
module.exports.candidateCardIdsFromPrediction = candidateCardIdsFromPrediction;
module.exports.clearFirstCharPredictionCacheForTest = clearFirstCharPredictionCacheForTest;
module.exports.clearFirstCharWarmupCacheForTest = clearFirstCharWarmupCacheForTest;
