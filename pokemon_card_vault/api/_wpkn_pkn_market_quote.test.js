const assert = require('node:assert/strict');
const test = require('node:test');
const {
  calculateWpknPknMarketQuote,
  referencePriceFromUsd,
} = require('./_wpkn_pkn_market_quote');

test('reference price uses USD ratio: PKN per 1 wPKN', () => {
  const ratio = referencePriceFromUsd(0.001, 0.005);
  assert.equal(ratio, 0.2);
});

test('wPKN to PKN quote uses GeckoTerminal USD prices and 0.005 PKN reference', async () => {
  const quote = await calculateWpknPknMarketQuote({
    direction: 'wpkn_to_pkn',
    amountIn: 10,
    wpknUsd: 0.001,
    pknUsd: 0.005,
    nowMs: Date.UTC(2026, 4, 28, 12, 0, 0),
  });

  assert.equal(quote.fromAsset, 'wPKN');
  assert.equal(quote.toAsset, 'PKN');
  assert.equal(quote.amountOut, 2);
  assert.equal(quote.marketPrice, 0.2);
});

test('PKN to wPKN quote inverts the USD ratio', async () => {
  const quote = await calculateWpknPknMarketQuote({
    direction: 'pkn_to_wpkn',
    amountIn: 10,
    wpknUsd: 0.001,
    pknUsd: 0.005,
    nowMs: Date.UTC(2026, 4, 28, 12, 0, 0),
  });

  assert.equal(quote.fromAsset, 'PKN');
  assert.equal(quote.toAsset, 'wPKN');
  assert.equal(quote.amountOut, 50);
});
