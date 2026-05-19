const { ethers } = require('ethers');
const { getFirebaseAdmin } = require('../server/_firebase');
const { ensureUniqueUsername } = require('../server/_username');

function normalizeAddress(address) {
  const normalized = String(address || '').trim().toLowerCase();
  if (!/^0x[a-f0-9]{40}$/.test(normalized)) {
    const error = new Error('Enter a valid wallet address.');
    error.statusCode = 400;
    throw error;
  }
  return normalized;
}

function validateSignature(signature) {
  const sig = String(signature || '').trim();
  if (!/^0x[a-fA-F0-9]+$/.test(sig)) {
    const error = new Error('Missing wallet signature.');
    error.statusCode = 400;
    throw error;
  }
  return sig;
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const sessionId = String(req.body?.sessionId || '').trim();
    const normalized = normalizeAddress(req.body?.address);
    const sig = validateSignature(req.body?.signature);
    if (!/^[a-f0-9]{48}$/.test(sessionId)) {
      return res.status(400).json({ error: 'Wallet link session is invalid.' });
    }

    const admin = getFirebaseAdmin();
    const firestore = admin.firestore();
    const sessionRef = firestore.collection('wallet_link_sessions').doc(sessionId);
    const nonceRef = firestore.collection('wallet_auth_nonces').doc(normalized);
    const walletRegistryRef = firestore.collection('wallet_addresses').doc(normalized);
    const walletOnlyUid = `wallet:${normalized}`;
    const walletOnlyUserRef = firestore.collection('users').doc(walletOnlyUid);
    const walletOnlyBalanceRef = firestore.collection('balances').doc(walletOnlyUid);
    const now = admin.firestore.FieldValue.serverTimestamp();
    const sessionDoc = await sessionRef.get();
    const session = sessionDoc.data() || {};
    if (!sessionDoc.exists || session.used === true) {
      return res.status(400).json({ error: 'Wallet link session expired. Start again from your profile.' });
    }
    if (Date.now() > Number(session.expiresAtMs || 0)) {
      return res.status(410).json({ error: 'Wallet link session expired. Start again from your profile.' });
    }

    const uid = String(session.uid || '').trim();
    const email = String(session.email || '').trim().toLowerCase();
    const returnPath = String(session.returnPath || '/profile');
    if (!uid) {
      return res.status(400).json({ error: 'Wallet link session is missing a profile.' });
    }
    const userSnapshot = await firestore.collection('users').doc(uid).get();
    const username = await ensureUniqueUsername({
      firestore,
      admin,
      uid,
      email,
      displayName: userSnapshot.data()?.displayName || email || 'Pokoin user',
    });

    await firestore.runTransaction(async (transaction) => {
      const [freshSessionDoc, nonceDoc, registryDoc] = await Promise.all([
        transaction.get(sessionRef),
        transaction.get(nonceRef),
        transaction.get(walletRegistryRef),
      ]);
      const freshSession = freshSessionDoc.data() || {};
      const nonce = nonceDoc.data() || {};
      if (!freshSessionDoc.exists || freshSession.used === true) {
        throw Object.assign(new Error('Wallet link session expired. Start again from your profile.'), {
          statusCode: 400,
        });
      }
      if (Date.now() > Number(freshSession.expiresAtMs || 0)) {
        throw Object.assign(new Error('Wallet link session expired. Start again from your profile.'), {
          statusCode: 410,
        });
      }
      if (!nonceDoc.exists || !nonce.message || nonce.used === true) {
        throw Object.assign(new Error('Wallet sign-in nonce expired. Try again.'), {
          statusCode: 400,
        });
      }
      const issuedAt = Date.parse(nonce.issuedAt || '');
      if (!Number.isFinite(issuedAt) || Date.now() - issuedAt > 10 * 60 * 1000) {
        throw Object.assign(new Error('Wallet sign-in nonce expired. Try again.'), {
          statusCode: 400,
        });
      }
      const recovered = ethers.verifyMessage(nonce.message, sig).toLowerCase();
      if (recovered !== normalized) {
        throw Object.assign(new Error('Wallet signature did not match address.'), {
          statusCode: 401,
        });
      }

      const ownerUid = registryDoc.data()?.uid;
      const canClaimWalletOnlyAccount = ownerUid === walletOnlyUid;
      if (registryDoc.exists && ownerUid && ownerUid !== uid && !canClaimWalletOnlyAccount) {
        throw Object.assign(new Error('This wallet is already linked to another account.'), {
          statusCode: 409,
        });
      }

      const userRef = firestore.collection('users').doc(uid);
      const balanceRef = firestore.collection('balances').doc(uid);
      const userDoc = await transaction.get(userRef);
      const existingWallet = String(userDoc.data()?.walletAddress || '').trim().toLowerCase();
      if (existingWallet && existingWallet !== normalized) {
        throw Object.assign(new Error('This profile already has a different linked wallet.'), {
          statusCode: 409,
        });
      }

      const linkedWallets = await transaction.get(
        firestore.collection('wallet_addresses').where('uid', '==', uid).limit(2),
      );
      const otherLinkedWallet = linkedWallets.docs
        .map((doc) => doc.id)
        .find((address) => address !== normalized);
      if (otherLinkedWallet) {
        throw Object.assign(new Error('This profile already has a different linked wallet.'), {
          statusCode: 409,
        });
      }

      const walletOnlyUser = canClaimWalletOnlyAccount ? await transaction.get(walletOnlyUserRef) : null;
      const walletOnlyBalance = canClaimWalletOnlyAccount
        ? await transaction.get(walletOnlyBalanceRef)
        : null;
      const sourceAvailable = Number(walletOnlyBalance?.data()?.availablePkn || 0);
      const sourceLocked = Number(walletOnlyBalance?.data()?.lockedPkn || 0);

      transaction.update(nonceRef, { used: true, usedAt: now });
      transaction.update(sessionRef, {
        used: true,
        usedAt: now,
        walletAddress: normalized,
        updatedAt: now,
      });
      transaction.set(
        userRef,
        {
          walletAddress: normalized,
          walletConnectedAt: now,
          username,
          usernameLower: username,
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
      if (canClaimWalletOnlyAccount) {
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
        const walletOnlyUsername = String(walletOnlyUser?.data()?.username || '').trim().toLowerCase();
        if (walletOnlyUsername) {
          transaction.delete(firestore.collection('usernames').doc(walletOnlyUsername));
        }
      }
    });

    const customToken = await admin.auth().createCustomToken(uid, {
      walletAddress: normalized,
      provider: 'metamask_link',
    });

    return res.status(200).json({
      customToken,
      uid,
      walletAddress: normalized,
      returnPath: returnPath.startsWith('/') && !returnPath.startsWith('//') ? returnPath : '/profile',
    });
  } catch (error) {
    console.error('wallet-link-complete failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Wallet link failed.',
    });
  }
};
