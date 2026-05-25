const assert = require('node:assert/strict');
const test = require('node:test');
const {
  calculateCryptoPknQuote,
  calculatePknCryptoSaleQuote,
  settlementAddress,
} = require('./_crypto_pkn_purchase');

test('stablecoin crypto purchase quote uses 0.005 USDT per PKN', async () => {
  const quote = await calculateCryptoPknQuote({
    asset: 'USDT',
    amountIn: 10,
    nowMs: Date.UTC(2026, 4, 21, 12, 0, 0),
  });

  assert.equal(quote.fromAsset, 'USDT');
  assert.equal(quote.toAsset, 'PKN');
  assert.equal(quote.pknUsd, 0.005);
  assert.equal(quote.marketPrice, 1);
  assert.equal(quote.feeBps, 30);
  assert.equal(quote.amountOut, 1994);
  assert.equal(quote.settlementAddress, settlementAddress());
  assert.equal(quote.quoteExpiresAt, '2026-05-21T12:01:00.000Z');
});

test('EURC purchase quote uses euro stablecoin market price', async () => {
  const previousPrice = process.env.CRYPTO_PKN_EURC_USD_PRICE;
  process.env.CRYPTO_PKN_EURC_USD_PRICE = '1.16';
  try {
    const quote = await calculateCryptoPknQuote({
      asset: 'EURC',
      amountIn: 10,
      nowMs: Date.UTC(2026, 4, 21, 12, 0, 0),
    });

    assert.equal(quote.fromAsset, 'EURC');
    assert.equal(quote.toAsset, 'PKN');
    assert.equal(quote.chainName, 'Ethereum');
    assert.equal(quote.marketPrice, 1.16);
    assert.equal(quote.feeBps, 100);
    assert.equal(quote.amountOut, 2296);
    assert.equal(quote.tokenAddress, '0x1abaea1f7c830bd89acc67ec4af516284b1bc33c');
  } finally {
    if (previousPrice == null) {
      delete process.env.CRYPTO_PKN_EURC_USD_PRICE;
    } else {
      process.env.CRYPTO_PKN_EURC_USD_PRICE = previousPrice;
    }
  }
});

test('unsupported crypto purchase assets are rejected', async () => {
  await assert.rejects(
    calculateCryptoPknQuote({ asset: 'PEPE', amountIn: 1 }),
    /not supported yet/,
  );
});

test('BTC crypto purchase quote uses Bitcoin settlement address', async () => {
  const previousAddress = process.env.BITCOIN_SETTLEMENT_ADDRESS;
  const previousPrice = process.env.CRYPTO_PKN_BTC_USD_PRICE;
  process.env.BITCOIN_SETTLEMENT_ADDRESS = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080';
  process.env.CRYPTO_PKN_BTC_USD_PRICE = '100000';
  try {
    const quote = await calculateCryptoPknQuote({
      asset: 'BTC',
      amountIn: 0.001,
      nowMs: Date.UTC(2026, 4, 21, 12, 0, 0),
    });

    assert.equal(quote.fromAsset, 'BTC');
    assert.equal(quote.toAsset, 'PKN');
    assert.equal(quote.chainName, 'Bitcoin');
    assert.equal(quote.settlementAddress, 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kygt080');
    assert.equal(quote.marketPrice, 100000);
    assert.equal(quote.amountOut, 19800);
  } finally {
    if (previousAddress == null) {
      delete process.env.BITCOIN_SETTLEMENT_ADDRESS;
    } else {
      process.env.BITCOIN_SETTLEMENT_ADDRESS = previousAddress;
    }
    if (previousPrice == null) {
      delete process.env.CRYPTO_PKN_BTC_USD_PRICE;
    } else {
      process.env.CRYPTO_PKN_BTC_USD_PRICE = previousPrice;
    }
  }
});

test('PKN crypto sale quote prices target asset in reverse', async () => {
  const previousPrice = process.env.CRYPTO_PKN_ETH_USD_PRICE;
  process.env.CRYPTO_PKN_ETH_USD_PRICE = '2500';
  try {
    const quote = await calculatePknCryptoSaleQuote({
      asset: 'ETH',
      amountIn: 1000,
      nowMs: Date.UTC(2026, 4, 21, 12, 0, 0),
    });

    assert.equal(quote.fromAsset, 'PKN');
    assert.equal(quote.toAsset, 'ETH');
    assert.equal(quote.marketPrice, 2500);
    assert.equal(quote.pknUsd, 0.005);
    assert.equal(quote.feeBps, 100);
    assert.equal(quote.amountOut, 0.00198);
    assert.equal(quote.quoteExpiresAt, '2026-05-21T12:01:00.000Z');
  } finally {
    if (previousPrice == null) {
      delete process.env.CRYPTO_PKN_ETH_USD_PRICE;
    } else {
      process.env.CRYPTO_PKN_ETH_USD_PRICE = previousPrice;
    }
  }
});
