const PKN_USDT_REFERENCE_PRICE = 0.005;

function pknCheckoutReferencePrice() {
  const value = Number(process.env.PKN_CHECKOUT_USDT_PRICE || PKN_USDT_REFERENCE_PRICE);
  if (!Number.isFinite(value) || value <= 0) {
    throw Object.assign(new Error('PKN checkout price is not configured.'), {
      statusCode: 500,
    });
  }
  return value;
}

function pknAmountForFiatCents(fiatCents) {
  const fiatAmount = Number(fiatCents) / 100;
  return Math.round(fiatAmount / pknCheckoutReferencePrice());
}

module.exports = {
  PKN_USDT_REFERENCE_PRICE,
  pknAmountForFiatCents,
  pknCheckoutReferencePrice,
};
