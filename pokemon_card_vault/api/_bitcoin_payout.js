const bitcoin = require('bitcoinjs-lib');
const { ECPairFactory } = require('ecpair');
const tinysecp = require('tiny-secp256k1');

const ECPair = ECPairFactory(tinysecp);
const DEFAULT_EXPLORER_API = 'https://blockstream.info/api';
const DEFAULT_FEE_RATE = 8;
const DUST_SATS = 546;

function intEnv(name, fallback) {
  const value = Number(process.env[name]);
  return Number.isFinite(value) ? Math.trunc(value) : fallback;
}

function numberEnv(name, fallback) {
  const value = Number(process.env[name]);
  return Number.isFinite(value) ? value : fallback;
}

function bitcoinNetwork() {
  return String(process.env.BITCOIN_NETWORK || 'mainnet').trim().toLowerCase() === 'testnet'
    ? bitcoin.networks.testnet
    : bitcoin.networks.bitcoin;
}

function explorerBaseUrl() {
  return String(process.env.BITCOIN_EXPLORER_API_URL || DEFAULT_EXPLORER_API).replace(/\/$/, '');
}

function normalizeBtcAddress(address, message = 'Enter a valid Bitcoin payout address.') {
  const value = String(address || '').trim();
  try {
    bitcoin.address.toOutputScript(value, bitcoinNetwork());
  } catch (_) {
    const error = new Error(message);
    error.statusCode = 400;
    throw error;
  }
  return value;
}

function satsFromBtc(value) {
  const amount = Number(value);
  if (!Number.isFinite(amount) || amount <= 0) {
    const error = new Error('BTC payout amount must be greater than zero.');
    error.statusCode = 400;
    throw error;
  }
  return Math.round(amount * 100000000);
}

function payoutKeyPair() {
  const raw = String(process.env.BITCOIN_PAYOUT_PRIVATE_KEY_WIF || '').trim();
  const wif = raw.includes(':') ? raw.split(':').pop().trim() : raw;
  if (!wif) {
    return null;
  }
  try {
    return ECPair.fromWIF(wif, bitcoinNetwork());
  } catch (error) {
    throw Object.assign(new Error('BITCOIN_PAYOUT_PRIVATE_KEY_WIF is invalid.'), {
      statusCode: 500,
      cause: error,
    });
  }
}

function payoutAddressFor(keyPair) {
  const configured = String(process.env.BITCOIN_PAYOUT_ADDRESS || '').trim();
  if (configured) {
    return normalizeBtcAddress(configured, 'BITCOIN_PAYOUT_ADDRESS is invalid.');
  }
  const payment = bitcoin.payments.p2wpkh({
    pubkey: Buffer.from(keyPair.publicKey),
    network: bitcoinNetwork(),
  });
  return payment.address;
}

async function fetchJson(url) {
  const response = await fetch(url, { headers: { accept: 'application/json' } });
  const payload = await response.json().catch(() => null);
  if (!response.ok || payload == null) {
    const error = new Error('Bitcoin explorer request failed.');
    error.statusCode = 502;
    throw error;
  }
  return payload;
}

async function fetchFeeRate() {
  const override = numberEnv('BITCOIN_FEE_RATE_SATS_PER_VBYTE', 0);
  if (override > 0) {
    return Math.ceil(override);
  }
  const estimates = await fetchJson(`${explorerBaseUrl()}/fee-estimates`).catch(() => ({}));
  return Math.max(1, Math.ceil(Number(estimates['3'] || estimates['6'] || DEFAULT_FEE_RATE)));
}

async function bitcoinPayoutLiquidity() {
  const keyPair = payoutKeyPair();
  if (!keyPair) {
    return { asset: 'BTC', available: 0, configured: false };
  }
  const fromAddress = payoutAddressFor(keyPair);
  const [utxos, feeRate] = await Promise.all([
    fetchJson(`${explorerBaseUrl()}/address/${fromAddress}/utxo`),
    fetchFeeRate(),
  ]);
  const confirmed = (Array.isArray(utxos) ? utxos : []).filter((utxo) => utxo.status?.confirmed);
  const sats = confirmed.reduce((sum, utxo) => sum + Number(utxo.value || 0), 0);
  const reserveFee = estimateFee(Math.max(1, confirmed.length), 2, feeRate);
  return {
    asset: 'BTC',
    available: Math.max(0, (sats - reserveFee - DUST_SATS) / 100000000),
    configured: true,
    address: fromAddress,
    feeRate,
  };
}

