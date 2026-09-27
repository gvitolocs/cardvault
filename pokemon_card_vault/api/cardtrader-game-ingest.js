'use strict';

const {
  ingestGameList,
  isPokemonIngestGame,
  ingestGameConfig,
  scopedIngestGame,
  assertIngestService,
  pokemonStaysOnPiError,
  unknownIngestGameError,
  authorizeIngestRequest,
  publicIngestGame,
  probeIngestDatabase,
  ingestDatabaseUrl,
  importerOptionsForGame,
  assertBoundedApply,
} = require('./_cardtrader_game_ingest');

function sendError(res, error) {
  const status = Number(error.statusCode || 500) || 500;
  return res.status(status).json({
    error: error.message || 'CardTrader game ingest failed.',
    code: error.code || '',
  });
}

function requestedGame(req) {
  return req.params?.game
    || req.query?.game
    || req.body?.game
    || '';
}

function pinScopedGame(gameId, env = process.env) {
  const scoped = scopedIngestGame(env);
  if (scoped && gameId && scoped !== gameId) {
    const error = new Error(`This ingest process is pinned to ${scoped}.`);
    error.statusCode = 404;
    error.code = 'INGEST_GAME_PINNED';
    throw error;
  }
  return scoped;
}

async function listIngestGames(req, res, env = process.env) {
  pinScopedGame('', env);
  const scoped = scopedIngestGame(env);
  const games = ingestGameList()
    .filter((game) => !scoped || game.id === scoped)
    .map((game) => publicIngestGame(game, env));
  return res.status(200).json({
    ok: true,
    service: env.POKOIN_API_SERVICE_NAME || 'cardtrader-game-ingest-api',
    writer: 'nezopt-15t',
    pokemon: 'pi',
    count: games.length,
    games,
  });
}

async function statusIngestGame(req, res, env = process.env) {
  const raw = requestedGame(req);
  if (isPokemonIngestGame(raw)) {
    throw pokemonStaysOnPiError();
  }
  authorizeIngestRequest(req, env);
  const config = ingestGameConfig(raw);
  if (!config) {
    throw unknownIngestGameError(raw);
  }
  pinScopedGame(config.id, env);
  const postgres = await probeIngestDatabase(config, env);
  return res.status(postgres.ok ? 200 : 503).json({
    ok: postgres.ok,
    service: env.POKOIN_API_SERVICE_NAME || 'cardtrader-game-ingest-api',
    game: publicIngestGame(config, env),
    postgres,
    cardtraderToken: Boolean(env.CARDTRADER_AUTH_TOKEN || env.CARDTRADER_API_TOKEN),
  });
}

async function postIngestGame(req, res, env = process.env) {
  authorizeIngestRequest(req, env);
  const raw = requestedGame(req);
  if (isPokemonIngestGame(raw)) {
    throw pokemonStaysOnPiError();
  }
  const config = ingestGameConfig(raw);
  if (!config) {
    throw unknownIngestGameError(raw);
  }
  pinScopedGame(config.id, env);
  const body = req.body && typeof req.body === 'object' && !Buffer.isBuffer(req.body) ? req.body : {};
  const options = importerOptionsForGame(config, body);
  assertBoundedApply(options, body);
  if (!ingestDatabaseUrl(config, env) && (options.apply || !options.discoverOnly)) {
    const error = new Error(`${config.databaseUrlEnv} is not configured for 15T.`);
    error.statusCode = 503;
    error.code = 'INGEST_DATABASE_URL_MISSING';
    throw error;
  }
  process.env[config.databaseUrlEnv] = ingestDatabaseUrl(config, env);
  const { run } = require('../scripts/cardtrader-multigame-import');
  const summary = await run(options);
  return res.status(200).json({
    ok: true,
    game: publicIngestGame(config, env),
    apply: options.apply,
    discoverOnly: options.discoverOnly,
    images: false,
    summary,
  });
}

module.exports = async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  try {
    assertIngestService(process.env);
    const method = String(req.method || 'GET').toUpperCase();
    if (method === 'OPTIONS') {
      res.setHeader('Allow', 'GET, POST, OPTIONS');
      return res.status(204).end();
    }
    const raw = requestedGame(req);
    if (!raw) {
      if (method !== 'GET') {
        res.setHeader('Allow', 'GET');
        return res.status(405).json({ error: 'Method not allowed.' });
      }
      return await listIngestGames(req, res);
    }
    if (method === 'GET') {
      return await statusIngestGame(req, res);
    }
    if (method === 'POST') {
      return await postIngestGame(req, res);
    }
    res.setHeader('Allow', 'GET, POST, OPTIONS');
    return res.status(405).json({ error: 'Method not allowed.' });
  } catch (error) {
    return sendError(res, error);
  }
};
