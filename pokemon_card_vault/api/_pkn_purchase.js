async function handleCompletedCheckout({ admin, session }) {
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

  return {
    amountPkn: pknAmount,
    fulfillmentTarget,
    walletAddress: walletAddress || null,
  };
}

module.exports = { handleCompletedCheckout };
