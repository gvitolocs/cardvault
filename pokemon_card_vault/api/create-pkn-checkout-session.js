const Stripe = require('stripe');
const { getFirebaseAdmin, verifyBearerToken } = require('./_firebase');
const { handleCompletedCheckout } = require('./_pkn_purchase');

const allowedPackages = new Map([
  [500, 500],
  [2500, 2500],
  [10000, 10000],
]);

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
    const { pknAmount, fiatCents, checkoutSessionId } = req.body || {};
    const stripe = new Stripe(stripeSecret, { apiVersion: '2025-12-31.clover' });
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

    const expectedFiat = allowedPackages.get(Number(pknAmount));
    if (!expectedFiat || expectedFiat !== Number(fiatCents)) {
      return res.status(400).json({ error: 'Invalid PKN package.' });
    }

    const userDoc = await admin.firestore().collection('users').doc(decoded.uid).get();
    const userData = userDoc.data() || {};
    const walletAddress = userData.walletAddress || '';
    const successUrl = `${process.env.PUBLIC_SITE_URL || 'https://pokoin.com'}/buy?status=success`;
    const cancelUrl = `${process.env.PUBLIC_SITE_URL || 'https://pokoin.com'}/buy?status=cancelled`;

    const session = await stripe.checkout.sessions.create({
      mode: 'payment',
      payment_method_types: ['card'],
      customer_email: decoded.email || userData.email || undefined,
      success_url: `${successUrl}&session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: cancelUrl,
      line_items: [
        {
          quantity: 1,
          price_data: {
            currency: process.env.PKN_CHECKOUT_CURRENCY || 'eur',
            unit_amount: expectedFiat,
            product_data: {
              name: `${pknAmount} PKN`,
              description: walletAddress
                ? 'Pokoin purchase queued for on-chain delivery.'
                : 'Pokoin site credit purchase.',
            },
          },
        },
      ],
      metadata: {
        uid: decoded.uid,
        email: decoded.email || userData.email || '',
        pknAmount: String(pknAmount),
        fiatCents: String(expectedFiat),
        walletAddress,
        fulfillmentTarget: walletAddress ? 'onchain_pending' : 'site_credit',
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
