const {
  analyticsBoostsForRows,
  cleanAutocompletePoolLimit,
  rankAutocompleteEntries,
  rowsForAutocompleteSearchTerm,
  scoreExplanation,
} = require('./marketplace-autocomplete');
const {
  cleanLanguage,
  cleanLimit,
  cleanSearchTerm,
} = require('./marketplace-search-candidates');

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Access-Control-Max-Age': '86400',
};
const POKOIN_BASE_URL = 'https://pokoin.com';

function setCorsHeaders(res) {
  for (const [key, value] of Object.entries(CORS_HEADERS)) {
    res.setHeader(key, value);
  }
}

function cleanText(value, maxLength = 80) {
  return String(value || '').trim().replace(/\s+/g, ' ').slice(0, maxLength);
}

function isIllustratorCredit(value) {
  const text = cleanText(value, 120);
  return /^illus\.?(?:\s|:|$)/i.test(text) ||
    /^illustrator(?:\s|:|$)/i.test(text) ||
    /^artist(?:\s|:|$)/i.test(text);
}

function cleanSearchableCardField(value, maxLength = 80) {
  if (isIllustratorCredit(value)) return '';
  return cleanText(value, maxLength);
}

function cleanRarityAliases(value) {
  const aliases = Array.isArray(value)
    ? value
    : Array.isArray(value?.aliases)
      ? value.aliases
      : [];
  const cleaned = aliases
    .map((alias) => cleanSearchableCardField(alias, 60))
    .filter(Boolean);
  return [...new Set(cleaned)].slice(0, 6);
}

