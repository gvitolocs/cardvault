const { marketplaceQuery } = require('./_marketplace_db');

const MEMORY_CACHE_TTL_MS = 30 * 1000;
let cachedSnapshot = null;
let cachedSnapshotAt = 0;

function normalizeCardImages(card) {
  return {
    ...card,
    imageUrl: normalizeImageUrl(card.imageUrl),
    previewImageUrl: normalizeImageUrl(card.previewImageUrl || card.imageUrl),
  };
}

function isCardTraderImageUrl(value) {
  try {
    return new URL(String(value || '')).hostname === 'cardtrader.com';
  } catch (_) {
    return false;
  }
}

function hasCdnBackedImages(card) {
  const imageUrl = String(card.imageUrl || '').trim();
  const previewImageUrl = String(card.previewImageUrl || card.imageUrl || '').trim();
  return Boolean(imageUrl) &&
    Boolean(previewImageUrl) &&
    !isCardTraderImageUrl(imageUrl) &&
    !isCardTraderImageUrl(previewImageUrl);
}

function normalizeSections(sections = {}) {
  const recentlySeenIds = Array.isArray(sections.recentlySeenIds)
    ? sections.recentlySeenIds
    : [];
  const bestSellerIds = Array.isArray(sections.bestSellerIds)
    ? sections.bestSellerIds
    : [];
  const featuredIds = Array.isArray(sections.featuredIds)
    ? sections.featuredIds
    : [];
  return {
    recentlySeenIds,
    bestSellerIds,
    featuredIds:
      featuredIds.length > 0
        ? featuredIds
        : bestSellerIds.length > 0
          ? bestSellerIds
          : recentlySeenIds,
  };
}

function normalizeImageUrl(value) {
  const text = String(value || '').trim();
  if (!text) {
    return '';
  }
  try {
    const url = new URL(text);
    if (url.hostname !== 'cdn.pokoin.com') {
      return text;
    }
    return `/card-images${url.pathname}${url.search}`;
  } catch (_) {
    return text;
  }
}

function toCardJson(row) {
  return {
    id: String(row.card_id ?? ''),
    name: row.name || '',
    imageUrl: row.cdn_image_url || row.image_url || '',
    previewImageUrl: row.preview_image_url || row.cdn_image_url || row.image_url || '',
    rarity: row.rarity || 'Card',
    type: row.card_type || 'Trading card',
    set: row.set_name || 'Pokemon',
    number: row.item_kind === 'product'
      ? (row.product_variant || row.version || '')
      : (row.card_number || String(row.card_id ?? '')),
    itemKind: row.item_kind || 'single',
    productType: row.product_type || 'card',
    trainerName: row.trainer_name || '',
    cardPalette: row.card_palette || null,
    emoji: row.emoji || '',
    price: Number(1000n + (BigInt(row.card_id || 0) % 120000n)),
    stock: 0,
    rating: 0,
    reviewCount: 0,
    isFoil: false,
    isHolo: String(row.rarity || '').toLowerCase().includes('holo'),
    tags: [row.set_name, row.rarity, row.card_type, row.trainer_name].filter(Boolean),
    condition: 'NM',
    isGraded: false,
  };
}

async function fetchMissingSectionCards(sectionIds, existingIds) {
  const missingIds = sectionIds
    .map((id) => Number(id))
    .filter((id) => Number.isSafeInteger(id) && id > 0 && !existingIds.has(String(id)));
  if (missingIds.length === 0) {
    return [];
  }
  const result = await marketplaceQuery(
    `
      select
        card_id, name, image_url, cdn_image_url, preview_image_url,
        set_name, rarity, card_type, card_number, product_variant,
        item_kind, product_type, trainer_name, card_palette, emoji
      from public.marketplace_search_candidates
      where card_id = any($1::bigint[])
    `,
    [missingIds],
  );
  return result.rows.map(toCardJson);
}

async function fetchSnapshot() {
  const now = Date.now();
  if (cachedSnapshot && now - cachedSnapshotAt < MEMORY_CACHE_TTL_MS) {
    return cachedSnapshot;
  }
  const result = await marketplaceQuery(
    'select public.get_marketplace_home_snapshot($1) as snapshot',
    [120],
  );
  const snapshot = result.rows[0]?.snapshot || { cards: [], sections: {} };

  const cards = Array.isArray(snapshot.cards)
    ? snapshot.cards.map(normalizeCardImages).filter(hasCdnBackedImages)
    : [];
  const cardIds = new Set(cards.map((card) => String(card.id)));
  const sections = normalizeSections(snapshot.sections);
  const sectionIds = [
    ...sections.recentlySeenIds,
    ...sections.bestSellerIds,
    ...sections.featuredIds,
  ];
  const sectionCards = (await fetchMissingSectionCards(sectionIds, cardIds))
    .map(normalizeCardImages)
    .filter(hasCdnBackedImages);
  for (const card of sectionCards) {
    if (!cardIds.has(String(card.id))) {
      cardIds.add(String(card.id));
      cards.push(card);
    }
  }
  const normalized = {
    ...snapshot,
    cards,
    sections: {
      recentlySeenIds: sections.recentlySeenIds.filter((id) => cardIds.has(String(id))),
      bestSellerIds: sections.bestSellerIds.filter((id) => cardIds.has(String(id))),
      featuredIds: sections.featuredIds.filter((id) => cardIds.has(String(id))),
    },
  };
  cachedSnapshot = normalized;
  cachedSnapshotAt = now;
  return normalized;
}

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const snapshot = await fetchSnapshot();
    res.setHeader(
      'Cache-Control',
      'public, max-age=10, s-maxage=30, stale-while-revalidate=60',
    );
    return res.status(200).json(snapshot);
  } catch (error) {
    console.error('marketplace-home failed', error);
    return res.status(500).json({ error: 'Marketplace home failed.' });
  }
};
