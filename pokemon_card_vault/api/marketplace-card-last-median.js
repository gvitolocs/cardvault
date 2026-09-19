const {
  lastMedianPayload,
  readOracleLastMedian,
  soldSliceFromSearchParams,
} = require('./marketplace-card-sales');

const MAX_BATCH_IDS = 40;

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Access-Control-Max-Age': '86400',
};

function setCorsHeaders(res) {
  for (const [key, value] of Object.entries(CORS_HEADERS)) {
    res.setHeader(key, value);
  }
}

function cleanCardId(value) {
  const text = String(value || '').trim();
  if (!/^[0-9]+$/.test(text)) {
    return '';
  }
  const id = Number(text);
  return Number.isSafeInteger(id) && id > 0 ? String(id) : '';
}

function uniqueCardIds(req) {
  const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
  const ids = [];
  const seen = new Set();
  const add = (value) => {
    const id = cleanCardId(value);
    if (!id || seen.has(id) || ids.length >= MAX_BATCH_IDS) {
      return;
    }
    seen.add(id);
    ids.push(id);
  };
  add(url.searchParams.get('cardId') || url.searchParams.get('blueprintId'));
  String(url.searchParams.get('cardIds') || '')
    .split(',')
    .forEach(add);
  return ids;
}

module.exports = async function handler(req, res) {
  setCorsHeaders(res);
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET, OPTIONS');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const cardIds = uniqueCardIds(req);
    if (!cardIds.length) {
      return res.status(400).json({ error: 'cardId is required.' });
    }
    const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
    const slice = soldSliceFromSearchParams(url.searchParams);
    const prices = await Promise.all(cardIds.map((cardId) => readOracleLastMedian({
      cardId,
      ...slice,
    })));
    const first = prices[0] || lastMedianPayload(cardIds[0], null, slice);
    res.setHeader('Cache-Control', 'public, max-age=20, s-maxage=120');
    return res.status(200).json({
      card_id: first.card_id,
      day: first.day,
      median_pkn: first.median_pkn,
      sample_count: first.sample_count,
      currency: 'PKN',
      source: 'cardtrader_removed_sale',
      condition: first.condition,
      language: first.language,
      reverse: first.reverse,
      firstEdition: first.firstEdition,
      graded: first.graded,
      prices,
    });
  } catch (error) {
    console.error('marketplace-card-last-median failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Marketplace last-day median failed.',
    });
  }
};

module.exports.cleanCardId = cleanCardId;
module.exports.uniqueCardIds = uniqueCardIds;
module.exports.setCorsHeaders = setCorsHeaders;
module.exports.MAX_BATCH_IDS = MAX_BATCH_IDS;
