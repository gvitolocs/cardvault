const {
  listMarketplaceImages,
  recordMarketplaceImage,
} = require('./_marketplace_image_log');

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Max-Age': '86400',
};

const hitsByIp = new Map();

function clientIp(req) {
  const forwarded = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim();
  return forwarded || String(req.socket?.remoteAddress || req.headers['x-real-ip'] || '');
}

function rateLimited(ip) {
  const now = Date.now();
  const windowMs = 60_000;
  const current = hitsByIp.get(ip) || [];
  const fresh = current.filter((stamp) => now - stamp < windowMs);
  if (fresh.length >= 40) {
    hitsByIp.set(ip, fresh);
    return true;
  }
  fresh.push(now);
  hitsByIp.set(ip, fresh);
  return false;
}

module.exports = async function handler(req, res) {
  for (const [key, value] of Object.entries(CORS_HEADERS)) {
    res.setHeader(key, value);
  }
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }
  if (req.method === 'GET') {
    const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
    const rows = listMarketplaceImages(url.searchParams.get('limit'));
    res.setHeader('Cache-Control', 'no-store');
    return res.status(200).json({ count: rows.length, rows });
  }
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'GET, POST, OPTIONS');
    return res.status(405).json({ error: 'Method not allowed.' });
  }
  if (rateLimited(clientIp(req))) {
    return res.status(429).json({ error: 'Too many image logs.' });
  }
  const body = req.body && typeof req.body === 'object' ? req.body : {};
  const entry = recordMarketplaceImage({
    source: body.source || 'client',
    status: body.status || 'error',
    route: body.route || body.routePath,
    cardId: body.cardId || body.card_id,
    ctId: body.ctId || body.ct_id,
    name: body.name,
    url: body.url || body.imageUrl,
    fallbackUrl: body.fallbackUrl,
    error: body.error,
    sessionId: body.sessionId,
  });
  return res.status(201).json({ ok: true, prefixKind: entry.prefixKind, prefix: entry.prefix });
};

module.exports._test = {
  clientIp,
  rateLimited,
};
