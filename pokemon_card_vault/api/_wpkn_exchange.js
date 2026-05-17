const { ethers } = require('ethers');

const WPKN_DECIMALS = 18;
const QUOTE_TTL_MS = 60 * 1000;
const DEFAULT_SPREAD_BPS = 100;
const DEFAULT_IMPACT_BPS = 75;
const DEFAULT_MAX_ORDER_PKN = 100000;
const DEFAULT_MIN_ORDER_PKN = 1000;
const DEFAULT_AVAILABLE_LIQUIDITY_PKN = 2000000;
const DEFAULT_WPKN_RESERVE_PKN = 2000000;
const DEFAULT_PKN_LOCKED_TARGET = 2000000;
const MAX_INVENTORY_BPS = 300;
const MAX_SIZE_IMPACT_BPS = 500;
const BPS_DENOMINATOR = 10000;

const ERC20_ABI = [
  'function balanceOf(address owner) view returns (uint256)',
  'function decimals() view returns (uint8)',
  'function transfer(address to, uint256 amount) returns (bool)',
];
const ERC20_INTERFACE = new ethers.Interface([
  'event Transfer(address indexed from, address indexed to, uint256 value)',
]);
const PANCAKE_PAIR_ABI = [
  'function getReserves() view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)',
  'function token0() view returns (address)',
  'function token1() view returns (address)',
];

function intEnv(name, fallback) {
  const value = Number(process.env[name]);
  return Number.isFinite(value) ? Math.trunc(value) : fallback;
}

