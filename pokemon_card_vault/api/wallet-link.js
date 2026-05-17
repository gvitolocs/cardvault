const { ethers } = require('ethers');
const { getFirebaseAdmin, verifyBearerToken } = require('../server/_firebase');
const { ensureUniqueUsername } = require('../server/_username');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const decoded = await verifyBearerToken(req);
    const { address, signature } = req.body || {};
    const normalized = String(address || '').trim().toLowerCase();
    const sig = String(signature || '').trim();
    if (!/^0x[a-f0-9]{40}$/.test(normalized)) {
      return res.status(400).json({ error: 'Enter a valid wallet address.' });
    }
    if (!/^0x[a-fA-F0-9]+$/.test(sig)) {
      return res.status(400).json({ error: 'Missing wallet signature.' });
    }

    const admin = getFirebaseAdmin();
    const firestore = admin.firestore();
    const nonceRef = firestore.collection('wallet_auth_nonces').doc(normalized);
    const nonceDoc = await nonceRef.get();
    const nonceData = nonceDoc.data();
    if (!nonceDoc.exists || !nonceData?.message || nonceData.used === true) {
      return res.status(400).json({ error: 'Wallet sign-in nonce expired. Try again.' });
    }

    const issuedAt = Date.parse(nonceData.issuedAt || '');
    if (!Number.isFinite(issuedAt) || Date.now() - issuedAt > 10 * 60 * 1000) {
      return res.status(400).json({ error: 'Wallet sign-in nonce expired. Try again.' });
    }

    const recovered = ethers.verifyMessage(nonceData.message, sig).toLowerCase();
    if (recovered !== normalized) {
      return res.status(401).json({ error: 'Wallet signature did not match address.' });
    }

    const uid = decoded.uid;
    const email = String(decoded.email || '').trim().toLowerCase();
    const now = admin.firestore.FieldValue.serverTimestamp();
    await ensureUniqueUsername({
      firestore,
      admin,
      uid,
      email,
      displayName: decoded.name || '',
    });
    const userRef = firestore.collection('users').doc(uid);
    const balanceRef = firestore.collection('balances').doc(uid);
    const walletRegistryRef = firestore.collection('wallet_addresses').doc(normalized);
    const linkedRegistryRef = firestore.collection('wallet_addresses');
    const requestRef = firestore.collection('withdraw_requests').doc();
    const ledgerRef = firestore.collection('ledger_entries').doc();

    let convertedPkn = 0;
    await firestore.runTransaction(async (transaction) => {
      const freshNonce = await transaction.get(nonceRef);
      if (!freshNonce.exists || freshNonce.data()?.used === true) {
        throw Object.assign(new Error('Wallet sign-in nonce expired. Try again.'), {
          statusCode: 400,
        });
      }

      const registry = await transaction.get(walletRegistryRef);
      const ownerUid = registry.data()?.uid;
      if (registry.exists && ownerUid && ownerUid !== uid) {
        throw Object.assign(new Error('This wallet is already linked to another account.'), {
          statusCode: 409,
        });
      }

      const userDoc = await transaction.get(userRef);
      const existingWallet = String(userDoc.data()?.walletAddress || '').trim().toLowerCase();
      if (existingWallet && existingWallet !== normalized) {
        throw Object.assign(
          new Error(
            'This account already has a linked wallet. Switch MetaMask accounts to sign in as a wallet-only user, or disconnect the current wallet first.',
          ),
          { statusCode: 409 },
        );
      }

      const linkedWallets = await transaction.get(linkedRegistryRef.where('uid', '==', uid).limit(2));
      const otherLinkedWallet = linkedWallets.docs
        .map((doc) => doc.id)
        .find((address) => address !== normalized);
      if (otherLinkedWallet) {
        throw Object.assign(
          new Error(
            'This account already has a linked wallet. Switch MetaMask accounts to sign in as a wallet-only user, or disconnect the current wallet first.',
          ),
          { statusCode: 409 },
        );
      }

      const balance = await transaction.get(balanceRef);
      convertedPkn = Number(balance.data()?.availablePkn || 0);

      transaction.update(nonceRef, { used: true, usedAt: now });
      transaction.set(
        userRef,
        {
          walletAddress: normalized,
          walletConnectedAt: now,
          walletBalanceMode: 'on_chain',
          updatedAt: now,
        },
        { merge: true },
      );
      transaction.set(
        walletRegistryRef,
        {
          uid,
          email,
          address: normalized,
          verifiedAt: now,
          updatedAt: now,
        },
        { merge: true },
      );

      if (convertedPkn > 0) {
        transaction.set(
          balanceRef,
          {
            availablePkn: admin.firestore.FieldValue.increment(-convertedPkn),
            lockedPkn: admin.firestore.FieldValue.increment(convertedPkn),
            updatedAt: now,
          },
          { merge: true },
        );
        transaction.set(requestRef, {
          uid,
          email,
          toAddress: normalized,
          amountPkn: convertedPkn,
          status: 'pending',
          source: 'wallet_connect_conversion',
          createdAt: now,
          updatedAt: now,
        });
        transaction.set(ledgerRef, {
          uid,
          type: 'wallet_connect_conversion_requested',
          amountPkn: -convertedPkn,
          toAddress: normalized,
          withdrawRequestId: requestRef.id,
          createdAt: now,
        });
      }
    });

    return res.status(200).json({
      ok: true,
      walletAddress: normalized,
      convertedPkn,
      withdrawRequestId: convertedPkn > 0 ? requestRef.id : null,
    });
  } catch (error) {
    console.error('wallet-link failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Wallet link failed.',
    });
  }
};
