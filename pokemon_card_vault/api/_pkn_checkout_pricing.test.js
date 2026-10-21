const assert = require('node:assert/strict');
const test = require('node:test');

const {
  PKN_USDT_REFERENCE_PRICE,
  pknAmountForFiatCents,
  pknCheckoutReferencePrice,
} = require('./_pkn_checkout_pricing');

test('default PKN reference price is 0.005 USDT', () => {
  const previous = process.env.PKN_CHECKOUT_USDT_PRICE;
  delete process.env.PKN_CHECKOUT_USDT_PRICE;
  try {
    assert.equal(pknCheckoutReferencePrice(), PKN_USDT_REFERENCE_PRICE);
  } finally {
    if (previous === undefined) {
      delete process.env.PKN_CHECKOUT_USDT_PRICE;
    } else {
      process.env.PKN_CHECKOUT_USDT_PRICE = previous;
    }
  }
});

test('fixed packages map fiat cents to PKN at the reference price', () => {
  const previous = process.env.PKN_CHECKOUT_USDT_PRICE;
  delete process.env.PKN_CHECKOUT_USDT_PRICE;
  try {
    assert.equal(pknAmountForFiatCents(500), 1000);
    assert.equal(pknAmountForFiatCents(2500), 5000);
    assert.equal(pknAmountForFiatCents(10000), 20000);
  } finally {
    if (previous === undefined) {
      delete process.env.PKN_CHECKOUT_USDT_PRICE;
    } else {
      process.env.PKN_CHECKOUT_USDT_PRICE = previous;
    }
  }
});
