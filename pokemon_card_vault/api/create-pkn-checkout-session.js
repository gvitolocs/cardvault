const Stripe = require('stripe');
const path = require('path');

function requireServerHelper(name) {
  const serverPath = path.join(__dirname, '..', 'server', name);
  try {
    return require(serverPath);
  } catch (error) {
    if (
      error.code !== 'MODULE_NOT_FOUND' ||
      !String(error.message).includes(serverPath)
    ) {
      throw error;
    }
    return require(`./${name}`);
  }
}

const {
  pknAmountForFiatCents,
  pknCheckoutReferencePrice,
} = requireServerHelper('_pkn_checkout_pricing');
const { getFirebaseAdmin, verifyBearerToken } = requireServerHelper('_firebase');
const { handleCompletedCheckout } = requireServerHelper('_pkn_purchase');

const allowedFiatCents = new Set([500, 2500, 10000]);
const packageLookupKeys = new Map([
  [500, 'pkn_starter_1000_pkn_500_eur'],
  [2500, 'pkn_collector_5000_pkn_2500_eur'],
  [10000, 'pkn_validator_20000_pkn_10000_eur'],
]);

async function stripePriceForPackage(stripe, { fiatCents, lookupKey }) {
  const expectedLookupKey = packageLookupKeys.get(Number(fiatCents));
  if (!expectedLookupKey || lookupKey !== expectedLookupKey) {
    return null;
  }
  const prices = await stripe.prices.list({
    lookup_keys: [lookupKey],
    active: true,
    limit: 1,
  });
  const price = prices.data[0];
  if (
    !price ||
    price.unit_amount !== Number(fiatCents) ||
    price.currency !== 'eur'
  ) {
    return null;
  }
  return price.id;
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const stripeSecret = process.env.STRIPE_SECRET_KEY;
    if (!stripeSecret) {
      return res.status(500).json({ error: 'Stripe is not configured yet.' });
    }

    const decoded = await verifyBearerToken(req);
    const { pknAmount, fiatCents, checkoutSessionId, lookupKey } = req.body || {};
    const stripeOptions = process.env.STRIPE_API_VERSION
      ? { apiVersion: process.env.STRIPE_API_VERSION }
      : {};
    const stripe = new Stripe(stripeSecret, stripeOptions);
    const admin = getFirebaseAdmin();

    if (checkoutSessionId) {
      const session = await stripe.checkout.sessions.retrieve(String(checkoutSessionId));
      if (session.metadata?.uid !== decoded.uid) {
        return res.status(403).json({ error: 'Checkout session does not belong to this account.' });
      }
      if (session.payment_status !== 'paid') {
        return res.status(409).json({ error: 'Payment is not complete yet.' });
      }
      const result = await handleCompletedCheckout({ admin, session });
      return res.status(200).json({ ok: true, ...result });
    }

    const fiat = Number(fiatCents);
    const expectedPknAmount = pknAmountForFiatCents(fiat);
    if (!allowedFiatCents.has(fiat) || Number(pknAmount) !== expectedPknAmount) {
      return res.status(400).json({ error: 'Invalid PKN package.' });
    }

    const userDoc = await admin.firestore().collection('users').doc(decoded.uid).get();
    const userData = userDoc.data() || {};
    const successUrl = `${process.env.PUBLIC_SITE_URL || 'https://pokoin.com'}/buy?status=success`;
    const cancelUrl = `${process.env.PUBLIC_SITE_URL || 'https://pokoin.com'}/buy?status=cancelled`;
    const priceId = await stripePriceForPackage(stripe, {
      fiatCents: fiat,
      lookupKey: String(lookupKey || ''),
    });

    const session = await stripe.checkout.sessions.create({
      mode: 'payment',
      payment_method_types: ['card'],
      customer_email: decoded.email || userData.email || undefined,
      success_url: `${successUrl}&session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: cancelUrl,
      line_items: [
        priceId
          ? {
              quantity: 1,
              price: priceId,
            }
          : {
              quantity: 1,
              price_data: {
                currency: process.env.PKN_CHECKOUT_CURRENCY || 'eur',
                unit_amount: fiat,
                product_data: {
                  name: `${expectedPknAmount} PKN`,
                  description: `Pokoin account balance credit at 1 PKN = ${pknCheckoutReferencePrice()} USDT.`,
                },
              },
            },
      ],
      metadata: {
        uid: decoded.uid,
        email: decoded.email || userData.email || '',
        pknAmount: String(expectedPknAmount),
        fiatCents: String(fiat),
        lookupKey: String(lookupKey || ''),
        fulfillmentTarget: 'site_credit',
      },
    });

    return res.status(200).json({ id: session.id, url: session.url });
  } catch (error) {
    console.error('create-pkn-checkout-session failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Checkout failed.',
    });
  }
};
