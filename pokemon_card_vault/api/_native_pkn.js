const { ethers } = require('ethers');

const DEFAULT_POKOIN_RPC_URL = 'https://rpc.pokoin.com/rpc';
const DEFAULT_POKOIN_TREASURY_ADDRESS = '0x74466c3a204429b22ce8558f3f18f3c59f67fcb3';

function provider() {
  return new ethers.JsonRpcProvider(process.env.POKOIN_RPC_URL || DEFAULT_POKOIN_RPC_URL);
}

function treasuryAddress() {
  return String(process.env.POKOIN_TREASURY_ADDRESS || DEFAULT_POKOIN_TREASURY_ADDRESS)
    .trim()
    .toLowerCase();
}

function treasuryPrivateKey() {
  return process.env.POKOIN_TREASURY_PRIVATE_KEY || process.env.BNB_SETTLEMENT_PRIVATE_KEY || '';
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
  const [tx, receipt] = await Promise.all([
    rpc.getTransaction(normalizedTx),
    rpc.getTransactionReceipt(normalizedTx),
  ]);
  if (!tx || !receipt) {
    const error = new Error('Funding transaction was not found yet.');
    error.statusCode = 404;
    throw error;
  }
  if (receipt.status !== 1) {
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
  if (BigInt(tx.value.toString()) < required) {
    const error = new Error('Funding transaction amount is too low.');
    error.statusCode = 400;
    throw error;
  }

  return {
    txHash: normalizedTx,
    fromAddress: normalizedFrom,
    amountPkn: Number(ethers.formatUnits(tx.value, 18)),
  };
}

async function sendNativePkn({ toAddress, amountPkn }) {
  const key = treasuryPrivateKey();
  if (!key) {
    return { mode: 'manual_pending', txHash: null };
  }
  const wallet = new ethers.Wallet(key, provider());
  const tx = await wallet.sendTransaction({
    to: normalizeAddress(toAddress, 'Recipient linked wallet is invalid.'),
    value: pknWei(amountPkn),
  });
  return { mode: 'automatic_available', txHash: tx.hash };
}

module.exports = {
  sendNativePkn,
  treasuryAddress,
  verifyNativeDeposit,
};
