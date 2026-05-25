#!/usr/bin/env node

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { Pool } = require('pg');

const cardtraderImport = require('./cardtrader-multigame-import');

const ROOT_DIR = path.resolve(__dirname, '..');
const DEFAULT_WORKER_ID = `${os.hostname()}:${process.pid}`;
const DEFAULT_POLL_INTERVAL_MS = 30_000;

function cleanEnvValue(value) {
  const trimmed = String(value || '').trim();
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1).replace(/\\n/g, '\n');
  }
  return trimmed;
}

function loadEnv(filePath = path.join(ROOT_DIR, '.env.local')) {
  if (!fs.existsSync(filePath)) return;
  for (const line of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const stripped = line.trim();
    if (!stripped || stripped.startsWith('#') || !stripped.includes('=')) continue;
    const separator = stripped.indexOf('=');
    const key = stripped.slice(0, separator).replace(/^export\s+/, '').trim();
    if (!key || process.env[key]) continue;
    process.env[key] = cleanEnvValue(stripped.slice(separator + 1));
  }
}

function parseCsv(value) {
  return String(value || '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

function parseArgs(argv) {
  const options = {
    game: 'pokemon',
    mode: 'dry_run',
    once: false,
    poll: false,
    enqueue: false,
    jobId: '',
    workerId: process.env.CARDTRADER_IMPORT_WORKER_ID || DEFAULT_WORKER_ID,
    pollIntervalMs: Number(process.env.CARDTRADER_IMPORT_POLL_INTERVAL_MS || DEFAULT_POLL_INTERVAL_MS),
    streamAll: true,
    expansionIds: [],
    limit: Infinity,
    batchSize: 500,
    concurrency: 4,
    imageConcurrency: 4,
    imageChunkSize: 50,
    images: true,
    refresh: true,
    syncSearch: true,
    ensureSchema: false,
    languages: 'en',
    supabaseTransport: 'rest',
  };
  for (const arg of argv) {
    if (arg === '--once') {
      options.once = true;
    } else if (arg === '--poll') {
      options.poll = true;
    } else if (arg === '--enqueue') {
      options.enqueue = true;
    } else if (arg === '--apply') {
      options.mode = 'apply';
    } else if (arg === '--dry-run') {
      options.mode = 'dry_run';
    } else if (arg === '--stream-all') {
      options.streamAll = true;
    } else if (arg === '--no-stream-all') {
      options.streamAll = false;
    } else if (arg === '--images') {
      options.images = true;
    } else if (arg === '--no-images') {
      options.images = false;
    } else if (arg === '--refresh') {
      options.refresh = true;
    } else if (arg === '--no-refresh') {
      options.refresh = false;
    } else if (arg === '--sync-search' || arg === '--sync-supabase') {
      options.syncSearch = true;
    } else if (arg === '--no-sync-search' || arg === '--no-sync-supabase') {
      options.syncSearch = false;
    } else if (arg === '--ensure-schema') {
      options.ensureSchema = true;
    } else if (arg.startsWith('--game=')) {
      options.game = arg.slice('--game='.length).trim() || 'pokemon';
    } else if (arg.startsWith('--mode=')) {
      const mode = arg.slice('--mode='.length).trim();
      if (mode === 'apply' || mode === 'dry_run') options.mode = mode;
    } else if (arg.startsWith('--job-id=')) {
      options.jobId = arg.slice('--job-id='.length).trim();
    } else if (arg.startsWith('--worker-id=')) {
      options.workerId = arg.slice('--worker-id='.length).trim() || DEFAULT_WORKER_ID;
    } else if (arg.startsWith('--poll-interval-ms=')) {
      options.pollIntervalMs = Number(arg.slice('--poll-interval-ms='.length));
    } else if (arg.startsWith('--expansion-ids=')) {
      options.expansionIds = parseCsv(arg.slice('--expansion-ids='.length))
        .filter((value) => /^\d+$/.test(value))
        .map(Number);
      options.streamAll = options.expansionIds.length === 0;
    } else if (arg.startsWith('--limit=')) {
      const raw = arg.slice('--limit='.length).trim().toLowerCase();
      options.limit = raw === 'all' || raw === 'none' ? Infinity : Number(raw);
    } else if (arg.startsWith('--batch-size=')) {
      options.batchSize = Number(arg.slice('--batch-size='.length));
    } else if (arg.startsWith('--concurrency=')) {
      options.concurrency = Number(arg.slice('--concurrency='.length));
    } else if (arg.startsWith('--image-concurrency=')) {
      options.imageConcurrency = Number(arg.slice('--image-concurrency='.length));
    } else if (arg.startsWith('--image-chunk-size=')) {
      options.imageChunkSize = Number(arg.slice('--image-chunk-size='.length));
    } else if (arg.startsWith('--languages=')) {
      options.languages = arg.slice('--languages='.length).trim() || 'en';
    } else if (arg.startsWith('--supabase-transport=')) {
      options.supabaseTransport = arg.slice('--supabase-transport='.length).trim() || 'rest';
    }
  }
  if (!options.game) throw new Error('--game is required.');
  if (options.mode !== 'dry_run' && options.mode !== 'apply') {
    throw new Error('--mode must be dry_run or apply.');
  }
  if (!Number.isFinite(options.limit) && options.limit !== Infinity) {
    throw new Error('--limit must be a number or all.');
  }
  if (!Number.isSafeInteger(options.batchSize) || options.batchSize < 1 || options.batchSize > 5000) {
    throw new Error('--batch-size must be between 1 and 5000.');
  }
  if (!Number.isSafeInteger(options.concurrency) || options.concurrency < 1 || options.concurrency > 50) {
    throw new Error('--concurrency must be between 1 and 50.');
  }
  if (!Number.isSafeInteger(options.imageConcurrency) || options.imageConcurrency < 1 || options.imageConcurrency > 50) {
    throw new Error('--image-concurrency must be between 1 and 50.');
  }
  if (!Number.isSafeInteger(options.imageChunkSize) || options.imageChunkSize < 1 || options.imageChunkSize > 500) {
    throw new Error('--image-chunk-size must be between 1 and 500.');
  }
  if (!Number.isSafeInteger(options.pollIntervalMs) || options.pollIntervalMs < 1000) {
    throw new Error('--poll-interval-ms must be at least 1000.');
  }
  if (!options.streamAll && options.expansionIds.length === 0) {
    throw new Error('Use --stream-all or --expansion-ids for worker import jobs.');
  }
  return options;
}

function requireEnv(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required.`);
  return value;
}

function createPool() {
  return new Pool({
    connectionString: requireEnv('MARKETPLACE_DATABASE_URL'),
    max: Number(process.env.CARDTRADER_IMPORT_WORKER_DB_POOL_MAX || 2),
    idleTimeoutMillis: 10_000,
    connectionTimeoutMillis: 10_000,
    ssl: { rejectUnauthorized: process.env.MARKETPLACE_DATABASE_SSL_VERIFY === '1' },
  });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function jobId() {
  return `cti_${Date.now().toString(36)}_${crypto.randomBytes(6).toString('hex')}`;
}

function publicOptions(options) {
  return {
    game: options.game,
    mode: options.mode,
    streamAll: options.streamAll,
    expansionIds: options.expansionIds,
    limit: options.limit === Infinity ? 'all' : options.limit,
    batchSize: options.batchSize,
    concurrency: options.concurrency,
    imageConcurrency: options.imageConcurrency,
    imageChunkSize: options.imageChunkSize,
    images: options.images,
    refresh: options.refresh,
    syncSearch: options.syncSearch,
    ensureSchema: options.ensureSchema,
    languages: options.languages,
    supabaseTransport: options.supabaseTransport,
  };
}

async function enqueueJob(pool, options, requestedBy = {}) {
  const id = options.jobId || jobId();
  const payload = publicOptions(options);
  const result = await pool.query(
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
      values ($1, $2, $3, $4, $5, $6, $7::jsonb)
      returning *
    `,
    [
      id,
      options.game,
      options.mode,
      requestedBy.uid || '',
      requestedBy.email || '',
      requestedBy.username || '',
      JSON.stringify(payload),
    ],
  );
  return result.rows[0];
}

async function acquireNextJob(pool, workerId, jobIdFilter = '') {
  const values = [workerId];
  const filter = jobIdFilter ? 'and job_id = $2' : '';
  if (jobIdFilter) values.push(jobIdFilter);
  const result = await pool.query(
    `
      update public.marketplace_cardtrader_import_jobs job
      set status = 'running',
        worker_id = $1,
        attempt_count = attempt_count + 1,
        started_at = coalesce(started_at, now()),
        heartbeat_at = now(),
        updated_at = now()
      where job.job_id = (
        select queued.job_id
        from public.marketplace_cardtrader_import_jobs queued
        where queued.status = 'queued'
          ${filter}
        order by queued.requested_at asc
        for update skip locked
        limit 1
      )
      returning *
    `,
    values,
  );
  return result.rows[0] || null;
}

async function heartbeat(pool, job, patch = {}) {
  await pool.query(
    `
      update public.marketplace_cardtrader_import_jobs
      set heartbeat_at = now(),
        progress = progress || $2::jsonb,
        updated_at = now()
      where job_id = $1
        and status = 'running'
    `,
    [job.job_id, JSON.stringify(patch)],
  );
}

function importOptionsFromJob(job) {
  const payload = job.request_payload || {};
  const argv = [
    `--game=${payload.game || job.game}`,
    payload.mode === 'apply' || job.mode === 'apply' ? '--apply' : '--dry-run',
    payload.streamAll === false ? '--no-stream-all' : '--stream-all',
    ...(Array.isArray(payload.expansionIds) && payload.expansionIds.length > 0
      ? [`--expansion-ids=${payload.expansionIds.join(',')}`]
      : []),
    `--limit=${payload.limit || 'all'}`,
    `--batch-size=${payload.batchSize || 500}`,
    `--concurrency=${payload.concurrency || 4}`,
    `--image-concurrency=${payload.imageConcurrency || 4}`,
    `--image-chunk-size=${payload.imageChunkSize || 50}`,
    payload.images === false ? '--no-images' : '--images',
    payload.refresh === false ? '--no-refresh' : '--refresh',
    payload.syncSearch === false ? '--no-sync-search' : '--sync-search',
    ...(payload.ensureSchema ? ['--ensure-schema'] : []),
    `--languages=${payload.languages || 'en'}`,
    `--supabase-transport=${payload.supabaseTransport || 'rest'}`,
  ];
  return cardtraderImport.parseArgs(argv);
}

async function markJobFinished(pool, job, summary) {
  await pool.query(
    `
      update public.marketplace_cardtrader_import_jobs
      set status = 'succeeded',
        summary = $2::jsonb,
        progress = progress || $3::jsonb,
        heartbeat_at = now(),
        finished_at = now(),
        updated_at = now()
      where job_id = $1
    `,
    [
      job.job_id,
      JSON.stringify(summary || {}),
      JSON.stringify({
        counts: summary?.counts || {},
        finishedAt: new Date().toISOString(),
      }),
    ],
  );
}

async function markJobFailed(pool, job, error) {
  await pool.query(
    `
      update public.marketplace_cardtrader_import_jobs
      set status = 'failed',
        error_message = $2,
        heartbeat_at = now(),
        finished_at = now(),
        updated_at = now()
      where job_id = $1
    `,
    [job.job_id, String(error?.message || error).slice(0, 2000)],
  );
}

async function runJob(pool, job) {
  await heartbeat(pool, job, { phase: 'starting_import', startedAt: new Date().toISOString() });
  const options = importOptionsFromJob(job);
  const summary = await cardtraderImport.run(options);
  await markJobFinished(pool, job, summary);
  return summary;
}

async function runOnce(pool, options) {
  const job = await acquireNextJob(pool, options.workerId, options.jobId);
  if (!job) return null;
  try {
    const summary = await runJob(pool, job);
    return { jobId: job.job_id, status: 'succeeded', summary };
  } catch (error) {
    await markJobFailed(pool, job, error);
    throw error;
  }
}

async function poll(pool, options) {
  do {
    const result = await runOnce(pool, options);
    if (options.once) return result;
    if (!result) await sleep(options.pollIntervalMs);
  } while (options.poll || !options.once);
  return null;
}

async function main() {
  loadEnv();
  const options = parseArgs(process.argv.slice(2));
  const pool = createPool();
  try {
    if (options.enqueue) {
      const job = await enqueueJob(pool, options, {
        username: options.workerId,
      });
      console.log(JSON.stringify({ enqueued: job.job_id, status: job.status }, null, 2));
      return;
    }
    const result = await poll(pool, { ...options, once: options.once || !options.poll });
    console.log(JSON.stringify(result || { status: 'idle' }, null, 2));
  } finally {
    await pool.end().catch(() => {});
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message || error);
    process.exitCode = 1;
  });
}

module.exports = {
  acquireNextJob,
  enqueueJob,
  importOptionsFromJob,
  parseArgs,
  publicOptions,
  runJob,
};
