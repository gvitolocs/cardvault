const { ethers } = require('ethers');

const DEFAULT_POKOIN_RPC_URL = 'https://rpc.pokoin.com/rpc';
const DEFAULT_POKOIN_BANK_ADDRESS = '0xb4029f68e360280aa4ad21d8ae5ad8896b8768b2';
const DEFAULT_POKOIN_RESERVE_ADDRESS = '0x74466c3a204429b22ce8558f3f18f3c59f67fcb3';

function provider() {
  return new ethers.JsonRpcProvider(process.env.POKOIN_RPC_URL || DEFAULT_POKOIN_RPC_URL);
}

function treasuryAddress() {
  return String(process.env.POKOIN_BANK_ADDRESS || DEFAULT_POKOIN_BANK_ADDRESS)
    .trim()
    .toLowerCase();
}

function reserveAddress() {
  return String(process.env.POKOIN_RESERVE_ADDRESS || DEFAULT_POKOIN_RESERVE_ADDRESS)
    .trim()
    .toLowerCase();
}

function reservePrivateKey() {
  return process.env.POKOIN_RESERVE_PRIVATE_KEY || '';
}

function bankPrivateKey() {
  return process.env.POKOIN_BANK_PRIVATE_KEY || '';
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

function pknWei(amountPkn) {
  return ethers.parseUnits(String(amountPkn), 18);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function explorerBaseUrl() {
  const rpcUrl = String(process.env.POKOIN_RPC_URL || DEFAULT_POKOIN_RPC_URL).trim();
  return rpcUrl.replace(/\/rpc\/?$/, '').replace(/\/$/, '');
}

async function addressTransactions(address, { limit = 40 } = {}) {
  const normalized = normalizeAddress(address);
  const response = await fetch(`${explorerBaseUrl()}/explorer/address/${normalized}`);
  if (!response.ok) {
    const error = new Error('Could not load Pokoin bank activity.');
    error.statusCode = 502;
    throw error;
  }
  const payload = await response.json();
  return ((payload.transactions || [])
    .filter((tx) => tx && typeof tx === 'object')
    .slice(0, limit));
}

async function verifyNativeDeposit({ txHash, fromAddress, expectedAmountPkn }) {
  const normalizedTx = String(txHash || '').trim().toLowerCase();
  if (!/^0x[a-f0-9]{64}$/.test(normalizedTx)) {
    const error = new Error('Enter a valid funding transaction hash.');
    error.statusCode = 400;
    throw error;
  }

  const normalizedFrom = normalizeAddress(
    fromAddress,
    'Link the wallet that funded this transfer before sending.',
  );
  const rpc = provider();
  let tx = null;
  let receipt = null;
  for (let attempt = 0; attempt < 6; attempt += 1) {
    [tx, receipt] = await Promise.all([
      rpc.send('eth_getTransactionByHash', [normalizedTx]),
      rpc.send('eth_getTransactionReceipt', [normalizedTx]),
    ]);
    if (tx && receipt) {
      break;
    }
    await sleep(1500);
  }
  if (!tx || !receipt) {
    const error = new Error('Funding transaction was not found yet.');
    error.statusCode = 404;
    throw error;
  }
  if (receipt.status !== 1 && receipt.status !== '0x1') {
    const error = new Error('Funding transaction failed on PokoinPoS.');
    error.statusCode = 400;
    throw error;
  }
  if (String(tx.from || '').toLowerCase() !== normalizedFrom) {
    const error = new Error('Funding transaction must be sent from your linked wallet.');
    error.statusCode = 403;
    throw error;
  }
  if (String(tx.to || '').toLowerCase() !== treasuryAddress()) {
    const error = new Error('Funding transaction must be sent to the Pokoin treasury wallet.');
    error.statusCode = 400;
    throw error;
  }
  const required = pknWei(expectedAmountPkn);
  const txValue = typeof tx.value === 'string' ? BigInt(tx.value) : BigInt(tx.value.toString());
  if (txValue < required) {
    const error = new Error('Funding transaction amount is too low.');
    error.statusCode = 400;
    throw error;
  }

  return {
    txHash: normalizedTx,
    fromAddress: normalizedFrom,
    amountPkn: Number(ethers.formatUnits(txValue, 18)),
  };
}

async function waitForNativeReceipt({
  txHash,
  timeoutMs = 30000,
  intervalMs = 1500,
} = {}) {
  const normalizedTx = String(txHash || '').trim().toLowerCase();
  if (!/^0x[a-f0-9]{64}$/.test(normalizedTx)) {
    const error = new Error('Enter a valid native PKN transaction hash.');
    error.statusCode = 400;
    throw error;
  }

  const rpc = provider();
  const startedAt = Date.now();
  while (Date.now() - startedAt <= timeoutMs) {
    const receipt = await rpc.send('eth_getTransactionReceipt', [normalizedTx]);
    if (receipt) {
      const status = receipt.status;
      return {
        txHash: normalizedTx,
        blockHash: receipt.blockHash || null,
        blockNumber:
          typeof receipt.blockNumber === 'string'
            ? Number.parseInt(receipt.blockNumber, 16)
            : Number(receipt.blockNumber || 0),
        status,
        ok: status === 1 || status === '0x1',
        raw: receipt,
      };
    }
    await sleep(intervalMs);
  }

  const error = new Error('Native PKN transaction was not confirmed yet.');
  error.statusCode = 202;
  throw error;
}

async function sendBankPkn({ toAddress, amountPkn }) {
  const key = bankPrivateKey();
  if (!key) {
    return { mode: 'manual_pending', txHash: null };
  }
  const wallet = new ethers.Wallet(key, provider());
  const expected = treasuryAddress();
  if ((await wallet.getAddress()).toLowerCase() !== expected) {
    throw Object.assign(new Error('POKOIN_BANK_PRIVATE_KEY does not match POKOIN_BANK_ADDRESS.'), {
      statusCode: 500,
    });
  }
  const tx = await wallet.sendTransaction({
    to: normalizeAddress(toAddress, 'Recipient payout wallet is invalid.'),
    value: pknWei(amountPkn),
  });
  const receipt = await waitForNativeReceipt({ txHash: tx.hash }).catch(() => null);
  return { mode: 'automatic_available', txHash: tx.hash, receipt };
}

async function sendReservePkn({ toAddress, amountPkn }) {
  const key = reservePrivateKey();
  if (!key) {
    return { mode: 'manual_pending', txHash: null };
  }
  const wallet = new ethers.Wallet(key, provider());
  const expected = reserveAddress();
  if ((await wallet.getAddress()).toLowerCase() !== expected) {
    throw Object.assign(new Error('POKOIN_RESERVE_PRIVATE_KEY does not match POKOIN_RESERVE_ADDRESS.'), {
      statusCode: 500,
    });
  }
  const tx = await wallet.sendTransaction({
    to: normalizeAddress(toAddress, 'Recipient payout wallet is invalid.'),
    value: pknWei(amountPkn),
  });
  const receipt = await waitForNativeReceipt({ txHash: tx.hash }).catch(() => null);
  return { mode: 'automatic_available', txHash: tx.hash, receipt };
}

module.exports = {
  addressTransactions,
  reserveAddress,
  sendBankPkn,
  sendReservePkn,
  treasuryAddress,
  verifyNativeDeposit,
  waitForNativeReceipt,
};
