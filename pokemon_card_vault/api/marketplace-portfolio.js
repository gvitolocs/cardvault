'use strict';

/**
 * React Portfolio / Explore BFF: Pokoin catalog + native listing overlay.
 * PKN only. Pokoin CDN art. Never CardTrader leftover image hosts.
 * Never the candyext dump.
 */
const { marketplaceQuery } = require('./_marketplace_db');
const {
  parseGameFromRequest,
  runWithGame,
  currentGame,
  isPokemonGame,
} = require('./_marketplace_game');
const {
  cleanText,
  parseLimit,
  parsePublicCardId,
  reactImageUrls,
  setCorsHeaders,
  jsonOk,
} = require('./_marketplace_react_card');

const GAME_LABEL = {
  pokemon: 'Pokémon',
  one_piece: 'One Piece',
  riftbound: 'Riftbound',
};

function gameLabel(game) {
  return GAME_LABEL[game] || game || 'Pokoin';
}

function isCardtraderHost(value) {
  const text = String(value || '').trim();
  if (!text) {
    return false;
  }
  try {
    const url = new URL(text, 'https://pokoin.com');
    return /(^|\.)cardtrader\.com$/i.test(url.hostname);
  } catch (_) {
    return /cardtrader\.com/i.test(text);
  }
}

function dropForeignImages(row = {}) {
  const next = { ...row };
  for (const key of ['cdn_image_url', 'image_url', 'preview_image_url', 'homepage_image_url']) {
    if (isCardtraderHost(next[key])) {
      next[key] = '';
    }
  }
  return next;
}

function isUndefinedTable(error) {
  return error?.code === '42P01' || /does not exist/i.test(String(error?.message || ''));
}

function holdingFromRow(row, game) {
  const cardId = parsePublicCardId(row.card_id);
  const images = reactImageUrls(dropForeignImages({
    card_id: cardId,
    ct_id: row.ct_id,
    cdn_image_url: row.cdn_image_url,
    image_url: row.image_url,
  }));
  const qty = Math.max(0, Number(row.qty) || 0) || 1;
  const pricePkn = Number(row.floor_pkn) || 0;
  const totalPkn = Number(row.total_pkn) || (pricePkn * qty) || 0;
  const name = cleanText(row.catalog_name || row.card_name, 240);
  const expansion = cleanText(row.expansion_name || row.catalog_set || row.set_name, 240);
  const listingCount = Math.max(0, Number(row.listing_count) || 0);
  const canonicalPath = cleanText(row.canonical_path, 800)
    || (cardId ? `/marketplace/en/cards/${cardId}` : '');
  return {
    id: cardId,
    cardId,
    card_id: cardId,
    name,
    expansion,
    set: expansion,
    set_name: expansion,
    number: cleanText(row.card_number || row.collector_number, 80),
    game: gameLabel(game),
    gameId: game,
    qty,
    listingCount,
    pricePkn,
    totalPkn,
    condition: cleanText(row.condition, 80),
    language: cleanText(row.language, 16).toUpperCase(),
    sealed: row.sealed === true,
    source: listingCount > 0 ? 'native' : 'catalog',
    canonicalPath,
    canonical_path: canonicalPath,
    ...images,
  };
}

function rollupSets(items) {
  const bySet = new Map();
  for (const item of items) {
    const key = item.expansion || '—';
    const current = bySet.get(key) || { name: key, pkn: 0, qty: 0, listings: 0 };
    current.pkn += Number(item.totalPkn) || 0;
    current.qty += Number(item.qty) || 0;
    current.listings += Number(item.listingCount) || 0;
    bySet.set(key, current);
  }
  return [...bySet.values()].sort((a, b) => b.pkn - a.pkn);
}

function emptyPayload(game) {
  const label = gameLabel(game);
  return {
    game,
    generated: new Date().toISOString(),
    totals: { pkn: 0, qty: 0, listings: 0, cards: 0 },
    games: [{ id: game, name: label, pkn: 0, qty: 0 }],
    sets: [],
    items: [],
  };
}

