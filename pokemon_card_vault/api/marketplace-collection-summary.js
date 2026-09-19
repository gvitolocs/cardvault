'use strict';

/**
 * Authenticated collection summary for dashboard Portfolio.
 * Dashboard.pokoin.com shares only a Domain=.pokoin.com ID-token cookie —
 * Firebase Auth IndexedDB is origin-scoped, so the client Firestore SDK has
 * request.auth == null there. This BFF verifies the bearer and reads with Admin.
 */

const { verifyBearerToken } = require('./_firebase');
const { summarizeOwnedCollection } = require('./_user_card_collection');

module.exports = async function handler(req, res) {
  try {
    if (req.method !== 'GET') {
      res.setHeader('Allow', 'GET');
      return res.status(405).json({ error: 'Method not allowed.' });
    }
    const decoded = await verifyBearerToken(req);
    const { getFirebaseAdmin } = require('./_firebase');
    const admin = getFirebaseAdmin();
    const firestore = admin.firestore();
    const summary = await summarizeOwnedCollection({
      firestore,
      uid: decoded.uid,
    });
    res.setHeader('Cache-Control', 'private, no-store');
    return res.status(200).json(summary);
  } catch (error) {
    const status = Number(error.statusCode) || 500;
    if (status >= 500) {
      console.error('marketplace-collection-summary failed', error);
    }
    return res.status(status >= 400 && status < 600 ? status : 500).json({
      error: status === 401 ? 'Authentication required.' : 'Could not load collection.',
    });
  }
};

module.exports._test = {
  summarizeOwnedCollection,
};
