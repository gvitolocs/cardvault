'use strict';

const http = require('http');
const { Readable } = require('stream');
const path = require('path');

const {
  ingestGameList,
  ingestGameConfig,
  ingestApiPath,
  scopedIngestGame,
  publicIngestGame,
} = require('../api/_cardtrader_game_ingest');
const { sanitizePublicJson } = require('../api/_public_error');

const DEFAULT_HOST = process.env.ORACLE_API_HOST || '127.0.0.1';
const DEFAULT_PORT = Number(process.env.CARDTRADER_INGEST_PORT || process.env.PORT || 18082);
const JSON_LIMIT_BYTES = Number(process.env.ORACLE_API_JSON_LIMIT_BYTES || 10 * 1024 * 1024);
const HANDLER_PATH = path.join(__dirname, '..', 'api', 'cardtrader-game-ingest.js');

function ingestRouteDefinitions() {
  const scoped = scopedIngestGame();
  const games = ingestGameList().filter((game) => !scoped || game.id === scoped);
  return [
    {
      path: '/api/ingest',
      file: 'cardtrader-game-ingest.js',
      methods: ['GET', 'OPTIONS'],
      purpose: 'List isolated CardTrader ingest APIs. Each writes to nezopt 15T. Pokemon is not listed.',
    },
    ...games.flatMap((game) => ([
      {
        path: ingestApiPath(game),
        file: 'cardtrader-game-ingest.js',
        methods: ['GET', 'POST', 'OPTIONS'],
        purpose: `Ingest ${game.displayName} from CardTrader into 15T ${game.database}.`,
        game: game.slug,
      },
      {
        path: `/api/ingest/${game.id}`,
        file: 'cardtrader-game-ingest.js',
        methods: ['GET', 'POST', 'OPTIONS'],
        purpose: `Alias for ${ingestApiPath(game)}.`,
        game: game.id,
      },
    ])),
    {
      path: '/api/ingest/:game',
      file: 'cardtrader-game-ingest.js',
      methods: ['GET', 'POST', 'OPTIONS'],
      purpose: 'Per-game CardTrader ingest. Pokemon returns 404 (stays on the Pi).',
    },
  ];
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
    regexp: new RegExp(`^/${pattern}$`),
    paramNames,
  };
}

function routeForPathname(pathname, definitions = ingestRouteDefinitions()) {
  const cleanPath = pathname.length > 1 && pathname.endsWith('/') ? pathname.slice(0, -1) : pathname;
  const compiled = definitions.map(compileRoute);
  for (const route of compiled) {
    const match = cleanPath.match(route.regexp);
    if (match) {
      return {
        route,
        params: {
          ...(route.game ? { game: route.game } : {}),
          ...Object.fromEntries(
            route.paramNames.map((name, index) => [name, decodeURIComponent(match[index + 1] || '')]),
          ),
        },
      };
    }
  }
  return null;
}

function queryFromSearchParams(searchParams) {
  const query = {};
  for (const [key, value] of searchParams.entries()) {
    query[key] = value;
  }
  return query;
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
  return {};
}

function decorateResponse(res) {
  res.status = function status(code) {
    res.statusCode = Number(code) || 200;
    return res;
  };
  res.json = function json(payload) {
    const sanitized = sanitizePublicJson(res.statusCode || 200, payload);
    res.statusCode = sanitized.statusCode;
    if (!res.headersSent && !res.getHeader('Content-Type')) {
      res.setHeader('Content-Type', 'application/json; charset=utf-8');
    }
    return res.end(JSON.stringify(sanitized.payload));
  };
  return res;
}

function sendJson(res, statusCode, payload) {
  if (res.writableEnded) return;
  const sanitized = sanitizePublicJson(statusCode, payload);
  res.statusCode = sanitized.statusCode;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(sanitized.payload));
}

function copyIncomingRequest(req, url, bodyBuffer, params) {
  const clone = Readable.from(bodyBuffer);
  clone.method = req.method;
  clone.url = `${url.pathname}${url.search}`;
  clone.headers = req.headers;
  clone.query = queryFromSearchParams(url.searchParams);
  clone.params = params;
  clone.body = bodyFromBuffer(bodyBuffer, req.headers['content-type'] || '');
  return clone;
}

async function pipelineIngestHealth() {
  const { probeIngestDatabase } = require('../api/_cardtrader_game_ingest');
  const scoped = scopedIngestGame();
  const games = ingestGameList().filter((game) => !scoped || game.id === scoped);
  const checks = {};
  await Promise.all(games.map(async (game) => {
    checks[game.id] = await probeIngestDatabase(game);
  }));
  const ok = Boolean(process.env.MARKETPLACE_DATABASE_URL);
  return {
    ok,
    service: process.env.POKOIN_API_SERVICE_NAME || 'cardtrader-game-ingest-api',
    writer: 'nezopt-15t',
    pokemon: 'pi',
    checks,
  };
}

function createCardtraderGameIngestServer() {
  return http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
      const pathname = url.pathname.length > 1 && url.pathname.endsWith('/')
        ? url.pathname.slice(0, -1)
        : url.pathname;

      if (pathname === '/healthz' || pathname === '/api/healthz') {
        const health = await pipelineIngestHealth();
        sendJson(res, health.ok ? 200 : 503, health);
        return;
      }

      if (pathname === '/api/__routes') {
        sendJson(res, 200, {
          count: ingestRouteDefinitions().length,
          writer: 'nezopt-15t',
          pokemon: 'pi',
          routes: ingestRouteDefinitions(),
        });
        return;
      }

      const matched = routeForPathname(pathname);
      if (!matched) {
        sendJson(res, 404, { error: 'API route not found.' });
        return;
      }

      const handler = require(HANDLER_PATH);
      const proxiedReq = copyIncomingRequest(
        req,
        url,
        await readRequestBody(req),
        matched.params,
      );
      decorateResponse(res);
      await handler(proxiedReq, res);
      if (!res.writableEnded) {
        res.end();
      }
    } catch (error) {
      if (error instanceof SyntaxError) {
        sendJson(res, 400, { error: 'Invalid JSON request body.' });
        return;
      }
      sendJson(res, error.statusCode || 500, { error: error.message || 'Internal server error.' });
    }
  });
}

function startServer({
  host = DEFAULT_HOST,
  port = DEFAULT_PORT,
} = {}) {
  const server = createCardtraderGameIngestServer();
  server.listen(port, host, () => {
    const service = process.env.POKOIN_API_SERVICE_NAME || 'cardtrader-game-ingest-api';
    const scoped = scopedIngestGame();
    const games = ingestGameList()
      .filter((game) => !scoped || game.id === scoped)
      .map((game) => publicIngestGame(game).apiPath);
    console.log(`${service} listening on http://${host}:${port}`);
    console.log(`ingest ${games.join(' ')}`);
  });
  return server;
}

if (require.main === module) {
  startServer();
}

module.exports = {
  createCardtraderGameIngestServer,
  ingestRouteDefinitions,
  routeForPathname,
  startServer,
};