function payloadFromRows(rows, game) {
  const items = (rows || []).map((row) => holdingFromRow(row, game)).filter((row) => row.id);
  const totals = items.reduce((acc, item) => {
    acc.pkn += Number(item.totalPkn) || 0;
    acc.qty += Number(item.qty) || 0;
    acc.listings += Number(item.listingCount) || 0;
    acc.cards += 1;
    return acc;
  }, { pkn: 0, qty: 0, listings: 0, cards: 0 });
  const label = gameLabel(game);
  return {
    game,
    generated: new Date().toISOString(),
    totals,
    games: [{ id: game, name: label, pkn: totals.pkn, qty: totals.qty }],
    sets: rollupSets(items),
    items,
  };
}

async function relationExists(qualified) {
  const result = await marketplaceQuery(
    'select to_regclass($1)::text as rel',
    [qualified],
  );
  return Boolean(result.rows[0]?.rel);
}

function listingJoinSql() {
  return `
      left join lateral (
        select
          min(listings.price_pkn)::float8 as floor_pkn,
          sum(listings.quantity_available * listings.price_pkn)::float8 as total_pkn,
          sum(listings.quantity_available)::int as qty,
          count(*)::int as listing_count,
          bool_or(listings.sealed) as sealed,
          max(listings.card_name) as card_name,
          max(listings.collector_number) as collector_number,
          max(listings.condition) as condition,
          max(listings.language) as language
        from public.marketplace_user_listings listings
        where listings.card_id = c.card_id::text
          and listings.status = 'active'
          and listings.quantity_available > 0
          and coalesce(listings.source, '') not ilike '%cardtrader%'
      ) listings on true
  `;
}

function cheapLookupSql() {
  return `
      left join lateral (
        select cheapest_price_pkn::float8 as floor_pkn, eligible_quantity::int as qty
        from public.cheapest_homepage_cache_blueprint cheap
        where cheap.cheapest_price_pkn is not null
          and cheap.cheapest_price_pkn > 0
          and coalesce(cheap.eligible_listing_count, 0) > 0
          and cheap.provider in ('pokoin_native', 'cardtrader')
          and cheap.pokoin_card_id = c.card_id::text
        order by case when cheap.provider = 'pokoin_native' then 0 else 1 end,
          cheap.cheapest_price_pkn asc
        limit 1
      ) cheap on true
  `;
}

function catalogSelectSql({ hasListings, hasCheap }) {
  const floor = hasListings && hasCheap
    ? 'coalesce(listings.floor_pkn, cheap.floor_pkn, 0)'
    : hasListings
      ? 'coalesce(listings.floor_pkn, 0)'
      : hasCheap
        ? 'coalesce(cheap.floor_pkn, 0)'
        : '0';
  const qty = hasListings && hasCheap
    ? 'coalesce(listings.qty, cheap.qty, 1)'
    : hasListings
      ? 'coalesce(listings.qty, 1)'
      : hasCheap
        ? 'coalesce(cheap.qty, 1)'
        : '1';
  const total = hasListings
    ? `coalesce(listings.total_pkn, (${floor}) * (${qty}), 0)`
    : `(${floor}) * (${qty})`;
  const listingCount = hasListings ? 'coalesce(listings.listing_count, 0)' : '0';
  const sealed = hasListings
    ? `coalesce(listings.sealed, c.item_kind = 'product')`
    : `c.item_kind = 'product'`;
  return {
    listingJoin: hasListings ? listingJoinSql() : '',
    cheapJoin: hasCheap ? cheapLookupSql() : '',
    select: `
        c.card_id::text as card_id,
        c.ct_id,
        (${floor})::float8 as floor_pkn,
        (${total})::float8 as total_pkn,
        (${qty})::int as qty,
        (${listingCount})::int as listing_count,
        (${sealed}) as sealed,
        ${hasListings ? 'listings.card_name' : 'null::text'} as card_name,
        c.name as catalog_name,
        c.set_name,
        c.expansion_name,
        c.card_number,
        ${hasListings ? 'listings.collector_number' : 'null::text'} as collector_number,
        ${hasListings ? 'listings.condition' : 'null'} as condition,
        ${hasListings ? 'listings.language' : 'null'} as language,
        c.cdn_image_url,
        c.image_url,
        urls.canonical_path
    `,
  };
}

