const { marketplaceQuery } = require('./_marketplace_db');
const { slugPart } = require('./_slug');
const {
  canonicalCardUrlForLookup,
} = require('./marketplace-card-url');
const {
  cleanCardId,
  publicCardIdForRow,
  cleanCollectorNumber,
  canonicalSlugForRow,
  canonicalPathForRow,
} = require('./_marketplace_canonical_path');

function rootPathIdWithSlug(value) {
  let pathname = String(value || '').trim();
  if (!pathname) {
    return 0;
  }
  try {
    pathname = new URL(pathname, 'https://pokoin.com').pathname;
  } catch (_) {
    pathname = pathname.split(/[?#]/)[0];
  }
  const match = pathname.match(/^\/(\d+)\/([^/]+)\/?$/);
  if (!match || !String(match[2] || '').trim()) {
    return 0;
  }
  return cleanCardId(match[1]);
}

async function canonicalPathForCardId(cardId, query = marketplaceQuery) {
  const cleanId = cleanCardId(cardId);
  if (!cleanId) {
    return '';
  }
  const canonicalLookup = await canonicalCardUrlForLookup({ cardId: cleanId }, query);
  if (canonicalLookup?.canonicalPath) {
    return canonicalLookup.canonicalPath;
  }
  const result = await query(
    `
      select
        card_id,
        canonical_path,
        name,
        set_name,
        card_number,
        rarity
      from public.marketplace_card_urls
      where (card_id = $1::bigint or public_number = $1::bigint or ct_id = $1::bigint)
        and language = 'en'
      order by (card_id = $1::bigint) desc
      limit 1
    `,
    [cleanId],
  );
  const row = result.rows[0];
  if (!row) {
    return '';
  }
  return canonicalPathForRow(row);
}

async function canonicalPathForShortlinkPath(path, language, query = marketplaceQuery) {
  const canonicalLookup = await canonicalCardUrlForLookup({
    path,
    language,
  }, query);
  if (canonicalLookup?.canonicalPath) {
    return canonicalLookup.canonicalPath;
  }

  const rootId = rootPathIdWithSlug(path);
  if (!rootId || rootId % 2 !== 0) {
    return '';
  }
  const doubledRootLookup = await canonicalCardUrlForLookup({
    path,
    language,
    urlCardId: String(rootId),
  }, query);
  return doubledRootLookup?.canonicalPath || '';
}

function createHandler({ query = marketplaceQuery } = {}) {
  return async function handler(req, res) {
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      res.setHeader('Allow', 'GET, HEAD');
      return res.status(405).json({ error: 'Method not allowed.' });
    }

    try {
      const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
      const cardId = cleanCardId(url.searchParams.get('cardId'));
      const language = url.searchParams.get('language') || url.searchParams.get('lang');
      const requestedPath = url.searchParams.get('path');
      const path = requestedPath
        ? await canonicalPathForShortlinkPath(requestedPath, language, query)
        : await canonicalPathForCardId(cardId, query);
      if (!path) {
        return res.status(404).json({ error: 'Card shortlink not found.' });
      }
      res.setHeader('Cache-Control', 'public, max-age=60, s-maxage=300');
      res.setHeader('Location', path);
      return res.status(302).end();
    } catch (error) {
      console.error('marketplace-card-shortlink failed', error);
      return res.status(error.statusCode || 500).json({
        error: error.message || 'Marketplace card shortlink failed.',
      });
    }
  };
}

module.exports = createHandler();

module.exports.canonicalPathForRow = canonicalPathForRow;
module.exports.canonicalSlugForRow = canonicalSlugForRow;

module.exports._test = {
  canonicalPathForCardId,
  canonicalPathForShortlinkPath,
  canonicalPathForRow,
  canonicalSlugForRow,
  cleanCardId,
  publicCardIdForRow,
  slugPart,
  cleanCollectorNumber,
  createHandler,
};
