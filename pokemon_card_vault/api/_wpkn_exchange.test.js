const assert = require('node:assert/strict');
const test = require('node:test');
const { calculateQuote } = require('./_wpkn_exchange');

test('PKN to wPKN quote uses market ratio instead of 1:1 reserve backing', () => {
  const quote = calculateQuote({
    direction: 'pkn_to_wpkn',
    amountIn: 1000,
    marketPrice: 2,
    nowMs: Date.UTC(2026, 4, 27, 10, 0, 0),
  });

  assert.equal(quote.fromAsset, 'PKN');
  assert.equal(quote.toAsset, 'wPKN');
  assert.equal(quote.marketPrice, 2);
  assert.equal(quote.amountOut, 495);
  assert.equal(quote.quoteExpiresAt, '2026-05-27T10:01:00.000Z');
});

test('wPKN to PKN quote uses market ratio instead of 1:1 reserve backing', () => {
  const quote = calculateQuote({
    direction: 'wpkn_to_pkn',
    amountIn: 1000,
    marketPrice: 2,
    nowMs: Date.UTC(2026, 4, 27, 10, 0, 0),
  });

  assert.equal(quote.fromAsset, 'wPKN');
  assert.equal(quote.toAsset, 'PKN');
  assert.equal(quote.amountOut, 1980);
});
