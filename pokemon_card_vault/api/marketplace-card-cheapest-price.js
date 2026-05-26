const { marketplaceQuery } = require('./_marketplace_db');
const { cardIdFromDoubledId } = require('./marketplace-card-versions');
const {
  cardTraderAvailabilityJoin,
  cheapestHomepageCacheRelationName,
} = require('./marketplace-cards');

const MAX_BATCH_IDS = 50;
const MAX_STRUCTURED_RESULTS = 10;
const DEFAULT_STRUCTURED_RESULTS = 5;
const PKN_USD_REFERENCE_PRICE = 0.005;

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

function cleanText(value, maxLength = 240) {
  return String(value || '').trim().replace(/\s+/g, ' ').slice(0, maxLength);
}

function cleanCardId(value) {
  const text = String(value || '').trim();
  if (!/^[0-9]+$/.test(text)) return '';
  const id = Number(text);
  return Number.isSafeInteger(id) && id > 0 ? String(id) : '';
}

function cleanLanguage(value) {
  const language = String(value || 'en').trim().toLowerCase();
  return /^[a-z]{2}(?:-[a-z]{2})?$/.test(language) ? language : 'en';
}

function cleanLimit(value, fallback = DEFAULT_STRUCTURED_RESULTS) {
  if (value === undefined || value === null || value === '') return fallback;
  const limit = Number(value);
  if (!Number.isFinite(limit)) return fallback;
  return Math.min(Math.max(Math.trunc(limit), 1), MAX_STRUCTURED_RESULTS);
}

function addUniqueId(ids, value) {
  const id = cleanCardId(value);
  if (id && !ids.includes(id) && ids.length < MAX_BATCH_IDS) {
    ids.push(id);
  }
}

function splitIds(value) {
  return String(value || '')
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean);
}

