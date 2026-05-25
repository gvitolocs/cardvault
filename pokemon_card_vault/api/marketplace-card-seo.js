const {
  cardIdFromDoubledId,
  resolveCardRoute,
  rowsForVersions,
} = require('./marketplace-card-versions');

const BOT_CACHE_CONTROL = 'public, max-age=60, s-maxage=300, stale-while-revalidate=600';
const DEFAULT_IMAGE = 'https://pokoin.com/pokoin-project-banner-1360x430.png';
const ROOT_CARD_ROUTE_PATTERN = /^\/(\d+)(?:\/([^/?#]+))?\/?$/;
const DEFAULT_LANGUAGE = 'en';
const CARD_IMAGE_ORIGIN = 'https://pokoin.com';
const CARD_IMAGE_PREFIX = '/card-images';
const CDN_IMAGE_HOST = 'cdn.pokoin.com';

function escapeHtml(value) {
  return String(value || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function absoluteUrl(req, value) {
  const text = String(value || '').trim();
  if (!text) return '';
  try {
    return new URL(text).toString();
  } catch (_) {
    const host = req.headers.host || 'pokoin.com';
    return new URL(text.startsWith('/') ? text : `/${text}`, `https://${host}`).toString();
  }
}

function firstNonEmpty(...values) {
  return values.map((value) => String(value || '').trim()).find(Boolean) || '';
}

function cardImageProxyUrl(pathname, search = '') {
  let imagePath = String(pathname || '').trim();
  if (!imagePath) return '';
  if (!imagePath.startsWith('/')) {
    imagePath = `/${imagePath}`;
  }
  while (imagePath === CARD_IMAGE_PREFIX || imagePath.startsWith(`${CARD_IMAGE_PREFIX}/`)) {
    imagePath = imagePath.slice(CARD_IMAGE_PREFIX.length) || '/';
  }
  return new URL(`${CARD_IMAGE_PREFIX}${imagePath}${search}`, CARD_IMAGE_ORIGIN).toString();
}

function publicCardImageUrl(value) {
  const clean = String(value || '').trim();
  if (!clean) return '';
  try {
    const url = new URL(clean);
    if (url.hostname === CDN_IMAGE_HOST) {
      return cardImageProxyUrl(url.pathname, url.search);
    }
    if (
      url.hostname === 'pokoin.com' &&
      (url.pathname === CARD_IMAGE_PREFIX || url.pathname.startsWith(`${CARD_IMAGE_PREFIX}/`))
    ) {
      return cardImageProxyUrl(url.pathname, url.search);
    }
    return clean;
  } catch (_) {
    if (clean === CARD_IMAGE_PREFIX || clean.startsWith(`${CARD_IMAGE_PREFIX}/`)) {
      return cardImageProxyUrl(clean);
    }
    if (clean.startsWith('card-images/')) {
      return cardImageProxyUrl(`/${clean}`);
    }
    return clean;
  }
}

function preferredCardImage(row = {}) {
  return publicCardImageUrl(firstNonEmpty(
    row.cdn_image_url,
    row.image_url,
    row.homepage_image_url,
    row.preview_image_url,
    DEFAULT_IMAGE,
  ));
}

function imageTypeForUrl(value) {
  const clean = String(value || '').trim().toLowerCase().split(/[?#]/)[0];
  if (clean.endsWith('.jpg') || clean.endsWith('.jpeg')) return 'image/jpeg';
  if (clean.endsWith('.png')) return 'image/png';
  if (clean.endsWith('.webp')) return 'image/webp';
  if (clean.endsWith('.gif')) return 'image/gif';
  return '';
}

function slugPart(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function canonicalSlugForCard(row = {}) {
  const parts = [
    firstNonEmpty(row.rarity, 'Card'),
    row.name,
    firstNonEmpty(row.expansion_number, row.card_number),
    firstNonEmpty(row.expansion_name, row.set_name),
  ];
  return parts.map(slugPart).filter(Boolean).join('-');
}

function canonicalPathForCard(row = {}) {
  const storedPath = String(row.canonical_path || row.canonicalPath || '').trim();
  if (storedPath.startsWith('/marketplace/') && storedPath.includes('/cards/')) {
    return storedPath;
  }
  const id = String(row.card_id || row.id || '').trim();
  const slug = canonicalSlugForCard(row);
  const numericId = Number(id);
  if (!Number.isSafeInteger(numericId) || numericId <= 0 || !slug) {
    return '';
  }
  return `/marketplace/${DEFAULT_LANGUAGE}/cards/${numericId * 2}/${slug}`;
}

function cardTitle(row) {
  const name = firstNonEmpty(row.name, 'Pokémon card');
  const suffix = [row.expansion_name, row.expansion_number]
    .map((value) => String(value || '').trim())
    .filter(Boolean)
    .join(' ');
  return suffix ? `${name} - ${suffix} | Pokoin Card Reserve` : `${name} | Pokoin Card Reserve`;
}

function cardDescription(row) {
  const name = firstNonEmpty(row.name, 'this Pokémon card');
  const setName = firstNonEmpty(row.expansion_name, row.set_name);
  const details = [row.rarity, row.expansion_number, setName].filter(Boolean).join(' - ');
  const detailSentence = details ? `${name} (${details})` : name;
  return `Buy now ${detailSentence}. Pokoin Card Reserve offers a safe and collector-friendly way to browse Pokémon cards, compare seller listings, and use PKN wallet settlement.`;
}

function htmlForCard(req, row, canonicalPath) {
  const canonicalUrl = absoluteUrl(req, canonicalPath);
  const imageUrl = absoluteUrl(req, preferredCardImage(row));
  const title = cardTitle(row);
  const description = cardDescription(row);
  const escapedTitle = escapeHtml(title);
  const escapedDescription = escapeHtml(description);
  const escapedImage = escapeHtml(imageUrl);
  const escapedImageType = escapeHtml(imageTypeForUrl(imageUrl));
  const escapedCanonical = escapeHtml(canonicalUrl);

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="description" content="${escapedDescription}">
  <meta name="robots" content="index, follow, max-image-preview:large, max-snippet:-1">
  <link rel="canonical" href="${escapedCanonical}">
  <meta property="og:type" content="product">
  <meta property="og:site_name" content="Pokoin Card Reserve">
  <meta property="og:title" content="${escapedTitle}">
  <meta property="og:description" content="${escapedDescription}">
  <meta property="og:url" content="${escapedCanonical}">
  <meta property="og:image" content="${escapedImage}">
  <meta property="og:image:secure_url" content="${escapedImage}">
  ${escapedImageType ? `<meta property="og:image:type" content="${escapedImageType}">` : ''}
  <meta property="og:image:width" content="734">
  <meta property="og:image:height" content="1024">
  <meta property="og:image:alt" content="${escapeHtml(firstNonEmpty(row.name, 'Pokoin card image'))}">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${escapedTitle}">
  <meta name="twitter:description" content="${escapedDescription}">
  <meta name="twitter:image" content="${escapedImage}">
  <meta name="twitter:image:alt" content="${escapeHtml(firstNonEmpty(row.name, 'Pokoin card image'))}">
  <link rel="icon" href="/favicon.ico" sizes="any">
  <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png">
  <link rel="manifest" href="/manifest.json">
  <title>${escapedTitle}</title>
</head>
<body>
  <main>
    <h1>${escapedTitle}</h1>
    <p>${escapedDescription}</p>
    <p><a href="${escapedCanonical}">Open this card on Pokoin Card Reserve</a></p>
    <img src="${escapedImage}" alt="${escapeHtml(firstNonEmpty(row.name, 'Pokoin card'))}" style="max-width: 320px; height: auto;">
  </main>
  <script src="/seo-bootstrap.js" defer></script>
</body>
</html>`;
}

function parseCardRoute(url) {
  const rewrittenCardPath = url.searchParams.get('cardPath');
  if (rewrittenCardPath) {
    const parts = ['marketplace', url.searchParams.get('language') || 'en', 'cards']
      .concat(String(rewrittenCardPath).split('/').filter(Boolean));
    return parseMarketplaceCardParts(parts);
  }

  const queryCardId = String(url.searchParams.get('cardId') || '').trim();
  const queryCardSlug = String(
    url.searchParams.get('cardSlug') || url.searchParams.get('slug') || '',
  ).trim();
  if (/^\d+$/.test(queryCardId)) {
    return {
      cardId: queryCardId,
      cardSlug: queryCardSlug,
    };
  }

  const rootCardRoute = url.pathname.match(ROOT_CARD_ROUTE_PATTERN);
  if (rootCardRoute) {
    return {
      cardId: rootCardRoute[1],
      cardSlug: decodeURIComponent(rootCardRoute[2] || ''),
    };
  }

  const parts = url.pathname.split('/').filter(Boolean);
  return parseMarketplaceCardParts(parts);
}

function parseMarketplaceCardParts(parts) {
  const cardsIndex = parts.indexOf('cards');
  if (cardsIndex < 0 || cardsIndex + 1 >= parts.length) {
    return { cardId: '', cardSlug: '' };
  }
  const firstSegment = decodeURIComponent(parts[cardsIndex + 1] || '');
  const restParts = parts.slice(cardsIndex + 2)
    .filter((part) => part && part !== 'versions');
  const restSlug = decodeURIComponent(restParts.join('-'));
  const numericPrefix = firstSegment.match(/^(\d+)(?:-(.*))?$/);
  if (numericPrefix) {
    const numericId = numericPrefix[1];
    const inlineSlug = numericPrefix[2] || '';
    const cardSlug = restSlug || inlineSlug;
    if (restSlug) {
      return {
        ...resolveCardRoute({
          cardSlug,
          doubledCardId: numericId,
        }),
        decodedFromDoubledId: true,
      };
    }
    if (inlineSlug) {
      return {
        ...resolveCardRoute({
          cardSlug,
          cardId: numericId,
        }),
        legacyNumericSlug: true,
      };
    }
    return {
      cardId: numericId,
      cardSlug,
      legacyIdOnly: true,
    };
  }
  return {
    cardId: '',
    cardSlug: [firstSegment, restSlug].filter(Boolean).join('-'),
  };
}

async function rowsForCardPreview(route, fetchRowsForVersions = rowsForVersions) {
  if (route.decodedFromDoubledId && route.cardId) {
    const authoritativeRows = await fetchRowsForVersions({
      cardId: route.cardId,
      limit: 1,
      searchLanguage: DEFAULT_LANGUAGE,
    });
    if (authoritativeRows.length > 0) {
      return authoritativeRows;
    }
  }

  const rows = await fetchRowsForVersions({
    cardId: route.cardId,
    cardSlug: route.cardSlug,
    limit: 1,
    searchLanguage: DEFAULT_LANGUAGE,
  });
  if (rows.length > 0 || !route.cardId || !route.cardSlug) {
    return rows;
  }

  // Older root links can contain CardTrader-style text that does not match the
  // current canonical slug exactly. The numeric card id is still authoritative.
  const idOnlyRows = await fetchRowsForVersions({
    cardId: route.cardId,
    limit: 1,
    searchLanguage: DEFAULT_LANGUAGE,
  });
  if (idOnlyRows.length > 0) {
    return idOnlyRows;
  }

  const decodedRootUrlId = cardIdFromDoubledId(route.cardId);
  if (!decodedRootUrlId || decodedRootUrlId === route.cardId) {
    return [];
  }
  return fetchRowsForVersions({
    cardId: decodedRootUrlId,
    cardSlug: route.cardSlug,
    limit: 1,
    searchLanguage: DEFAULT_LANGUAGE,
  });
}

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).send('Method not allowed');
  }

  try {
    const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
    const route = parseCardRoute(url);
    const rows = await rowsForCardPreview(route);
    const card = rows[0];
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Cache-Control', BOT_CACHE_CONTROL);
    if (!card) {
      return res.status(404).send(htmlForCard(req, {
        name: 'Pokoin Card Reserve',
        preview_image_url: DEFAULT_IMAGE,
      }, url.pathname));
    }

    return res.status(200).send(
      htmlForCard(req, card, canonicalPathForCard(card) || url.pathname),
    );
  } catch (error) {
    console.error('marketplace-card-seo failed', error);
    return res.status(500).send('Marketplace card preview failed.');
  }
};

module.exports.parseCardRoute = parseCardRoute;
module.exports.cardDescription = cardDescription;
module.exports.cardTitle = cardTitle;
module.exports.canonicalPathForCard = canonicalPathForCard;
module.exports.canonicalSlugForCard = canonicalSlugForCard;
module.exports.cardIdFromDoubledId = cardIdFromDoubledId;
module.exports.preferredCardImage = preferredCardImage;
module.exports.publicCardImageUrl = publicCardImageUrl;
module.exports.htmlForCard = htmlForCard;
module.exports.rowsForCardPreview = rowsForCardPreview;
