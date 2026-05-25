const { ethers } = require('ethers');
const { bitcoinPayoutLiquidity, sendBitcoinPayout } = require('./_bitcoin_payout');

const PKN_USDT_REFERENCE_PRICE = 0.005;
const QUOTE_TTL_MS = 60 * 1000;
const DEFAULT_FEE_BPS = 100;
const STABLECOIN_FEE_BPS = 30;
const DEFAULT_SELL_FEE_BPS = 100;
const ERC20_ABI = [
  'function decimals() view returns (uint8)',
  'function transfer(address to, uint256 amount) returns (bool)',
  'event Transfer(address indexed from, address indexed to, uint256 value)',
];
const ERC20_INTERFACE = new ethers.Interface([
  'event Transfer(address indexed from, address indexed to, uint256 value)',
]);

const CHAIN_CONFIG = {
  BTC: {
    asset: 'BTC',
    chainName: 'Bitcoin',
    coingeckoId: 'bitcoin',
    bitcoin: true,
  },
  ETH: {
    asset: 'ETH',
    chainId: 1,
    chainName: 'Ethereum',
    rpcEnv: 'ETHEREUM_RPC_URL',
    defaultRpcUrl: 'https://ethereum.publicnode.com',
    coingeckoId: 'ethereum',
    native: true,
  },
  BNB: {
    asset: 'BNB',
    chainId: 56,
    chainName: 'BNB Chain',
    rpcEnv: 'BNB_RPC_URL',
    defaultRpcUrl: 'https://bsc-dataseed.binance.org',
    coingeckoId: 'binancecoin',
    native: true,
  },
  USDT: {
    asset: 'USDT',
    chainId: 56,
    chainName: 'BNB Chain',
    rpcEnv: 'BNB_RPC_URL',
    defaultRpcUrl: 'https://bsc-dataseed.binance.org',
    tokenAddressEnv: 'USDT_BNB_CONTRACT_ADDRESS',
    defaultTokenAddress: '0x55d398326f99059fF775485246999027B3197955',
    stablecoin: true,
  },
  EURC: {
    asset: 'EURC',
    chainId: 1,
    chainName: 'Ethereum',
    rpcEnv: 'ETHEREUM_RPC_URL',
    defaultRpcUrl: 'https://ethereum.publicnode.com',
    tokenAddressEnv: 'EURC_ETH_CONTRACT_ADDRESS',
    defaultTokenAddress: '0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c',
    coingeckoId: 'eurc',
  },
  USDC: {
    asset: 'USDC',
    chainId: 56,
    chainName: 'BNB Chain',
    rpcEnv: 'BNB_RPC_URL',
    defaultRpcUrl: 'https://bsc-dataseed.binance.org',
    tokenAddressEnv: 'USDC_BNB_CONTRACT_ADDRESS',
    defaultTokenAddress: '0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d',
    stablecoin: true,
  },
  DAI: {
    asset: 'DAI',
    chainId: 56,
    chainName: 'BNB Chain',
    rpcEnv: 'BNB_RPC_URL',
    defaultRpcUrl: 'https://bsc-dataseed.binance.org',
    tokenAddressEnv: 'DAI_BNB_CONTRACT_ADDRESS',
    defaultTokenAddress: '0x1af3f329e8be154074d8769d1ffa4ee058b1dbc3',
    stablecoin: true,
  },
  LINK: {
    asset: 'LINK',
    chainId: 1,
    chainName: 'Ethereum',
    rpcEnv: 'ETHEREUM_RPC_URL',
    defaultRpcUrl: 'https://ethereum.publicnode.com',
    tokenAddressEnv: 'LINK_ETH_CONTRACT_ADDRESS',
    defaultTokenAddress: '0x514910771af9ca656af840dff83e8264ecf986ca',
    coingeckoId: 'chainlink',
  },
  UNI: {
    asset: 'UNI',
    chainId: 1,
    chainName: 'Ethereum',
    rpcEnv: 'ETHEREUM_RPC_URL',
    defaultRpcUrl: 'https://ethereum.publicnode.com',
    tokenAddressEnv: 'UNI_ETH_CONTRACT_ADDRESS',
    defaultTokenAddress: '0x1f9840a85d5af5bf1d1762f925bdaddc4201f984',
    coingeckoId: 'uniswap',
  },
  CAKE: {
    asset: 'CAKE',
    chainId: 56,
    chainName: 'BNB Chain',
    rpcEnv: 'BNB_RPC_URL',
    defaultRpcUrl: 'https://bsc-dataseed.binance.org',
    tokenAddressEnv: 'CAKE_BNB_CONTRACT_ADDRESS',
    defaultTokenAddress: '0x0e09fabb73bd3ade0a17ecc321fd13a19e81ce82',
    coingeckoId: 'pancakeswap-token',
  },
};

