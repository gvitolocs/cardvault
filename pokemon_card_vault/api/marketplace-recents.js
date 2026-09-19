'use strict';

const { marketplaceQuery, marketplaceWriteQuery } = require('./_marketplace_db');
const { authErrorResponse, verifyBearerToken } = require('./_firebase');
const {
  parsePublicCardId,
  setCorsHeaders,
} = require('./_marketplace_react_card');

const RECENT_MAX = 24;

function normalizeRecentIds(values) {
  const out = [];
  const seen = new Set();
  for (const value of values || []) {
    const id = parsePublicCardId(value);
    if (!id || seen.has(id)) {
      continue;
    }
    seen.add(id);
    out.push(id);
    if (out.length >= RECENT_MAX) {
      break;
    }
  }
  return out;
}

function isUndefinedTable(error) {
  return error?.code === '42P01' || /does not exist/i.test(String(error?.message || ''));
}

async function readRecents(uid) {
  try {
    const result = await marketplaceQuery(
      `select card_ids
         from public.marketplace_user_recents
        where user_uid = $1
        limit 1`,
      [uid],
    );
    return normalizeRecentIds(result.rows[0]?.card_ids || []);
  } catch (error) {
    if (isUndefinedTable(error)) {
      return [];
    }
    throw error;
  }
}

async function writeRecents(uid, ids) {
  const cardIds = normalizeRecentIds(ids);
  await marketplaceWriteQuery(
    `insert into public.marketplace_user_recents (user_uid, card_ids, updated_at)
     values ($1, $2::bigint[], now())
     on conflict (user_uid) do update
       set card_ids = excluded.card_ids,
           updated_at = now()`,
    [uid, cardIds],
  );
  return cardIds;
}

function cors(res) {
  setCorsHeaders(res);
  res.setHeader('Access-Control-Allow-Methods', 'GET, PUT, POST, OPTIONS');
}

function jsonPrivate(res, body) {
  cors(res);
  res.setHeader('Cache-Control', 'private, no-store');
  return res.status(200).json(body);
}

module.exports = async function handler(req, res) {
  cors(res);
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }
  try {
    const decoded = await verifyBearerToken(req);
    const uid = String(decoded.uid || '').trim();
    if (!uid) {
      return res.status(401).json({ error: 'Missing Pokoin user.' });
    }
    if (req.method === 'GET') {
      return jsonPrivate(res, { cardIds: await readRecents(uid) });
    }
    if (req.method === 'PUT' || req.method === 'POST') {
      const incoming = req.body?.cardIds || req.body?.card_ids || [];
      const extra = req.body?.cardId ?? req.body?.card_id;
      const merged = extra != null && extra !== ''
        ? [extra, ...(Array.isArray(incoming) ? incoming : [])]
        : incoming;
      return jsonPrivate(res, { cardIds: await writeRecents(uid, merged) });
    }
    res.setHeader('Allow', 'GET, PUT, POST, OPTIONS');
    return res.status(405).json({ error: 'GET, PUT, or POST only.' });
  } catch (error) {
    if (error.statusCode === 401 || error.code === 'auth/id-token-expired') {
      const auth = authErrorResponse(error);
      return res.status(auth.statusCode).json(auth.body);
    }
    console.error('marketplace-recents failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Recents failed.',
    });
  }
};

module.exports._test = {
  normalizeRecentIds,
  isUndefinedTable,
};
