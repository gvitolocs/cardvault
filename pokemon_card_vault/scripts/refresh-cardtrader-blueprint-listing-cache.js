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
  for (const filePath of [primaryPath, ...fallbackPaths]) {
    const result = loadEnvFile(filePath);
    if (result.loaded) loaded.push(result.path);
  }
  return loaded;
}

function integerOrNull(value) {
  const number = Number(value);
  return Number.isSafeInteger(number) ? Math.trunc(number) : null;
}

function parseArgs(argv) {
  const options = {
    envFile: process.env.CARDTRADER_LISTING_CACHE_REFRESH_ENV_FILE || DEFAULT_ENV_FILE,
    dryRun: false,
    maxBlueprints: undefined,
    refreshBatchBlueprints: undefined,
    blueprintConcurrency: undefined,
    requestDelayMs: undefined,
    productType: undefined,
    language: '',
    blueprintIds: [],
  };

  for (const arg of argv) {
    if (arg === '--dry-run') {
      options.dryRun = true;
    } else if (arg === '--apply') {
      options.dryRun = false;
    } else if (arg.startsWith('--env-file=')) {
      options.envFile = arg.slice('--env-file='.length).trim();
    } else if (arg.startsWith('--max-blueprints=')) {
      options.maxBlueprints = integerOrNull(arg.slice('--max-blueprints='.length));
    } else if (arg.startsWith('--refresh-batch-blueprints=')) {
      options.refreshBatchBlueprints = integerOrNull(arg.slice('--refresh-batch-blueprints='.length));
    } else if (arg.startsWith('--blueprint-concurrency=')) {
      options.blueprintConcurrency = integerOrNull(arg.slice('--blueprint-concurrency='.length));
    } else if (arg.startsWith('--request-delay-ms=')) {
      options.requestDelayMs = integerOrNull(arg.slice('--request-delay-ms='.length));
    } else if (arg.startsWith('--product-type=')) {
      options.productType = arg.slice('--product-type='.length).trim();
    } else if (arg.startsWith('--language=')) {
      options.language = arg.slice('--language='.length).trim();
    } else if (arg.startsWith('--blueprint-id=')) {
      const id = integerOrNull(arg.slice('--blueprint-id='.length));
      if (id != null && id > 0) options.blueprintIds.push(id);
    } else if (arg.startsWith('--blueprint-ids=')) {
      options.blueprintIds.push(...arg.slice('--blueprint-ids='.length)
        .split(',')
        .map((value) => integerOrNull(value.trim()))
        .filter((id) => id != null && id > 0));
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
    maxBlueprints: options.maxBlueprints,
    refreshBatchBlueprints: options.refreshBatchBlueprints,
    blueprintConcurrency: options.blueprintConcurrency,
    requestDelayMs: options.requestDelayMs,
    productType: options.productType,
    language: options.language || undefined,
    blueprintCount: options.blueprintIds.length,
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

  const {
    normalizeCacheRefreshOptions,
    runCacheRefresh,
  } = require('../api/_cardtrader_blueprint_listing_cache_refresh');
  const refreshOptions = normalizeCacheRefreshOptions({
    dryRun: cliOptions.dryRun,
    maxBlueprints: cliOptions.maxBlueprints,
    refreshBatchBlueprints: cliOptions.refreshBatchBlueprints,
    blueprintConcurrency: cliOptions.blueprintConcurrency,
    requestDelayMs: cliOptions.requestDelayMs,
    productType: cliOptions.productType,
    language: cliOptions.language,
    blueprintIds: cliOptions.blueprintIds.join(','),
    onProgress: (progress) => {
      console.log('CardTrader listing cache refresh progress', progress);
    },
  });

  console.log('Starting CardTrader listing cache refresh', {
    envFilesLoaded: loadedEnvFiles.length,
    tokenKey: tokenKeyStatus(),
    options: publicOptions(refreshOptions),
  });
  const startedAt = Date.now();
  const result = await runCacheRefresh(refreshOptions);
  console.log('Finished CardTrader listing cache refresh', {
    ok: true,
    durationMs: Date.now() - startedAt,
    dryRun: refreshOptions.dryRun,
    result,
  });
}

if (require.main === module) {
  main()
    .catch((error) => {
      console.error('CardTrader listing cache refresh failed', {
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