function intEnv(name, fallback) {
  const value = Number(process.env[name]);
  return Number.isFinite(value) ? Math.trunc(value) : fallback;
}

function numberEnv(name, fallback) {
  const value = Number(process.env[name]);
  return Number.isFinite(value) ? value : fallback;
}

function normalizeAsset(asset) {
  const normalized = String(asset || '').trim().toUpperCase();
  if (!CHAIN_CONFIG[normalized]) {
    const error = new Error(`Buying PKN with ${normalized || 'this asset'} is not supported yet.`);
    error.statusCode = 400;
    throw error;
  }
  return normalized;
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

function normalizeBitcoinAddress(address) {
  const value = String(address || '').trim();
  if (!/^(bc1|[13])[a-zA-HJ-NP-Z0-9]{25,87}$/i.test(value)) {
    const error = new Error('Bitcoin settlement address is not configured.');
    error.statusCode = 500;
    throw error;
  }
  return value;
}

function normalizeTxHash(txHash) {
  const value = String(txHash || '').trim().toLowerCase();
  if (!/^(0x)?[a-f0-9]{64}$/.test(value)) {
    const error = new Error('Enter a valid deposit transaction hash.');
    error.statusCode = 400;
    throw error;
  }
  return value.startsWith('0x') ? value : `0x${value}`;
}

function normalizeBitcoinTxid(txHash) {
  const value = String(txHash || '').trim().toLowerCase();
  if (!/^[a-f0-9]{64}$/.test(value)) {
    const error = new Error('Enter a valid Bitcoin transaction id.');
    error.statusCode = 400;
    throw error;
  }
  return value;
}

function normalizeAmount(value) {
  const amount = Number(value);
  if (!Number.isFinite(amount) || amount <= 0) {
    const error = new Error('Enter an amount greater than zero.');
    error.statusCode = 400;
    throw error;
  }
  const max = numberEnv('CRYPTO_PKN_MAX_INPUT_AMOUNT', 1000000);
  if (amount > max) {
    const error = new Error(`Enter an amount up to ${max}.`);
    error.statusCode = 400;
    throw error;
  }
  return amount;
}

function normalizePknAmount(value) {
  const amount = Number(value);
  if (!Number.isInteger(amount) || amount <= 0) {
    const error = new Error('Enter a whole PKN amount greater than zero.');
    error.statusCode = 400;
    throw error;
  }
  const max = numberEnv('CRYPTO_PKN_MAX_SELL_PKN', 1000000000);
  if (amount > max) {
    const error = new Error(`Enter a PKN amount up to ${max}.`);
    error.statusCode = 400;
    throw error;
  }
  return amount;
}

function settlementAddress() {
  return normalizeAddress(
    process.env.CRYPTO_PKN_SETTLEMENT_ADDRESS ||
      process.env.WPKN_SETTLEMENT_ADDRESS ||
      '0x74466c3a204429B22CE8558F3F18f3C59F67fCB3',
    'Crypto settlement address is not configured.',
  );
}

function settlementAddressFor(config) {
  if (config.bitcoin) {
    return normalizeBitcoinAddress(process.env.BITCOIN_SETTLEMENT_ADDRESS);
  }
  return settlementAddress();
}

function providerFor(config) {
  return new ethers.JsonRpcProvider(process.env[config.rpcEnv] || config.defaultRpcUrl);
}

function payoutPrivateKeyFor(config) {
  if (config.bitcoin) {
    return '';
  }
  return process.env[`CRYPTO_PKN_${config.asset}_PAYOUT_PRIVATE_KEY`] ||
    process.env[`${config.asset}_PAYOUT_PRIVATE_KEY`] ||
    process.env.CRYPTO_PKN_EVM_PAYOUT_PRIVATE_KEY ||
    process.env.BNB_SETTLEMENT_PRIVATE_KEY ||
    '';
}

function tokenAddress(config) {
  if (config.bitcoin) {
    return null;
  }
  if (!config.tokenAddressEnv) {
    return null;
  }
  return normalizeAddress(
    process.env[config.tokenAddressEnv] || config.defaultTokenAddress,
    `${config.asset} token contract is not configured.`,
  );
}

async function marketUsdPrice(config) {
  if (config.stablecoin) {
    return 1;
  }
  const envPrice = numberEnv(`CRYPTO_PKN_${config.asset}_USD_PRICE`, 0);
  if (envPrice > 0) {
    return envPrice;
  }
  if (!config.coingeckoId) {
    const error = new Error(`Market price for ${config.asset} is not configured.`);
    error.statusCode = 500;
    throw error;
  }
  const url = new URL('https://api.coingecko.com/api/v3/simple/price');
  url.searchParams.set('ids', config.coingeckoId);
  url.searchParams.set('vs_currencies', 'usd');
  const response = await fetch(url, { headers: { accept: 'application/json' } });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(`Market price for ${config.asset} is unavailable.`);
    error.statusCode = 502;
    throw error;
  }
  const price = Number(payload?.[config.coingeckoId]?.usd || 0);
  if (!Number.isFinite(price) || price <= 0) {
    const error = new Error(`Market price for ${config.asset} is unavailable.`);
    error.statusCode = 502;
    throw error;
  }
  return price;
}

