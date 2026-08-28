#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');

const DEFAULT_MAX_BLUEPRINTS = 100_000;
const DEFAULT_MAX_PRODUCTS = 1_000_000;
const DEFAULT_BATCH_BLUEPRINTS = 700;
const DEFAULT_BLUEPRINT_CONCURRENCY = 1;
const DEFAULT_REQUEST_DELAY_MS = 300;
const DEFAULT_FAILURE_BACKOFF_MS = 60_000;
const DEFAULT_MAX_FAILURE_BACKOFF_MS = 60 * 60_000;
const DEFAULT_CYCLE_SLEEP_MS = 24 * 60 * 60_000;
const LOCK_NAME = 'pokoin-cardtrader-market-refresh-worker';
let logFilePath = '';

function nowIso() {
  return new Date().toISOString();
}

function log(message, metadata = undefined) {
  const suffix = metadata == null ? '' : ` ${JSON.stringify(metadata)}`;
  const line = `[${nowIso()}] ${message}${suffix}`;
  console.log(line);
  if (logFilePath) {
    try {
      fs.appendFileSync(logFilePath, `${line}\n`, 'utf8');
    } catch (_) {
      // Keep stdout/journald logging alive even if the mounted log directory fails.
    }
  }
}

function cleanInteger(value, fallback, min, max) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(Math.max(Math.trunc(parsed), min), max);
}

function envInteger(names, fallback, min, max) {
  for (const name of names) {
    if (process.env[name] !== undefined && process.env[name] !== '') {
      return cleanInteger(process.env[name], fallback, min, max);
    }
  }
  return fallback;
}

