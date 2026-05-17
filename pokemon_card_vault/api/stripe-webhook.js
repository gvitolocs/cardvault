const Stripe = require('stripe');
const { getFirebaseAdmin } = require('../server/_firebase');
const { handleCompletedCheckout } = require('../server/_pkn_purchase');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).send('Method not allowed');
  }

  const stripeSecret = process.env.STRIPE_SECRET_KEY;
  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;
  if (!stripeSecret || !webhookSecret) {
    return res.status(500).send('Stripe webhook is not configured.');
  }

  const stripeOptions = process.env.STRIPE_API_VERSION
    ? { apiVersion: process.env.STRIPE_API_VERSION }
    : {};
  const stripe = new Stripe(stripeSecret, stripeOptions);

  let event;
  try {
    const chunks = [];
    for await (const chunk of req) {
      chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
    }
    const rawBody = Buffer.concat(chunks);
    event = stripe.webhooks.constructEvent(
      rawBody,
      req.headers['stripe-signature'],
      webhookSecret,
    );
  } catch (error) {
    console.error('Stripe webhook signature failed', error);
    return res.status(400).send(`Webhook Error: ${error.message}`);
  }

  try {
    if (event.type === 'checkout.session.completed') {
      await handleCompletedCheckout({
        admin: getFirebaseAdmin(),
        session: event.data.object,
      });
    }
    return res.status(200).json({ received: true });
  } catch (error) {
    console.error('Stripe webhook handling failed', error);
    return res.status(500).send('Webhook handling failed.');
  }
};

