const { marketplaceQuery } = require('./_marketplace_db');
const { slugPart } = require('./_slug');
const {
  canonicalCardUrlForLookup,
} = require('./marketplace-card-url');

function cleanCardId(value) {
  const id = Number(String(value || '').trim());
  return Number.isSafeInteger(id) && id > 0 ? id : 0;
}

function cleanCollectorNumber(value, cardId) {
  const text = String(value || '')
    .trim()
    .replace(/^#+\s*/, '');
  if (!text || text === String(cardId || '').trim()) {
    return '';
  }
  return text;
}

function canonicalSlugForRow(row = {}) {
  const parts = [
    String(row.rarity || '').trim() || 'Card',
    row.display_name || row.canonical_name || row.name,
    cleanCollectorNumber(row.card_number, row.card_id),
    row.set_name,
  ];
  return parts.map(slugPart).filter(Boolean).join('-');
}

function canonicalPathForRow(row = {}) {
  const storedPath = String(row.canonical_path || row.canonicalPath || '').trim();
  if (storedPath.startsWith('/marketplace/') && storedPath.includes('/cards/')) {
    return storedPath;
  }
  const cleanId = cleanCardId(row.card_id);
  const slug = canonicalSlugForRow(row);
  return cleanId && slug ? `/marketplace/en/cards/${cleanId * 2}/${slug}` : '';
}

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
      where card_id = $1::bigint
        and language = 'en'
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

module.exports._test = {
  canonicalPathForCardId,
  canonicalPathForShortlinkPath,
  canonicalPathForRow,
  canonicalSlugForRow,
  cleanCardId,
  slugPart,
  cleanCollectorNumber,
  createHandler,
};
