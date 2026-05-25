const { marketplaceQuery } = require('./_marketplace_db');
const { authorizeSearchDebugRequest } = require('./_search_debug_auth');

const MAX_PAYLOAD_DEPTH = 4;
const MAX_PAYLOAD_KEYS = 60;
const MAX_PAYLOAD_ARRAY = 80;
const SECRET_KEY_PATTERN =
  /(authorization|cookie|credential|password|secret|token|api[_-]?key|private[_-]?key|session)/i;
const DEBUG_TOKEN_ENVS = [
  'FLUTTER_DEBUG_LOG_TOKEN',
  'POKOIN_DEBUG_LOG_TOKEN',
  'MARKETPLACE_DEBUG_LOG_TOKEN',
];
const MIGRATION_PATH = 'oracle-postgres/schema/010_flutter_debug_logs.sql';
const DEFAULT_READ_LIMIT = 200;
const MAX_READ_LIMIT = 5000;

function configuredDebugToken() {
  for (const name of DEBUG_TOKEN_ENVS) {
    const token = String(process.env[name] || '').trim();
    if (token) return token;
  }
  return '';
}

function headerValue(headers, name) {
  if (!headers) return '';
  return headers[name] || headers[name.toLowerCase()] || headers[name.toUpperCase()] || '';
}

function requestDebugToken(req) {
  const direct =
    headerValue(req.headers, 'x-flutter-debug-token') ||
    headerValue(req.headers, 'x-pokoin-debug-token') ||
    headerValue(req.headers, 'x-debug-token');
  if (direct) return String(direct).trim();
  const authorization = String(headerValue(req.headers, 'authorization') || '');
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : '';
}

async function authorizeFlutterDebugRequest(req) {
  const configuredToken = configuredDebugToken();
  const suppliedToken = requestDebugToken(req);
  if (configuredToken && suppliedToken && suppliedToken === configuredToken) {
    return { uid: 'debug-token', username: 'debug-token' };
  }
  return authorizeSearchDebugRequest(req);
}

function cleanText(value, maxLength = 240) {
  return String(value || '').trim().slice(0, maxLength);
}

function cleanIdentifier(value) {
  return cleanText(value, 160);
}

function cleanEventName(value) {
  return cleanText(value, 120)
    .toLowerCase()
    .replace(/[^a-z0-9_.:-]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function cleanCategory(value) {
  return cleanEventName(value || 'flutter') || 'flutter';
}

function cleanLimit(value, fallback = DEFAULT_READ_LIMIT) {
  const limit = Number(value);
  if (!Number.isFinite(limit)) return fallback;
  return Math.min(Math.max(Math.trunc(limit), 1), MAX_READ_LIMIT);
}

function cleanTimestamp(value) {
  const raw = cleanText(value, 80);
  if (!raw) return null;
  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) return null;
  return date.toISOString();
}

function cleanUrl(value) {
  const raw = cleanText(value, 1000);
  if (!raw) return '';
  try {
    const isAbsolute = /^[a-z][a-z0-9+.-]*:\/\//i.test(raw);
    const parsed = new URL(raw, 'https://pokoin.com');
    for (const key of [...parsed.searchParams.keys()]) {
      if (SECRET_KEY_PATTERN.test(key)) {
        parsed.searchParams.delete(key);
      }
    }
    if (isAbsolute) {
      return parsed.toString().slice(0, 1000);
    }
    return `${parsed.pathname}${parsed.search}${parsed.hash}`.slice(0, 1000);
  } catch (_) {
    return raw.replace(SECRET_KEY_PATTERN, '[redacted]').slice(0, 1000);
  }
}

function sanitizeValue(value, depth = 0) {
  if (value == null || typeof value === 'boolean') return value;
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value === 'string') return value.slice(0, 1000);
  if (depth >= MAX_PAYLOAD_DEPTH) return '[truncated]';
  if (Array.isArray(value)) {
    return value
      .slice(0, MAX_PAYLOAD_ARRAY)
      .map((entry) => sanitizeValue(entry, depth + 1));
  }
  if (typeof value === 'object') {
    const result = {};
    for (const [key, rawEntry] of Object.entries(value).slice(0, MAX_PAYLOAD_KEYS)) {
      const cleanKey = cleanText(key, 80);
      if (!cleanKey || SECRET_KEY_PATTERN.test(cleanKey)) continue;
      result[cleanKey] = sanitizeValue(rawEntry, depth + 1);
    }
    return result;
  }
  return String(value).slice(0, 1000);
}

