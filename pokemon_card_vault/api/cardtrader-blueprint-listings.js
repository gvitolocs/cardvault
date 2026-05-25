const { marketplaceQuery } = require('./_marketplace_db');

const PROVIDER = 'cardtrader';
const DEFAULT_LIMIT = 100;
const MAX_LIMIT = 250;
const MAX_PAGE = 1000;
const SENSITIVE_METADATA_KEY = /(token|secret|password|authorization|credential|cookie|api[_-]?key|private[_-]?key|email|phone)/i;

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
  return String(value || '').trim().slice(0, maxLength);
}

function cleanNumericId(value) {
  const text = cleanText(value, 80);
  if (!/^[0-9]+$/.test(text)) return '';
  const number = Number(text);
  return Number.isSafeInteger(number) && number > 0 ? String(number) : '';
}

function cleanCardId(value) {
  const text = cleanText(value, 80);
  return /^[A-Za-z0-9:_-]+$/.test(text) ? text : '';
}

function cleanLimit(value, fallback = DEFAULT_LIMIT) {
  if (value == null || value === '') return fallback;
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(Math.max(Math.trunc(number), 1), MAX_LIMIT);
}

function cleanPage(value) {
  if (value == null || value === '') return 1;
  const number = Number(value);
  if (!Number.isFinite(number)) return 1;
  return Math.min(Math.max(Math.trunc(number), 1), MAX_PAGE);
}

function firstSearchValue(searchParams, names) {
  for (const name of names) {
    const value = searchParams.get(name);
    if (value != null && String(value).trim()) return value;
  }
  return '';
}

function parseListingRequest(searchParams) {
  const blueprintInput = firstSearchValue(searchParams, [
    'blueprintId',
    'blueprint_id',
    'cardtraderBlueprintId',
    'cardtrader_blueprint_id',
    'id',
  ]);
  const cardInput = firstSearchValue(searchParams, ['cardId', 'card_id']);
  const blueprintId = blueprintInput ? cleanNumericId(blueprintInput) : '';
  const cardId = cardInput ? cleanCardId(cardInput) : '';

  if (blueprintInput && !blueprintId) {
    const error = new Error('Missing or invalid blueprintId.');
    error.statusCode = 400;
    throw error;
  }
  if (cardInput && !cardId) {
    const error = new Error('Missing or invalid cardId.');
    error.statusCode = 400;
    throw error;
  }
  if (!blueprintId && !cardId) {
    const error = new Error('Provide blueprintId or cardId.');
    error.statusCode = 400;
    throw error;
  }

  return {
    blueprintId,
    cardId,
    requestedId: blueprintId || cardId,
    requestedParam: blueprintId ? 'blueprintId' : 'cardId',
    limit: cleanLimit(searchParams.get('limit')),
    page: cleanPage(searchParams.get('page')),
    cursor: cleanText(searchParams.get('cursor'), 500),
  };
}

function toIsoString(value) {
  if (value == null || value === '') return null;
  if (value instanceof Date) return value.toISOString();
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? String(value) : date.toISOString();
}

function numberOrNull(value) {
  if (value == null || value === '') return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function integerOrNull(value) {
  if (value == null || value === '') return null;
  const number = Number(value);
  return Number.isSafeInteger(number) ? Math.trunc(number) : null;
}

function sanitizeMetadata(value, depth = 0) {
  if (value == null) return null;
  if (depth > 4) return null;
  if (Array.isArray(value)) {
    return value.slice(0, 50).map((item) => sanitizeMetadata(item, depth + 1));
  }
  if (typeof value === 'object') {
    const output = {};
    for (const [key, nestedValue] of Object.entries(value)) {
      const cleanKey = cleanText(key, 120);
      if (!cleanKey || SENSITIVE_METADATA_KEY.test(cleanKey)) continue;
      output[cleanKey] = sanitizeMetadata(nestedValue, depth + 1);
    }
    return output;
  }
  if (typeof value === 'string') return cleanText(value, 1000);
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value === 'boolean') return value;
  return null;
}

