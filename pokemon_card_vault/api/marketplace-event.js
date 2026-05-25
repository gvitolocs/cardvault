const marketplaceDb = require('./_marketplace_db');
const { verifyBearerToken } = require('./_firebase');

const WEIGHTS = {
  view: 1,
  search: 2,
  click: 4,
  reserve: 10,
  cart_add: 8,
  sale: 20,
};

const ALLOWED_METADATA_KEYS = new Set([
  'source',
  'query',
  'resultRank',
  'resultCount',
  'language',
  'name',
  'set',
  'number',
  'rarity',
  'type',
  'itemKind',
  'productType',
  'trainerName',
  'tags',
]);

const HOT_REFRESH_INTERVAL = "2 minutes";

async function optionalUserUid(req) {
  const header = req.headers.authorization || '';
  if (!header.startsWith('Bearer ')) {
    return null;
  }
  try {
    const decoded = await verifyBearerToken(req);
    return typeof decoded.uid === 'string' && decoded.uid.trim()
      ? decoded.uid.trim().slice(0, 128)
      : null;
  } catch (error) {
    console.warn('marketplace-event auth ignored', {
      message: error.message,
      code: error.code,
      statusCode: error.statusCode,
    });
    return null;
  }
}

function cleanMetadata(value) {
  const source =
    value && typeof value === 'object' && !Array.isArray(value) ? value : {};
  const result = {};
  for (const [key, rawValue] of Object.entries(source)) {
    if (!ALLOWED_METADATA_KEYS.has(key) || rawValue == null) continue;
    if (typeof rawValue === 'string') {
      const text = rawValue.trim().slice(0, 160);
      if (text) result[key] = text;
    } else if (typeof rawValue === 'number' && Number.isFinite(rawValue)) {
      result[key] = Math.trunc(rawValue);
    } else if (typeof rawValue === 'boolean') {
      result[key] = rawValue;
    } else if (Array.isArray(rawValue)) {
      const values = rawValue
        .map((entry) => String(entry || '').trim().slice(0, 80))
        .filter(Boolean)
        .slice(0, 8);
      if (values.length > 0) result[key] = values;
    }
  }
  return result;
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  const cardId = Number(req.body?.cardId);
  const eventType = String(req.body?.eventType || '').trim();
  if (!Number.isSafeInteger(cardId) || cardId <= 0 || !WEIGHTS[eventType]) {
    return res.status(400).json({ error: 'Invalid marketplace event.' });
  }
  const metadata = cleanMetadata({
    ...(req.body?.metadata || {}),
    source: String(req.body?.source || 'web').slice(0, 40),
  });

  try {
    const userUid = await optionalUserUid(req);
    const values = [
      cardId,
      eventType,
      WEIGHTS[eventType],
      JSON.stringify(metadata),
    ];
    try {
      await marketplaceDb.marketplaceQuery(
        `
          insert into public.marketplace_card_events (card_id, event_type, weight, metadata, user_uid)
          values ($1, $2, $3, $4::jsonb, $5)
        `,
        [...values, userUid],
      );
    } catch (error) {
      if (error.code !== '42703') {
        throw error;
      }
      await marketplaceDb.marketplaceQuery(
        `
          insert into public.marketplace_card_events (card_id, event_type, weight, metadata)
          values ($1, $2, $3, $4::jsonb)
        `,
        values,
      );
    }

    const query = typeof metadata.query === 'string' ? metadata.query.trim() : '';
    if (eventType === 'search' && query.length >= 2) {
      await marketplaceDb.marketplaceQuery(
        `
          select public.record_marketplace_query_chunks($1, $2, $3, $4)
        `,
        [
          query,
          typeof metadata.language === 'string' ? metadata.language : 'en',
          eventType,
          WEIGHTS[eventType],
        ],
      ).catch((error) => {
        if (error.code !== '42P01' && error.code !== '42883') {
          throw error;
        }
      });
    }

    await marketplaceDb.marketplaceQuery(
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

    return res.status(204).end();
  } catch (error) {
    console.warn('marketplace-event failed', error);
    return res.status(204).end();
  }
};
