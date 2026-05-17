const { getFirebaseAdmin, verifyBearerToken } = require('../server/_firebase');
const { deleteProfilePictureFromR2 } = require('../server/_r2');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const decoded = await verifyBearerToken(req);
    const admin = getFirebaseAdmin();
    const userRef = admin.firestore().collection('users').doc(decoded.uid);
    const snapshot = await userRef.get();
    const storagePath = snapshot.data()?.photoStoragePath;

    if (typeof storagePath === 'string' && storagePath.startsWith(`profile-pictures/${decoded.uid}/`)) {
      await deleteProfilePictureFromR2(storagePath).catch(() => {});
    }

    await admin.auth().updateUser(decoded.uid, { photoURL: null });
    await userRef.set(
      {
        photoUrl: null,
        photoStoragePath: null,
        photoInlineId: null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return res.status(200).json({ ok: true });
  } catch (error) {
    console.error('remove-profile-picture failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Profile picture removal failed.',
    });
  }
};