function quoteExpiry(nowMs = Date.now()) {
  return new Date(nowMs + intEnv('CRYPTO_PKN_QUOTE_TTL_MS', QUOTE_TTL_MS));
}

async function calculateCryptoPknQuote({ asset, amountIn, nowMs = Date.now() }) {
  const normalizedAsset = normalizeAsset(asset);
  const amount = normalizeAmount(amountIn);
  const config = CHAIN_CONFIG[normalizedAsset];
  const marketPrice = await marketUsdPrice(config);
  const pknUsd = numberEnv('CRYPTO_PKN_USDT_PRICE', PKN_USDT_REFERENCE_PRICE);
  const feeBps = intEnv(
    'CRYPTO_PKN_FEE_BPS',
    config.stablecoin ? STABLECOIN_FEE_BPS : DEFAULT_FEE_BPS,
  );
  const grossPkn = amount * marketPrice / pknUsd;
  const amountOut = Math.max(0, Math.floor(grossPkn * (10000 - feeBps) / 10000));
  if (amountOut <= 0) {
    const error = new Error('Quote is too small for a PKN purchase.');
    error.statusCode = 400;
    throw error;
  }
  return {
    asset: normalizedAsset,
    fromAsset: normalizedAsset,
    toAsset: 'PKN',
    amountIn: amount,
    amountOut,
    feeAmount: Math.max(0, Math.floor(grossPkn) - amountOut),
    feeBps,
    marketPrice,
    pknUsd,
    chainId: config.chainId,
    chainName: config.chainName,
    settlementAddress: settlementAddressFor(config),
    tokenAddress: tokenAddress(config),
    quoteExpiresAt: quoteExpiry(nowMs).toISOString(),
  };
}

