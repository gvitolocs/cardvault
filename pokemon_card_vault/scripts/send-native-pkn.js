#!/usr/bin/env node
const { ethers } = require('ethers');
const { waitForNativeReceipt } = require('../api/_native_pkn');

function usage() {
  console.error(
    'Usage: POKOIN_BANK_PRIVATE_KEY=0x... node scripts/send-native-pkn.js <toAddress> <amountPkn>',
  );
  process.exit(1);
}

async function main() {
  const [, , toAddress, amountPkn] = process.argv;
  if (!toAddress || !amountPkn) {
    usage();
  }
  if (!/^0x[a-fA-F0-9]{40}$/.test(toAddress)) {
    throw new Error('Recipient must be a valid 0x address.');
  }
  const privateKey = process.env.POKOIN_BANK_PRIVATE_KEY;
  if (!privateKey) {
    throw new Error('Set POKOIN_BANK_PRIVATE_KEY.');
  }

  const provider = new ethers.JsonRpcProvider(
    process.env.POKOIN_RPC_URL || 'https://rpc.pokoin.com/rpc',
  );
  const wallet = new ethers.Wallet(privateKey, provider);
  const tx = await wallet.sendTransaction({
    to: toAddress,
    value: ethers.parseUnits(String(amountPkn), 18),
  });

  console.log(`Submitted ${amountPkn} PKN from ${await wallet.getAddress()} to ${toAddress}`);
  console.log(`Transaction: ${tx.hash}`);

  const receipt = await waitForNativeReceipt({ txHash: tx.hash });
  if (!receipt.ok) {
    throw new Error(`Transaction failed: ${tx.hash}`);
  }
  console.log(`Confirmed in block ${receipt.blockNumber}`);
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