function envBoolean(names, fallback = false) {
  for (const name of names) {
    const value = process.env[name];
    if (value === undefined || value === '') continue;
    if (/^(1|true|yes|on)$/i.test(value)) return true;
    if (/^(0|false|no|off)$/i.test(value)) return false;
  }
  return fallback;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function ensureDirectory(directory) {
  fs.mkdirSync(directory, { recursive: true });
}

function readJsonFile(filePath) {
  try {
    if (!fs.existsSync(filePath)) return {};
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (error) {
    log('Ignoring unreadable state file', { filePath, message: error.message });
    return {};
  }
}

function writeJsonFile(filePath, value) {
  ensureDirectory(path.dirname(filePath));
  const tmpPath = `${filePath}.${process.pid}.tmp`;
  fs.writeFileSync(tmpPath, `${JSON.stringify({ ...value, updatedAt: nowIso() }, null, 2)}\n`, 'utf8');
  fs.renameSync(tmpPath, filePath);
}

function publicError(error) {
  return {
    message: error && error.message ? error.message : String(error),
    code: error && error.code ? error.code : '',
    statusCode: error && error.statusCode ? error.statusCode : '',
  };
}

function resolveProjectDir() {
  return path.resolve(process.env.PROJECT_DIR || process.cwd());
}

function createLockPool() {
  const { Pool } = require(path.join(resolveProjectDir(), 'node_modules/pg'));
  const connectionString = process.env.MARKETPLACE_DATABASE_URL || process.env.MARKETPLACE_PEER4_DATABASE_URL || '';
  if (!connectionString) {
    throw new Error('MARKETPLACE_DATABASE_URL is not configured.');
  }
  const sanitizedConnectionString =
    process.env.MARKETPLACE_DATABASE_SSL_VERIFY === '1'
      ? connectionString
      : connectionString.replace(/([?&])sslmode=[^&]+&?/i, (match, prefix) =>
          prefix === '?' && match.endsWith('&') ? '?' : prefix === '?' ? '' : '',
        ).replace(/[?&]$/, '');
  return new Pool({
    connectionString: sanitizedConnectionString,
    max: 1,
    idleTimeoutMillis: 0,
    connectionTimeoutMillis: Number(process.env.MARKETPLACE_DATABASE_CONNECT_MS || 8_000),
    application_name: 'cardtrader-market-refresh-lock',
    ssl: { rejectUnauthorized: process.env.MARKETPLACE_DATABASE_SSL_VERIFY === '1' },
  });
}

async function acquireDatabaseLockPool() {
  const lockPool = createLockPool();
  const result = await lockPool.query(
    'select pg_try_advisory_lock(hashtext($1), 0) as locked',
    [LOCK_NAME],
  );
  if (!result.rows[0] || result.rows[0].locked !== true) {
    await lockPool.end();
    const error = new Error('Another CardTrader market refresh worker already holds the database lock.');
    error.code = 'CARDTRADER_MARKET_REFRESH_LOCKED';
    throw error;
  }
  return lockPool;
}

async function main() {
  const projectDir = resolveProjectDir();
  process.chdir(projectDir);

  const stateDir = path.resolve(process.env.CARDTRADER_MARKET_STATE_DIR || path.join(projectDir, 'deploy/cardtrader-market-refresh/state'));
  const stateFile = path.resolve(process.env.CARDTRADER_MARKET_STATE_FILE || path.join(stateDir, 'state.json'));
  ensureDirectory(stateDir);
  const logDir = path.resolve(process.env.CARDTRADER_MARKET_LOG_DIR || path.join(projectDir, 'deploy/cardtrader-market-refresh/logs'));
  ensureDirectory(logDir);
  logFilePath = path.resolve(process.env.CARDTRADER_MARKET_LOG_FILE || path.join(logDir, 'worker.log'));

  const envFile = process.env.CARDTRADER_MARKET_REFRESH_ENV_FILE ||
    process.env.CARDTRADER_DAILY_ENV_FILE ||
    path.join(projectDir, '.env');

  const {
    loadDefaultFallbackEnvFiles,
    tokenKeyStatus,
  } = require(path.join(projectDir, 'scripts/refresh-cardtrader-market-listings.js'));
  const {
    readBlueprintIdsFromOracle,
    runRefresh,
  } = require(path.join(projectDir, 'api/_cardtrader_daily_listings_refresh.js'));
  const {
    getMarketplacePool,
  } = require(path.join(projectDir, 'api/_marketplace_db.js'));

  const loadedEnvFiles = loadDefaultFallbackEnvFiles(envFile);
  if (loadedEnvFiles.length === 0) {
    throw new Error(`Env file not found: ${path.resolve(envFile)}`);
  }

  const lockPool = await acquireDatabaseLockPool();

  const maxBlueprints = envInteger(['CARDTRADER_MARKET_MAX_BLUEPRINTS'], DEFAULT_MAX_BLUEPRINTS, 1, DEFAULT_MAX_BLUEPRINTS);
  const maxProducts = envInteger(['CARDTRADER_MARKET_MAX_PRODUCTS'], DEFAULT_MAX_PRODUCTS, 1, DEFAULT_MAX_PRODUCTS);
  const batchBlueprints = envInteger(['CARDTRADER_MARKET_REFRESH_BATCH_BLUEPRINTS'], DEFAULT_BATCH_BLUEPRINTS, 1, 10_000);
  const blueprintConcurrency = envInteger(['CARDTRADER_MARKET_BLUEPRINT_CONCURRENCY'], DEFAULT_BLUEPRINT_CONCURRENCY, 1, 50);
  const requestDelayMs = envInteger(['CARDTRADER_MARKET_REQUEST_DELAY_MS'], DEFAULT_REQUEST_DELAY_MS, 0, 10_000);
  const cycleSleepMs = envInteger(['CARDTRADER_MARKET_CYCLE_SLEEP_MS'], DEFAULT_CYCLE_SLEEP_MS, 0, 7 * DEFAULT_CYCLE_SLEEP_MS);
  const failureBackoffMs = envInteger(['CARDTRADER_MARKET_FAILURE_BACKOFF_MS'], DEFAULT_FAILURE_BACKOFF_MS, 1_000, DEFAULT_MAX_FAILURE_BACKOFF_MS);
  const maxFailureBackoffMs = envInteger(['CARDTRADER_MARKET_MAX_FAILURE_BACKOFF_MS'], DEFAULT_MAX_FAILURE_BACKOFF_MS, failureBackoffMs, 24 * 60 * 60_000);
  const configuredStartOffset = envInteger(['RESUME_OFFSET', 'START_OFFSET', 'CARDTRADER_MARKET_START_OFFSET'], 0, 0, maxBlueprints);
  const configuredFetchedProducts = envInteger(['COMMITTED_PRODUCTS', 'CARDTRADER_MARKET_COMMITTED_PRODUCTS'], 0, 0, maxProducts);
  const runOnce = envBoolean(['CARDTRADER_MARKET_RUN_ONCE'], false);

  log('Started CardTrader market refresh worker', {
    projectDir,
    stateFile,
    envFilesLoaded: loadedEnvFiles.length,
    tokenKey: tokenKeyStatus(),
    maxBlueprints,
    maxProducts,
    batchBlueprints,
    blueprintConcurrency,
    requestDelayMs,
    cycleSleepMs,
    configuredStartOffset,
    runOnce,
  });

  let consecutiveFailures = 0;
  let state = readJsonFile(stateFile);

  process.once('SIGTERM', () => {
    log('Received SIGTERM; exiting after current operation');
    process.exitCode = 0;
  });
  process.once('SIGINT', () => {
    log('Received SIGINT; exiting after current operation');
    process.exitCode = 0;
  });

  while (process.exitCode == null) {
    try {
      const blueprintIds = await readBlueprintIdsFromOracle(maxBlueprints);
      const totalBlueprints = blueprintIds.length;
      const stateHasOffset = Number.isSafeInteger(Number(state.nextOffset));
      let offset = stateHasOffset ? Number(state.nextOffset) : configuredStartOffset;
      let cycleFetchedProducts = stateHasOffset
        ? cleanInteger(state.cycleFetchedProducts, 0, 0, maxProducts)
        : configuredFetchedProducts;

      if (offset >= totalBlueprints || cycleFetchedProducts >= maxProducts) {
        const completedAt = nowIso();
        log('Completed CardTrader market refresh cycle', {
          totalBlueprints,
          nextOffset: 0,
          cycleFetchedProducts,
          sleepingMs: cycleSleepMs,
        });
        state = {
          status: runOnce ? 'completed' : 'sleeping',
          nextOffset: 0,
          cycleFetchedProducts: 0,
          lastCompletedAt: completedAt,
          totalBlueprints,
          maxBlueprints,
          maxProducts,
          batchBlueprints,
        };
        writeJsonFile(stateFile, state);
        if (runOnce) {
          log('Exiting after completed CardTrader market refresh cycle', {
            totalBlueprints,
            completedAt,
          });
          break;
        }
        if (cycleSleepMs > 0) await sleep(cycleSleepMs);
        continue;
      }

      const batchIds = blueprintIds.slice(offset, offset + batchBlueprints);
      const batchStart = offset;
      const batchEnd = offset + batchIds.length;
      const batchIndex = Math.floor(batchStart / batchBlueprints) + 1;
      const totalBatches = Math.ceil(totalBlueprints / batchBlueprints);
      const startedAt = Date.now();
      state = {
        ...state,
        status: 'running',
        nextOffset: batchStart,
        cycleFetchedProducts,
        batchIndex,
        totalBatches,
        batchBlueprints: batchIds.length,
        totalBlueprints,
        maxBlueprints,
        maxProducts,
        startedBatchAt: nowIso(),
      };
      writeJsonFile(stateFile, state);

      log('Starting CardTrader market refresh batch', {
        batchIndex,
        totalBatches,
        offset: batchStart,
        batchEnd,
        batchBlueprints: batchIds.length,
        remainingProductLimit: maxProducts - cycleFetchedProducts,
      });

      const result = await runRefresh({
        dryRun: false,
        archiveMissing: true,
        maxBlueprints: batchIds.length,
        maxProducts: maxProducts - cycleFetchedProducts,
        refreshBatchBlueprints: batchBlueprints,
        blueprintConcurrency,
        requestDelayMs,
        blueprintIds: batchIds.join(','),
        onProgress: (progress) => log('CardTrader market refresh progress', progress),
      });

      cycleFetchedProducts += cleanInteger(result && result.fetchedProducts, 0, 0, maxProducts);
      consecutiveFailures = 0;
      state = {
        status: 'running',
        nextOffset: batchEnd,
        cycleFetchedProducts,
        lastCommittedOffset: batchStart,
        lastCommittedBatchIndex: batchIndex,
        lastCommittedAt: nowIso(),
        lastBatchDurationMs: Date.now() - startedAt,
        totalBlueprints,
        maxBlueprints,
        maxProducts,
        batchBlueprints,
        result,
      };
      writeJsonFile(stateFile, state);

      log('Finished CardTrader market refresh batch', {
        batchIndex,
        totalBatches,
        offset: batchStart,
        nextOffset: batchEnd,
        durationMs: Date.now() - startedAt,
        result,
      });
    } catch (error) {
      consecutiveFailures += 1;
      const backoffMs = Math.min(
        maxFailureBackoffMs,
        failureBackoffMs * (2 ** Math.min(consecutiveFailures - 1, 8)),
      );
      state = {
        ...state,
        status: 'backing_off',
        consecutiveFailures,
        lastError: publicError(error),
        nextRetryAt: new Date(Date.now() + backoffMs).toISOString(),
      };
      writeJsonFile(stateFile, state);
      log('CardTrader market refresh batch failed; backing off', {
        consecutiveFailures,
        backoffMs,
        error: publicError(error),
      });
      await sleep(backoffMs);
    }
  }

  try {
    await lockPool.query('select pg_advisory_unlock(hashtext($1), 0)', [LOCK_NAME]);
  } finally {
    await lockPool.end();
    await getMarketplacePool().end();
  }
}

main().catch((error) => {
  console.error(`[${nowIso()}] CardTrader market refresh worker fatal error`, publicError(error));
  process.exitCode = 1;
});
