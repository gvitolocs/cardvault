async function handleCompletedCheckout({ admin, session }) {
  const firestore = admin.firestore();
  const purchaseRef = firestore.collection('pkn_purchases').doc(session.id);
  const metadata = session.metadata || {};
  const uid = metadata.uid;
  const pknAmount = Number(metadata.pknAmount || 0);
  const fiatCents = Number(metadata.fiatCents || session.amount_total || 0);
  const fulfillmentTarget = 'site_credit';

  if (!uid || !Number.isInteger(pknAmount) || pknAmount <= 0) {
    throw new Error('Invalid checkout metadata.');
  }

  let existingResult = null;

  await firestore.runTransaction(async (transaction) => {
    const existing = await transaction.get(purchaseRef);
    if (existing.exists) {
      const data = existing.data() || {};
      existingResult = {
        amountPkn: data.amountPkn || pknAmount,
        fulfillmentTarget: data.fulfillmentTarget || fulfillmentTarget,
        status: data.status || 'processed',
      };
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
      fulfillmentTarget,
      status: 'credited',
      createdAt: now,
      paidAt: now,
      updatedAt: now,
    });

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
  });

  if (existingResult) {
    return existingResult;
  }

  return {
    amountPkn: pknAmount,
    fulfillmentTarget,
    status: 'credited',
  };
}

module.exports = { handleCompletedCheckout };
