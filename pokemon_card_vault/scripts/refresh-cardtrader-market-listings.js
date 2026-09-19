#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');

const ROOT_DIR = path.resolve(__dirname, '..');
const POKOINPOS_ROOT = process.env.POKOINPOS_ROOT || '/Users/giuseppe/pokoinpos';
const DEFAULT_ENV_FILE = path.join(POKOINPOS_ROOT, 'deploy/env/peer4-postgres.env');

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

function loadEnvFile(filePath) {
  const resolved = path.resolve(filePath);
  if (!fs.existsSync(resolved)) return { path: resolved, loaded: false };
  for (const line of fs.readFileSync(resolved, 'utf8').split(/\r?\n/)) {
    const stripped = line.trim();
    if (!stripped || stripped.startsWith('#') || !stripped.includes('=')) continue;
    const separator = stripped.indexOf('=');
    const key = stripped.slice(0, separator).replace(/^export\s+/, '').trim();
    if (!key || process.env[key]) continue;
    process.env[key] = cleanEnvValue(stripped.slice(separator + 1));
  }
  return { path: resolved, loaded: true };
}

function loadDefaultFallbackEnvFiles(primaryPath, fallbackPaths = [path.join(ROOT_DIR, '.env.local')]) {
  const loaded = [];
  for (const filePath of [
    primaryPath,
    ...fallbackPaths,
  ]) {
    const result = loadEnvFile(filePath);
    if (result.loaded) loaded.push(result.path);
  }
  return loaded;
}

function integerOrNull(value) {
  if (value == null || value === '') return null;
  const number = Number(value);
  return Number.isSafeInteger(number) ? Math.trunc(number) : null;
}

