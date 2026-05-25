const crypto = require('node:crypto');
const {
  PROVIDER,
  cleanText,
  configuredCardTraderApiToken,
  normalizeCardTraderMarketProduct,
  normalizeRefreshOptions,
  removedDayForRefreshDate,
  rowsFromMarketplacePayload,
  runRefresh,
  safeRefreshSample,
} = require('./_cardtrader_daily_listings_refresh');

const SCHEDULE_OWNER = 'oracle_peer4_host_cron';

function requestHeader(req, name) {
  const headers = req.headers || {};
  const target = String(name || '').toLowerCase();
  for (const [key, value] of Object.entries(headers)) {
    if (key.toLowerCase() === target) return Array.isArray(value) ? value[0] : String(value || '');
  }
  return '';
}

function timingSafeEqualText(left, right) {
  const leftBuffer = Buffer.from(String(left || ''));
  const rightBuffer = Buffer.from(String(right || ''));
  if (!leftBuffer.length || leftBuffer.length !== rightBuffer.length) return false;
  return crypto.timingSafeEqual(leftBuffer, rightBuffer);
}

function bearerToken(req) {
  const header = requestHeader(req, 'authorization');
  return header.toLowerCase().startsWith('bearer ') ? header.slice('Bearer '.length).trim() : '';
}

function configuredRefreshSecrets(env = process.env) {
  return [
    env.CARDTRADER_DAILY_LISTINGS_SECRET,
    env.CARDTRADER_DAILY_REFRESH_SECRET,
    env.CRON_SECRET,
  ]
    .map((value) => cleanText(value, 500))
    .filter(Boolean);
}

function configuredRefreshSecret(env = process.env) {
  return configuredRefreshSecrets(env)[0] || '';
}

function authorizeRefreshRequest(req, env = process.env) {
  const secrets = configuredRefreshSecrets(env);
  if (secrets.length === 0) {
    const error = new Error('CardTrader daily refresh secret is not configured.');
    error.statusCode = 503;
    error.code = 'CARDTRADER_REFRESH_SECRET_MISSING';
    throw error;
  }
  const supplied = cleanText(requestHeader(req, 'x-cardtrader-refresh-secret'), 500) ||
    bearerToken(req);
  if (!secrets.some((secret) => timingSafeEqualText(supplied, secret))) {
    const error = new Error('CardTrader daily refresh access denied.');
    error.statusCode = 401;
    throw error;
  }
  return { type: 'cron_or_admin_secret' };
}

function requestOptions(req) {
  const url = new URL(req.url || '/', `https://${req.headers?.host || 'pokoin.com'}`);
  const body = req.body && typeof req.body === 'object' ? req.body : {};
  const get = (name) => body[name] ?? url.searchParams.get(name);
  return normalizeRefreshOptions(get);
}

function tableMissingResponse(res, error) {
  return res.status(503).json({
    error: 'CardTrader global market listing Oracle tables/functions are not installed yet.',
    setupRequired: true,
    migration: 'oracle-postgres/schema/012_cardtrader_market_listings.sql',
    code: error.code,
  });
}

module.exports = async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'GET' && req.method !== 'POST') {
    res.setHeader('Allow', 'GET, POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    authorizeRefreshRequest(req);
    const options = requestOptions(req);
    const result = await runRefresh(options);
    return res.status(200).json({
      ok: true,
      provider: PROVIDER,
      source: 'global_cardtrader_marketplace_products',
      apiPath: '/api/v2/marketplace/products',
      scheduleOwner: SCHEDULE_OWNER,
      dryRun: options.dryRun,
      archiveMissing: options.archiveMissing,
      removedDay: options.removedDay,
      maxBlueprints: options.maxBlueprints,
      maxProducts: options.maxProducts,
      blueprintBatchSize: options.blueprintBatchSize,
      blueprintConcurrency: options.blueprintConcurrency,
      expansionId: options.expansionId,
      requestedBlueprintCount: options.blueprintIds.length,
      ...result,
    });
  } catch (error) {
    if (error.code === '42P01' || error.code === '42883') return tableMissingResponse(res, error);
    console.error('cardtrader-daily-listings-refresh failed', {
      code: error.code || '',
      statusCode: error.statusCode || 500,
      message: error.message,
    });
    return res.status(error.statusCode || 500).json({
      error: error.message || 'CardTrader daily listings refresh failed.',
      code: error.code,
    });
  }
};

module.exports._test = {
  authorizeRefreshRequest,
  configuredCardTraderApiToken,
  configuredRefreshSecret,
  configuredRefreshSecrets,
  normalizeCardTraderMarketProduct,
  removedDayForRefreshDate,
  requestOptions,
  rowsFromMarketplacePayload,
  safeRefreshSample,
};
