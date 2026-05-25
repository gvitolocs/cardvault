const { marketplaceQuery } = require('./_marketplace_db');

const HOT_POOL_TTL_MS = 60_000;
let hotPoolCache = null;
let hotPoolRefresh = null;

function cleanLimit(value, fallback = 50) {
  const limit = Number(value);
  if (!Number.isFinite(limit)) {
    return fallback;
  }
  return Math.min(Math.max(Math.trunc(limit), 1), 1000);
}

function cleanWindow(value) {
  const normalized = String(value || '24h').trim().toLowerCase();
  return ['1h', '24h', '7d'].includes(normalized) ? normalized : '24h';
}

function scoreColumn(window) {
  switch (window) {
    case '1h':
      return 'hot_score_1h';
    case '7d':
      return 'hot_score_7d';
    default:
      return 'hot_score_24h';
  }
}

function wantsCards(value) {
  return value === '1' || value === 'true' || value === 'yes';
}

function toCardRow(row) {
  return {
    card_id: String(row.blueprint_id ?? ''),
    name: row.name || '',
    set_name: row.set_name || '',
    card_number: row.card_number || '',
    product_variant: row.product_variant || '',
    rarity: row.rarity || '',
    card_type: row.card_type || '',
    item_kind: row.item_kind || 'single',
    product_type: row.product_type || 'card',
    trainer_name: row.trainer_name || '',
    canonical_path: row.canonical_path || '',
    canonicalPath: row.canonical_path || '',
    artist: row.artist || row.illustrator || '',
    illustrator: row.illustrator || row.artist || '',
    image_url: row.image_url || '',
    cdn_image_url: row.cdn_image_url || '',
    preview_image_url: row.preview_image_url || '',
    card_palette: row.card_palette || null,
    emoji: row.emoji || '',
    imported_at: row.imported_at || null,
  };
}

async function fetchHotBlueprintRows(limit, window) {
  const orderBy = scoreColumn(window);
  const result = await marketplaceQuery(
    `
      with hot as (
        select *
        from public.marketplace_hot_blueprints
        where ${orderBy} > 0
        order by ${orderBy} desc, last_event_at desc nulls last, blueprint_id desc
        limit $1
      )
      select
        hot.blueprint_id,
        hot.name,
        hot.set_name,
        hot.card_number,
        hot.rarity,
        hot.card_type,
        urls.canonical_path,
        hot.item_kind,
        hot.product_type,
        hot.views_1h,
        hot.searches_1h,
        hot.clicks_1h,
        hot.cart_adds_1h,
        hot.reserves_1h,
        hot.sales_1h,
        hot.hot_score_1h,
        hot.views_24h,
        hot.searches_24h,
        hot.clicks_24h,
        hot.cart_adds_24h,
        hot.reserves_24h,
        hot.sales_24h,
        hot.hot_score_24h,
        hot.views_7d,
        hot.searches_7d,
        hot.clicks_7d,
        hot.cart_adds_7d,
        hot.reserves_7d,
        hot.sales_7d,
        hot.hot_score_7d,
        hot.last_event_at,
        hot.refreshed_at,
        c.product_variant,
        c.trainer_name,
        c.image_url,
        c.cdn_image_url,
        c.preview_image_url,
        c.card_palette,
        c.emoji,
        c.imported_at,
        artist.artist,
        artist.illustrator
      from hot
      left join public.marketplace_search_candidates c
        on c.card_id = hot.blueprint_id
      left join public.marketplace_blueprint_artists artist
        on artist.blueprint_id = hot.blueprint_id
      left join public.marketplace_card_urls urls
        on urls.card_id = hot.blueprint_id
        and urls.language = 'en'
      order by hot.${orderBy} desc, hot.last_event_at desc nulls last, hot.blueprint_id desc
    `,
    [limit],
  );
  return result.rows;
}