async function calculatePknCryptoSaleQuote({ asset, amountIn, nowMs = Date.now() }) {
  const normalizedAsset = normalizeAsset(asset);
  const amount = normalizePknAmount(amountIn);
  const config = CHAIN_CONFIG[normalizedAsset];
  const marketPrice = await marketUsdPrice(config);
  const pknUsd = numberEnv('CRYPTO_PKN_USDT_PRICE', PKN_USDT_REFERENCE_PRICE);
  const feeBps = intEnv('CRYPTO_PKN_SELL_FEE_BPS', DEFAULT_SELL_FEE_BPS);
  const grossCrypto = amount * pknUsd / marketPrice;
  const amountOut = Math.max(0, grossCrypto * (10000 - feeBps) / 10000);
  if (amountOut <= 0) {
    const error = new Error('Quote is too small for a crypto sale.');
    error.statusCode = 400;
    throw error;
  }
  return {
    asset: normalizedAsset,
    fromAsset: 'PKN',
    toAsset: normalizedAsset,
    amountIn: amount,
    amountOut,
    feeAmount: Math.max(0, grossCrypto - amountOut),
    feeBps,
    marketPrice,
    pknUsd,
    chainId: config.chainId,
    chainName: config.chainName,
    quoteExpiresAt: quoteExpiry(nowMs).toISOString(),
  };
}

async function payoutLiquidityFor(asset) {
  const normalizedAsset = normalizeAsset(asset);
  const config = CHAIN_CONFIG[normalizedAsset];
  if (config.bitcoin) {
    return bitcoinPayoutLiquidity();
  }
  const key = payoutPrivateKeyFor(config);
  if (!key) {
    return { asset: normalizedAsset, available: 0, configured: false };
  }
  const provider = providerFor(config);
  const wallet = new ethers.Wallet(key, provider);
  const address = await wallet.getAddress();
  if (config.native) {
    const balance = await provider.getBalance(address);
    return {
      asset: normalizedAsset,
      available: Number(ethers.formatUnits(balance, 18)),
      configured: true,
      address,
    };
  }
  const contractAddress = tokenAddress(config);
  const contract = new ethers.Contract(
    contractAddress,
    ['function balanceOf(address owner) view returns (uint256)', 'function decimals() view returns (uint8)'],
    provider,
  );
  const [balance, decimals] = await Promise.all([
    contract.balanceOf(address),
    contract.decimals().catch(() => 18),
  ]);
  return {
    asset: normalizedAsset,
    available: Number(ethers.formatUnits(balance, Number(decimals))),
    configured: true,
    address,
    tokenAddress: contractAddress,
  };
}

async function assertPayoutLiquidity({ asset, amountOut }) {
  const liquidity = await payoutLiquidityFor(asset);
  const required = Number(amountOut);
  if (!liquidity.configured) {
    const error = new Error(`${asset} payout wallet is not configured.`);
    error.statusCode = 503;
    throw error;
  }
  if (!Number.isFinite(liquidity.available) || liquidity.available < required) {
    const error = new Error(
      `${asset} payout liquidity is too low. Available: ${liquidity.available || 0} ${asset}.`,
    );
    error.statusCode = 409;
    error.available = liquidity.available || 0;
    throw error;
  }
  return liquidity;
}

function normalizePayoutAddress(asset, address) {
  const normalizedAsset = normalizeAsset(asset);
  const config = CHAIN_CONFIG[normalizedAsset];
  if (config.bitcoin) {
    return normalizeBitcoinAddress(address);
  }
  return normalizeAddress(address, `Enter a valid ${normalizedAsset} payout address.`);
}

async function tokenDecimals(provider, address) {
  const contract = new ethers.Contract(address, ERC20_ABI, provider);
  return Number(await contract.decimals().catch(() => 18));
}

async function sendCryptoPayout({ asset, toAddress, amountOut }) {
  const normalizedAsset = normalizeAsset(asset);
  const config = CHAIN_CONFIG[normalizedAsset];
  if (config.bitcoin) {
    return sendBitcoinPayout({ toAddress, amountBtc: amountOut });
  }
  const key = payoutPrivateKeyFor(config);
  if (!key) {
    return { mode: 'manual_pending', txHash: null };
  }
  const payoutAddress = normalizeAddress(
    toAddress,
    `Enter a valid ${normalizedAsset} payout address.`,
  );
  const provider = providerFor(config);
  const wallet = new ethers.Wallet(key, provider);
  if (config.native) {
    const tx = await wallet.sendTransaction({
      to: payoutAddress,
      value: ethers.parseUnits(String(amountOut), 18),
    });
    return { mode: 'automatic_available', txHash: tx.hash, fromAddress: await wallet.getAddress() };
  }
  const address = tokenAddress(config);
  const contract = new ethers.Contract(address, ERC20_ABI, wallet);
  const decimals = await tokenDecimals(provider, address);
  const tx = await contract.transfer(
    payoutAddress,
    ethers.parseUnits(String(amountOut), decimals),
  );
  return { mode: 'automatic_available', txHash: tx.hash, fromAddress: await wallet.getAddress() };
}

