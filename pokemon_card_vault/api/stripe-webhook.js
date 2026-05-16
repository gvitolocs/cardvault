const Stripe = require('stripe');
const { getFirebaseAdmin } = require('./_firebase');

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

  const stripe = new Stripe(stripeSecret, { apiVersion: '2025-12-31.clover' });

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
      await handleCompletedCheckout(event.data.object);
    }
    return res.status(200).json({ received: true });
  } catch (error) {
    console.error('Stripe webhook handling failed', error);
    return res.status(500).send('Webhook handling failed.');
  }
};

async function handleCompletedCheckout(session) {
  const admin = getFirebaseAdmin();
  const firestore = admin.firestore();
  const purchaseRef = firestore.collection('pkn_purchases').doc(session.id);
  const metadata = session.metadata || {};
  const uid = metadata.uid;
  const pknAmount = Number(metadata.pknAmount || 0);
  const fiatCents = Number(metadata.fiatCents || session.amount_total || 0);
  const walletAddress = metadata.walletAddress || '';
  const fulfillmentTarget = walletAddress ? 'onchain_pending' : 'site_credit';

  if (!uid || !Number.isInteger(pknAmount) || pknAmount <= 0) {
    throw new Error('Invalid checkout metadata.');
  }

  await firestore.runTransaction(async (transaction) => {
    const existing = await transaction.get(purchaseRef);
    if (existing.exists) {
      return;
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    transaction.set(purchaseRef, {
      uid,
      email: metadata.email || session.customer_details?.email || '',
      stripeSessionId: session.id,
      stripePaymentIntentId: session.payment_intent || '',
      amountFiat: fiatCents,
      currency: session.currency || 'eur',
      amountPkn: pknAmount,
      walletAddress: walletAddress || null,
      fulfillmentTarget,
      status: fulfillmentTarget === 'site_credit' ? 'credited' : 'onchain_pending',
      createdAt: now,
      paidAt: now,
      updatedAt: now,
    });

    if (fulfillmentTarget === 'site_credit') {
      const balanceRef = firestore.collection('balances').doc(uid);
      transaction.set(
        balanceRef,
        {
          availablePkn: admin.firestore.FieldValue.increment(pknAmount),
          lockedPkn: admin.firestore.FieldValue.increment(0),
          updatedAt: now,
        },
        { merge: true },
      );
      transaction.set(firestore.collection('ledger_entries').doc(), {
        uid,
        type: 'pkn_purchase_credit',
        amountPkn: pknAmount,
        stripeSessionId: session.id,
        createdAt: now,
      });
    }
  });
}
