const { marketplaceQuery } = require('./_marketplace_db');
const { slugParts } = require('./_slug');
const { cardIdFromDoubledId } = require('./marketplace-card-versions');

const LEGACY_URL_ID_CARD_ID_OVERRIDES = {
  // This public number was shipped for Drifloon before the direct-id lookup fix;
  // it now collides with a different real card id (Nacli).
  248768: '124384',
};

function cleanLanguage(value) {
  const language = String(value || 'en').trim().toLowerCase();
  return /^[a-z]{2}(?:-[a-z]{2})?$/.test(language) ? language : 'en';
}

function cleanCardId(value) {
  const id = Number(String(value || '').trim());
  return Number.isSafeInteger(id) && id > 0 ? String(id) : '';
}

function cleanCanonicalPath(value) {
  const path = String(value || '').trim();
  if (!path.startsWith('/marketplace/') || !path.includes('/cards/')) {
    return '';
  }
  return path.split(/[?#]/)[0];
}

function canonicalSlugFromPath(value) {
  const path = cleanCanonicalPath(value);
  if (!path) {
    return '';
  }
  const parts = path.split('/').filter(Boolean);
  const cardsIndex = parts.indexOf('cards');
  if (cardsIndex < 0 || cardsIndex + 2 >= parts.length) {
    return '';
  }
  return parts.slice(cardsIndex + 2).join('-');
}

function slugsEquivalent(left, right) {
  const leftParts = slugParts(left);
  const rightParts = slugParts(right);
  return leftParts.length > 0 &&
    rightParts.length > 0 &&
    leftParts.join('-') === rightParts.join('-');
}

function publicNumberFromCanonicalPath(value) {
  const path = cleanCanonicalPath(value);
  const match = path.match(/\/cards\/(\d+)(?:\/|$)/);
  return match ? match[1] : '';
}

function parseRootCardPath(value) {
  const text = String(value || '').trim();
  if (!text) {
    return { cardId: '', cardSlug: '' };
  }
  let pathname = text;
  try {
    pathname = new URL(text, 'https://pokoin.com').pathname;
  } catch (_) {
    pathname = text.split(/[?#]/)[0];
  }
  const match = pathname.match(/^\/(\d+)(?:\/([^/]+))?\/?$/);
  if (!match) {
    return { cardId: '', cardSlug: '' };
  }
  return {
    cardId: cleanCardId(match[1]),
    cardSlug: decodeURIComponent(match[2] || '').trim(),
  };
}

function parseMarketplaceCardPath(value) {
  const text = String(value || '').trim();
  if (!text) {
    return { language: '', doubledCardId: '', cardSlug: '' };
  }
  let pathname = text;
  try {
    pathname = new URL(text, 'https://pokoin.com').pathname;
  } catch (_) {
    pathname = text.split(/[?#]/)[0];
  }
  const match = pathname.match(
    /^\/marketplace\/([a-z]{2}(?:-[a-z]{2})?)\/cards\/(\d+)(?:\/(.+))?\/?$/i,
  );
  if (!match) {
    return { language: '', doubledCardId: '', cardSlug: '' };
  }
  return {
    language: cleanLanguage(match[1]),
    doubledCardId: cleanCardId(match[2]),
    cardSlug: decodeURIComponent(match[3] || '').trim(),
  };
}

function candidateCardIdsForLookup({ cardId, cardSlug, path, doubledCardId, urlCardId } = {}) {
  const marketplacePath = parseMarketplaceCardPath(path);
  const cleanDirectCardId = cleanCardId(cardId);
  const legacyOverride = LEGACY_URL_ID_CARD_ID_OVERRIDES[cleanDirectCardId];
  const explicitDoubledId =
    cleanCardId(doubledCardId) ||
    cleanCardId(urlCardId) ||
    marketplacePath.doubledCardId;
  const decodedDoubledId = (explicitDoubledId && (marketplacePath.cardSlug || doubledCardId || urlCardId))
    ? cardIdFromDoubledId(explicitDoubledId)
    : '';
  const routeCardId = legacyOverride || cleanDirectCardId || decodedDoubledId || parseRootCardPath(path).cardId;
  const candidates = [];
  if (routeCardId) {
    candidates.push(routeCardId);
  }
  return [...new Set(candidates)];
}

async function canonicalCardUrlForLookup(
  { cardId, cardSlug, path, language, doubledCardId, urlCardId } = {},
  query = marketplaceQuery,
) {
  const cleanDirectCardId = cleanCardId(cardId);
  const candidateIds = candidateCardIdsForLookup({
    cardId,
    cardSlug,
    path,
    doubledCardId,
    urlCardId,
  });
  if (candidateIds.length === 0) {
    return null;
  }
  const cleanLang = cleanLanguage(language || parseMarketplaceCardPath(path).language);
  const requestedSlug =
    String(cardSlug || parseMarketplaceCardPath(path).cardSlug || parseRootCardPath(path).cardSlug || '').trim();
  const numericCandidateIds = candidateIds.map((id) => Number(id));
  const requestedUrlId = cleanCardId(
    doubledCardId || urlCardId || parseMarketplaceCardPath(path).doubledCardId,
  );
  const decodedRequestedUrlId = cardIdFromDoubledId(requestedUrlId);
  const result = await query(
    `
      select card_id, language, canonical_path
      from public.marketplace_card_urls
      where (
          card_id = any($1::bigint[])
          or ($3::text <> '' and canonical_path like '%/cards/' || $3::text || '/%')
        )
        and language = $2
      order by
        case
          when $3::text <> '' and canonical_path like '%/cards/' || $3::text || '/%' then 0
          else 1
        end,
        array_position($1::bigint[], card_id)
    `,
    [numericCandidateIds, cleanLang, requestedUrlId],
  );
  const canonicalPathSegment = `/cards/${requestedUrlId}/`;
  const pathMatchedRow = requestedUrlId
    ? result.rows.find((row) => cleanCanonicalPath(row.canonical_path).includes(canonicalPathSegment))
    : null;
  if (pathMatchedRow) {
    const pathMatchedCanonical = cleanCanonicalPath(pathMatchedRow.canonical_path);
    const pathMatchedSlug = canonicalSlugFromPath(pathMatchedCanonical);
    if (
      requestedSlug &&
      pathMatchedSlug &&
      decodedRequestedUrlId &&
      !slugsEquivalent(requestedSlug, pathMatchedSlug)
    ) {
      const rowByDecodedId = result.rows.find((row) => String(row.card_id || '') === decodedRequestedUrlId);
      if (rowByDecodedId && cleanCanonicalPath(rowByDecodedId.canonical_path)) {
        return {
          cardId: String(rowByDecodedId.card_id),
          language: rowByDecodedId.language || cleanLang,
          canonicalPath: cleanCanonicalPath(rowByDecodedId.canonical_path),
          publicNumber: publicNumberFromCanonicalPath(rowByDecodedId.canonical_path),
        };
      }
    }
    return {
      cardId: String(pathMatchedRow.card_id),
      language: pathMatchedRow.language || cleanLang,
      canonicalPath: pathMatchedCanonical,
      publicNumber: publicNumberFromCanonicalPath(pathMatchedRow.canonical_path),
    };
  }
  const rowById = new Map(
    result.rows
      .filter((row) => cleanCanonicalPath(row.canonical_path))
      .map((row) => [String(row.card_id || ''), row]),
  );
  for (const id of candidateIds) {
    const row = rowById.get(id);
    if (row) {
      return {
        cardId: String(row.card_id),
        language: row.language || cleanLang,
        canonicalPath: cleanCanonicalPath(row.canonical_path),
        publicNumber: publicNumberFromCanonicalPath(row.canonical_path),
      };
    }
  }
  return null;
}

function createHandler({ query = marketplaceQuery } = {}) {
  return async function handler(req, res) {
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      res.setHeader('Allow', 'GET, HEAD');
      return res.status(405).json({ error: 'Method not allowed.' });
    }

    try {
      const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
      const lookup = await canonicalCardUrlForLookup({
        cardId: url.searchParams.get('cardId'),
        cardSlug: url.searchParams.get('cardSlug') || url.searchParams.get('slug'),
        path: url.searchParams.get('path'),
        language: url.searchParams.get('language') || url.searchParams.get('lang'),
        doubledCardId: url.searchParams.get('doubledCardId'),
        urlCardId: url.searchParams.get('urlCardId'),
      }, query);
      if (!lookup) {
        return res.status(404).json({ error: 'Marketplace card URL not found.' });
      }
      res.setHeader('Cache-Control', 'public, max-age=60, s-maxage=300');
      if (req.method === 'HEAD') {
        return res.status(200).end();
      }
      return res.status(200).json(lookup);
    } catch (error) {
      console.error('marketplace-card-url failed', error);
      return res.status(error.statusCode || 500).json({
        error: error.message || 'Marketplace card URL lookup failed.',
      });
    }
  };
}

module.exports = createHandler();

module.exports.canonicalCardUrlForLookup = canonicalCardUrlForLookup;

module.exports._test = {
  candidateCardIdsForLookup,
  canonicalCardUrlForLookup,
  cleanCanonicalPath,
  cleanCardId,
  cleanLanguage,
  createHandler,
  canonicalSlugFromPath,
  parseMarketplaceCardPath,
  publicNumberFromCanonicalPath,
  parseRootCardPath,
  slugsEquivalent,
};
