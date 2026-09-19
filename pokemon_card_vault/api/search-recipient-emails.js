const { getFirebaseAdmin, verifyBearerToken } = require('../server/_firebase');
const {
  displayNameSearchKey,
  ensureUniqueUsername,
  updateUniqueUsername,
} = require('../server/_username');

function pushMatch(bag, seen, { username, displayName, uid }, selfUid, query) {
  const handle = String(username || '').trim().toLowerCase();
  if (!handle || !/^[a-z0-9]{3,32}$/.test(handle) || uid === selfUid || seen.has(handle)) {
    return;
  }
  const label = String(displayName || '').trim();
  const compactLabel = displayNameSearchKey(label);
  if (!(handle.startsWith(query) || (compactLabel && compactLabel.startsWith(query)))) {
    return;
  }
  seen.add(handle);
  bag.push({
    username: handle,
    displayName: label && label.toLowerCase() !== handle ? label : '',
  });
}

module.exports = async function handler(req, res) {
  if (req.method !== 'GET' && req.method !== 'POST') {
    res.setHeader('Allow', 'GET, POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const decoded = await verifyBearerToken(req);
    const admin = getFirebaseAdmin();
    const firestore = admin.firestore();

    if (req.method === 'POST') {
      const requestedUsername = String(req.body?.username || '').trim();
      if (requestedUsername) {
        const username = await updateUniqueUsername({
          firestore,
          admin,
          uid: decoded.uid,
          desiredUsername: requestedUsername,
        });
        return res.status(200).json({ username });
      }
      const userDoc = await firestore.collection('users').doc(decoded.uid).get();
      const profile = userDoc.data() || {};
      const username = await ensureUniqueUsername({
        firestore,
        admin,
        uid: decoded.uid,
        email: decoded.email || profile.email || '',
        displayName: profile.displayName || decoded.name || '',
      });
      return res.status(200).json({ username });
    }

    // Accept "Raffaella Sabatino" / "raf" — compact to letters/digits for prefix match.
    const rawQuery = String(req.query.q || '').trim().toLowerCase();
    const query = displayNameSearchKey(rawQuery);

    if (query.length < 2) {
      return res.status(200).json({ usernames: [], results: [] });
    }

    const seen = new Set();
    const results = [];

    // 1) Handle prefix (doc id === username).
    try {
      const byId = await firestore
        .collection('usernames')
        .orderBy(admin.firestore.FieldPath.documentId())
        .startAt(query)
        .endAt(`${query}\uf8ff`)
        .limit(12)
        .get();
      for (const doc of byId.docs) {
        const data = doc.data() || {};
        pushMatch(results, seen, {
          username: data.username || doc.id,
          displayName: data.displayName,
          uid: data.uid,
        }, decoded.uid, query);
      }
    } catch (err) {
      console.warn('search-recipient-emails documentId scan failed', err.message || err);
    }

    // 2) Display-name prefix (spaces stripped): "raf" → Raffaella Sabatino.
    if (results.length < 8) {
      try {
        const byDisplay = await firestore
          .collection('usernames')
          .orderBy('displayNameSearch')
          .startAt(query)
          .endAt(`${query}\uf8ff`)
          .limit(12)
          .get();
        for (const doc of byDisplay.docs) {
          const data = doc.data() || {};
          pushMatch(results, seen, {
            username: data.username || doc.id,
            displayName: data.displayName,
            uid: data.uid,
          }, decoded.uid, query);
        }
      } catch (err) {
        console.warn('search-recipient-emails displayNameSearch scan failed', err.message || err);
      }
    }

    const usernames = results.slice(0, 8).map((row) => row.username);
    return res.status(200).json({ usernames, results: results.slice(0, 8) });
  } catch (error) {
    console.error('search-recipient-emails failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Recipient search failed.',
    });
  }
};