function cleanExtensionQuery(value) {
  return cleanSearchTerm(cleanText(value, 240)
    .replace(/\billus\.?(?:\s*:?\s*)[a-z][a-z .'-]{1,80}$/i, ' ')
    .replace(/\billustrator(?:\s*:?\s*)[a-z][a-z .'-]{1,80}$/i, ' ')
    .replace(/\bartist(?:\s*:?\s*)[a-z][a-z .'-]{1,80}$/i, ' '));
}

function cleanedParts(rawParts = {}) {
  const rarityAliases = cleanRarityAliases(
    rawParts.rarityAliases ?? rawParts.rarity_aliases ?? rawParts.cardRarityAliases,
  );
  const parts = {
    name: cleanText(rawParts.name ?? rawParts.cardName ?? rawParts.pokemonName),
    collectorNumber: cleanText(
      rawParts.collectorNumber ??
        rawParts.collectionNumber ??
        rawParts.number ??
        rawParts.cardNumber,
      40,
    ),
    expansion: cleanText(
      rawParts.expansion ??
        rawParts.expansionName ??
        rawParts.set ??
        rawParts.setName,
    ),
    rarity: cleanSearchableCardField(rawParts.rarity ?? rawParts.cardRarity, 60),
    variation: cleanSearchableCardField(
      rawParts.variation ?? rawParts.variant ?? rawParts.cardVariant,
      60,
    ),
  };
  if (rarityAliases.length > 0) {
    parts.rarityAliases = rarityAliases;
  }
  return parts;
}

function compactPart(value) {
  return cleanText(value)
    .replace(/\bcard\b/gi, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function buildExtensionSearchTerm(body = {}) {
  const parts = cleanedParts(body);
  const explicitQuery = cleanExtensionQuery(body.search_term ?? body.searchTerm ?? body.query);
  if (explicitQuery) {
    return {
      searchTerm: explicitQuery,
      searchTerms: searchTermVariants(explicitQuery, parts),
      parts,
      source: 'query',
    };
  }
  const tokens = [
    compactPart(parts.name),
    compactPart(parts.variation),
    compactPart(parts.collectorNumber),
    compactPart(parts.expansion),
    compactPart(parts.rarity),
  ].filter(Boolean);
  const searchTerm = cleanSearchTerm(tokens.join(' '));
  return {
    searchTerm,
    searchTerms: searchTermVariants(searchTerm, parts),
    parts,
    source: 'structured_fields',
  };
}

function searchTermVariants(searchTerm, parts = {}) {
  const base = cleanSearchTerm(searchTerm);
  const variants = base ? [base] : [];
  const aliases = parts.rarityAliases || [];
  if (aliases.length > 0) {
    const stem = [
      compactPart(parts.name),
      compactPart(parts.variation),
      compactPart(parts.collectorNumber),
      compactPart(parts.expansion),
    ].filter(Boolean).join(' ');
    const source = cleanSearchTerm(stem || base);
    for (const alias of aliases) {
      const aliasTerm = cleanSearchTerm([source, compactPart(alias)].filter(Boolean).join(' '));
      if (aliasTerm) variants.push(aliasTerm);
    }
  }
  return [...new Set(variants)].slice(0, 8);
}

function slugPart(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function cleanCollectorNumberForSlug(value) {
  return cleanText(value, 80)
    .split('|')
    .map((part) => part.trim())
    .filter(Boolean)
    .pop() || '';
}

function doubledCardId(value) {
  const id = String(value || '').trim();
  if (!/^[0-9]+$/.test(id)) return '';
  const parsed = BigInt(id);
  if (parsed <= BigInt(0)) return '';
  return String(parsed * BigInt(2));
}

function marketplacePathForRow(row, language = 'en') {
  const cardId = String(row.card_id || row.id || '');
  const doubledId = doubledCardId(cardId);
  const cleanLanguage = slugPart(language) || 'en';
  const cleanSlugPart = (part) => {
    const slug = slugPart(part);
    return slug === 'trading-card' ? '' : slug;
  };
  const slug = [
    row.rarity || 'Card',
    row.name,
    cleanCollectorNumberForSlug(row.card_number),
    row.set_name,
  ].map(cleanSlugPart).filter(Boolean).join('-');
  if (!doubledId || !slug) return '';
  return `/marketplace/${cleanLanguage}/cards/${doubledId}/${slug}`;
}

function matchFromEntry(entry, language = 'en') {
  const row = entry.row;
  const marketplacePath = marketplacePathForRow(row, language);
  const marketplaceUrl = marketplacePath ? `${POKOIN_BASE_URL}${marketplacePath}` : '';
  return {
    cardId: String(row.card_id || row.id || ''),
    name: row.name || '',
    expansionName: row.set_name || '',
    collectorNumber: row.card_number || '',
    rarity: row.rarity || '',
    cardType: row.card_type || '',
    itemKind: row.item_kind || '',
    productType: row.product_type || '',
    trainerName: row.trainer_name || '',
    imageUrl: row.cdn_image_url || row.image_url || '',
    previewImageUrl: row.preview_image_url || row.cdn_image_url || row.image_url || '',
    cardPalette: row.card_palette || {},
    emoji: row.emoji || '',
    marketplacePath,
    marketplaceUrl,
    canonicalPath: marketplacePath,
    canonicalUrl: marketplaceUrl,
    score: entry.score,
    relevanceScore: entry.relevanceScore,
    analyticsBoost: entry.analyticsBoost,
  };
}

async function searchExtensionCard(body = {}) {
  const { searchTerm, searchTerms, parts, source } = buildExtensionSearchTerm(body);
  const limit = cleanLimit(body.limit ?? body.result_limit ?? body.resultLimit ?? 8);
  const resultLimit = Math.min(limit, 50);
  const poolLimit = cleanAutocompletePoolLimit(body.pool_limit ?? body.poolLimit ?? 420);
  const language = cleanLanguage(body.language ?? body.search_language ?? body.lang);
  const wantsDebug = body.debug === true || body.debug === '1';
  if (!searchTerm) {
    return {
      query: searchTerm,
      input: parts,
      source,
      language,
      matches: [],
      ...(wantsDebug ? { debug: { reason: 'empty_search_term' } } : {}),
    };
  }

  const candidateDebug = wantsDebug ? { steps: [] } : null;
  const candidateStarted = Date.now();
  const rowGroups = await Promise.all(searchTerms.map((term) =>
    rowsForAutocompleteSearchTerm(
      term,
      poolLimit,
      language,
      candidateDebug,
      null,
    )));
  const rowsById = new Map();
  for (const rowsForTerm of rowGroups) {
    for (const row of rowsForTerm) {
      const id = String(row.card_id || row.id || '');
      if (id && !rowsById.has(id)) rowsById.set(id, row);
    }
  }
  const rows = [...rowsById.values()];
  const candidateDurationMs = Date.now() - candidateStarted;
  const analyticsStarted = Date.now();
  const analyticsBoosts = await analyticsBoostsForRows(rows);
  const analyticsDurationMs = Date.now() - analyticsStarted;
  const rankStarted = Date.now();
  const rankedEntries = rankAutocompleteEntries(rows, searchTerm, resultLimit, analyticsBoosts);
  const rankDurationMs = Date.now() - rankStarted;

  return {
    query: searchTerm,
    input: parts,
    source,
    language,
    matches: rankedEntries.map((entry) => matchFromEntry(entry, language)),
    ...(wantsDebug ? {
      debug: {
        searchTerms,
        candidateRows: rows.length,
        boostedRows: analyticsBoosts.size,
        candidateDurationMs,
        analyticsDurationMs,
        rankDurationMs,
        candidateDebug,
        ranked: rankedEntries.slice(0, 12).map((entry) => ({
          ...scoreExplanation(entry.row, searchTerm),
          score: entry.score,
          relevanceScore: entry.relevanceScore,
          analyticsBoost: entry.analyticsBoost,
        })),
      },
    } : {}),
  };
}

module.exports = async function handler(req, res) {
  setCorsHeaders(res);
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST, OPTIONS');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const started = Date.now();
    const payload = await searchExtensionCard(req.body || {});
    const durationMs = Date.now() - started;
    res.setHeader('Cache-Control', 'public, max-age=5, s-maxage=30');
    res.setHeader('Server-Timing', `extension-card-search;dur=${durationMs}`);
    return res.status(200).json(payload);
  } catch (error) {
    console.error('extension-card-search failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Extension card search failed.',
    });
  }
};

module.exports.buildExtensionSearchTerm = buildExtensionSearchTerm;
module.exports.cleanExtensionQuery = cleanExtensionQuery;
module.exports.isIllustratorCredit = isIllustratorCredit;
module.exports.marketplacePathForRow = marketplacePathForRow;
module.exports.searchExtensionCard = searchExtensionCard;