function encodeCursor(row) {
  const lastSeenAt = toIsoString(row.last_seen_at);
  const externalListingId = cleanText(row.external_listing_id, 240);
  if (!lastSeenAt || !externalListingId) return '';
  return Buffer.from(JSON.stringify([lastSeenAt, externalListingId]), 'utf8').toString('base64url');
}

function decodeCursor(cursor) {
  const text = cleanText(cursor, 500);
  if (!text) return null;
  try {
    const decoded = JSON.parse(Buffer.from(text, 'base64url').toString('utf8'));
    if (!Array.isArray(decoded) || decoded.length !== 2) return null;
    const lastSeenAt = toIsoString(decoded[0]);
    const externalListingId = cleanText(decoded[1], 240);
    if (!lastSeenAt || !externalListingId) return null;
    return { lastSeenAt, externalListingId };
  } catch (_) {
    return null;
  }
}

function listingRow(row = {}) {
  return {
    externalListingId: row.external_listing_id || '',
    externalProductId: row.external_product_id || '',
    blueprintId: row.blueprint_id == null ? null : String(row.blueprint_id),
    cardtraderBlueprintId: row.cardtrader_blueprint_id == null
      ? row.blueprint_id == null ? null : String(row.blueprint_id)
      : String(row.cardtrader_blueprint_id),
    pokoinCardId: row.pokoin_card_id || '',
    price: numberOrNull(row.price),
    priceCents: integerOrNull(row.price_cents),
    currency: row.currency || '',
    quantity: Number(row.quantity || 0),
    condition: row.condition || '',
    language: row.language || '',
    properties: sanitizeMetadata(row.properties || {}),
    rawMetadata: sanitizeMetadata(row.raw_metadata || {}),
    seller: {
      accountId: row.seller_account_id || '',
      accountName: row.seller_account_name || '',
      country: row.seller_country || '',
      type: row.seller_type || '',
    },
    firstSeenAt: toIsoString(row.first_seen_at),
    lastSeenAt: toIsoString(row.last_seen_at),
    importedAt: toIsoString(row.imported_at),
    updatedAt: toIsoString(row.updated_at),
    source: {
      provider: row.provider || PROVIDER,
      table: 'cardtrader_market_listing_snapshots',
    },
  };
}

function queryConditionsForRequest(request, values) {
  const filters = ['provider = $1', 'quantity > 0'];
  const matchConditions = [];
  values.push(PROVIDER);

  function addNumericMatch(id) {
    if (!id) return;
    const index = values.push(id);
    matchConditions.push(`blueprint_id = $${index}::bigint`);
    matchConditions.push(`cardtrader_blueprint_id = $${index}::bigint`);
  }

  function addCardMatch(id) {
    if (!id) return;
    const index = values.push(id);
    matchConditions.push(`pokoin_card_id = $${index}::text`);
    const numericId = cleanNumericId(id);
    if (numericId) {
      const numericIndex = values.push(numericId);
      matchConditions.push(`blueprint_id = $${numericIndex}::bigint`);
      matchConditions.push(`cardtrader_blueprint_id = $${numericIndex}::bigint`);
    }
  }

  addNumericMatch(request.blueprintId);
  addCardMatch(request.cardId);
  filters.push(`(${matchConditions.join(' or ')})`);
  return filters;
}

