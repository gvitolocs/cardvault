const crypto = require('crypto');
const sharp = require('sharp');
const { getFirebaseAdmin, verifyBearerToken } = require('../server/_firebase');
const { deleteProfilePictureFromR2, uploadProfilePictureToR2 } = require('../server/_r2');

const maxDownloadBytes = 6 * 1024 * 1024;

function isGoogleAvatarUrl(value) {
  try {
    const url = new URL(value);
    return (
      url.protocol === 'https:' &&
      (url.hostname === 'lh3.googleusercontent.com' ||
        url.hostname.endsWith('.googleusercontent.com') ||
        url.hostname === 'googleusercontent.com')
    );
  } catch (_) {
    return false;
  }
}

async function downloadImage(url) {
  const response = await fetch(url, {
    redirect: 'follow',
    headers: {
      accept: 'image/avif,image/webp,image/png,image/jpeg,image/*',
      'user-agent': 'pokoin-google-avatar-cache/1.0',
    },
  });
  if (!response.ok) {
    throw Object.assign(new Error('Google profile picture download failed.'), {
      statusCode: 502,
    });
  }
  const contentLength = Number(response.headers.get('content-length') || 0);
  if (contentLength > maxDownloadBytes) {
    throw Object.assign(new Error('Google profile picture is too large.'), {
      statusCode: 400,
    });
  }
  const buffer = Buffer.from(await response.arrayBuffer());
  if (!buffer.length || buffer.length > maxDownloadBytes) {
    throw Object.assign(new Error('Google profile picture is too large.'), {
      statusCode: 400,
    });
  }
  return buffer;
}

async function assertPublicAvatarUrl(url) {
  const response = await fetch(url, { method: 'GET' });
  if (!response.ok) {
    throw Object.assign(
      new Error(`Cached profile picture is not publicly readable (${response.status}).`),
      { statusCode: 502 },
    );
  }
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const decoded = await verifyBearerToken(req);
    const admin = getFirebaseAdmin();
    const authUser = await admin.auth().getUser(decoded.uid);
    const userRef = admin.firestore().collection('users').doc(decoded.uid);
    const snapshot = await userRef.get();
    const profile = snapshot.data() || {};

    if (
      typeof profile.photoStoragePath === 'string' &&
      profile.photoStoragePath.startsWith(`profile-pictures/${decoded.uid}/`) &&
      profile.photoSource !== 'google'
    ) {
      return res.status(200).json({
        ok: true,
        skipped: 'custom-profile-picture',
        photoUrl: profile.photoUrl || null,
      });
    }

    const sourceUrl =
      authUser.photoURL ||
      decoded.picture ||
      (typeof req.body?.photoUrl === 'string' ? req.body.photoUrl : '');
    if (!sourceUrl || !isGoogleAvatarUrl(sourceUrl)) {
      return res.status(200).json({
        ok: true,
        skipped: 'no-google-profile-picture',
        photoUrl: profile.photoUrl || null,
      });
    }

    const sourceHash = crypto.createHash('sha256').update(sourceUrl).digest('hex').slice(0, 20);
    const storagePath = `profile-pictures/${decoded.uid}/google-${sourceHash}.webp`;
    if (profile.photoSource === 'google' && profile.photoStoragePath === storagePath && profile.photoUrl) {
      return res.status(200).json({ ok: true, cached: true, photoUrl: profile.photoUrl });
    }

    const sourceBuffer = await downloadImage(sourceUrl);
    const avatarBuffer = await sharp(sourceBuffer)
      .rotate()
      .resize(256, 256, { fit: 'cover', position: 'centre' })
      .webp({ quality: 88 })
      .toBuffer();
    const uploaded = await uploadProfilePictureToR2({
      key: storagePath,
      body: avatarBuffer,
    });
    if (!uploaded?.url) {
      return res.status(500).json({
        error:
          'Cloudflare R2 profile picture storage is not configured. Add R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY.',
      });
    }
    await assertPublicAvatarUrl(uploaded.url);

    const previousStoragePath = profile.photoStoragePath;
    if (
      typeof previousStoragePath === 'string' &&
      previousStoragePath.startsWith(`profile-pictures/${decoded.uid}/`) &&
      previousStoragePath !== uploaded.key
    ) {
      await deleteProfilePictureFromR2(previousStoragePath).catch(() => {});
    }

    await userRef.set(
      {
        photoUrl: uploaded.url,
        photoStoragePath: uploaded.key,
        photoInlineId: null,
        photoSource: 'google',
        googlePhotoUrlHash: sourceHash,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return res.status(200).json({ ok: true, photoUrl: uploaded.url });
  } catch (error) {
    console.error('cache-google-profile-picture failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Google profile picture cache failed.',
    });
  }
};
