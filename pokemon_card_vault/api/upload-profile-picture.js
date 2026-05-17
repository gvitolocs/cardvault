const crypto = require('crypto');
const sharp = require('sharp');
const { getFirebaseAdmin, verifyBearerToken } = require('../server/_firebase');
const { deleteProfilePictureFromR2, uploadProfilePictureToR2 } = require('../server/_r2');

const maxUploadBytes = 6 * 1024 * 1024;

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const decoded = await verifyBearerToken(req);
    const { imageBase64 } = req.body || {};
    if (typeof imageBase64 !== 'string' || imageBase64.trim().isEmpty) {
      return res.status(400).json({ error: 'Missing image data.' });
    }

    const rawBase64 = imageBase64.replace(/^data:image\/\w+;base64,/, '');
    const sourceBuffer = Buffer.from(rawBase64, 'base64');
    if (!sourceBuffer.length || sourceBuffer.length > maxUploadBytes) {
      return res.status(400).json({ error: 'Image must be smaller than 6 MB.' });
    }

    const avatarBuffer = await sharp(sourceBuffer)
      .rotate()
      .resize(256, 256, { fit: 'cover', position: 'centre' })
      .webp({ quality: 88 })
      .toBuffer();

    const admin = getFirebaseAdmin();
    const avatarId = crypto.randomUUID();
    const userRef = admin.firestore().collection('users').doc(decoded.uid);
    const existingProfile = await userRef.get();
    const previousStoragePath = existingProfile.data()?.photoStoragePath;
    const storagePath = `profile-pictures/${decoded.uid}/${avatarId}.webp`;
    const uploaded = await uploadProfilePictureToR2({
      key: storagePath,
      body: avatarBuffer,
    });
    const photoUrl = uploaded?.url || `data:image/webp;base64,${avatarBuffer.toString('base64')}`;

    if (uploaded && typeof previousStoragePath === 'string' && previousStoragePath !== storagePath) {
      await deleteProfilePictureFromR2(previousStoragePath).catch(() => {});
    }

    await admin.auth().updateUser(decoded.uid, { photoURL: photoUrl });
    await userRef.set(
      {
        photoUrl,
        photoStoragePath: uploaded?.key || null,
        photoInlineId: uploaded ? null : avatarId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return res.status(200).json({ photoUrl });
  } catch (error) {
    console.error('upload-profile-picture failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Profile picture upload failed.',
    });
  }
};
