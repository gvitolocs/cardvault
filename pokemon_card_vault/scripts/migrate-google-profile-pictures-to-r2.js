#!/usr/bin/env node

const crypto = require('crypto');
const path = require('path');
const sharp = require('sharp');

const { getFirebaseAdmin } = require('../api/_firebase');
const { uploadProfilePictureToR2 } = require('../api/_r2');

const maxDownloadBytes = 6 * 1024 * 1024;
const write = process.argv.includes('--write');
const limitArg = process.argv.find((arg) => arg.startsWith('--limit='));
const limit = limitArg ? Number(limitArg.split('=')[1]) : Infinity;

function loadEnvFile(filePath) {
  const fs = require('fs');
  if (!fs.existsSync(filePath)) {
    return;
  }
  for (const line of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) {
      continue;
    }
    const [rawKey, ...rawValueParts] = trimmed.split('=');
    const key = rawKey.replace(/^export\s+/, '').trim();
    if (process.env[key]) {
      continue;
    }
    const value = rawValueParts
      .join('=')
      .trim()
      .replace(/^['"]|['"]$/g, '');
    process.env[key] = value;
  }
}

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

function isR2ProfilePath(profile, uid) {
  return (
    typeof profile.photoStoragePath === 'string' &&
    profile.photoStoragePath.startsWith(`profile-pictures/${uid}/`) &&
    typeof profile.photoUrl === 'string' &&
    profile.photoUrl.trim().length > 0
  );
}

async function downloadImage(url) {
  const response = await fetch(url, {
    redirect: 'follow',
    headers: {
      accept: 'image/avif,image/webp,image/png,image/jpeg,image/*',
      'user-agent': 'pokoin-google-avatar-r2-migration/1.0',
    },
  });
  if (!response.ok) {
    throw new Error(`download failed ${response.status}`);
  }
  const contentLength = Number(response.headers.get('content-length') || 0);
  if (contentLength > maxDownloadBytes) {
    throw new Error('image too large');
  }
  const buffer = Buffer.from(await response.arrayBuffer());
  if (!buffer.length || buffer.length > maxDownloadBytes) {
    throw new Error('image too large');
  }
  return buffer;
}

async function assertPublicAvatarUrl(url) {
  const response = await fetch(url, { method: 'GET' });
  if (!response.ok) {
    throw new Error(`uploaded avatar is not publicly readable (${response.status})`);
  }
}

async function migrateUser({ admin, authUser, profile }) {
  const uid = authUser.uid;
  if (isR2ProfilePath(profile, uid)) {
    return { status: 'already-r2' };
  }

  const sourceUrl = authUser.photoURL || profile.photoUrl || '';
  if (!isGoogleAvatarUrl(sourceUrl)) {
    return { status: 'skipped-no-google-photo' };
  }

  const sourceHash = crypto.createHash('sha256').update(sourceUrl).digest('hex').slice(0, 20);
  const storagePath = `profile-pictures/${uid}/google-${sourceHash}.webp`;

  if (!write) {
    return { status: 'would-migrate', storagePath };
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
    throw new Error('R2 profile picture storage is not configured.');
  }
  await assertPublicAvatarUrl(uploaded.url);

  await admin.firestore().collection('users').doc(uid).set(
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

  return { status: 'migrated', storagePath: uploaded.key };
}

async function main() {
  loadEnvFile(path.resolve(__dirname, '../.env.local'));
  const admin = getFirebaseAdmin();
  const usersCollection = admin.firestore().collection('users');

  const counts = {
    scanned: 0,
    migrated: 0,
    wouldMigrate: 0,
    alreadyR2: 0,
    skipped: 0,
    failed: 0,
  };

  let pageToken;
  do {
    const page = await admin.auth().listUsers(1000, pageToken);
    for (const authUser of page.users) {
      if (counts.scanned >= limit) {
        pageToken = undefined;
        break;
      }
      counts.scanned += 1;
      const profileSnapshot = await usersCollection.doc(authUser.uid).get();
      const profile = profileSnapshot.exists ? profileSnapshot.data() || {} : {};
      try {
        const result = await migrateUser({ admin, authUser, profile });
        if (result.status === 'migrated') {
          counts.migrated += 1;
          console.log(`migrated ${authUser.uid} -> ${result.storagePath}`);
        } else if (result.status === 'would-migrate') {
          counts.wouldMigrate += 1;
          console.log(`would migrate ${authUser.uid} -> ${result.storagePath}`);
        } else if (result.status === 'already-r2') {
          counts.alreadyR2 += 1;
        } else {
          counts.skipped += 1;
        }
      } catch (error) {
        counts.failed += 1;
        console.warn(`failed ${authUser.uid}: ${error.message}`);
      }
    }
    pageToken = page.pageToken;
  } while (pageToken);

  console.log(JSON.stringify({ mode: write ? 'write' : 'dry-run', counts }, null, 2));
  if (!write && counts.wouldMigrate > 0) {
    console.log('Run with --write to upload avatars to R2 and update Firestore.');
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
