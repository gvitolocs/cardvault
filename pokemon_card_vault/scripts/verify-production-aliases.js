#!/usr/bin/env node
'use strict';

const { spawnSync } = require('node:child_process');

const REPRESENTATIVE_CARD_ROUTE = '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions';

const DEPLOYMENT_HEALTH_CHECKS = [
  { path: '/', label: 'home page', expect: 'ok' },
  { path: '/marketplace', label: 'marketplace page', expect: 'ok' },
  { path: REPRESENTATIVE_CARD_ROUTE, label: 'representative card route', expect: 'ok' },
  { path: '/api/marketplace-home', label: 'marketplace home API', expect: 'json' },
];

const PRODUCTION_ALIASES = [
  'pokoin.com',
  'www.pokoin.com',
  'wallet.pokoin.com',
  'forum.pokoin.com',
  'cards.pokoin.com',
  'cardcaveau.pokoin.com',
  'cardvault.pokoin.com',
  'explorer.pokoin.com',
];

const FULL_ROUTE_ALIASES = new Set([
  'pokoin.com',
  'www.pokoin.com',
  'explorer.pokoin.com',
]);

const ALIAS_LANDING_CHECKS = {
  'wallet.pokoin.com': [
    { path: '/', label: 'wallet alias landing', expect: 'ok' },
    { path: '/wallet', label: 'wallet canonical route', expect: 'ok' },
  ],
  'forum.pokoin.com': [
    { path: '/', label: 'forum alias landing', expect: 'ok' },
    { path: '/forum', label: 'forum canonical route', expect: 'ok' },
  ],
  'cards.pokoin.com': [
    { path: '/', label: 'cards alias landing', expect: 'ok' },
    { path: '/marketplace', label: 'cards marketplace route', expect: 'ok' },
  ],
  'cardcaveau.pokoin.com': [
    { path: '/', label: 'cardcaveau alias landing', expect: 'ok' },
    { path: '/marketplace', label: 'cardcaveau marketplace route', expect: 'ok' },
  ],
  'cardvault.pokoin.com': [
    { path: '/', label: 'cardvault alias landing', expect: 'ok' },
    { path: '/marketplace', label: 'cardvault marketplace route', expect: 'ok' },
  ],
};

const USER_AGENT = 'PokoinDeployVerifier/1.0';
const DEFAULT_TIMEOUT_MS = 30000;
const DEFAULT_ATTEMPTS = 4;
const DEFAULT_RETRY_DELAY_MS = 4000;

function usage() {
  return [
    'Usage: node scripts/verify-production-aliases.js --deployment-url <url> [--set-aliases|--skip-aliases]',
    '',
    'Verifies the produced Vercel deployment URL and, for production deploys,',
    'sets and verifies the Pokoin custom domain aliases.',
  ].join('\n');
}

function parseArgs(argv) {
  const options = {
    deploymentUrl: '',
    setAliases: false,
    skipAliases: false,
    attempts: DEFAULT_ATTEMPTS,
    retryDelayMs: DEFAULT_RETRY_DELAY_MS,
    timeoutMs: DEFAULT_TIMEOUT_MS,
  };

  for (let index = 2; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === '--deployment-url') {
      options.deploymentUrl = argv[index + 1] || '';
      index += 1;
    } else if (arg === '--set-aliases') {
      options.setAliases = true;
    } else if (arg === '--skip-aliases') {
      options.skipAliases = true;
    } else if (arg === '--attempts') {
      options.attempts = Number.parseInt(argv[index + 1] || '', 10);
      index += 1;
    } else if (arg === '--retry-delay-ms') {
      options.retryDelayMs = Number.parseInt(argv[index + 1] || '', 10);
      index += 1;
    } else if (arg === '--timeout-ms') {
      options.timeoutMs = Number.parseInt(argv[index + 1] || '', 10);
      index += 1;
    } else if (arg === '--help' || arg === '-h') {
      options.help = true;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (options.help) {
    return options;
  }
  if (!options.deploymentUrl) {
    throw new Error('Missing --deployment-url.');
  }
  if (options.setAliases && options.skipAliases) {
    throw new Error('Use only one of --set-aliases or --skip-aliases.');
  }
  if (!Number.isInteger(options.attempts) || options.attempts < 1) {
    throw new Error('--attempts must be a positive integer.');
  }
  if (!Number.isInteger(options.retryDelayMs) || options.retryDelayMs < 0) {
    throw new Error('--retry-delay-ms must be a non-negative integer.');
  }
  if (!Number.isInteger(options.timeoutMs) || options.timeoutMs < 1000) {
    throw new Error('--timeout-ms must be at least 1000.');
  }

  return options;
}

function normalizeBaseUrl(rawUrl) {
  const withScheme = /^https?:\/\//i.test(rawUrl) ? rawUrl : `https://${rawUrl}`;
  const parsed = new URL(withScheme);
  parsed.pathname = parsed.pathname.replace(/\/+$/, '');
  parsed.search = '';
  parsed.hash = '';
  return parsed.toString().replace(/\/$/, '');
}

function buildUrl(baseUrl, routePath) {
  const url = new URL(routePath, `${baseUrl}/`);
  return url.toString();
}

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

function isVercelNotFound(status, body) {
  return status === 404 || body.includes('404: NOT_FOUND') || body.includes('DEPLOYMENT_NOT_FOUND');
}

async function fetchWithTimeout(url, timeoutMs) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, {
      headers: {
        accept: 'text/html,application/json;q=0.9,*/*;q=0.8',
        'user-agent': USER_AGENT,
      },
      redirect: 'follow',
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timeout);
  }
}

