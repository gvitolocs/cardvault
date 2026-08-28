const { defaultIndexName, meiliConfigured, meiliSearch } = require('./_meili_client');

function cleanSearchTerm(value) {
  return String(value || '').trim().slice(0, 80);
}

function cleanLanguage(value) {
  const language = String(value || 'en').trim().toLowerCase();
  if (/^[a-z]{2}(?:-[a-z]{2})?$/.test(language)) {
    return language;
  }
  return 'en';
}

function foldDiacritics(value) {
  return String(value || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '');
}

function compact(value) {
  return foldDiacritics(value).toLowerCase().replace(/[^a-z0-9]/g, '');
}

function meiliMarketplaceIndexName() {
  return String(process.env.MEILI_MARKETPLACE_INDEX || defaultIndexName());
}

function meiliNameTokenIndexName() {
  return String(process.env.MEILI_NAME_TOKEN_INDEX || 'marketplace_name_tokens');
}

function meiliSearchLimit(value, fallback = 100, min = 1) {
  const limit = Number(value);
  if (!Number.isFinite(limit)) return fallback;
  return Math.min(Math.max(Math.trunc(limit), min), 1000);
}

function queryTokens(value) {
  return cleanSearchTerm(value)
    .split(/\s+/)
    .map((token) => compact(token))
    .filter(Boolean);
}

async function meiliMarketplaceCandidates(searchTerm, searchLanguage, limit, offset = 0) {
  if (!meiliConfigured()) {
    const error = new Error('Meilisearch is not configured for marketplace candidates.');
    error.code = 'MEILI_NOT_CONFIGURED';
    throw error;
  }
  const q = cleanSearchTerm(searchTerm);
  const tokens = queryTokens(q);
  const language = cleanLanguage(searchLanguage);
  const filter = [`language = "${language}"`];
  const response = await meiliSearch(meiliMarketplaceIndexName(), {
    q,
    limit: meiliSearchLimit(limit, 120),
    offset: meiliSearchLimit(offset, 0, 0),
    showRankingScore: true,
    attributesToRetrieve: ['card_id', '_rankingScore'],
    attributesToHighlight: [],
    ...(tokens.length > 0 ? { facets: ['language'] } : {}),
    filter,
  });
  return (response.hits || []).map((hit, index) => ({
    card_id: String(hit.card_id || ''),
    meili_rank: Number(hit._rankingScore || 0),
    meili_position: index + 1,
  })).filter((row) => row.card_id);
}

async function meiliPredictedNameTokens(fragment, searchLanguage, limit = 20) {
  if (!meiliConfigured()) {
    const error = new Error('Meilisearch is not configured for name-token predictions.');
    error.code = 'MEILI_NOT_CONFIGURED';
    throw error;
  }
  const q = cleanSearchTerm(fragment);
  const normalized = compact(q);
  const language = cleanLanguage(searchLanguage);
  const response = await meiliSearch(meiliNameTokenIndexName(), {
    q,
    limit: meiliSearchLimit(limit, 20),
    showRankingScore: true,
    filter: [`language = "${language}"`],
    attributesToRetrieve: [
      'display_token',
      'normalized_token',
      'language',
      'card_count',
      'candidate_card_ids',
      '_rankingScore',
    ],
  });
  return (response.hits || []).map((hit, index) => ({
    display_token: String(hit.display_token || ''),
    normalized_token: compact(hit.normalized_token || hit.display_token || ''),
    confidence: Math.max(60, Math.round(Number(hit._rankingScore || 0) * 100)),
    score: Number(hit._rankingScore || 0) * 100000,
    source_rank: index + 1,
    language,
    matched_prefix: normalized,
    card_count: Number(hit.card_count || 0),
    ids_count: Array.isArray(hit.candidate_card_ids) ? hit.candidate_card_ids.length : 0,
    candidate_card_ids: Array.isArray(hit.candidate_card_ids)
      ? hit.candidate_card_ids.slice(0, 24).map((id) => String(id))
      : [],
    source: 'meili_name_token',
  })).filter((row) => row.display_token && row.normalized_token);
}

module.exports = {
  meiliMarketplaceIndexName,
  meiliNameTokenIndexName,
  meiliMarketplaceCandidates,
  meiliPredictedNameTokens,
};