async function hotBlueprintRows(limit, window) {
  const now = Date.now();
  const cacheKey = `${window}:${limit}`;
  if (hotPoolCache?.key === cacheKey && now - hotPoolCache.createdAtMs < HOT_POOL_TTL_MS) {
    return { rows: hotPoolCache.rows, source: 'server_cache_hit' };
  }
  if (hotPoolCache?.key === cacheKey && hotPoolRefresh) {
    return { rows: hotPoolCache.rows, source: 'server_cache_stale' };
  }
  hotPoolRefresh = fetchHotBlueprintRows(limit, window)
    .then((rows) => {
      hotPoolCache = { key: cacheKey, rows, createdAtMs: Date.now() };
      return rows;
    })
    .finally(() => {
      hotPoolRefresh = null;
    });
  const rows = await hotPoolRefresh;
  return { rows, source: 'server_cache_refresh' };
}

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
    const window = cleanWindow(url.searchParams.get('window'));
    const limit = cleanLimit(url.searchParams.get('limit'));
    const includeCards = wantsCards(url.searchParams.get('includeCards'));
    const started = Date.now();
    const { rows, source } = await hotBlueprintRows(limit, window);
    const durationMs = Date.now() - started;
    res.setHeader('Cache-Control', 'public, max-age=10, s-maxage=60, stale-while-revalidate=120');
    res.setHeader('Server-Timing', `hot-blueprints;dur=${durationMs}`);
    return res.status(200).json({
      window,
      limit,
      pool: {
        source,
        size: rows.length,
        limit,
        ttlSeconds: Math.trunc(HOT_POOL_TTL_MS / 1000),
        durationMs,
      },
      blueprints: rows.map((row) => ({
        blueprintId: String(row.blueprint_id),
        name: row.name || '',
        set: row.set_name || '',
        number: row.card_number || '',
        rarity: row.rarity || '',
        type: row.card_type || '',
        canonicalPath: row.canonical_path || '',
        canonical_path: row.canonical_path || '',
        artist: row.artist || row.illustrator || '',
        illustrator: row.illustrator || row.artist || '',
        itemKind: row.item_kind || 'single',
        productType: row.product_type || 'card',
        views1h: Number(row.views_1h || 0),
        searches1h: Number(row.searches_1h || 0),
        clicks1h: Number(row.clicks_1h || 0),
        cartAdds1h: Number(row.cart_adds_1h || 0),
        reserves1h: Number(row.reserves_1h || 0),
        sales1h: Number(row.sales_1h || 0),
        hotScore1h: Number(row.hot_score_1h || 0),
        views24h: Number(row.views_24h || 0),
        searches24h: Number(row.searches_24h || 0),
        clicks24h: Number(row.clicks_24h || 0),
        cartAdds24h: Number(row.cart_adds_24h || 0),
        reserves24h: Number(row.reserves_24h || 0),
        sales24h: Number(row.sales_24h || 0),
        hotScore24h: Number(row.hot_score_24h || 0),
        views7d: Number(row.views_7d || 0),
        searches7d: Number(row.searches_7d || 0),
        clicks7d: Number(row.clicks_7d || 0),
        cartAdds7d: Number(row.cart_adds_7d || 0),
        reserves7d: Number(row.reserves_7d || 0),
        sales7d: Number(row.sales_7d || 0),
        hotScore7d: Number(row.hot_score_7d || 0),
        lastEventAt: row.last_event_at,
        refreshedAt: row.refreshed_at,
      })),
      ...(includeCards
        ? { cards: rows.map(toCardRow).filter((row) => row.card_id && (row.preview_image_url || row.cdn_image_url || row.image_url)) }
        : {}),
    });
  } catch (error) {
    console.error('marketplace-hot-blueprints failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Marketplace hot blueprints failed.',
    });
  }
};

module.exports.cleanLimit = cleanLimit;
module.exports.cleanWindow = cleanWindow;
module.exports.wantsCards = wantsCards;
module.exports.hotBlueprintRows = hotBlueprintRows;
