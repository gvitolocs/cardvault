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
    const walletOnlyUid = `wallet:${normalized}`;
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
    const walletOnlyUserRef = firestore.collection('users').doc(walletOnlyUid);
    const walletOnlyBalanceRef = firestore.collection('balances').doc(walletOnlyUid);
    const walletRegistryRef = firestore.collection('wallet_addresses').doc(normalized);
    const linkedRegistryRef = firestore.collection('wallet_addresses');

    await firestore.runTransaction(async (transaction) => {
      const freshNonce = await transaction.get(nonceRef);
      if (!freshNonce.exists || freshNonce.data()?.used === true) {
        throw Object.assign(new Error('Wallet sign-in nonce expired. Try again.'), {
          statusCode: 400,
        });
      }

      const registry = await transaction.get(walletRegistryRef);
      const ownerUid = registry.data()?.uid;
      const canClaimWalletOnlyAccount = ownerUid === walletOnlyUid;
      const walletOnlyUser = canClaimWalletOnlyAccount
        ? await transaction.get(walletOnlyUserRef)
        : null;
      const walletOnlyBalance = canClaimWalletOnlyAccount
        ? await transaction.get(walletOnlyBalanceRef)
        : null;
      if (registry.exists && ownerUid && ownerUid !== uid && !canClaimWalletOnlyAccount) {
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

      transaction.update(nonceRef, { used: true, usedAt: now });
      transaction.set(
        userRef,
        {
          walletAddress: normalized,
          walletConnectedAt: now,
          updatedAt: now,
        },
        { merge: true },
      );
      if (canClaimWalletOnlyAccount) {
        const sourceAvailable = Number(walletOnlyBalance.data()?.availablePkn || 0);
        const sourceLocked = Number(walletOnlyBalance.data()?.lockedPkn || 0);
        if (sourceAvailable || sourceLocked) {
          transaction.set(
            balanceRef,
            {
              availablePkn: admin.firestore.FieldValue.increment(sourceAvailable),
              lockedPkn: admin.firestore.FieldValue.increment(sourceLocked),
              updatedAt: now,
            },
            { merge: true },
          );
          transaction.set(
            walletOnlyBalanceRef,
            {
              availablePkn: 0,
              lockedPkn: 0,
              mergedIntoUid: uid,
              updatedAt: now,
            },
            { merge: true },
          );
        }
        transaction.set(
          walletOnlyUserRef,
          {
            mergedIntoUid: uid,
            mergedAt: now,
            active: false,
            updatedAt: now,
          },
          { merge: true },
        );
        const walletOnlyUsername = String(walletOnlyUser.data()?.username || '').trim().toLowerCase();
        if (walletOnlyUsername) {
          transaction.delete(firestore.collection('usernames').doc(walletOnlyUsername));
        }
      }
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
    });

    return res.status(200).json({
      ok: true,
      walletAddress: normalized,
    });
  } catch (error) {
    console.error('wallet-link failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Wallet link failed.',
    });
  }
};