function estimateFee(inputCount, outputCount, feeRate) {
  // Conservative native-SegWit P2WPKH estimate: 10 overhead + 68/input + 31/output.
  return Math.ceil((10 + inputCount * 68 + outputCount * 31) * feeRate);
}

function selectUtxos(utxos, targetSats, feeRate) {
  const sorted = [...utxos]
    .filter((utxo) => Number(utxo.value || 0) > 0)
    .sort((a, b) => Number(a.value || 0) - Number(b.value || 0));
  const selected = [];
  let total = 0;
  for (const utxo of sorted) {
    selected.push(utxo);
    total += Number(utxo.value || 0);
    const feeWithChange = estimateFee(selected.length, 2, feeRate);
    if (total >= targetSats + feeWithChange + DUST_SATS) {
      return { selected, total, fee: feeWithChange, change: total - targetSats - feeWithChange };
    }
    const feeNoChange = estimateFee(selected.length, 1, feeRate);
    if (total >= targetSats + feeNoChange) {
      return { selected, total, fee: feeNoChange, change: 0 };
    }
  }
  const error = new Error('BTC payout wallet has insufficient confirmed liquidity.');
  error.statusCode = 409;
  throw error;
}

async function sendBitcoinPayout({ toAddress, amountBtc }) {
  const keyPair = payoutKeyPair();
  if (!keyPair) {
    return { mode: 'bitcoin_manual_pending', txHash: null };
  }
  const network = bitcoinNetwork();
  const fromAddress = payoutAddressFor(keyPair);
  const payoutAddress = normalizeBtcAddress(toAddress);
  const amountSats = satsFromBtc(amountBtc);
  const minSats = satsFromBtc(numberEnv('BITCOIN_MIN_PAYOUT_BTC', 0.00001));
  const maxSats = satsFromBtc(numberEnv('BITCOIN_MAX_PAYOUT_BTC', 0.01));
  if (amountSats < minSats) {
    const error = new Error('BTC payout amount is below the minimum.');
    error.statusCode = 400;
    throw error;
  }
  if (amountSats > maxSats) {
    const error = new Error('BTC payout amount exceeds the maximum.');
    error.statusCode = 400;
    throw error;
  }

  const [utxos, feeRate] = await Promise.all([
    fetchJson(`${explorerBaseUrl()}/address/${fromAddress}/utxo`),
    fetchFeeRate(),
  ]);
  const confirmedUtxos = (Array.isArray(utxos) ? utxos : []).filter((utxo) => utxo.status?.confirmed);
  const { selected, fee, change } = selectUtxos(confirmedUtxos, amountSats, feeRate);
  const psbt = new bitcoin.Psbt({ network });
  for (const utxo of selected) {
    psbt.addInput({
      hash: utxo.txid,
      index: Number(utxo.vout),
      witnessUtxo: {
        script: bitcoin.address.toOutputScript(fromAddress, network),
        value: BigInt(Number(utxo.value)),
      },
    });
  }
  psbt.addOutput({ address: payoutAddress, value: BigInt(amountSats) });
  if (change >= DUST_SATS) {
    psbt.addOutput({ address: fromAddress, value: BigInt(change) });
  }
  for (let index = 0; index < selected.length; index += 1) {
    psbt.signInput(index, keyPair);
  }
  psbt.finalizeAllInputs();
  const txHex = psbt.extractTransaction().toHex();
  const response = await fetch(`${explorerBaseUrl()}/tx`, {
    method: 'POST',
    headers: { 'content-type': 'text/plain' },
    body: txHex,
  });
  const txid = (await response.text()).trim();
  if (!response.ok || !/^[a-f0-9]{64}$/i.test(txid)) {
    const error = new Error(txid || 'Bitcoin payout broadcast failed.');
    error.statusCode = 502;
    throw error;
  }
  return {
    mode: 'automatic_bitcoin',
    txHash: txid.toLowerCase(),
    fromAddress,
    feeSats: fee,
    feeRate,
  };
}

module.exports = {
  bitcoinPayoutLiquidity,
  normalizeBtcAddress,
  sendBitcoinPayout,
};