function numberEnv(name, fallback) {
  const value = Number(process.env[name]);
  return Number.isFinite(value) ? value : fallback;
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
  if (!Number.isInteger(amount)) {
    const error = new Error('Enter a whole PKN/wPKN amount.');
    error.statusCode = 400;
    throw error;
  }
  const min = intEnv('WPKN_EXCHANGE_MIN_ORDER_PKN', DEFAULT_MIN_ORDER_PKN);
  const max = intEnv('WPKN_EXCHANGE_MAX_ORDER_PKN', DEFAULT_MAX_ORDER_PKN);
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

function normalizeAddress(address, message = 'Enter a valid 0x address.') {
  const value = String(address || '').trim().toLowerCase();
  if (!/^0x[a-f0-9]{40}$/.test(value)) {
    const error = new Error(message);
    error.statusCode = 400;
    throw error;
  }
  return value;
}

function quoteExpiry(nowMs = Date.now()) {
  return new Date(nowMs + intEnv('WPKN_EXCHANGE_QUOTE_TTL_MS', QUOTE_TTL_MS));
}

function roundPositive(value) {
  return Math.max(0, Math.floor(value));
}

function calculateQuote({ direction, amountIn, reserves = {}, marketPrice, nowMs = Date.now() }) {
  const normalizedDirection = normalizeDirection(direction);
  const amount = normalizeAmount(amountIn);
  const spreadBps = intEnv('WPKN_EXCHANGE_SPREAD_BPS', DEFAULT_SPREAD_BPS);
  const impactCoefficientBps = intEnv(
    'WPKN_EXCHANGE_IMPACT_COEFFICIENT_BPS',
    DEFAULT_IMPACT_BPS,
  );
  const availableLiquidity = Math.max(
    1,
    Number(reserves.availableLiquidityPkn) ||
      intEnv('WPKN_EXCHANGE_AVAILABLE_LIQUIDITY_PKN', DEFAULT_AVAILABLE_LIQUIDITY_PKN),
  );
  const settlementWpknPkn = Math.max(
    0,
    Number(reserves.settlementWpknPkn) ||
      intEnv('WPKN_EXCHANGE_WPKN_RESERVE_PKN', DEFAULT_WPKN_RESERVE_PKN),
  );
  const lockedPkn = Math.max(0, Number(reserves.lockedPkn) || 0);
  const pknTarget = Math.max(
    1,
    intEnv('WPKN_EXCHANGE_PKN_LOCKED_TARGET', DEFAULT_PKN_LOCKED_TARGET),
  );

  const referencePrice = Number(marketPrice) || numberEnv('WPKN_EXCHANGE_MARKET_PRICE', 1);
  const wpknReserveRatio = settlementWpknPkn / DEFAULT_WPKN_RESERVE_PKN;
  const lockedRatio = lockedPkn / pknTarget;
  const inventoryBps =
    normalizedDirection === 'pkn_to_wpkn'
      ? roundPositive((1 - wpknReserveRatio) * MAX_INVENTORY_BPS)
      : roundPositive(lockedRatio * MAX_INVENTORY_BPS);
  const sizeImpactBps = Math.min(
    MAX_SIZE_IMPACT_BPS,
    roundPositive((amount / availableLiquidity) * impactCoefficientBps),
  );
  const totalCostBps = Math.max(0, spreadBps + inventoryBps + sizeImpactBps);
  const grossOut =
    normalizedDirection === 'pkn_to_wpkn' ? amount / referencePrice : amount * referencePrice;
  const amountOut = roundPositive(grossOut * (BPS_DENOMINATOR - totalCostBps) / BPS_DENOMINATOR);
  const feeAmount = Math.max(0, roundPositive(grossOut) - amountOut);

  return {
    direction: normalizedDirection,
    fromAsset: normalizedDirection === 'pkn_to_wpkn' ? 'PKN' : 'wPKN',
    toAsset: normalizedDirection === 'pkn_to_wpkn' ? 'wPKN' : 'PKN',
    amountIn: amount,
    amountOut,
    feeAmount,
    marketPrice: referencePrice,
    spreadBps,
    inventoryBps,
    sizeImpactBps,
    totalCostBps,
    quoteExpiresAt: quoteExpiry(nowMs).toISOString(),
    settlementMode: settlementMode(),
  };
}

function settlementMode() {
  return process.env.BNB_SETTLEMENT_PRIVATE_KEY &&
    process.env.BNB_RPC_URL &&
    process.env.WPKN_CONTRACT_ADDRESS
    ? 'automatic_available'
    : 'manual_pending';
}

async function reserveSnapshot(firestore) {
  const configDoc = await firestore.collection('wpkn_exchange_config').doc('reserves').get();
  const data = configDoc.data() || {};
  return {
    availableLiquidityPkn: Number(data.availableLiquidityPkn || 0) || undefined,
    settlementWpknPkn: Number(data.settlementWpknPkn || 0) || undefined,
    lockedPkn: Number(data.lockedPkn || 0) || undefined,
  };
}

async function pancakeSpotPrice() {
  if (
    !process.env.BNB_RPC_URL ||
    !process.env.PANCAKE_WPKN_BNB_PAIR_ADDRESS ||
    !process.env.WPKN_CONTRACT_ADDRESS
  ) {
    return numberEnv('WPKN_EXCHANGE_MARKET_PRICE', 1);
  }

  const provider = new ethers.JsonRpcProvider(process.env.BNB_RPC_URL);
  const pair = new ethers.Contract(
    process.env.PANCAKE_WPKN_BNB_PAIR_ADDRESS,
    PANCAKE_PAIR_ABI,
    provider,
  );
  const [token0, token1, reserves] = await Promise.all([
    pair.token0(),
    pair.token1(),
    pair.getReserves(),
  ]);
  const wpkn = process.env.WPKN_CONTRACT_ADDRESS.toLowerCase();
  const token0IsWpkn = String(token0).toLowerCase() === wpkn;
  const token1IsWpkn = String(token1).toLowerCase() === wpkn;
  if (!token0IsWpkn && !token1IsWpkn) {
    return numberEnv('WPKN_EXCHANGE_MARKET_PRICE', 1);
  }

  const reserveWpkn = Number(ethers.formatUnits(token0IsWpkn ? reserves[0] : reserves[1], 18));
  const reserveBnb = Number(ethers.formatUnits(token0IsWpkn ? reserves[1] : reserves[0], 18));
  if (!Number.isFinite(reserveWpkn) || !Number.isFinite(reserveBnb) || reserveWpkn <= 0) {
    return numberEnv('WPKN_EXCHANGE_MARKET_PRICE', 1);
  }

  const bnbUsd = numberEnv('WPKN_EXCHANGE_BNB_USD_PRICE', 1);
  const pknUsd = numberEnv('WPKN_EXCHANGE_PKN_USD_PRICE', bnbUsd);
  return Math.max(0.000001, (reserveBnb / reserveWpkn) * (bnbUsd / pknUsd));
}

async function maybeSendWpkn({ toAddress, amountWpkn }) {
  if (settlementMode() !== 'automatic_available') {
    return { mode: 'manual_pending', txHash: null };
  }

  const provider = new ethers.JsonRpcProvider(process.env.BNB_RPC_URL);
  const wallet = new ethers.Wallet(process.env.BNB_SETTLEMENT_PRIVATE_KEY, provider);
  const contract = new ethers.Contract(process.env.WPKN_CONTRACT_ADDRESS, ERC20_ABI, wallet);
  const decimals = Number(await contract.decimals().catch(() => WPKN_DECIMALS));
  const tx = await contract.transfer(
    normalizeAddress(toAddress, 'Enter a valid BSC payout address.'),
    ethers.parseUnits(String(amountWpkn), decimals),
  );
  return { mode: 'automatic_available', txHash: tx.hash };
}

async function verifyWpknDeposit({ txHash, expectedAmountWpkn }) {
  if (!process.env.BNB_RPC_URL || !process.env.WPKN_CONTRACT_ADDRESS) {
    const error = new Error('BNB RPC or wPKN contract env vars are missing.');
    error.statusCode = 500;
    throw error;
  }
  const settlementAddress = normalizeAddress(
    process.env.WPKN_SETTLEMENT_ADDRESS,
    'wPKN settlement address is not configured.',
  );
  const normalizedTx = String(txHash || '').trim().toLowerCase();
  if (!/^0x[a-f0-9]{64}$/.test(normalizedTx)) {
    const error = new Error('Enter a valid wPKN deposit tx hash.');
    error.statusCode = 400;
    throw error;
  }

  const provider = new ethers.JsonRpcProvider(process.env.BNB_RPC_URL);
  const receipt = await provider.getTransactionReceipt(normalizedTx);
  if (!receipt) {
    const error = new Error('Deposit transaction was not found yet.');
    error.statusCode = 404;
    throw error;
  }
  if (receipt.status !== 1) {
    const error = new Error('Deposit transaction failed on BNB Chain.');
    error.statusCode = 400;
    throw error;
  }

  const tokenAddress = process.env.WPKN_CONTRACT_ADDRESS.toLowerCase();
  const contract = new ethers.Contract(process.env.WPKN_CONTRACT_ADDRESS, ERC20_ABI, provider);
  const decimals = Number(await contract.decimals().catch(() => WPKN_DECIMALS));
  const required = ethers.parseUnits(String(expectedAmountWpkn), decimals);
  let deposited = 0n;
  let fromAddress = null;

  for (const log of receipt.logs || []) {
    if (String(log.address).toLowerCase() !== tokenAddress) {
      continue;
    }
    let parsed = null;
    try {
      parsed = ERC20_INTERFACE.parseLog(log);
    } catch (_) {
      continue;
    }
    if (parsed?.name !== 'Transfer') {
      continue;
    }
    const to = String(parsed.args.to || '').toLowerCase();
    if (to !== settlementAddress) {
      continue;
    }
    deposited += BigInt(parsed.args.value.toString());
    fromAddress = String(parsed.args.from || '').toLowerCase();
  }

  if (deposited < required) {
    const error = new Error('Deposit amount is lower than the quoted wPKN amount.');
    error.statusCode = 400;
    throw error;
  }

  return {
    txHash: normalizedTx,
    fromAddress,
    amountWpkn: Number(ethers.formatUnits(deposited, decimals)),
  };
}

function publicQuote(quoteId, quote) {
  return {
    quoteId,
    direction: quote.direction,
    fromAsset: quote.fromAsset,
    toAsset: quote.toAsset,
    amountIn: quote.amountIn,
    amountOut: quote.amountOut,
    feeAmount: quote.feeAmount,
    marketPrice: quote.marketPrice,
    spreadBps: quote.spreadBps,
    inventoryBps: quote.inventoryBps,
    sizeImpactBps: quote.sizeImpactBps,
    totalCostBps: quote.totalCostBps,
    quoteExpiresAt: quote.quoteExpiresAt,
    settlementMode: quote.settlementMode,
  };
}

module.exports = {
  calculateQuote,
  maybeSendWpkn,
  normalizeAddress,
  normalizeAmount,
  normalizeDirection,
  pancakeSpotPrice,
  publicQuote,
  reserveSnapshot,
  settlementMode,
  verifyWpknDeposit,
};
