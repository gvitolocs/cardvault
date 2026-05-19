const { marketplaceQuery } = require('./_marketplace_db');

const SEARCH_RPC_V2 = 'search_marketplace_blueprint_candidates_v2';

function cleanSearchTerm(value) {
  return String(value || '').trim().slice(0, 80);
}

function cleanLimit(value) {
  const limit = Number(value);
  if (!Number.isFinite(limit)) {
    return 20;
  }
  return Math.min(Math.max(Math.trunc(limit), 1), 15874);
}

function cleanOffset(value) {
  const offset = Number(value);
  if (!Number.isFinite(offset)) {
    return 0;
  }
  return Math.min(Math.max(Math.trunc(offset), 0), 15874);
}

function cleanLanguage(value) {
  const language = String(value || 'en').trim().toLowerCase();
  if (/^[a-z]{2}(?:-[a-z]{2})?$/.test(language)) {
    return language;
  }
  return 'en';
}

async function searchWithDatabase(searchTerm, resultLimit, resultOffset, searchLanguage = 'en') {
  const result = await marketplaceQuery(
    `select * from public.${SEARCH_RPC_V2}($1, $2, $3, $4)`,
    [searchTerm, resultLimit, resultOffset, cleanLanguage(searchLanguage)],
  );
  return result.rows;
}

async function rowsForSearchTerm(searchTerm, resultLimit, resultOffset = 0, searchLanguage = 'en') {
  return searchWithDatabase(searchTerm, resultLimit, resultOffset, searchLanguage);
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const searchTerm = cleanSearchTerm(req.body?.search_term ?? req.body?.searchTerm);
    const resultLimit = cleanLimit(req.body?.result_limit ?? req.body?.limit);
    const resultOffset = cleanOffset(req.body?.result_offset ?? req.body?.offset);
    const searchLanguage = cleanLanguage(req.body?.search_language ?? req.body?.language);
    if (!searchTerm) {
      return res.status(200).json([]);
    }

    const started = Date.now();
    const rows = await rowsForSearchTerm(searchTerm, resultLimit, resultOffset, searchLanguage);
    res.setHeader('Cache-Control', 'public, max-age=5, s-maxage=20');
    res.setHeader('Server-Timing', `search;dur=${Date.now() - started}`);
    return res.status(200).json(rows);
  } catch (error) {
    console.error('marketplace-search-candidates failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Marketplace search candidate fetch failed.',
    });
  }
};

module.exports.rowsForSearchTerm = rowsForSearchTerm;
module.exports.cleanSearchTerm = cleanSearchTerm;
module.exports.cleanLimit = cleanLimit;
module.exports.cleanLanguage = cleanLanguage;