function parseArgs(argv) {
  const options = {
    envFile: process.env.CARDTRADER_MARKET_REFRESH_ENV_FILE || DEFAULT_ENV_FILE,
    dryRun: false,
    archiveMissing: undefined,
    byBlueprint: false,
    completeBook: false,
    finalize: undefined,
    maxBlueprints: undefined,
    maxProducts: undefined,
    maxExpansions: undefined,
    requestDelayMs: undefined,
    blueprintBatchSize: undefined,
    blueprintConcurrency: undefined,
    expansionConcurrency: undefined,
    persistConcurrency: undefined,
    expansionShardCount: undefined,
    expansionShardIndex: undefined,
    refreshBatchBlueprints: undefined,
    removedDay: '',
    blueprintIds: [],
    expansionIds: [],
    expansionId: undefined,
    minExpansionId: undefined,
    language: '',
  };

  for (const arg of argv) {
    if (arg === '--dry-run') {
      options.dryRun = true;
    } else if (arg === '--apply') {
      options.dryRun = false;
    } else if (arg === '--archive-missing') {
      options.archiveMissing = true;
    } else if (arg === '--no-archive-missing') {
      options.archiveMissing = false;
    } else if (arg === '--by-blueprint') {
      options.byBlueprint = true;
    } else if (arg === '--by-expansion') {
      options.byBlueprint = false;
    } else if (arg === '--complete-book') {
      options.completeBook = true;
    } else if (arg === '--no-complete-book') {
      options.completeBook = false;
    } else if (arg === '--finalize') {
      options.finalize = true;
    } else if (arg === '--no-finalize') {
      options.finalize = false;
    } else if (arg.startsWith('--env-file=')) {
      options.envFile = arg.slice('--env-file='.length).trim();
    } else if (arg.startsWith('--max-blueprints=')) {
      options.maxBlueprints = integerOrNull(arg.slice('--max-blueprints='.length));
    } else if (arg.startsWith('--max-products=')) {
      options.maxProducts = integerOrNull(arg.slice('--max-products='.length));
    } else if (arg.startsWith('--max-expansions=')) {
      options.maxExpansions = integerOrNull(arg.slice('--max-expansions='.length));
    } else if (arg.startsWith('--request-delay-ms=')) {
      options.requestDelayMs = integerOrNull(arg.slice('--request-delay-ms='.length));
    } else if (arg.startsWith('--blueprint-batch-size=')) {
      options.blueprintBatchSize = integerOrNull(arg.slice('--blueprint-batch-size='.length));
    } else if (arg.startsWith('--blueprint-concurrency=')) {
      options.blueprintConcurrency = integerOrNull(arg.slice('--blueprint-concurrency='.length));
    } else if (arg.startsWith('--expansion-concurrency=')) {
      options.expansionConcurrency = integerOrNull(arg.slice('--expansion-concurrency='.length));
    } else if (arg.startsWith('--persist-concurrency=')) {
      options.persistConcurrency = integerOrNull(arg.slice('--persist-concurrency='.length));
    } else if (arg.startsWith('--shard-count=')) {
      options.expansionShardCount = integerOrNull(arg.slice('--shard-count='.length));
    } else if (arg.startsWith('--shard-index=')) {
      options.expansionShardIndex = integerOrNull(arg.slice('--shard-index='.length));
    } else if (arg.startsWith('--min-expansion-id=')) {
      options.minExpansionId = integerOrNull(arg.slice('--min-expansion-id='.length));
    } else if (arg.startsWith('--refresh-batch-blueprints=')) {
      options.refreshBatchBlueprints = integerOrNull(arg.slice('--refresh-batch-blueprints='.length));
    } else if (arg.startsWith('--removed-day=')) {
      options.removedDay = arg.slice('--removed-day='.length).trim();
    } else if (arg.startsWith('--blueprint-id=')) {
      const id = integerOrNull(arg.slice('--blueprint-id='.length));
      if (id != null && id > 0) options.blueprintIds.push(id);
    } else if (arg.startsWith('--blueprint-ids=')) {
      options.blueprintIds.push(...arg.slice('--blueprint-ids='.length)
        .split(',')
        .map((value) => integerOrNull(value.trim()))
        .filter((id) => id != null && id > 0));
    } else if (arg.startsWith('--expansion-id=')) {
      const id = integerOrNull(arg.slice('--expansion-id='.length));
      if (id != null && id > 0) options.expansionIds.push(id);
      options.expansionId = id;
    } else if (arg.startsWith('--expansion-ids=')) {
      options.expansionIds.push(...arg.slice('--expansion-ids='.length)
        .split(',')
        .map((value) => integerOrNull(value.trim()))
        .filter((id) => id != null && id > 0));
    } else if (arg.startsWith('--language=')) {
      options.language = arg.slice('--language='.length).trim();
    } else {
      throw new Error(`Unknown option: ${arg}`);
    }
  }

  return options;
}

function tokenKeyStatus(env = process.env) {
  if (String(env.CARDTRADER_AUTH_TOKEN || '').trim()) return 'CARDTRADER_AUTH_TOKEN';
  if (String(env.CARDTRADER_API_TOKEN || '').trim()) return 'CARDTRADER_API_TOKEN';
  return '';
}

function databaseConfigured(env = process.env) {
  return Boolean(String(env.MARKETPLACE_DATABASE_URL || env.MARKETPLACE_PEER4_DATABASE_URL || '').trim());
}

function publicOptions(options) {
  return {
    dryRun: options.dryRun,
    byBlueprint: options.byBlueprint,
    completeBook: options.completeBook,
    finalize: options.finalize,
    archiveMissing: options.archiveMissing,
    maxBlueprints: options.maxBlueprints,
    maxProducts: options.maxProducts,
    maxExpansions: options.maxExpansions,
    requestDelayMs: options.requestDelayMs,
    blueprintBatchSize: options.blueprintBatchSize,
    blueprintConcurrency: options.blueprintConcurrency,
    expansionConcurrency: options.expansionConcurrency,
    persistConcurrency: options.persistConcurrency,
    expansionShardCount: options.expansionShardCount,
    expansionShardIndex: options.expansionShardIndex,
    refreshBatchBlueprints: options.refreshBatchBlueprints,
    removedDay: options.removedDay || undefined,
    blueprintCount: options.blueprintIds.length,
    expansionCount: options.expansionIds.length,
    expansionId: options.expansionId,
    minExpansionId: options.minExpansionId,
    language: options.language || undefined,
  };
}

