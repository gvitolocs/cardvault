const DEFAULT_PKN_USD = 0.005;
const DEFAULT_SPREAD_BPS = 100;
const QUOTE_TTL_MS = 30 * 1000;
const BPS_DENOMINATOR = 10000;
const GECKO_API_BASE = 'https://api.geckoterminal.com/api/v2';
const DEFAULT_WPKN_BSC = '0x91A17E2bddfF839078BD395482B38e4AC15276f4';
const DEFAULT_GECKO_NETWORK = 'bsc';

function intEnv(name, fallback) {
  const value = Number(process.env[name]);
  return Number.isFinite(value) ? Math.trunc(value) : fallback;
}

function numberEnv(name, fallback) {
  const value = Number(process.env[name]);
  return Number.isFinite(value) ? value : fallback;
}

function roundPositive(value) {
  return Math.max(0, Math.floor(value));
}

function roundMarketOutput(value) {
  return Math.max(0, Math.round(value));
}

function normalizeDirection(direction) {
  const value = String(direction || '').trim().toLowerCase();
  if (value === 'pkn_to_wpkn' || value === 'wpkn_to_pkn') {
    return value;
  }
  const error = new Error('Choose PKN -> wPKN or wPKN -> PKN.');
  error.statusCode = 400;
  throw error;
}

function normalizeAmount(value) {
  const amount = Number(value);
  if (!Number.isInteger(amount) || amount <= 0) {
    const error = new Error('Enter a whole PKN/wPKN amount.');
    error.statusCode = 400;
    throw error;
  }
  const min = intEnv('WPKN_MARKET_QUOTE_MIN_AMOUNT', 1);
  const max = intEnv('WPKN_MARKET_QUOTE_MAX_AMOUNT', 100000000);
  if (amount < min) {
    const error = new Error(`Amount too low, the minimum is ${min}`);
    error.statusCode = 400;
    throw error;
  }
  if (amount > max) {
    const error = new Error(`Enter an amount up to ${max}.`);
    error.statusCode = 400;
    throw error;
  }
  return amount;
}

function pknUsdPrice() {
  return numberEnv(
    'WPKN_EXCHANGE_PKN_USD_PRICE',
    numberEnv('CRYPTO_PKN_USDT_PRICE', DEFAULT_PKN_USD),
  );
}

function wpknContractAddress() {
  return String(process.env.WPKN_CONTRACT_ADDRESS || DEFAULT_WPKN_BSC).trim().toLowerCase();
}

function geckoNetwork() {
  return String(process.env.GECKOTERMINAL_NETWORK || DEFAULT_GECKO_NETWORK).trim().toLowerCase();
}

async function geckoTerminalWpknUsd() {
  const override = numberEnv('WPKN_USD_PRICE_OVERRIDE', 0);
  if (override > 0) {
    return override;
  }

  const token = wpknContractAddress();
  const url = `${GECKO_API_BASE}/simple/networks/${geckoNetwork()}/token_price/${token}`;
  const response = await fetch(url, {
    headers: { accept: 'application/json' },
    cache: 'no-store',
  }).catch(() => null);
  if (!response || !response.ok) {
    const error = new Error('GeckoTerminal wPKN price is unavailable.');
    error.statusCode = 503;
    throw error;
  }

  const payload = await response.json().catch(() => ({}));
  const price = Number(payload?.data?.attributes?.token_prices?.[token] || 0);
  if (!Number.isFinite(price) || price <= 0) {
    const error = new Error('GeckoTerminal returned an invalid wPKN price.');
    error.statusCode = 503;
    throw error;
  }
  return price;
}

function referencePriceFromUsd(wpknUsd, pknUsd) {
  return Math.max(0.000001, wpknUsd / pknUsd);
}

async function calculateWpknPknMarketQuote({
  direction,
  amountIn,
  wpknUsd,
  pknUsd,
  nowMs = Date.now(),
}) {
  const normalizedDirection = normalizeDirection(direction);
  const amount = normalizeAmount(amountIn);
  const spreadBps = intEnv('WPKN_EXCHANGE_SPREAD_BPS', DEFAULT_SPREAD_BPS);
  const resolvedWpknUsd = Number(wpknUsd) > 0 ? Number(wpknUsd) : await geckoTerminalWpknUsd();
  const resolvedPknUsd = Number(pknUsd) > 0 ? Number(pknUsd) : pknUsdPrice();
  const marketPrice = referencePriceFromUsd(resolvedWpknUsd, resolvedPknUsd);
  const grossOut =
    normalizedDirection === 'pkn_to_wpkn' ? amount / marketPrice : amount * marketPrice;
  const netOut = grossOut * (BPS_DENOMINATOR - spreadBps) / BPS_DENOMINATOR;
  const amountOut = roundMarketOutput(netOut);
  const feeAmount = Math.max(0, roundMarketOutput(grossOut) - amountOut);

  return {
    direction: normalizedDirection,
    fromAsset: normalizedDirection === 'pkn_to_wpkn' ? 'PKN' : 'wPKN',
    toAsset: normalizedDirection === 'pkn_to_wpkn' ? 'wPKN' : 'PKN',
    amountIn: amount,
    amountOut,
    feeAmount,
    feeBps: spreadBps,
    marketPrice,
    wpknUsd: resolvedWpknUsd,
    pknUsd: resolvedPknUsd,
    priceSource: 'geckoterminal',
    poolId: 'WPKN-PKN-market',
    reserveIn: `$${resolvedWpknUsd.toFixed(6)} wPKN`,
    reserveOut: `$${resolvedPknUsd.toFixed(6)} PKN`,
    quoteExpiresAt: new Date(nowMs + intEnv('WPKN_MARKET_QUOTE_TTL_MS', QUOTE_TTL_MS)).toISOString(),
  };
}

module.exports = {
  calculateWpknPknMarketQuote,
  geckoTerminalWpknUsd,
  pknUsdPrice,
  referencePriceFromUsd,
};
