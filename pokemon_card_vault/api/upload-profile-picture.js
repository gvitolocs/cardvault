const crypto = require('crypto');
const sharp = require('sharp');
const { getFirebaseAdmin, verifyBearerToken } = require('./_firebase');

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
    const token = crypto.randomUUID();
    const bucket = admin.storage().bucket();
    const filePath = `profile-pictures/${decoded.uid}/avatar-256.webp`;
    const file = bucket.file(filePath);

    await file.save(avatarBuffer, {
      resumable: false,
      metadata: {
        contentType: 'image/webp',
        cacheControl: 'public, max-age=31536000, immutable',
        metadata: {
          firebaseStorageDownloadTokens: token,
        },
      },
    });

    const encodedPath = encodeURIComponent(filePath);
    const photoUrl = `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encodedPath}?alt=media&token=${token}`;
    await admin.auth().updateUser(decoded.uid, { photoURL: photoUrl });
    await admin.firestore().collection('users').doc(decoded.uid).set(
      {
        photoUrl,
        photoStoragePath: filePath,
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