function urlsJoinSql() {
  return `
      left join lateral (
        select canonical_path
        from public.marketplace_card_urls u
        where u.card_id = c.card_id
          and u.language = 'en'
        order by u.canonical_path
        limit 1
      ) urls on true
  `;
}

async function queryById({ cardId, hasListings, hasCheap }) {
  const parts = catalogSelectSql({ hasListings, hasCheap });
  const result = await marketplaceQuery(
    `
      select
        ${parts.select}
      from public.marketplace_search_candidates c
      ${parts.listingJoin}
      ${parts.cheapJoin}
      ${urlsJoinSql()}
      where c.card_id = $1::bigint or c.ct_id = $1::bigint
      order by case when c.card_id = $1::bigint then 0 else 1 end, c.card_id
      limit 1
    `,
    [cardId],
  );
  return result.rows || [];
}

async function queryPokemonPriced({ limit, hasListings }) {
  const listingJoin = hasListings ? listingJoinSql() : '';
  const listingFloor = hasListings ? 'listings.floor_pkn' : 'null::float8';
  const listingTotal = hasListings ? 'listings.total_pkn' : 'null::float8';
  const listingQty = hasListings ? 'listings.qty' : 'null::int';
  const listingCount = hasListings ? 'coalesce(listings.listing_count, 0)' : '0';
  const sealed = hasListings
    ? `coalesce(listings.sealed, c.item_kind = 'product')`
    : `c.item_kind = 'product'`;
  const result = await marketplaceQuery(
    `
      select
        card_id,
        ct_id,
        floor_pkn,
        coalesce(listing_total, floor_pkn * qty)::float8 as total_pkn,
        qty,
        listing_count,
        sealed,
        card_name,
        catalog_name,
        set_name,
        expansion_name,
        card_number,
        collector_number,
        condition,
        language,
        cdn_image_url,
        image_url,
        canonical_path
      from (
        select distinct on (c.card_id)
          c.card_id::text as card_id,
          c.ct_id,
          coalesce(${listingFloor}, cheap.cheapest_price_pkn, 0)::float8 as floor_pkn,
          ${listingTotal} as listing_total,
          coalesce(${listingQty}, cheap.eligible_quantity, 1)::int as qty,
          (${listingCount})::int as listing_count,
          (${sealed}) as sealed,
          ${hasListings ? 'listings.card_name' : 'null::text'} as card_name,
          c.name as catalog_name,
          c.set_name,
          c.expansion_name,
          c.card_number,
          ${hasListings ? 'listings.collector_number' : 'null::text'} as collector_number,
          ${hasListings ? 'listings.condition' : 'null'} as condition,
          ${hasListings ? 'listings.language' : 'null'} as language,
          c.cdn_image_url,
          c.image_url,
          urls.canonical_path
        from public.cheapest_homepage_cache_blueprint cheap
        join public.marketplace_search_candidates c
          on c.card_id = cheap.pokoin_card_id::bigint
        ${listingJoin}
        ${urlsJoinSql()}
        where cheap.cheapest_price_pkn is not null
          and cheap.cheapest_price_pkn > 0
          and coalesce(cheap.eligible_listing_count, 0) > 0
          and cheap.provider in ('pokoin_native', 'cardtrader')
          and coalesce(c.cdn_image_url, c.image_url) is not null
        order by c.card_id,
          case when cheap.provider = 'pokoin_native' then 0 else 1 end,
          cheap.cheapest_price_pkn asc
      ) ranked
      order by floor_pkn desc, qty desc, card_id
      limit $1
    `,
    [limit],
  );
  return result.rows || [];
}

