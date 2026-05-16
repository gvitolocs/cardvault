const { getFirebaseAdmin, verifyBearerToken } = require('./_firebase');
const { ensureUniqueUsername } = require('./_username');

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

    const query = String(req.query.q || '').trim().toLowerCase();

    if (query.length < 2) {
      return res.status(200).json({ usernames: [] });
    }
    if (!/^[a-z0-9_]{0,32}$/.test(query)) {
      return res.status(200).json({ usernames: [] });
    }

    const snapshot = await firestore
      .collection('usernames')
      .orderBy('username')
      .startAt(query)
      .endAt(`${query}\uf8ff`)
      .limit(8)
      .get();

    const usernames = [];
    for (const doc of snapshot.docs) {
      const username = String(doc.data()?.username || doc.id || '').trim().toLowerCase();
      const uid = String(doc.data()?.uid || '');
      if (!username || uid === decoded.uid) {
        continue;
      }
      usernames.push(username);
      if (usernames.length >= 5) {
        break;
      }
    }

    return res.status(200).json({ usernames });
  } catch (error) {
    console.error('search-recipient-emails failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Recipient search failed.',
    });
  }
};
