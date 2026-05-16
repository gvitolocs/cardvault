const { ethers } = require('ethers');
const { getFirebaseAdmin } = require('./_firebase');
const { ensureUniqueUsername } = require('./_username');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
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
    const nonceRef = admin.firestore().collection('wallet_auth_nonces').doc(normalized);
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

    const walletRegistryRef = firestore.collection('wallet_addresses').doc(normalized);
    const walletRegistry = await walletRegistryRef.get();
    const existingOwner = walletRegistry.data()?.uid;
    const uid = existingOwner || `wallet:${normalized}`;
    let email = `${normalized.slice(2)}@wallet.pokoin.local`;
    let displayName = `${normalized.slice(0, 6)}...${normalized.slice(-4)}`;

    try {
      const authUser = await admin.auth().getUser(uid);
      email = authUser.email || email;
      displayName = authUser.displayName || displayName;
    } catch (error) {
      if (error.code !== 'auth/user-not-found') {
        throw error;
      }
      await admin.auth().createUser({
        uid,
        email,
        displayName,
      });
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    const username = await ensureUniqueUsername({
      firestore,
      admin,
      uid,
      email,
      displayName,
    });
    await firestore.runTransaction(async (transaction) => {
      const freshNonce = await transaction.get(nonceRef);
      if (!freshNonce.exists || freshNonce.data()?.used === true) {
        throw Object.assign(new Error('Wallet sign-in nonce expired. Try again.'), {
          statusCode: 400,
        });
      }

      const freshRegistry = await transaction.get(walletRegistryRef);
      const freshOwner = freshRegistry.data()?.uid;
      if (freshRegistry.exists && freshOwner && freshOwner !== uid) {
        throw Object.assign(new Error('This wallet is already linked to another account.'), {
          statusCode: 409,
        });
      }

      transaction.update(nonceRef, { used: true, usedAt: now });
      transaction.set(
        firestore.collection('users').doc(uid),
        {
          email,
          displayName,
          username,
          usernameLower: username,
          walletAddress: normalized,
          authProvider: 'wallet',
          updatedAt: now,
          lastLoginAt: now,
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
      transaction.set(
        firestore.collection('balances').doc(uid),
        {
          availablePkn: admin.firestore.FieldValue.increment(0),
          lockedPkn: admin.firestore.FieldValue.increment(0),
          updatedAt: now,
        },
        { merge: true },
      );
    });

    const customToken = await admin.auth().createCustomToken(uid, {
      walletAddress: normalized,
      provider: 'metamask',
    });

    return res.status(200).json({
      customToken,
      uid,
      email,
      displayName,
      username,
      walletAddress: normalized,
    });
  } catch (error) {
    console.error('wallet-auth-verify failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Wallet verification failed.',
    });
  }
};
