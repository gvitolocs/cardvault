const { marketplaceQuery } = require('./_marketplace_db');
const { authorizeSearchDebugRequest } = require('./_search_debug_auth');

const EVENT_TYPES = new Set(['view', 'search', 'click', 'reserve', 'cart_add', 'sale']);
const WINDOW_INTERVALS = {
  '15m': '15 minutes',
  '1h': '1 hour',
  '24h': '24 hours',
  '7d': '7 days',
};

function cleanLimit(value, fallback = 200) {
  const limit = Number(value);
  if (!Number.isFinite(limit)) return fallback;
  return Math.min(Math.max(Math.trunc(limit), 1), 500);
}

function cleanWindow(value) {
  const window = String(value || '24h').trim().toLowerCase();
  return WINDOW_INTERVALS[window] ? window : '24h';
}

function cleanEventType(value) {
  const eventType = String(value || '').trim().toLowerCase();
  return EVENT_TYPES.has(eventType) ? eventType : '';
}

function cleanCardId(value) {
  const id = Number(value);
  return Number.isSafeInteger(id) && id > 0 ? id : 0;
}

function cleanUserUid(value) {
  return String(value || '').trim().slice(0, 128);
}

function eventRow(row) {
  return {
    id: String(row.id || ''),
    cardId: String(row.card_id || ''),
    userUid: row.user_uid || '',
    eventType: row.event_type || '',
    weight: Number(row.weight || 0),
    occurredAt: row.occurred_at || null,
    metadata: row.metadata || {},
    card: {
      name: row.name || '',
      setName: row.set_name || '',
      collectorNumber: row.collector_number || '',
      imageUrl: row.image_url || '',
    },
  };
}

function addFilter(filters, values, clause, value) {
  values.push(value);
  filters.push(clause.replace('?', `$${values.length}`));
}

async function readMarketplaceEvents(queryParams = {}) {
  const limit = cleanLimit(queryParams.limit);
  const windowKey = cleanWindow(queryParams.window);
  const eventType = cleanEventType(queryParams.eventType);
  const cardId = cleanCardId(queryParams.cardId);
  const userUid = cleanUserUid(queryParams.userUid);
  const values = [WINDOW_INTERVALS[windowKey]];
  const filters = ['e.occurred_at >= now() - $1::interval'];

  if (eventType) addFilter(filters, values, 'e.event_type = ?', eventType);
  if (cardId) addFilter(filters, values, 'e.card_id = ?', cardId);
  if (userUid) addFilter(filters, values, 'e.user_uid = ?', userUid);
  values.push(limit);
  const limitParam = `$${values.length}`;
  const where = filters.join('\n        and ');

  const result = await marketplaceQuery(
    `
      select
        e.id,
        e.card_id,
        coalesce(e.user_uid, '') as user_uid,
        e.event_type,
        e.weight,
        e.metadata,
        e.occurred_at,
        coalesce(nullif(c.display_name, ''), nullif(c.name, ''), b.name, '') as name,
        coalesce(nullif(c.set_name, ''), nullif(b.expansion->>'name', ''), '') as set_name,
        coalesce(
          nullif(c.card_number, ''),
          nullif(b.blueprint->>'number', ''),
          nullif(b.blueprint->>'collector_number', ''),
          nullif(b.blueprint->>'card_number', ''),
          b.version,
          ''
        ) as collector_number,
        coalesce(
          nullif(c.preview_image_url, ''),
          nullif(c.cdn_image_url, ''),
          nullif(c.image_url, ''),
          nullif(b.preview_image_url, ''),
          nullif(b.cdn_image_url, ''),
          nullif(b.image_url, ''),
          ''
        ) as image_url
      from public.marketplace_card_events e
      left join public.marketplace_search_candidates c
        on c.card_id = e.card_id
      left join public.cardtrader_pokemon_blueprints b
        on b.id = e.card_id
      where ${where}
      order by e.occurred_at desc, e.id desc
      limit ${limitParam}
    `,
    values,
  );

  const summary = {};
  for (const row of result.rows) {
    const key = row.event_type || 'unknown';
    summary[key] = (summary[key] || 0) + 1;
  }
  return {
    rows: result.rows.map(eventRow),
    summary,
    filters: {
      limit,
      window: windowKey,
      interval: WINDOW_INTERVALS[windowKey],
      eventType,
      cardId: cardId ? String(cardId) : '',
      userUid,
    },
    generatedAt: new Date().toISOString(),
  };
}

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    await authorizeSearchDebugRequest(req);
    const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
    const payload = await readMarketplaceEvents(Object.fromEntries(url.searchParams));
    res.setHeader('Cache-Control', 'no-store');
    return res.status(200).json(payload);
  } catch (error) {
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Marketplace debug events failed.',
    });
  }
};

module.exports.cleanCardId = cleanCardId;
module.exports.cleanEventType = cleanEventType;
module.exports.cleanLimit = cleanLimit;
module.exports.cleanUserUid = cleanUserUid;
module.exports.cleanWindow = cleanWindow;
module.exports.eventRow = eventRow;
module.exports.readMarketplaceEvents = readMarketplaceEvents;