async function closeMarketplacePool() {
  try {
    const { getMarketplacePool } = require('../api/_marketplace_db');
    await getMarketplacePool().end();
  } catch (_) {
    // Best-effort cleanup only; failures here should not mask the refresh result.
  }
}

async function main() {
  const cliOptions = parseArgs(process.argv.slice(2));
  const loadedEnvFiles = loadDefaultFallbackEnvFiles(cliOptions.envFile);
  if (loadedEnvFiles.length === 0) {
    throw new Error(`Env file not found: ${path.resolve(cliOptions.envFile)}`);
  }
  if (!tokenKeyStatus()) {
    throw new Error('Missing CARDTRADER_AUTH_TOKEN or CARDTRADER_API_TOKEN in the Oracle/peer4 job environment.');
  }
  if (!databaseConfigured()) {
    throw new Error('Missing MARKETPLACE_DATABASE_URL in the Oracle/peer4 job environment.');
  }

  const { normalizeRefreshOptions, runRefresh } = require('../api/_cardtrader_daily_listings_refresh');
  const refreshOptions = normalizeRefreshOptions({
    dryRun: cliOptions.dryRun,
    byBlueprint: cliOptions.byBlueprint,
    completeBook: cliOptions.completeBook,
    finalize: cliOptions.finalize,
    archiveMissing: cliOptions.archiveMissing,
    maxBlueprints: cliOptions.maxBlueprints,
    maxProducts: cliOptions.maxProducts,
    maxExpansions: cliOptions.maxExpansions,
    requestDelayMs: cliOptions.requestDelayMs,
    blueprintBatchSize: cliOptions.blueprintBatchSize,
    blueprintConcurrency: cliOptions.blueprintConcurrency,
    expansionConcurrency: cliOptions.expansionConcurrency,
    persistConcurrency: cliOptions.persistConcurrency,
    expansionShardCount: cliOptions.expansionShardCount,
    expansionShardIndex: cliOptions.expansionShardIndex,
    refreshBatchBlueprints: cliOptions.refreshBatchBlueprints,
    removedDay: cliOptions.removedDay,
    blueprintIds: cliOptions.blueprintIds.join(','),
    expansionIds: cliOptions.expansionIds.join(','),
    expansionId: cliOptions.expansionId,
    minExpansionId: cliOptions.minExpansionId,
    language: cliOptions.language,
    onProgress: (progress) => {
      console.log('CardTrader market listing refresh progress', progress);
    },
  });

  console.log('Starting CardTrader market listing refresh', {
    envFilesLoaded: loadedEnvFiles.length,
    tokenKey: tokenKeyStatus(),
    options: publicOptions(refreshOptions),
  });
  const startedAt = Date.now();
  const result = await runRefresh(refreshOptions);
  console.log('Finished CardTrader market listing refresh', {
    ok: true,
    durationMs: Date.now() - startedAt,
    dryRun: refreshOptions.dryRun,
    archiveMissing: refreshOptions.archiveMissing,
    removedDay: refreshOptions.removedDay,
    result,
  });
}

if (require.main === module) {
  main()
    .catch((error) => {
      console.error('CardTrader market listing refresh failed', {
        message: error.message,
        code: error.code || '',
        statusCode: error.statusCode || '',
      });
      process.exitCode = 1;
    })
    .finally(closeMarketplacePool);
}

module.exports = {
  DEFAULT_ENV_FILE,
  loadDefaultFallbackEnvFiles,
  loadEnvFile,
  parseArgs,
  tokenKeyStatus,
};