async function queryCatalogList({ limit, hasListings, pokemon }) {
  const parts = catalogSelectSql({ hasListings, hasCheap: false });
  const fromSql = pokemon
    ? `(
        select *
        from public.marketplace_search_candidates
        where item_kind = 'single'
          and product_type = 'card'
          and coalesce(cdn_image_url, image_url) is not null
        order by search_weight desc, card_id desc
        limit $1
      ) c`
    : 'public.marketplace_search_candidates c';
  const result = await marketplaceQuery(
    `
      select
        ${parts.select}
      from ${fromSql}
      ${parts.listingJoin}
      ${urlsJoinSql()}
      where coalesce(c.cdn_image_url, c.image_url) is not null
      order by floor_pkn desc, qty desc, c.card_id
      limit $1
    `,
    [limit],
  );
  return result.rows || [];
}

async function queryCatalog({ limit, cardId, hasListings, hasCheap, pokemon }) {
  if (cardId) {
    return queryById({ cardId, hasListings, hasCheap });
  }
  if (pokemon && hasCheap) {
    return queryPokemonPriced({ limit, hasListings });
  }
  return queryCatalogList({ limit, hasListings, pokemon });
}

async function defaultLoadPortfolio({ limit = 400, cardId = '' } = {}) {
  const pokemon = isPokemonGame();
  let hasListings = false;
  let hasCheap = false;
  try {
    hasListings = await relationExists('public.marketplace_user_listings');
    hasCheap = await relationExists('public.cheapest_homepage_cache_blueprint');
  } catch (error) {
    if (!isUndefinedTable(error)) {
      throw error;
    }
  }
  try {
    return await queryCatalog({
      limit,
      cardId,
      hasListings,
      hasCheap,
      pokemon,
    });
  } catch (error) {
    if (!isUndefinedTable(error)) {
      throw error;
    }
    return queryCatalog({
      limit,
      cardId,
      hasListings: false,
      hasCheap: false,
      pokemon: false,
    });
  }
}

function limitForGame(raw, game) {
  const pokemon = game === 'pokemon';
  return parseLimit(raw, pokemon ? 400 : 2000, pokemon ? 500 : 2500);
}

function createHandler(deps = {}) {
  const loadPortfolio = deps.loadPortfolio || defaultLoadPortfolio;
  return async function handler(req, res) {
    setCorsHeaders(res);
    if (req.method === 'OPTIONS') {
      return res.status(204).end();
    }
    if (req.method !== 'GET') {
      res.setHeader('Allow', 'GET, OPTIONS');
      return res.status(405).json({ error: 'Method not allowed.' });
    }
    const game = parseGameFromRequest(req);
    return runWithGame(game, async () => {
      try {
        const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
        const cardId = parsePublicCardId(url.searchParams.get('id') || url.searchParams.get('cardId'));
        const limit = limitForGame(url.searchParams.get('limit'), currentGame());
        const rows = await loadPortfolio({ limit, cardId, game: currentGame() });
        const payload = payloadFromRows(rows, currentGame());
        if (!payload.items.length && cardId) {
          return jsonOk(res, { ...emptyPayload(currentGame()), id: cardId }, 'public, max-age=15, s-maxage=30');
        }
        return jsonOk(
          res,
          payload,
          'public, max-age=15, s-maxage=30, stale-while-revalidate=60',
        );
      } catch (error) {
        console.error('marketplace-portfolio failed', error);
        if (isUndefinedTable(error)) {
          return jsonOk(res, emptyPayload(currentGame()), 'public, max-age=15, s-maxage=30');
        }
        return res.status(error.statusCode || 500).json({
          error: error.message || 'Marketplace portfolio failed.',
        });
      }
    });
  };
}

module.exports = createHandler();
module.exports.createHandler = createHandler;
module.exports._test = {
  createHandler,
  holdingFromRow,
  payloadFromRows,
  dropForeignImages,
  isCardtraderHost,
  emptyPayload,
  isUndefinedTable,
  limitForGame,
};
