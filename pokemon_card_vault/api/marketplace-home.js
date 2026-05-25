const { marketplaceQuery } = require('./_marketplace_db');
const { withCardEmojiFields } = require('./_marketplace_card_emoji');
const {
  cardTraderAvailabilityJoin,
  cheapestHomepageCacheRelationName,
} = require('./marketplace-cards');
const {
  watchlistAnalyticsJoin,
  watchlistCountColumn,
  watchlistCountFromRow,
} = require('./_marketplace_watchlist_analytics');
const {
  cartAnalyticsJoin,
  cartHolderCountColumn,
  cartHolderCountFromRow,
} = require('./_marketplace_cart_analytics');

const MEMORY_CACHE_TTL_MS = 30 * 1000;
const HOT_REFRESH_INTERVAL = '2 minutes';
let cachedSnapshot = null;
let cachedSnapshotAt = 0;

function collectorNumberFromImageUrl(value) {
  const text = String(value || '');
  const match = text.match(/([0-9]{1,4}[A-Za-z]?)[-/]([0-9]{1,4})(?![0-9])/);
  return match ? `${match[1]}/${match[2]}` : '';
}

function cleanCollectorNumber(value) {
  return String(value || '').trim().replace(/^#+\s*/, '');
}

function hasCollectorNumber(value) {
  return /(^|[^0-9])[0-9]{1,4}[A-Za-z]?\/[0-9]{1,4}([^0-9]|$)/.test(
    String(value || '').trim(),
  );
}

function projectedCollectorNumber(row) {
  const explicit = String(
    row.card_number ||
      row.expansion_number ||
      row.number ||
      '',
  ).trim();
  if (explicit) {
    return cleanCollectorNumber(explicit);
  }
  return collectorNumberFromImageUrl(
    row.cdn_image_url ||
      row.image_url ||
      row.homepage_image_url ||
      row.preview_image_url,
  );
}

function projectedRarity(row) {
  const candidate = String(row.rarity || '').trim();
  const blueprint = String(
    row.blueprint_rarity ||
      row.collector_rarity ||
      row.pokemon_rarity ||
      '',
  ).trim();
  if (candidate && candidate.toLowerCase() !== 'card') {
    return candidate;
  }
  return blueprint || candidate || 'Card';
}

function normalizeCardImages(card) {
  return {
    ...card,
    imageUrl: normalizeImageUrl(card.imageUrl),
    previewImageUrl: normalizeImageUrl(card.previewImageUrl || card.imageUrl),
    homepageImageUrl: normalizeImageUrl(card.homepageImageUrl || card.previewImageUrl || card.imageUrl),
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
  const homepageImageUrl = String(card.homepageImageUrl || card.previewImageUrl || card.imageUrl || '').trim();
  return Boolean(imageUrl) &&
    Boolean(previewImageUrl) &&
    Boolean(homepageImageUrl) &&
    !isCardTraderImageUrl(imageUrl) &&
    !isCardTraderImageUrl(previewImageUrl) &&
    !isCardTraderImageUrl(homepageImageUrl);
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

function cardTilePrice(row) {
  const cardTraderPrice = Number(row.cardtrader_lowest_price_pkn ?? row.cardtraderLowestPricePkn);
  if (Number.isFinite(cardTraderPrice) && cardTraderPrice > 0) {
    return cardTraderPrice;
  }
  const listedPrice = Number(row.price ?? row.lowest_price_pkn);
  if (Number.isFinite(listedPrice) && listedPrice > 0) {
    return listedPrice;
  }
  return Number(1000n + (BigInt(row.card_id || 0) % 120000n));
}

function hasCardTraderAvailability(row = {}) {
  if (row.hasCardTraderListing === true || row.has_cardtrader_listing === true) {
    return true;
  }
  const count = Number(
    row.cardtraderEligibleListingCount ??
      row.cardtrader_eligible_listing_count ??
      0,
  );
  if (Number.isFinite(count) && count > 0) {
    return true;
  }
  const quantity = Number(
    row.cardtrader_listed_quantity ??
      row.cardtraderListedQuantity ??
      0,
  );
  return Number.isFinite(quantity) && quantity > 0;
}

function cardTileStock(row) {
  const explicitStock = Number(row.stock);
  const listedStock = Number(row.listed_quantity);
  const cardTraderStock = Number(row.cardtrader_listed_quantity ?? row.cardtraderListedQuantity ?? 0);
  const stock = Math.max(
    Number.isFinite(explicitStock) ? explicitStock : 0,
    Number.isFinite(listedStock) ? listedStock : 0,
    Number.isFinite(cardTraderStock) ? cardTraderStock : 0,
  );
  if (stock > 0) return Math.trunc(stock);
  return hasCardTraderAvailability(row) ? 1 : 0;
}

function cardTileTags(row, rarity) {
  return [row.set_name, rarity, row.card_type, row.trainer_name].filter(Boolean);
}

function normalizeTags(value) {
  return Array.isArray(value)
    ? value.map((entry) => String(entry || '').trim()).filter(Boolean)
    : [];
}

function normalizeHomeCard(card = {}) {
  const normalized = normalizeCardImages(withCardEmojiFields(card));
  const cardTraderAvailable = hasCardTraderAvailability(normalized);
  const cardTraderQuantity = Number(
    normalized.cardtraderListedQuantity ??
      normalized.cardtrader_listed_quantity ??
      normalized.analytics?.cardtraderListedQuantity ??
      0,
  );
  if (!cardTraderAvailable) {
    return normalized;
  }
  const cardTraderStock = Number.isFinite(cardTraderQuantity) && cardTraderQuantity > 0
    ? Math.trunc(cardTraderQuantity)
    : 1;
  const price = Number(
    normalized.cardtraderLowestPricePkn ??
      normalized.cardtrader_lowest_price_pkn ??
      normalized.price,
  );
  return {
    ...normalized,
    hasCardTraderListing: cardTraderAvailable,
    cardtraderEligibleListingCount: Number(
      normalized.cardtraderEligibleListingCount ??
        normalized.cardtrader_eligible_listing_count ??
        0,
    ),
    stock: Math.max(Number(normalized.stock || 0), cardTraderStock),
    price: Number.isFinite(price) && price > 0 ? price : normalized.price,
    tags: normalizeTags(normalized.tags).filter((tag) => tag !== 'NFT'),
  };
}

async function hydrateCanonicalCardTraderCache(cards, cheapestCacheRelation) {
  const ids = [...new Set(cards
    .map((card) => Number(card.id))
    .filter((id) => Number.isSafeInteger(id) && id > 0))];
  if (ids.length === 0) {
    return cards;
  }
  const result = await marketplaceQuery(
    `
      select distinct on (candidate_id)
        candidate_id,
        blueprint_id,
        pokoin_card_id,
        eligible_listing_count,
        eligible_quantity,
        cheapest_price_pkn
      from (
        select
          candidate.card_id as candidate_id,
          cache.blueprint_id,
          cache.pokoin_card_id,
          cache.eligible_listing_count,
          cache.eligible_quantity,
          cache.cheapest_price_pkn,
          case when cache.blueprint_id = candidate.card_id then 0 else 1 end as match_rank
        from unnest($1::bigint[]) as candidate(card_id)
        join ${cheapestCacheRelation} cache
          on cache.provider = 'cardtrader'
          and cache.eligible_listing_count > 0
          and cache.cheapest_price_pkn is not null
          and (
            cache.blueprint_id = candidate.card_id
            or cache.pokoin_card_id = candidate.card_id::text
          )
      ) matches
      order by
        candidate_id,
        match_rank,
        cheapest_price_pkn asc,
        eligible_listing_count desc,
        blueprint_id asc
    `,
    [ids],
  );
  const cacheById = new Map(result.rows.map((row) => [String(row.candidate_id), row]));
  return cards.map((card) => {
    const cache = cacheById.get(String(card.id));
    if (!cache) {
      return card;
    }
    const eligibleListingCount = Number(cache.eligible_listing_count || 0);
    const eligibleQuantity = Number(cache.eligible_quantity || 0);
    const cheapestPricePkn = Number(cache.cheapest_price_pkn);
    if (!Number.isFinite(cheapestPricePkn) || cheapestPricePkn <= 0 || eligibleListingCount <= 0) {
      return card;
    }
    return normalizeHomeCard({
      ...card,
      hasCardTraderListing: true,
      cardtraderEligibleListingCount: eligibleListingCount,
      cardtraderListedQuantity: Number.isFinite(eligibleQuantity) && eligibleQuantity > 0
        ? Math.trunc(eligibleQuantity)
        : 0,
      cardtraderLowestPricePkn: cheapestPricePkn,
      price: cheapestPricePkn,
    });
  });
}

function toCardJson(row) {
  const rarity = projectedRarity(row);
  const number = projectedCollectorNumber(row);
  const itemKind = hasCollectorNumber(number) ? 'single' : row.item_kind || 'single';
  const productType = hasCollectorNumber(number) ? 'card' : row.product_type || 'card';
  return withCardEmojiFields({
    id: String(row.card_id ?? ''),
    name: row.name || '',
    imageUrl: row.cdn_image_url || row.image_url || '',
    previewImageUrl: row.preview_image_url || row.cdn_image_url || row.image_url || '',
    homepageImageUrl: row.homepage_image_url || row.preview_image_url || row.cdn_image_url || row.image_url || '',
    rarity,
    type: row.card_type || 'Trading card',
    set: row.set_name || 'Pokemon',
    number: itemKind === 'product'
      ? (row.product_variant || row.version || '')
      : number,
    card_number: number,
    expansion_number: number,
    itemKind,
    productType,
    trainerName: row.trainer_name || '',
    canonicalPath: row.canonical_path || '',
    canonical_path: row.canonical_path || '',
    artist: row.artist || row.illustrator || '',
    illustrator: row.illustrator || row.artist || '',
    cardPalette: row.card_palette || null,
    emoji: row.emoji || '',
    price: cardTilePrice(row),
    stock: cardTileStock(row),
    rating: watchlistCountFromRow(row),
    cartHolderCount: cartHolderCountFromRow(row),
    reviewCount: 0,
    isFoil: false,
    isHolo: rarity.toLowerCase().includes('holo'),
    tags: cardTileTags(row, rarity),
    condition: 'NM',
    isGraded: false,
    hasCardTraderListing: row.has_cardtrader_listing === true ||
      Number(row.cardtrader_eligible_listing_count || 0) > 0 ||
      Number(row.cardtrader_listed_quantity || 0) > 0,
    cardtraderEligibleListingCount: Number(row.cardtrader_eligible_listing_count || 0),
    cardtraderListedQuantity: Number(row.cardtrader_listed_quantity || 0),
    cardtraderLowestPricePkn: row.cardtrader_lowest_price_pkn == null
      ? null
      : Number(row.cardtrader_lowest_price_pkn),
  });
}

async function artistMapForCardIds(cardIds) {
  const ids = [...new Set(cardIds
    .map((id) => Number(id))
    .filter((id) => Number.isSafeInteger(id) && id > 0))];
  if (ids.length === 0) {
    return new Map();
  }
  const result = await marketplaceQuery(
    `
      select blueprint_id, artist, illustrator
      from public.marketplace_blueprint_artists
      where blueprint_id = any($1::bigint[])
    `,
    [ids],
  );
  return new Map(result.rows.map((row) => [
    String(row.blueprint_id),
    {
      artist: row.artist || row.illustrator || '',
      illustrator: row.illustrator || row.artist || '',
    },
  ]));
}

function mergeArtistMetadata(cards, artistMap) {
  return cards.map((card) => {
    const metadata = artistMap.get(String(card.id));
    return metadata ? { ...card, ...metadata } : card;
  });
}

async function fetchMissingSectionCards(sectionIds, existingIds, cheapestCacheRelation) {
  const missingIds = sectionIds
    .map((id) => Number(id))
    .filter((id) => Number.isSafeInteger(id) && id > 0 && !existingIds.has(String(id)));
  if (missingIds.length === 0) {
    return [];
  }
  const result = await marketplaceQuery(
    `
      with settings as (
        select set_config('app.pkn_usdt_price', $2::text, true)
      )
      select
        marketplace_search_candidates.card_id,
        urls.canonical_path,
        marketplace_search_candidates.name,
        marketplace_search_candidates.image_url,
        marketplace_search_candidates.cdn_image_url,
        marketplace_search_candidates.preview_image_url,
        marketplace_search_candidates.homepage_image_url,
        marketplace_search_candidates.set_name,
        coalesce(
          case
            when lower(nullif(marketplace_search_candidates.rarity, '')) <> 'card'
            then marketplace_search_candidates.rarity
            else null
          end,
          nullif(blueprints.blueprint->>'rarity', ''),
          nullif(blueprints.blueprint->>'collector_rarity', ''),
          nullif(blueprints.blueprint#>>'{fixed_properties,pokemon_rarity}', ''),
          nullif(marketplace_search_candidates.rarity, ''),
          'Card'
        ) as rarity,
        marketplace_search_candidates.card_type,
        coalesce(
          nullif(marketplace_search_candidates.card_number, ''),
          nullif(blueprints.version, ''),
          nullif(blueprints.blueprint->>'number', ''),
          nullif(blueprints.blueprint->>'collector_number', ''),
          nullif(blueprints.blueprint->>'card_number', ''),
          marketplace_search_candidates.card_number
        ) as card_number,
        marketplace_search_candidates.product_variant,
        marketplace_search_candidates.item_kind,
        marketplace_search_candidates.product_type,
        marketplace_search_candidates.trainer_name,
        artist.artist,
        artist.illustrator,
        marketplace_search_candidates.card_palette,
        marketplace_search_candidates.emoji,
        ${watchlistCountColumn('watchlist_analytics')},
        ${cartHolderCountColumn('cart_analytics')},
        (
          coalesce(price_summary.listed_quantity, 0) +
          coalesce(cardtrader.eligible_quantity, 0)
        ) as listed_quantity,
        case
          when cardtrader.cheapest_price_pkn is not null then cardtrader.cheapest_price_pkn
          else price_summary.lowest_ask_pkn
        end as lowest_price_pkn,
        coalesce(cardtrader.eligible_quantity, 0) as cardtrader_listed_quantity,
        cardtrader.cheapest_price_pkn as cardtrader_lowest_price_pkn
      from settings,
        public.marketplace_search_candidates
      left join public.cardtrader_pokemon_blueprints blueprints
        on blueprints.id = marketplace_search_candidates.card_id
      left join public.marketplace_blueprint_artists artist
        on artist.blueprint_id = marketplace_search_candidates.card_id
      left join public.marketplace_blueprint_price_summary price_summary
        on price_summary.blueprint_id = marketplace_search_candidates.card_id
      ${cardTraderAvailabilityJoin('marketplace_search_candidates', cheapestCacheRelation)}
      ${watchlistAnalyticsJoin('marketplace_search_candidates', 'watchlist_analytics')}
      ${cartAnalyticsJoin('marketplace_search_candidates', 'cart_analytics')}
      left join public.marketplace_card_urls urls
        on urls.card_id = marketplace_search_candidates.card_id
        and urls.language = 'en'
      where marketplace_search_candidates.card_id = any($1::bigint[])
    `,
    [missingIds, String(process.env.PKN_CHECKOUT_USDT_PRICE || 0.005)],
  );
  return result.rows.map(toCardJson);
}

async function refreshHotBlueprintsIfStale() {
  try {
    await marketplaceQuery(
      `
        select case
          when coalesce(max(refreshed_at), timestamp with time zone 'epoch') < now() - $1::interval
          then public.refresh_marketplace_hot_blueprints()
          else null
        end as refreshed_count
        from public.marketplace_hot_blueprints
      `,
      [HOT_REFRESH_INTERVAL],
    );
  } catch (error) {
    console.warn('marketplace-home hot blueprint refresh skipped', error);
  }
}

async function fetchSnapshot() {
  const now = Date.now();
  if (cachedSnapshot && now - cachedSnapshotAt < MEMORY_CACHE_TTL_MS) {
    return cachedSnapshot;
  }
  await refreshHotBlueprintsIfStale();
  const result = await marketplaceQuery(
    'select public.get_marketplace_home_snapshot($1) as snapshot',
    [120],
  );
  const snapshot = result.rows[0]?.snapshot || { cards: [], sections: {} };

  const cheapestCacheRelation = await cheapestHomepageCacheRelationName();
  const cards = Array.isArray(snapshot.cards)
    ? snapshot.cards.map(normalizeHomeCard).filter(hasCdnBackedImages)
    : [];
  const cardIds = new Set(cards.map((card) => String(card.id)));
  const sections = normalizeSections(snapshot.sections);
  const sectionIds = [
    ...sections.recentlySeenIds,
    ...sections.bestSellerIds,
    ...sections.featuredIds,
  ];
  const sectionCards = (await fetchMissingSectionCards(
    sectionIds,
    cardIds,
    cheapestCacheRelation,
  ))
    .map(normalizeCardImages)
    .filter(hasCdnBackedImages);
  for (const card of sectionCards) {
    if (!cardIds.has(String(card.id))) {
      cardIds.add(String(card.id));
      cards.push(card);
    }
  }
  const hydratedCards = await hydrateCanonicalCardTraderCache(cards, cheapestCacheRelation);
  const artistMap = await artistMapForCardIds(hydratedCards.map((card) => card.id));
  const normalized = {
    ...snapshot,
    cards: mergeArtistMetadata(hydratedCards, artistMap),
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

module.exports.collectorNumberFromImageUrl = collectorNumberFromImageUrl;
module.exports.hasCollectorNumber = hasCollectorNumber;
module.exports.projectedCollectorNumber = projectedCollectorNumber;
module.exports.projectedRarity = projectedRarity;
module.exports.toCardJson = toCardJson;
module.exports.normalizeHomeCard = normalizeHomeCard;
module.exports.cardTilePrice = cardTilePrice;
module.exports.cardTileStock = cardTileStock;
module.exports.hasCardTraderAvailability = hasCardTraderAvailability;
