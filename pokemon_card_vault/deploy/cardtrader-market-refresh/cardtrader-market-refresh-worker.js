#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');

const DEFAULT_MAX_BLUEPRINTS = 100_000;
const DEFAULT_MAX_PRODUCTS = 1_000_000;
const DEFAULT_MAX_EXPANSIONS = 10_000;
const DEFAULT_REQUEST_DELAY_MS = 200;
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
    finalizeDailyRefresh,
    readCatalogExpansionsFromOracle,
    readUngroupedBlueprintIdsFromOracle,
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
  const maxExpansions = envInteger(['CARDTRADER_MARKET_MAX_EXPANSIONS'], DEFAULT_MAX_EXPANSIONS, 1, DEFAULT_MAX_EXPANSIONS);
  const requestDelayMs = envInteger(['CARDTRADER_MARKET_REQUEST_DELAY_MS'], DEFAULT_REQUEST_DELAY_MS, 0, 10_000);
  const cycleSleepMs = envInteger(['CARDTRADER_MARKET_CYCLE_SLEEP_MS'], DEFAULT_CYCLE_SLEEP_MS, 0, 7 * DEFAULT_CYCLE_SLEEP_MS);
  const failureBackoffMs = envInteger(['CARDTRADER_MARKET_FAILURE_BACKOFF_MS'], DEFAULT_FAILURE_BACKOFF_MS, 1_000, DEFAULT_MAX_FAILURE_BACKOFF_MS);
  const maxFailureBackoffMs = envInteger(['CARDTRADER_MARKET_MAX_FAILURE_BACKOFF_MS'], DEFAULT_MAX_FAILURE_BACKOFF_MS, failureBackoffMs, 24 * 60 * 60_000);
  const runOnce = envBoolean(['CARDTRADER_MARKET_RUN_ONCE'], false);

  log('Started CardTrader expansion market refresh worker', {
    projectDir,
    stateFile,
    envFilesLoaded: loadedEnvFiles.length,
    tokenKey: tokenKeyStatus(),
    mode: 'expansion',
    maxBlueprints,
    maxProducts,
    maxExpansions,
    requestDelayMs,
    cycleSleepMs,
    runOnce,
  });

  let consecutiveFailures = 0;
  let state = readJsonFile(stateFile);
  if (state.mode !== 'expansion') {
    state = {
      mode: 'expansion',
      nextExpansionIndex: 0,
      cycleFetchedProducts: 0,
      ungroupedDone: false,
      finalized: false,
    };
    writeJsonFile(stateFile, state);
  }

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
      const expansions = (await readCatalogExpansionsFromOracle()).slice(0, maxExpansions);
      const totalExpansions = expansions.length;
      const stateHasIndex = Number.isSafeInteger(Number(state.nextExpansionIndex));
      let expansionIndex = stateHasIndex ? Number(state.nextExpansionIndex) : 0;
      let cycleFetchedProducts = stateHasIndex
        ? cleanInteger(state.cycleFetchedProducts, 0, 0, maxProducts)
        : 0;
      let ungroupedDone = state.ungroupedDone === true;
      let finalized = state.finalized === true;

      if (
        expansionIndex >= totalExpansions &&
        ungroupedDone &&
        finalized
      ) {
        const completedAt = nowIso();
        log('Completed CardTrader expansion market refresh cycle', {
          totalExpansions,
          cycleFetchedProducts,
          sleepingMs: cycleSleepMs,
        });
        state = {
          mode: 'expansion',
          status: runOnce ? 'completed' : 'sleeping',
          nextExpansionIndex: 0,
          cycleFetchedProducts: 0,
          ungroupedDone: false,
          finalized: false,
          lastCompletedAt: completedAt,
          totalExpansions,
          maxExpansions,
          maxProducts,
        };
        writeJsonFile(stateFile, state);
        if (runOnce) {
          log('Exiting after completed CardTrader expansion market refresh cycle', {
            totalExpansions,
            completedAt,
          });
          break;
        }
        if (cycleSleepMs > 0) await sleep(cycleSleepMs);
        continue;
      }

      if (expansionIndex < totalExpansions) {
        const expansion = expansions[expansionIndex];
        const startedAt = Date.now();
        state = {
          ...state,
          mode: 'expansion',
          status: 'running',
          nextExpansionIndex: expansionIndex,
          cycleFetchedProducts,
          expansionId: expansion.expansionId,
          catalogBlueprints: expansion.blueprintIds.length,
          totalExpansions,
          maxExpansions,
          maxProducts,
          startedBatchAt: nowIso(),
        };
        writeJsonFile(stateFile, state);

        log('Starting CardTrader expansion refresh', {
          expansionIndex: expansionIndex + 1,
          totalExpansions,
          expansionId: expansion.expansionId,
          catalogBlueprints: expansion.blueprintIds.length,
          remainingProductLimit: maxProducts - cycleFetchedProducts,
        });

        const result = await runRefresh({
          dryRun: false,
          archiveMissing: false,
          completeBook: true,
          finalize: false,
          maxBlueprints,
          maxProducts: maxProducts - cycleFetchedProducts,
          requestDelayMs,
          expansionId: expansion.expansionId,
          expansionIds: String(expansion.expansionId),
          catalogBlueprintIds: expansion.blueprintIds,
          onProgress: (progress) => log('CardTrader market refresh progress', progress),
        });

        cycleFetchedProducts += cleanInteger(result && result.fetchedProducts, 0, 0, maxProducts);
        consecutiveFailures = 0;
        state = {
          mode: 'expansion',
          status: 'running',
          nextExpansionIndex: expansionIndex + 1,
          cycleFetchedProducts,
          ungroupedDone: false,
          finalized: false,
          lastCommittedExpansionId: expansion.expansionId,
          lastCommittedExpansionIndex: expansionIndex,
          lastCommittedAt: nowIso(),
          lastBatchDurationMs: Date.now() - startedAt,
          totalExpansions,
          maxExpansions,
          maxProducts,
          result,
        };
        writeJsonFile(stateFile, state);

        log('Finished CardTrader expansion refresh', {
          expansionIndex: expansionIndex + 1,
          totalExpansions,
          expansionId: expansion.expansionId,
          durationMs: Date.now() - startedAt,
          result,
        });
        continue;
      }

      if (!ungroupedDone) {
        const ungroupedIds = await readUngroupedBlueprintIdsFromOracle(Math.min(maxBlueprints, 5_000));
        if (ungroupedIds.length > 0) {
          log('Starting CardTrader ungrouped blueprint refresh', {
            blueprintCount: ungroupedIds.length,
          });
          const result = await runRefresh({
            dryRun: false,
            archiveMissing: true,
            finalize: false,
            byBlueprint: true,
            maxBlueprints: ungroupedIds.length,
            maxProducts: maxProducts - cycleFetchedProducts,
            requestDelayMs,
            blueprintIds: ungroupedIds.join(','),
            onProgress: (progress) => log('CardTrader market refresh progress', progress),
          });
          cycleFetchedProducts += cleanInteger(result && result.fetchedProducts, 0, 0, maxProducts);
          log('Finished CardTrader ungrouped blueprint refresh', { result });
        }
        ungroupedDone = true;
        state = {
          ...state,
          mode: 'expansion',
          ungroupedDone: true,
          cycleFetchedProducts,
        };
        writeJsonFile(stateFile, state);
        continue;
      }

      if (!finalized) {
        log('Finalizing CardTrader daily market refresh');
        const finalizedResult = await finalizeDailyRefresh();
        state = {
          ...state,
          mode: 'expansion',
          finalized: true,
          finalizedResult,
          lastFinalizedAt: nowIso(),
        };
        writeJsonFile(stateFile, state);
        log('Finalized CardTrader daily market refresh', finalizedResult);
      }
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