async function verifyUrl(url, check, timeoutMs) {
  const response = await fetchWithTimeout(url, timeoutMs);
  const body = await response.text();

  if (isVercelNotFound(response.status, body)) {
    throw new Error(`${check.label} returned Vercel 404/NOT_FOUND at ${url}`);
  }
  if (response.status !== 200) {
    throw new Error(`${check.label} returned HTTP ${response.status} at ${url}`);
  }
  if (check.expect === 'json') {
    try {
      const parsed = JSON.parse(body);
      if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
        throw new Error('JSON payload is not an object');
      }
    } catch (error) {
      throw new Error(`${check.label} did not return valid JSON at ${url}: ${error.message}`);
    }
  }
}

async function verifyChecks(baseUrl, checks, options) {
  for (const check of checks) {
    const url = buildUrl(baseUrl, check.path);
    await verifyUrl(url, check, options.timeoutMs);
    console.log(`OK ${check.label}: ${url}`);
  }
}

async function verifyWithRetries(label, baseUrl, checks, options) {
  let lastError;
  for (let attempt = 1; attempt <= options.attempts; attempt += 1) {
    try {
      await verifyChecks(baseUrl, checks, options);
      return;
    } catch (error) {
      lastError = error;
      if (attempt === options.attempts) {
        break;
      }
      console.error(`WARN ${label} check attempt ${attempt}/${options.attempts} failed: ${error.message}`);
      await sleep(options.retryDelayMs);
    }
  }
  throw new Error(`${label} failed health verification: ${lastError.message}`);
}

function setAlias(deploymentUrl, alias) {
  console.log(`Setting alias ${alias} -> ${deploymentUrl}`);
  const result = spawnSync('vercel', ['alias', 'set', deploymentUrl, alias], {
    stdio: 'inherit',
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error(`vercel alias set failed for ${alias}`);
  }
}

function checksForAlias(alias) {
  if (FULL_ROUTE_ALIASES.has(alias)) {
    return DEPLOYMENT_HEALTH_CHECKS;
  }
  return ALIAS_LANDING_CHECKS[alias] || [
    { path: '/', label: `${alias} landing`, expect: 'ok' },
  ];
}

async function main(argv = process.argv) {
  if (typeof fetch !== 'function') {
    throw new Error('This verifier requires Node.js with global fetch support.');
  }

  const options = parseArgs(argv);
  if (options.help) {
    console.log(usage());
    return;
  }

  const deploymentUrl = normalizeBaseUrl(options.deploymentUrl);
  console.log(`Verifying deployment ${deploymentUrl}`);
  await verifyWithRetries('deployment URL', deploymentUrl, DEPLOYMENT_HEALTH_CHECKS, options);

  if (options.skipAliases) {
    console.log('Skipping production alias updates for this deploy target.');
    return;
  }

  if (options.setAliases) {
    for (const alias of PRODUCTION_ALIASES) {
      setAlias(deploymentUrl, alias);
    }
  }

  for (const alias of PRODUCTION_ALIASES) {
    const aliasUrl = `https://${alias}`;
    console.log(`Verifying alias ${aliasUrl}`);
    await verifyWithRetries(alias, aliasUrl, checksForAlias(alias), options);
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(`ERROR: ${error.message}`);
    process.exit(1);
  });
}

module.exports = {
  ALIAS_LANDING_CHECKS,
  DEPLOYMENT_HEALTH_CHECKS,
  FULL_ROUTE_ALIASES,
  PRODUCTION_ALIASES,
  REPRESENTATIVE_CARD_ROUTE,
  checksForAlias,
  normalizeBaseUrl,
  parseArgs,
};
