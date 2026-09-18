'use strict';

/**
 * Authenticated collection holdings for /collection.
 * Same cross-host reason as marketplace-collection-summary: client Firestore
 * rules have no user_card_collections match, and dashboard cookie SSO has no
 * firebaseAuth.currentUser. Admin read; uid only from verified bearer.
 * POST ?action=remove removes copies of a physical holding (collection red-cross).
 */

const { getFirebaseAdmin, verifyBearerToken } = require('./_firebase');
const {
  listOwnedCollection,
  removeOwnedCollectionItem,
} = require('./_user_card_collection');

module.exports = async function handler(req, res) {
  try {
    if (req.method === 'GET') {
      const decoded = await verifyBearerToken(req);
      const admin = getFirebaseAdmin();
      const listed = await listOwnedCollection({
        firestore: admin.firestore(),
        uid: decoded.uid,
      });
      res.setHeader('Cache-Control', 'private, no-store');
      return res.status(200).json({
        uid: listed.uid,
        items: listed.items,
        cardsOwned: listed.cardsOwned,
        itemCount: listed.itemCount,
        physicalItems: listed.physicalItems,
        nftItems: listed.nftItems,
      });
    }

    if (req.method === 'POST') {
      const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
      const action = String(url.searchParams.get('action') || '');
      if (action !== 'remove') {
        return res.status(400).json({ error: 'Unknown collection action.' });
      }
      const decoded = await verifyBearerToken(req);
      const admin = getFirebaseAdmin();
      const result = await removeOwnedCollectionItem({
        firestore: admin.firestore(),
        admin,
        uid: decoded.uid,
        itemId: req.body?.itemId,
        quantity: req.body?.quantity,
      });
      res.setHeader('Cache-Control', 'private, no-store');
      return res.status(200).json(result);
    }

    res.setHeader('Allow', 'GET, POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  } catch (error) {
    const status = Number(error.statusCode) || 500;
    if (status >= 500) {
      console.error('marketplace-collection failed', error);
    }
    const message = status === 401
      ? 'Authentication required.'
      : status === 404
        ? 'Collection item not found.'
        : status === 400
          ? (error.message || 'Invalid collection request.')
          : (req.method === 'POST' ? 'Could not remove the card.' : 'Could not load collection.');
    return res.status(status >= 400 && status < 600 ? status : 500).json({ error: message });
  }
};

module.exports._test = {
  listOwnedCollection,
  removeOwnedCollectionItem,
};
