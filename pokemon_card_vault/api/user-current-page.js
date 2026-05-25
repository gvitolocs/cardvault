const { marketplaceQuery } = require('./_marketplace_db');
const { bearerTokenFromRequest, getFirebaseAdmin } = require('./_firebase');

const MIGRATION_PATH = 'oracle-postgres/schema/013_assistant_user_current_pages.sql';
const MAX_SESSION_ID_LENGTH = 160;

function cleanText(value, maxLength = 240) {
  return String(value || '').trim().slice(0, maxLength);
}

function headerValue(req, name) {
  const headers = req?.headers || {};
  const key = Object.keys(headers).find((entry) => entry.toLowerCase() === name.toLowerCase());
  const value = key ? headers[key] : '';
  return Array.isArray(value) ? value[0] || '' : String(value || '');
}

function cleanSessionId(value) {
  const text = cleanText(value, MAX_SESSION_ID_LENGTH);
  return /^[a-zA-Z0-9_.:-]{8,160}$/.test(text) ? text : '';
}

function cleanInternalPath(value) {
  const raw = cleanText(value, 800);
  if (!raw || raw.includes('\r') || raw.includes('\n')) {
    return '';
  }
  if (raw.startsWith('/')) {
    return isSafeInternalPath(raw) ? raw : '';
  }
  try {
    const url = new URL(raw);
    const host = url.hostname.toLowerCase();
    if ((url.protocol !== 'https:' && url.protocol !== 'http:') ||
        (host !== 'pokoin.com' && host !== 'www.pokoin.com')) {
      return '';
    }
    const path = `${url.pathname || '/'}${url.search}`;
    return isSafeInternalPath(path) ? path : '';
  } catch (_) {
    return '';
  }
}

function isSafeInternalPath(path) {
  return path.startsWith('/') &&
    !path.startsWith('//') &&
    !path.includes('\\') &&
    !path.includes('\r') &&
    !path.includes('\n') &&
    !/\/\.(?:\.|%2e)(?:\/|$)/i.test(path) &&
    path.length <= 800;
}

async function userScopeFromRequest(req) {
  const token = bearerTokenFromRequest(req);
  if (!token) {
    return { userUid: '', authenticated: false };
  }
  const decoded = await getFirebaseAdmin().auth().verifyIdToken(token);
  return {
    userUid: cleanText(decoded.uid, 160),
    authenticated: true,
  };
}

function sessionIdFromRequest(req) {
  const url = new URL(req.url || '/api/user-current-page', `https://${headerValue(req, 'host') || 'pokoin.com'}`);
  return cleanSessionId(
    req.body?.sessionId ||
    req.body?.session_id ||
    url.searchParams.get('sessionId') ||
    url.searchParams.get('session_id') ||
    headerValue(req, 'x-pokoin-session-id'),
  );
}

function currentPageRow(row) {
  return {
    sessionId: row.session_id || '',
    userUid: row.user_uid || '',
    path: row.path || '',
    source: row.source || '',
    updatedAt: row.updated_at || null,
  };
}

async function readCurrentPage({ sessionId, userUid }) {
  const result = await marketplaceQuery(
    `
      select session_id, user_uid, path, source, updated_at
      from public.assistant_user_current_pages
      where (
          $2::text <> ''
          and user_uid = $2
        ) or (
          $2::text = ''
          and session_id = $1
          and user_uid = ''
        )
      order by updated_at desc
      limit 1
    `,
    [sessionId, userUid],
  );
  return result.rows[0] ? currentPageRow(result.rows[0]) : null;
}

async function writeCurrentPage({ sessionId, userUid, path, source }) {
  const result = await marketplaceQuery(
    `
      insert into public.assistant_user_current_pages (
        session_id,
        user_uid,
        path,
        source,
        updated_at
      )
      values ($1, $2, $3, $4, now())
      on conflict (session_id, user_uid)
      do update set
        path = excluded.path,
        source = excluded.source,
        updated_at = now()
      returning session_id, user_uid, path, source, updated_at
    `,
    [sessionId, userUid, path, source],
  );
  return currentPageRow(result.rows[0] || {});
}

function isMissingTableError(error) {
  return error && error.code === '42P01';
}

function tableMissingResponse(res) {
  return res.status(503).json({
    error: 'Assistant current-page table is not installed yet.',
    setupRequired: true,
    migration: MIGRATION_PATH,
  });
}

module.exports = async function handler(req, res) {
  if (req.method !== 'GET' && req.method !== 'POST') {
    res.setHeader('Allow', 'GET, POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const scope = await userScopeFromRequest(req).catch((error) => {
      if (bearerTokenFromRequest(req)) {
        throw error;
      }
      return { userUid: '', authenticated: false };
    });
    const sessionId = sessionIdFromRequest(req);
    if (!sessionId) {
      return res.status(400).json({ error: 'A valid sessionId is required.' });
    }

    res.setHeader('Cache-Control', 'no-store');
    if (req.method === 'GET') {
      const page = await readCurrentPage({ sessionId, userUid: scope.userUid });
      return res.status(200).json({
        page,
        sessionId,
        authenticated: scope.authenticated,
      });
    }

    const path = cleanInternalPath(req.body?.path || req.body?.url);
    if (!path) {
      return res.status(400).json({ error: 'A safe internal Pokoin path is required.' });
    }
    const page = await writeCurrentPage({
      sessionId,
      userUid: scope.userUid,
      path,
      source: cleanText(req.body?.source || 'assistant', 80) || 'assistant',
    });
    return res.status(200).json({ ok: true, page });
  } catch (error) {
    if (isMissingTableError(error)) {
      return tableMissingResponse(res);
    }
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Assistant current page failed.',
    });
  }
};

module.exports._test = {
  cleanInternalPath,
  cleanSessionId,
  currentPageRow,
  readCurrentPage,
  sessionIdFromRequest,
  writeCurrentPage,
};
