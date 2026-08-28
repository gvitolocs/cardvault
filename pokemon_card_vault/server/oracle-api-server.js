const http = require('http');
const { Readable } = require('stream');
const path = require('path');

const { routeDefinitions } = require('./api-route-manifest');
const { observeApiRequest } = require('../api/_api_observability');

const API_DIR = path.join(__dirname, '..', 'api');
const DEFAULT_HOST = process.env.ORACLE_API_HOST || '0.0.0.0';
const DEFAULT_PORT = Number(process.env.PORT || process.env.ORACLE_API_PORT || 8080);
const JSON_LIMIT_BYTES = Number(process.env.ORACLE_API_JSON_LIMIT_BYTES || 10 * 1024 * 1024);
const RAW_BODY_ROUTE_FILES = new Set(
  routeDefinitions.filter((route) => route.rawBody).map((route) => route.file),
);

function normalizePathname(pathname) {
  if (!pathname) return '/';
  if (pathname.length > 1 && pathname.endsWith('/')) {
    return pathname.slice(0, -1);
  }
  return pathname;
}

function queryFromSearchParams(searchParams) {
  const query = {};
  for (const [key, value] of searchParams.entries()) {
    if (Object.prototype.hasOwnProperty.call(query, key)) {
      const existing = query[key];
      query[key] = Array.isArray(existing) ? [...existing, value] : [existing, value];
    } else {
      query[key] = value;
    }
  }
  return query;
}

function compileRoute(definition) {
  const segments = definition.path.split('/').filter(Boolean);
  const paramNames = [];
  const pattern = segments
    .map((segment) => {
      if (segment.startsWith(':')) {
        paramNames.push(segment.slice(1));
        return '([^/]+)';
      }
      return segment.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    })
    .join('/');

  return {
    ...definition,
    handlerPath: path.join(API_DIR, definition.file),
    regexp: new RegExp(`^/${pattern}$`),
    paramNames,
  };
}

const compiledRoutes = routeDefinitions.map(compileRoute);

function routeForPathname(pathname) {
  const cleanPath = normalizePathname(pathname);
  for (const route of compiledRoutes) {
    const match = cleanPath.match(route.regexp);
    if (match) {
      return {
        route,
        params: Object.fromEntries(
          route.paramNames.map((name, index) => [name, decodeURIComponent(match[index + 1] || '')]),
        ),
      };
    }
  }

  if (cleanPath.startsWith('/api/') && cleanPath.endsWith('.js')) {
    const withoutExtension = cleanPath.slice(0, -3);
    return routeForPathname(withoutExtension);
  }

  return null;
}

function appendParamsToQuery(url, params) {
  for (const [key, value] of Object.entries(params)) {
    if (value && !url.searchParams.has(key)) {
      url.searchParams.set(key, value);
    }
  }
}

function addLegacyActionQuery(url, params) {
  if (params.action && !url.searchParams.has('action')) {
    url.searchParams.set('action', params.action);
  }
}

function readRequestBody(req, limitBytes = JSON_LIMIT_BYTES) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;

    req.on('data', (chunk) => {
      const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
      size += buffer.length;
      if (size > limitBytes) {
        reject(Object.assign(new Error('Request body too large.'), { statusCode: 413 }));
        req.destroy();
        return;
      }
      chunks.push(buffer);
    });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

function bodyFromBuffer(buffer, contentType) {
  if (!buffer.length) return {};
  const normalizedType = String(contentType || '').toLowerCase();
  if (normalizedType.includes('application/json') || normalizedType.includes('+json')) {
    const text = buffer.toString('utf8').trim();
    if (!text) return {};
    return JSON.parse(text);
  }
  if (normalizedType.includes('application/x-www-form-urlencoded')) {
    return Object.fromEntries(new URLSearchParams(buffer.toString('utf8')).entries());
  }
  return buffer;
}

function copyIncomingRequest(req, url, bodyBuffer) {
  const clone = Readable.from(bodyBuffer);
  clone.method = req.method;
  clone.url = `${url.pathname}${url.search}`;
  clone.headers = req.headers;
  clone.query = queryFromSearchParams(url.searchParams);
  clone.params = {};
  clone.rawBody = bodyBuffer;
  clone.socket = req.socket;
  clone.connection = req.connection;
  clone.httpVersion = req.httpVersion;
  clone.httpVersionMajor = req.httpVersionMajor;
  clone.httpVersionMinor = req.httpVersionMinor;
  clone.complete = req.complete;
  clone.aborted = req.aborted;
  clone.destroyed = req.destroyed;
  return clone;
}

function decorateResponse(res) {
  res.status = function status(code) {
    res.statusCode = Number(code) || 200;
    return res;
  };
  res.json = function json(payload) {
    if (!res.headersSent && !res.getHeader('Content-Type')) {
      res.setHeader('Content-Type', 'application/json; charset=utf-8');
    }
    return res.end(JSON.stringify(payload));
  };
  res.send = function send(payload) {
    if (Buffer.isBuffer(payload)) {
      return res.end(payload);
    }
    if (payload && typeof payload === 'object') {
      return res.json(payload);
    }
    if (!res.headersSent && !res.getHeader('Content-Type')) {
      res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    }
    return res.end(payload == null ? '' : String(payload));
  };
  res.redirect = function redirect(statusOrUrl, maybeUrl) {
    const statusCode = typeof statusOrUrl === 'number' ? statusOrUrl : 302;
    const location = typeof statusOrUrl === 'number' ? maybeUrl : statusOrUrl;
    res.statusCode = statusCode;
    res.setHeader('Location', location);
    return res.end();
  };
  return res;
}

