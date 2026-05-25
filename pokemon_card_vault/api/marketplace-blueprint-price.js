const { marketplaceQuery } = require('./_marketplace_db');

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

function cleanBlueprintId(value) {
  const text = String(value || '').trim();
  if (!/^[0-9]+$/.test(text)) {
    return '';
  }
  const id = Number(text);
  if (!Number.isSafeInteger(id) || id <= 0) {
    return '';
  }
  return String(id);
}

function priceRow(row, blueprintId) {
  if (!row || row.lowest_ask_pkn == null) {
    return {
      blueprint_id: blueprintId,
      card_id: blueprintId,
      price_pkn: null,
      currency: 'PKN',
      unit: 'PKN',
      source: null,
      listing_count: 0,
      listed_quantity: 0,
      updated_at: null,
    };
  }

  return {
    blueprint_id: String(row.blueprint_id ?? blueprintId),
    card_id: String(row.blueprint_id ?? blueprintId),
    price_pkn: Number(row.lowest_ask_pkn),
    currency: 'PKN',
    unit: 'PKN',
    source: row.source || 'lowest_listing',
    listing_count: Number(row.active_listing_count || 0),
    listed_quantity: Number(row.listed_quantity || 0),
    updated_at: row.refreshed_at || null,
  };
}

function pknFromUsdPrice(priceUsd) {
  const value = Number(priceUsd);
  if (!Number.isFinite(value) || value <= 0) {
    return null;
  }
  const referencePrice = Number(process.env.PKN_CHECKOUT_USDT_PRICE || PKN_USD_REFERENCE_PRICE);
  if (!Number.isFinite(referencePrice) || referencePrice <= 0) {
    return null;
  }
  return value / referencePrice;
}

function parseCardTraderOfferPrice(html) {
  const text = String(html || '');
  const scriptMatches = text.matchAll(
    /<script[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi,
  );
  for (const match of scriptMatches) {
    try {
      const parsed = JSON.parse(match[1]);
      const nodes = Array.isArray(parsed) ? parsed : [parsed];
      for (const node of nodes) {
        const offers = Array.isArray(node?.offers) ? node.offers : [node?.offers];
        for (const offer of offers) {
          const currency = String(offer?.priceCurrency || '').trim().toUpperCase();
          const price = Number(offer?.price);
          if (currency === 'USD' && Number.isFinite(price) && price > 0) {
            return price;
          }
        }
      }
    } catch (_) {
      // Ignore unrelated structured data blocks.
    }
  }
  const escapedMatch = text.match(/&quot;priceCurrency&quot;:&quot;USD&quot;,&quot;price&quot;:&quot;([0-9]+(?:\.[0-9]+)?)&quot;/);
  if (escapedMatch) {
    return Number(escapedMatch[1]);
  }
  const rawMatch = text.match(/"priceCurrency"\s*:\s*"USD"\s*,\s*"price"\s*:\s*"([0-9]+(?:\.[0-9]+)?)"/);
  return rawMatch ? Number(rawMatch[1]) : null;
}

async function readCardTraderPagePrice(blueprintId) {
  const cleanId = cleanBlueprintId(blueprintId);
  if (!cleanId) {
    return priceRow(null, blueprintId);
  }
  const response = await fetch(`https://www.cardtrader.com/en/cards/${cleanId}`, {
    headers: {
      Accept: 'text/html,application/xhtml+xml',
      'User-Agent': 'PokoinMarketplacePriceBot/1.0',
    },
  });
  if (!response.ok) {
    return priceRow(null, cleanId);
  }
  const html = await response.text();
  const usdPrice = parseCardTraderOfferPrice(html);
  const pricePkn = pknFromUsdPrice(usdPrice);
  if (pricePkn == null) {
    return priceRow(null, cleanId);
  }
  return priceRow(
    {
      blueprint_id: cleanId,
      lowest_ask_pkn: pricePkn,
      active_listing_count: 0,
      listed_quantity: 0,
      refreshed_at: new Date().toISOString(),
      source: 'cardtrader_public_offer',
    },
    cleanId,
  );
}

async function readCardTraderCachedPrice(blueprintId) {
  return readCardTraderPagePrice(blueprintId);
}

function linkedCardTraderPredicate() {
  return `
    (
      lower(coalesce(source, '')) = 'cardtrader'
      or lower(coalesce(source, '')) like 'cardtrader%'
      or lower(coalesce(source_listing_id, '')) like '%cardtrader%'
      or lower(coalesce(source_listing_id, '')) like '%cardtrader.com%'
    )
  `;
}

async function readBlueprintPrice(blueprintId, options = {}) {
  const cleanId = cleanBlueprintId(blueprintId);
  if (!cleanId) {
    const error = new Error('Missing or invalid blueprintId.');
    error.statusCode = 400;
    throw error;
  }

  if (options.source === 'cardtrader') {
    return readCardTraderCachedPrice(cleanId);
  }

  const cardTraderResult = await marketplaceQuery(
    `
      select
        card_id as blueprint_id,
        min(price_pkn) as lowest_ask_pkn,
        count(*)::int as active_listing_count,
        sum(quantity_available)::int as listed_quantity,
        max(updated_at) as refreshed_at,
        'cardtrader_lowest_listing' as source
      from public.marketplace_user_listings
      where card_id = $1
        and status = 'active'
        and quantity_available > 0
        and price_pkn > 0
        and ${linkedCardTraderPredicate()}
      group by card_id
      limit 1
    `,
    [cleanId],
  );
  if (cardTraderResult.rows[0]?.lowest_ask_pkn != null) {
    return priceRow(cardTraderResult.rows[0], cleanId);
  }

  const result = await marketplaceQuery(
    `
      select
        blueprint_id,
        listed_quantity,
        active_listing_count,
        lowest_ask_pkn,
        refreshed_at
      from public.marketplace_blueprint_price_summary
      where blueprint_id = $1::bigint
        and active_listing_count > 0
        and listed_quantity > 0
        and lowest_ask_pkn is not null
      limit 1
    `,
    [cleanId],
  );
  const summary = priceRow(result.rows[0], cleanId);
  return summary;
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
    const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
    const blueprintId = url.searchParams.get('blueprintId') || url.searchParams.get('cardId');
    const source = String(url.searchParams.get('source') || '').trim().toLowerCase();
    const price = await readBlueprintPrice(blueprintId, { source });
    res.setHeader('Cache-Control', 'public, max-age=10, s-maxage=30');
    if (price.price_pkn == null) {
      return res.status(404).json({
        ...price,
        error: source === 'cardtrader'
          ? 'No active CardTrader PKN price found for this blueprint.'
          : 'No active PKN listing price found for this blueprint.',
      });
    }
    return res.status(200).json(price);
  } catch (error) {
    console.error('marketplace-blueprint-price failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Marketplace blueprint price failed.',
    });
  }
};

module.exports.cleanBlueprintId = cleanBlueprintId;
module.exports.linkedCardTraderPredicate = linkedCardTraderPredicate;
module.exports.parseCardTraderOfferPrice = parseCardTraderOfferPrice;
module.exports.pknFromUsdPrice = pknFromUsdPrice;
module.exports.priceRow = priceRow;
module.exports.readBlueprintPrice = readBlueprintPrice;
module.exports.readCardTraderCachedPrice = readCardTraderCachedPrice;
module.exports.readCardTraderPagePrice = readCardTraderPagePrice;
module.exports.setCorsHeaders = setCorsHeaders;