function pathnameFromValue(value) {
  const text = String(value || '').trim();
  if (!text) return '';
  try {
    return new URL(text, 'https://pokoin.com').pathname;
  } catch (_) {
    return text.split(/[?#]/)[0];
  }
}

function cardIdFromCanonicalPath(value) {
  const pathname = pathnameFromValue(value);
  const marketplaceMatch = pathname.match(/^\/marketplace\/[a-z]{2}(?:-[a-z]{2})?\/cards\/(\d+)(?:\/|$)/i);
  if (marketplaceMatch) {
    return cardIdFromDoubledId(marketplaceMatch[1]);
  }
  const rootMatch = pathname.match(/^\/(\d+)(?:\/|$)/);
  return rootMatch ? cleanCardId(rootMatch[1]) : '';
}

function cleanLookupCardIds(input = {}) {
  const ids = [];
  addUniqueId(ids, input.cardId);
  addUniqueId(ids, input.blueprintId);
  for (const id of splitIds(input.cardIds || input.blueprintIds || input.ids)) {
    addUniqueId(ids, id);
  }
  addUniqueId(ids, cardIdFromCanonicalPath(input.canonicalPath || input.path || input.url));
  return ids;
}

function finitePositiveNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? number : null;
}

function nullableNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function cheapestPriceRow(row = {}) {
  const cardTraderPrice = finitePositiveNumber(row.cardtrader_lowest_price_pkn);
  const nativePrice = finitePositiveNumber(row.native_lowest_ask_pkn);
  const cacheProvider = cleanText(row.homepage_cache_provider || row.cardtrader_provider, 80);
  const cacheSource = cacheProvider === 'pokoin_native'
    ? 'pokoin_native_homepage_cache'
    : 'cheapest_homepage_cache_blueprint';
  const usesHomepageCache = cardTraderPrice != null;
  const pricePkn = usesHomepageCache ? cardTraderPrice : null;
  const listingCount = usesHomepageCache
    ? Number(row.cardtrader_eligible_listing_count || 0)
    : 0;
  const listedQuantity = usesHomepageCache
    ? Number(row.cardtrader_listed_quantity || 0)
    : 0;
  const pknReferencePrice = finitePositiveNumber(process.env.PKN_CHECKOUT_USDT_PRICE) ||
    PKN_USD_REFERENCE_PRICE;
  const priceUsdt = pricePkn == null ? null : pricePkn * pknReferencePrice;

  return {
    cardId: String(row.card_id || ''),
    canonicalPath: row.canonical_path || '',
    publicNumber: row.public_number || '',
    language: row.language || 'en',
    name: row.name || '',
    set: row.set_name || '',
    number: row.card_number || '',
    currency: 'PKN',
    unit: 'PKN',
    price: pricePkn,
    pricePkn,
    priceUsdt,
    pknReferencePriceUsdt: pknReferencePrice,
    source: pricePkn == null
      ? null
      : cacheSource,
    provider: pricePkn == null ? null : (cacheProvider || 'cardtrader'),
    listingId: usesHomepageCache ? row.cardtrader_sample_listing_id || '' : '',
    listingCount,
    listedQuantity,
    available: pricePkn != null && listingCount > 0,
    inStock: pricePkn != null && listedQuantity > 0,
    updatedAt: usesHomepageCache
      ? row.cardtrader_updated_at || row.cardtrader_source_snapshot_at || null
      : null,
    nativeListing: {
      source: 'marketplace_blueprint_price_summary',
      pricePkn: nativePrice,
      listingCount: Number(row.native_active_listing_count || 0),
      listedQuantity: Number(row.native_listed_quantity || 0),
      updatedAt: row.native_refreshed_at || null,
    },
    cardtrader: {
      source: cacheSource,
      provider: cacheProvider || (cardTraderPrice == null ? '' : 'cardtrader'),
      available: cardTraderPrice != null && Number(row.cardtrader_eligible_listing_count || 0) > 0,
      pricePkn: cardTraderPrice,
      priceEur: nullableNumber(row.cardtrader_lowest_price_eur),
      listingCount: Number(row.cardtrader_eligible_listing_count || 0),
      listedQuantity: Number(row.cardtrader_listed_quantity || 0),
      sampleListingId: row.cardtrader_sample_listing_id || '',
      sampleProductId: row.cardtrader_sample_product_id || '',
      sourceSnapshotAt: row.cardtrader_source_snapshot_at || null,
      updatedAt: row.cardtrader_updated_at || null,
    },
  };
}

function hasStructuredLookup(input = {}) {
  return Boolean(
    cleanText(input.name || input.cardName || input.pokemonName, 120) ||
      cleanText(input.set || input.setName || input.expansion || input.expansionName, 120) ||
      cleanText(input.number || input.collectorNumber || input.collectionNumber || input.cardNumber, 80)
  );
}

async function readCheapestPrices(input = {}, query = marketplaceQuery) {
  const cardIds = cleanLookupCardIds(input);
  const name = cleanText(input.name || input.cardName || input.pokemonName, 120);
  const setName = cleanText(input.set || input.setName || input.expansion || input.expansionName, 120);
  const number = cleanText(input.number || input.collectorNumber || input.collectionNumber || input.cardNumber, 80);
  const language = cleanLanguage(input.language || input.lang);
  if (cardIds.length === 0 && !hasStructuredLookup({ name, setName, number })) {
    const error = new Error('Provide cardId, cardIds, canonicalPath, or name/set/number lookup fields.');
    error.statusCode = 400;
    throw error;
  }

  const cheapestCacheRelation = await cheapestHomepageCacheRelationName(query);
  const structuredLimit = cleanLimit(input.limit);
  const result = await query(
    `
      with explicit_ids as (
        select requested.card_id, requested.ordinality::bigint
        from unnest($1::bigint[]) with ordinality as requested(card_id, ordinality)
      ),
      structured_ids as (
        select
          c.card_id,
          (100000 + row_number() over (
            order by
              case
                when $2::text <> '' and public.marketplace_search_compact(c.name) = public.marketplace_search_compact($2::text) then 0
                else 1
              end,
              case
                when $4::text = '' then 1
                when public.marketplace_search_compact(c.card_number) = public.marketplace_search_compact($4::text) then 0
                when public.marketplace_search_compact(c.card_number) like '%' || public.marketplace_search_compact($4::text) || '%' then 1
                else 2
              end,
              case
                when $3::text <> '' and public.marketplace_search_compact(c.set_name) = public.marketplace_search_compact($3::text) then 0
                else 1
              end,
              c.search_weight desc,
              c.imported_at desc nulls last,
              c.card_id desc
          ))::bigint as ordinality
        from public.marketplace_search_candidates c
        where ($2::text <> '' or $3::text <> '' or $4::text <> '')
          and (
            $2::text = ''
            or public.marketplace_search_compact(c.name) = public.marketplace_search_compact($2::text)
            or c.name ilike '%' || $2::text || '%'
          )
          and (
            $3::text = ''
            or public.marketplace_search_compact(c.set_name) = public.marketplace_search_compact($3::text)
            or c.set_name ilike '%' || $3::text || '%'
          )
          and (
            $4::text = ''
            or public.marketplace_search_compact(c.card_number) = public.marketplace_search_compact($4::text)
            or public.marketplace_search_compact(c.card_number) like '%' || public.marketplace_search_compact($4::text) || '%'
          )
        order by ordinality
        limit $6
      ),
      candidate_ids as (
        select card_id, min(ordinality) as ordinality
        from (
          select * from explicit_ids
          union all
          select * from structured_ids
        ) candidates
        group by card_id
      )
      select
        candidate_ids.card_id,
        candidate_ids.ordinality,
        coalesce(c.name, '') as name,
        coalesce(c.set_name, '') as set_name,
        coalesce(
          nullif(c.card_number, ''),
          nullif(blueprints.version, ''),
          nullif(blueprints.blueprint->>'number', ''),
          nullif(blueprints.blueprint->>'collector_number', ''),
          nullif(blueprints.blueprint->>'card_number', ''),
          ''
        ) as card_number,
        coalesce(urls.language, $5::text) as language,
        coalesce(urls.canonical_path, '') as canonical_path,
        coalesce(substring(urls.canonical_path from '/cards/([0-9]+)(?:/|$)'), '') as public_number,
        price_summary.lowest_ask_pkn as native_lowest_ask_pkn,
        coalesce(price_summary.active_listing_count, 0) as native_active_listing_count,
        coalesce(price_summary.listed_quantity, 0) as native_listed_quantity,
        price_summary.refreshed_at as native_refreshed_at,
        native_listing.id::text as native_sample_listing_id,
        cardtrader.provider as homepage_cache_provider,
        cardtrader.cheapest_price_pkn as cardtrader_lowest_price_pkn,
        cardtrader.cheapest_price_eur as cardtrader_lowest_price_eur,
        coalesce(cardtrader.eligible_listing_count, 0) as cardtrader_eligible_listing_count,
        coalesce(cardtrader.eligible_quantity, 0) as cardtrader_listed_quantity,
        cardtrader.sample_listing_id as cardtrader_sample_listing_id,
        cardtrader.sample_product_id as cardtrader_sample_product_id,
        cardtrader.source_snapshot_at as cardtrader_source_snapshot_at,
        cardtrader.updated_at as cardtrader_updated_at
      from candidate_ids
      left join public.marketplace_search_candidates c
        on c.card_id = candidate_ids.card_id
      left join public.cardtrader_pokemon_blueprints blueprints
        on blueprints.id = candidate_ids.card_id
      left join public.marketplace_card_urls urls
        on urls.card_id = candidate_ids.card_id
        and urls.language = $5::text
      left join public.marketplace_blueprint_price_summary price_summary
        on price_summary.blueprint_id = candidate_ids.card_id
      left join lateral (
        select listing.id
        from (
          select
            native_listing.*,
            case when native_listing.card_id ~ '^[0-9]+$' then native_listing.card_id::bigint else null end as card_id_bigint
          from public.marketplace_user_listings
          native_listing
        ) listing
        where listing.card_id_bigint = candidate_ids.card_id
          and listing.status = 'active'
          and listing.quantity_available > 0
          and listing.price_pkn > 0
          and coalesce(listing.shipping_available, true) = true
          and not (
            listing.nft_available = true
            and coalesce(listing.shipping_available, false) = false
          )
        order by listing.price_pkn asc, listing.updated_at desc, listing.id asc
        limit 1
      ) native_listing on true
      ${cardTraderAvailabilityJoin('candidate_ids', cheapestCacheRelation)}
      order by candidate_ids.ordinality asc, candidate_ids.card_id asc
    `,
    [
      cardIds.map((id) => Number(id)),
      name,
      setName,
      number,
      language,
      structuredLimit,
    ],
  );

  return result.rows.map(cheapestPriceRow);
}

function lookupFromUrl(url) {
  return {
    cardId: url.searchParams.get('cardId') || url.searchParams.get('blueprintId'),
    cardIds: url.searchParams.get('cardIds') || url.searchParams.get('blueprintIds') || url.searchParams.get('ids'),
    canonicalPath: url.searchParams.get('canonicalPath') || url.searchParams.get('path') || url.searchParams.get('url'),
    name: url.searchParams.get('name') || url.searchParams.get('cardName') || url.searchParams.get('pokemonName'),
    setName: url.searchParams.get('set') || url.searchParams.get('setName') || url.searchParams.get('expansion') || url.searchParams.get('expansionName'),
    number: url.searchParams.get('number') || url.searchParams.get('collectorNumber') || url.searchParams.get('collectionNumber') || url.searchParams.get('cardNumber'),
    language: url.searchParams.get('language') || url.searchParams.get('lang'),
    limit: url.searchParams.get('limit'),
  };
}

function createHandler({ query = marketplaceQuery } = {}) {
  return async function handler(req, res) {
    setCorsHeaders(res);
    if (req.method === 'OPTIONS') {
      return res.status(204).end();
    }
    if (req.method !== 'GET') {
      res.setHeader('Allow', 'GET, OPTIONS');
      return res.status(405).json({ error: 'Method not allowed.' });
    }

    try {
      const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
      const lookup = lookupFromUrl(url);
      const prices = await readCheapestPrices(lookup, query);
      res.setHeader('Cache-Control', 'public, max-age=10, s-maxage=30, stale-while-revalidate=60');
      if (prices.length === 0) {
        return res.status(404).json({
          price: null,
          prices: [],
          count: 0,
          lookup,
          error: 'No marketplace price found for this lookup.',
        });
      }
      return res.status(200).json({
        price: prices[0],
        prices,
        count: prices.length,
        lookup,
      });
    } catch (error) {
      console.error('marketplace-card-cheapest-price failed', error);
      return res.status(error.statusCode || 500).json({
        error: error.message || 'Marketplace card cheapest price failed.',
      });
    }
  };
}

module.exports = createHandler();

module.exports._test = {
  cardIdFromCanonicalPath,
  cheapestPriceRow,
  cleanCardId,
  cleanLanguage,
  cleanLimit,
  cleanLookupCardIds,
  createHandler,
  lookupFromUrl,
  readCheapestPrices,
  setCorsHeaders,
};