async function verifyNativeDeposit({ config, txHash, fromAddress, expectedAmount }) {
  const provider = providerFor(config);
  const normalizedTx = normalizeTxHash(txHash);
  const normalizedFrom = normalizeAddress(fromAddress, 'Deposit must be sent from your linked wallet.');
  const expectedTo = settlementAddress();
  const [tx, receipt] = await Promise.all([
    provider.getTransaction(normalizedTx),
    provider.getTransactionReceipt(normalizedTx),
  ]);
  if (!tx || !receipt) {
    const error = new Error('Deposit transaction was not found yet.');
    error.statusCode = 404;
    throw error;
  }
  if (receipt.status !== 1) {
    const error = new Error('Deposit transaction failed.');
    error.statusCode = 400;
    throw error;
  }
  if (Number(tx.chainId) !== Number(config.chainId)) {
    const error = new Error(`Deposit must be on ${config.chainName}.`);
    error.statusCode = 400;
    throw error;
  }
  if (String(tx.from || '').toLowerCase() !== normalizedFrom) {
    const error = new Error('Deposit transaction must be sent from your linked wallet.');
    error.statusCode = 403;
    throw error;
  }
  if (String(tx.to || '').toLowerCase() !== expectedTo) {
    const error = new Error('Deposit transaction must be sent to the Pokoin settlement wallet.');
    error.statusCode = 400;
    throw error;
  }
  const required = ethers.parseUnits(String(expectedAmount), 18);
  if (tx.value < required) {
    const error = new Error('Deposit amount is lower than the quoted amount.');
    error.statusCode = 400;
    throw error;
  }
  return {
    txHash: normalizedTx,
    fromAddress: normalizedFrom,
    amountIn: Number(ethers.formatUnits(tx.value, 18)),
    blockNumber: receipt.blockNumber,
  };
}