function eventInput(body = {}, authorizedUser = {}) {
  const eventName = cleanEventName(body.eventName || body.name || body.event || body.type);
  const category = cleanCategory(body.category || body.source || 'flutter');
  const sessionId = cleanIdentifier(body.sessionId || body.session_id);
  const userId = cleanIdentifier(
    body.userId ||
      body.user_id ||
      body.debugUserId ||
      body.debug_user_id ||
      body.user?.uid,
  );
  const routePath = cleanText(body.route || body.path || body.routePath || body.route_path, 500);
  const browserUrl = cleanUrl(body.url || body.browserUrl || body.browser_url);
  const payload = sanitizeValue(body.payload || body.details || body.data || {});

  return {
    clientTimestamp: cleanTimestamp(
      body.clientTimestamp || body.clientTime || body.timestamp || body.at,
    ),
    sessionId,
    debugUserUid: cleanIdentifier(authorizedUser.uid),
    clientUserId: userId,
    routePath,
    browserUrl,
    eventName,
    category,
    payload,
  };
}

function requireValidEvent(input) {
  if (!input.eventName) {
    const error = new Error('Flutter debug event name is required.');
    error.statusCode = 400;
    throw error;
  }
  if (!input.sessionId) {
    const error = new Error('Flutter debug session id is required.');
    error.statusCode = 400;
    throw error;
  }
}

function tableMissingResponse(res) {
  return res.status(503).json({
    error: 'Flutter debug log table is not installed yet.',
    setupRequired: true,
    migration: MIGRATION_PATH,
  });
}

function isMissingTableError(error) {
  return error && error.code === '42P01';
}

function publicRow(row) {
  return {
    id: String(row.id || ''),
    receivedAt: row.received_at || null,
    clientTimestamp: row.client_timestamp || null,
    sessionId: row.session_id || '',
    debugUserUid: row.debug_user_uid || '',
    clientUserId: row.client_user_id || '',
    routePath: row.route_path || '',
    browserUrl: row.browser_url || '',
    eventName: row.event_name || '',
    category: row.category || '',
    payload: row.payload || {},
  };
}

function addFilter(filters, values, clause, value) {
  values.push(value);
  filters.push(clause.replace('?', `$${values.length}`));
}

async function writeFlutterDebugLog(input) {
  const result = await marketplaceQuery(
    `
      insert into public.flutter_debug_logs (
        client_timestamp,
        session_id,
        debug_user_uid,
        client_user_id,
        route_path,
        browser_url,
        event_name,
        category,
        payload
      )
      values ($1::timestamptz, $2, $3, $4, $5, $6, $7, $8, $9::jsonb)
      returning id, received_at
    `,
    [
      input.clientTimestamp,
      input.sessionId,
      input.debugUserUid,
      input.clientUserId,
      input.routePath,
      input.browserUrl,
      input.eventName,
      input.category,
      JSON.stringify(input.payload || {}),
    ],
  );
  return result.rows[0] || {};
}

async function readFlutterDebugLogs(query = {}) {
  const limit = cleanLimit(query.limit);
  const filters = [];
  const values = [];
  const sessionId = cleanIdentifier(query.sessionId || query.session_id);
  const userId = cleanIdentifier(query.userId || query.user || query.debugUserUid);
  const path = cleanText(query.path || query.routePath, 500);
  const category = cleanCategory(query.category || '');
  const eventName = cleanEventName(query.eventName || query.event || '');

  if (sessionId) addFilter(filters, values, 'session_id = ?', sessionId);
  if (userId) {
    values.push(userId);
    filters.push(`(debug_user_uid = $${values.length} or client_user_id = $${values.length})`);
  }
  if (path) addFilter(filters, values, 'route_path = ?', path);
  if (category && query.category) addFilter(filters, values, 'category = ?', category);
  if (eventName) addFilter(filters, values, 'event_name = ?', eventName);

  values.push(limit);
  const where = filters.length > 0 ? `where ${filters.join('\n        and ')}` : '';
  const result = await marketplaceQuery(
    `
      select
        id,
        received_at,
        client_timestamp,
        session_id,
        debug_user_uid,
        client_user_id,
        route_path,
        browser_url,
        event_name,
        category,
        payload
      from public.flutter_debug_logs
      ${where}
      order by received_at desc, id desc
      limit $${values.length}
    `,
    values,
  );

  return {
    rows: result.rows.map(publicRow),
    filters: {
      limit,
      sessionId,
      userId,
      path,
      category: query.category ? category : '',
      eventName,
    },
    generatedAt: new Date().toISOString(),
  };
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST' && req.method !== 'GET') {
    res.setHeader('Allow', 'GET, POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const authorizedUser = await authorizeFlutterDebugRequest(req);
    res.setHeader('Cache-Control', 'no-store');
    if (req.method === 'POST') {
      const input = eventInput(req.body || {}, authorizedUser);
      requireValidEvent(input);
      const row = await writeFlutterDebugLog(input);
      return res.status(201).json({
        ok: true,
        id: String(row.id || ''),
        receivedAt: row.received_at || null,
      });
    }

    const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
    const payload = await readFlutterDebugLogs(Object.fromEntries(url.searchParams));
    return res.status(200).json(payload);
  } catch (error) {
    if (isMissingTableError(error)) {
      return tableMissingResponse(res);
    }
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Flutter debug logs failed.',
    });
  }
};

module.exports._test = {
  cleanLimit,
  cleanUrl,
  eventInput,
  readFlutterDebugLogs,
  sanitizeValue,
};