function sendJson(res, statusCode, payload) {
  if (res.writableEnded) return;
  res.statusCode = statusCode;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(payload));
}

function sendHtml(res, statusCode, html) {
  if (res.writableEnded) return;
  res.statusCode = statusCode;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(html);
}

function stagingMarketplaceHtml(host = 'newapi.pokoin.com') {
  const safeHost = String(host || 'newapi.pokoin.com').replace(/[<>"'&]/g, '');
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Pokoin Oracle API Staging</title>
  <style>
    body { font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 2rem; line-height: 1.5; color: #172033; }
    main { max-width: 860px; }
    code, pre { background: #f5f7fb; border-radius: 6px; padding: 0.15rem 0.35rem; }
    a { color: #2457c5; }
    .badge { display: inline-block; background: #fff3cd; border: 1px solid #ffe08a; border-radius: 999px; padding: 0.2rem 0.65rem; font-size: 0.9rem; }
  </style>
</head>
<body>
  <main>
    <p class="badge">Oracle API staging</p>
    <h1>Pokoin Oracle API staging endpoint</h1>
    <p>This host is for testing the standalone Node API service before any production traffic is switched. It does not serve the Flutter marketplace app.</p>
    <h2>Useful checks</h2>
    <ul>
      <li><a href="/healthz">/healthz</a> - service health</li>
      <li><a href="/api/__routes">/api/__routes</a> - compact route index</li>
      <li><a href="/api/marketplace-home">/api/marketplace-home</a> - read-only marketplace API example</li>
      <li><a href="/api/marketplace-blueprint-price?blueprintId=274416">/api/marketplace-blueprint-price?blueprintId=274416</a> - read-only price lookup example</li>
    </ul>
    <h2>Example</h2>
    <pre>curl https://${safeHost}/healthz
curl https://${safeHost}/api/__routes</pre>
    <p>Production <code>https://pokoin.com</code> remains separate until the Vercel proxy is explicitly changed.</p>
  </main>
</body>
</html>`;
}

async function callHandler(req, res, matched) {
  const { route, params } = matched;
  const requestUrl = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  appendParamsToQuery(requestUrl, params);
  addLegacyActionQuery(requestUrl, params);

  const handler = require(route.handlerPath);
  if (typeof handler !== 'function') {
    sendJson(res, 500, { error: `API route ${route.file} does not export a handler.` });
    return;
  }

  const shouldKeepRaw = RAW_BODY_ROUTE_FILES.has(route.file);
  const proxiedReq = shouldKeepRaw
    ? req
    : copyIncomingRequest(req, requestUrl, await readRequestBody(req));

  if (shouldKeepRaw) {
    proxiedReq.url = `${requestUrl.pathname}${requestUrl.search}`;
    proxiedReq.query = queryFromSearchParams(requestUrl.searchParams);
    proxiedReq.params = params;
  } else {
    proxiedReq.params = params;
    proxiedReq.body = bodyFromBuffer(
      proxiedReq.rawBody,
      proxiedReq.headers['content-type'] || '',
    );
  }

  decorateResponse(res);
  await handler(proxiedReq, res);
  if (!res.writableEnded) {
    res.end();
  }
}

function createOracleApiServer() {
  return http.createServer(async (req, res) => {
    try {
      const { pathname } = new URL(req.url, `http://${req.headers.host || 'localhost'}`);

      if (pathname === '/healthz' || pathname === '/api/healthz') {
        sendJson(res, 200, {
          ok: true,
          service: 'pokoin-oracle-api',
          routes: routeDefinitions.length,
        });
        return;
      }

      if (pathname === '/marketplace') {
        sendHtml(res, 200, stagingMarketplaceHtml(req.headers.host || 'newapi.pokoin.com'));
        return;
      }

      if (pathname === '/api/__routes') {
        sendJson(res, 200, {
          routes: routeDefinitions.map(({ path: routePath, methods, file, purpose }) => ({
            path: routePath,
            methods,
            file,
            purpose,
          })),
        });
        return;
      }

      const matched = routeForPathname(pathname);
      if (!matched) {
        sendJson(res, 404, { error: 'API route not found.' });
        return;
      }

      await observeApiRequest({ req, res, route: matched.route }, () => callHandler(req, res, matched));
    } catch (error) {
      if (error instanceof SyntaxError) {
        sendJson(res, 400, { error: 'Invalid JSON request body.' });
        return;
      }
      if (error && error.statusCode === 413) {
        sendJson(res, 413, { error: error.message });
        return;
      }
      console.error('oracle-api-server request failed', error);
      sendJson(res, error.statusCode || 500, { error: error.message || 'Internal server error.' });
    }
  });
}

function startServer({
  host = DEFAULT_HOST,
  port = DEFAULT_PORT,
} = {}) {
  const server = createOracleApiServer();
  server.listen(port, host, () => {
    console.log(`pokoin-oracle-api listening on http://${host}:${port}`);
  });
  return server;
}

if (require.main === module) {
  startServer();
}

module.exports = {
  createOracleApiServer,
  routeForPathname,
  startServer,
  routeDefinitions,
  _test: {
    bodyFromBuffer,
    queryFromSearchParams,
    normalizePathname,
    readRequestBody,
    decorateResponse,
    stagingMarketplaceHtml,
  },
};