async function readCardTraderBlueprintListings(request, query = marketplaceQuery) {
  const values = [];
  const filters = queryConditionsForRequest(request, values);
  const cursor = decodeCursor(request.cursor);
  if (request.cursor && !cursor) {
    const error = new Error('Invalid cursor.');
    error.statusCode = 400;
    throw error;
  }
  if (cursor) {
    const lastSeenIndex = values.push(cursor.lastSeenAt);
    const listingIndex = values.push(cursor.externalListingId);
    filters.push(`(
      last_seen_at < $${lastSeenIndex}::timestamptz
      or (
        last_seen_at = $${lastSeenIndex}::timestamptz
        and external_listing_id > $${listingIndex}::text
      )
    )`);
  }

  const limit = cleanLimit(request.limit);
  const page = cleanPage(request.page);
  const offset = cursor ? 0 : (page - 1) * limit;
  const limitIndex = values.push(limit + 1);
  const offsetIndex = values.push(offset);
  const result = await query(
    `
      select
        provider,
        external_listing_id,
        external_product_id,
        blueprint_id,
        cardtrader_blueprint_id,
        pokoin_card_id,
        seller_account_id,
        seller_account_name,
        seller_country,
        seller_type,
        quantity,
        condition,
        language,
        price,
        price_cents,
        currency,
        properties,
        raw_metadata,
        first_seen_at,
        last_seen_at,
        imported_at,
        updated_at
      from public.cardtrader_market_listing_snapshots
      where ${filters.join('\n        and ')}
      order by last_seen_at desc, external_listing_id asc
      limit $${limitIndex}
      offset $${offsetIndex}
    `,
    values,
  );
  const rows = result.rows || [];
  const pageRows = rows.slice(0, limit);
  const lastRow = pageRows[pageRows.length - 1];
  const hasMore = rows.length > limit;
  const cardtraderBlueprintIds = [...new Set(pageRows
    .map((row) => row.cardtrader_blueprint_id ?? row.blueprint_id)
    .filter((id) => id != null)
    .map(String))];
  const pokoinCardIds = [...new Set(pageRows
    .map((row) => row.pokoin_card_id)
    .filter(Boolean)
    .map(String))];

  return {
    ok: true,
    provider: PROVIDER,
    source: 'oracle_cardtrader_market_listing_snapshots',
    liveCardTraderApiUsed: false,
    requested: {
      id: request.requestedId,
      param: request.requestedParam,
      blueprintId: request.blueprintId || null,
      cardId: request.cardId || null,
    },
    mapping: {
      cardtraderBlueprintIds,
      pokoinCardIds,
      supportsPokoinCardId: true,
    },
    pagination: {
      limit,
      page: cursor ? null : page,
      cursor: request.cursor || null,
      nextCursor: hasMore && lastRow ? encodeCursor(lastRow) : null,
      nextPage: hasMore && !cursor ? page + 1 : null,
      hasMore,
    },
    count: pageRows.length,
    listings: pageRows.map(listingRow),
  };
}

function tableMissingResponse(res, error) {
  return res.status(503).json({
    error: 'CardTrader global market listing Oracle table is not installed yet.',
    setupRequired: true,
    migration: 'oracle-postgres/schema/012_cardtrader_market_listings.sql',
    code: error.code,
  });
}

module.exports = async function handler(req, res) {
  setCorsHeaders(res);
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET, OPTIONS');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const url = new URL(req.url || '/', `https://${req.headers?.host || 'pokoin.com'}`);
    const request = parseListingRequest(url.searchParams);
    const payload = await readCardTraderBlueprintListings(request);
    res.setHeader('Cache-Control', 'public, max-age=15, s-maxage=120');
    return res.status(200).json(payload);
  } catch (error) {
    if (error.code === '42P01') return tableMissingResponse(res, error);
    console.error('cardtrader-blueprint-listings failed', {
      code: error.code || '',
      statusCode: error.statusCode || 500,
      message: error.message,
    });
    return res.status(error.statusCode || 500).json({
      error: error.message || 'CardTrader blueprint listings lookup failed.',
      code: error.code,
    });
  }
};

module.exports._test = {
  cleanCardId,
  cleanLimit,
  cleanNumericId,
  cleanPage,
  decodeCursor,
  encodeCursor,
  listingRow,
  parseListingRequest,
  queryConditionsForRequest,
  readCardTraderBlueprintListings,
  sanitizeMetadata,
  setCorsHeaders,
};