async function verifyTokenDeposit({ config, txHash, fromAddress, expectedAmount }) {
  const provider = providerFor(config);
  const normalizedTx = normalizeTxHash(txHash);
  const normalizedFrom = normalizeAddress(fromAddress, 'Deposit must be sent from your linked wallet.');
  const expectedTo = settlementAddress();
  const address = tokenAddress(config);
  const receipt = await provider.getTransactionReceipt(normalizedTx);
  if (!receipt) {
    const error = new Error('Deposit transaction was not found yet.');
    error.statusCode = 404;
    throw error;
  }
  if (receipt.status !== 1) {
    const error = new Error('Deposit transaction failed.');
    error.statusCode = 400;
    throw error;
  }
  const decimals = await tokenDecimals(provider, address);
  const required = ethers.parseUnits(String(expectedAmount), decimals);
  let deposited = 0n;
  for (const log of receipt.logs || []) {
    if (String(log.address || '').toLowerCase() !== address) {
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
    if (String(parsed.args.from || '').toLowerCase() !== normalizedFrom) {
      continue;
    }
    if (String(parsed.args.to || '').toLowerCase() !== expectedTo) {
      continue;
    }
    deposited += BigInt(parsed.args.value.toString());
  }
  if (deposited < required) {
    const error = new Error('Deposit amount is lower than the quoted amount.');
    error.statusCode = 400;
    throw error;
  }
  return {
    txHash: normalizedTx,
    fromAddress: normalizedFrom,
    amountIn: Number(ethers.formatUnits(deposited, decimals)),
    blockNumber: receipt.blockNumber,
  };
}

async function verifyBitcoinDeposit({ config, txHash, expectedAmount }) {
  const txid = normalizeBitcoinTxid(txHash);
  const expectedTo = settlementAddressFor(config);
  const baseUrl = String(
    process.env.BITCOIN_EXPLORER_API_URL || 'https://blockstream.info/api',
  ).replace(/\/$/, '');
  const response = await fetch(`${baseUrl}/tx/${txid}`, {
    headers: { accept: 'application/json' },
  });
  if (response.status === 404) {
    const error = new Error('Bitcoin deposit transaction was not found yet.');
    error.statusCode = 404;
    throw error;
  }
  const tx = await response.json().catch(() => null);
  if (!response.ok || !tx) {
    const error = new Error('Bitcoin deposit transaction is unavailable.');
    error.statusCode = 502;
    throw error;
  }
  const minConfirmations = intEnv('BITCOIN_MIN_CONFIRMATIONS', 1);
  const confirmed = Boolean(tx.status?.confirmed);
  let confirmations = confirmed ? 1 : 0;
  if (confirmed && tx.status?.block_height) {
    const tipResponse = await fetch(`${baseUrl}/blocks/tip/height`);
    const tipText = await tipResponse.text().catch(() => '');
    const tipHeight = Number(tipText);
    if (Number.isFinite(tipHeight) && tipHeight >= Number(tx.status.block_height)) {
      confirmations = tipHeight - Number(tx.status.block_height) + 1;
    }
  }
  if (confirmations < minConfirmations) {
    const error = new Error('Bitcoin deposit is not confirmed yet.');
    error.statusCode = 409;
    throw error;
  }
  const depositedSats = (tx.vout || [])
    .filter((output) => output.scriptpubkey_address === expectedTo)
    .reduce((sum, output) => sum + Number(output.value || 0), 0);
  const requiredSats = Math.ceil(Number(expectedAmount) * 100000000);
  if (depositedSats < requiredSats) {
    const error = new Error('Bitcoin deposit amount is lower than the quoted amount.');
    error.statusCode = 400;
    throw error;
  }
  return {
    txHash: txid,
    fromAddress: 'bitcoin',
    amountIn: depositedSats / 100000000,
    blockNumber: tx.status?.block_height || null,
    confirmations,
  };
}

async function verifyCryptoDeposit({ asset, txHash, fromAddress, expectedAmount }) {
  const normalizedAsset = normalizeAsset(asset);
  const config = CHAIN_CONFIG[normalizedAsset];
  if (config.bitcoin) {
    return verifyBitcoinDeposit({ config, txHash, expectedAmount });
  }
  if (config.native) {
    return verifyNativeDeposit({ config, txHash, fromAddress, expectedAmount });
  }
  return verifyTokenDeposit({ config, txHash, fromAddress, expectedAmount });
}

function publicCryptoPknQuote(quoteId, quote) {
  return {
    quoteId,
    fromAsset: quote.fromAsset,
    toAsset: quote.toAsset,
    amountIn: quote.amountIn,
    amountOut: quote.amountOut,
    feeAmount: quote.feeAmount,
    feeBps: quote.feeBps,
    marketPrice: quote.marketPrice,
    pknUsd: quote.pknUsd,
    chainId: quote.chainId,
    chainName: quote.chainName,
    settlementAddress: quote.settlementAddress,
    tokenAddress: quote.tokenAddress,
    quoteExpiresAt: quote.quoteExpiresAt,
  };
}

function publicPknCryptoSaleQuote(quoteId, quote) {
  return {
    quoteId,
    fromAsset: quote.fromAsset,
    toAsset: quote.toAsset,
    amountIn: quote.amountIn,
    amountOut: quote.amountOut,
    feeAmount: quote.feeAmount,
    feeBps: quote.feeBps,
    marketPrice: quote.marketPrice,
    pknUsd: quote.pknUsd,
    chainId: quote.chainId,
    chainName: quote.chainName,
    quoteExpiresAt: quote.quoteExpiresAt,
  };
}

module.exports = {
  CHAIN_CONFIG,
  calculateCryptoPknQuote,
  calculatePknCryptoSaleQuote,
  assertPayoutLiquidity,
  normalizeAddress,
  normalizeAsset,
  normalizeAmount,
  normalizePayoutAddress,
  publicCryptoPknQuote,
  publicPknCryptoSaleQuote,
  payoutLiquidityFor,
  sendCryptoPayout,
  settlementAddress,
  verifyCryptoDeposit,
};
