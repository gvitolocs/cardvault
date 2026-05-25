const { marketplaceQuery } = require('./_marketplace_db');
const { authorizeSearchDebugRequest } = require('./_search_debug_auth');
const crypto = require('node:crypto');

const DEFAULT_GAME = 'pokemon';
const ACTIVE_STATUSES = new Set(['queued', 'running']);

function cleanGame(value) {
  const game = String(value || DEFAULT_GAME)
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, '_')
    .replace(/^_+|_+$/g, '');
  return game || DEFAULT_GAME;
}

function cleanMode(value) {
  return value === 'apply' ? 'apply' : 'dry_run';
}

function cleanBoolean(value, fallback) {
  if (value === true || value === 'true' || value === '1') return true;
  if (value === false || value === 'false' || value === '0') return false;
  return fallback;
}

function cleanPositiveInteger(value, fallback, min, max) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(Math.max(Math.trunc(number), min), max);
}

function cleanLimit(value, fallback = 'all') {
  const raw = String(value ?? fallback).trim().toLowerCase();
  if (!raw || raw === 'all' || raw === 'none') return 'all';
  return String(cleanPositiveInteger(raw, 500, 1, 50_000));
}

function cleanExpansionIds(value) {
  const values = Array.isArray(value)
    ? value
    : String(value || '')
        .split(',')
        .map((entry) => entry.trim())
        .filter(Boolean);
  return values
    .map(Number)
    .filter((entry) => Number.isSafeInteger(entry) && entry > 0)
    .slice(0, 500);
}

function publicJob(row) {
  if (!row) return null;
  return {
    jobId: row.job_id || '',
    game: row.game || DEFAULT_GAME,
    mode: row.mode || 'dry_run',
    status: row.status || '',
    active: ACTIVE_STATUSES.has(row.status),
    requestPayload: row.request_payload || {},
    progress: row.progress || {},
    summary: row.summary || {},
    errorMessage: row.error_message || '',
    requestedAt: row.requested_at || null,
    startedAt: row.started_at || null,
    heartbeatAt: row.heartbeat_at || null,
    finishedAt: row.finished_at || null,
    updatedAt: row.updated_at || null,
  };
}

function tableMissingResponse(res) {
  return res.status(503).json({
    error: 'CardTrader Oracle import job table is not installed yet.',
    setupRequired: true,
    migration: 'oracle-postgres/schema/009_cardtrader_import_jobs.sql',
  });
}

async function latestJob(game) {
  const result = await marketplaceQuery(
    `
      select *
      from public.marketplace_cardtrader_import_jobs
      where lower(game) = lower($1)
      order by requested_at desc
      limit 1
    `,
    [game],
  );
  return result.rows[0] || null;
}

async function insertJob({ game, mode, payload, user }) {
  const jobId = `cti_${Date.now().toString(36)}_${crypto.randomBytes(6).toString('hex')}`;
  const result = await marketplaceQuery(
    `
      insert into public.marketplace_cardtrader_import_jobs (
        job_id,
        game,
        mode,
        requested_by_uid,
        requested_by_email,
        requested_by_username,
        request_payload
      )
      values (
        $7,
        $1,
        $2,
        $3,
        $4,
        $5,
        $6::jsonb
      )
      returning *
    `,
    [
      game,
      mode,
      user.uid || '',
      user.email || '',
      user.username || '',
      JSON.stringify(payload),
      jobId,
    ],
  );
  return result.rows[0];
}

function requestPayload(body = {}) {
  const game = cleanGame(body.game);
  const mode = cleanMode(body.mode);
  const expansionIds = cleanExpansionIds(body.expansionIds);
  return {
    game,
    mode,
    streamAll: expansionIds.length === 0 ? cleanBoolean(body.streamAll, true) : false,
    expansionIds,
    limit: cleanLimit(body.limit, mode === 'apply' ? 5000 : 'all'),
    batchSize: cleanPositiveInteger(body.batchSize, 500, 1, 5000),
    concurrency: cleanPositiveInteger(body.concurrency, 4, 1, 20),
    imageConcurrency: cleanPositiveInteger(body.imageConcurrency, 4, 1, 12),
    imageChunkSize: cleanPositiveInteger(body.imageChunkSize, 50, 1, 200),
    images: cleanBoolean(body.images, mode === 'apply'),
    refresh: cleanBoolean(body.refresh, mode === 'apply'),
    syncSearch: cleanBoolean(body.syncSearch, mode === 'apply'),
    ensureSchema: cleanBoolean(body.ensureSchema, false),
    languages: String(body.languages || 'en').trim().slice(0, 60) || 'en',
    supabaseTransport: String(body.supabaseTransport || 'rest').trim().slice(0, 40) || 'rest',
  };
}

module.exports = async function handler(req, res) {
  if (req.method !== 'GET' && req.method !== 'POST') {
    res.setHeader('Allow', 'GET, POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const user = await authorizeSearchDebugRequest(req);
    if (req.method === 'GET') {
      const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
      const game = cleanGame(url.searchParams.get('game'));
      const job = await latestJob(game);
      res.setHeader('Cache-Control', 'no-store');
      return res.status(200).json({
        ok: true,
        game,
        job: publicJob(job),
        oracleWorker: {
          configured: false,
          note: 'Vercel only queues and reads jobs. Run scripts/cardtrader-oracle-import-worker.js on the Oracle Cloud VM to process them.',
        },
      });
    }

    const payload = requestPayload(req.body || {});
    const job = await insertJob({
      game: payload.game,
      mode: payload.mode,
      payload,
      user,
    });
    res.setHeader('Cache-Control', 'no-store');
    return res.status(202).json({
      ok: true,
      enqueued: true,
      job: publicJob(job),
      oracleWorker: {
        configured: false,
        note: 'Queued in Oracle Postgres. The Oracle Cloud worker must pick this up; Vercel does not run the import.',
      },
    });
  } catch (error) {
    if (error.code === '42P01') return tableMissingResponse(res);
    if (error.code === '23505') {
      return res.status(409).json({
        error: 'A CardTrader import job is already queued or running for this game.',
        code: error.code,
      });
    }
    console.error('marketplace-debug-cardtrader-blueprints failed', {
      code: error.code || '',
      statusCode: error.statusCode || 500,
      message: error.message,
    });
    return res.status(error.statusCode || 500).json({
      error: error.message || 'CardTrader Oracle import job request failed.',
      code: error.code,
    });
  }
};

module.exports._test = {
  cleanExpansionIds,
  cleanGame,
  cleanLimit,
  cleanMode,
  publicJob,
  requestPayload,
};
