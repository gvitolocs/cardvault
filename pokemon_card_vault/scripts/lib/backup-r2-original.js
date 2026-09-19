'use strict';

const { CopyObjectCommand, HeadObjectCommand } = require('@aws-sdk/client-s3');

function originalsKeyFor(key) {
  const clean = String(key || '').replace(/^\/+/, '');
  if (!clean || clean.startsWith('originals/')) {
    return null;
  }
  return `originals/${clean}`;
}

/** Same leftover prefix and folder; extension becomes .png. Live JPEG/WebP stays. */
function siblingPngKey(key) {
  const clean = String(key || '').replace(/^\/+/, '');
  if (!clean || clean.startsWith('originals/')) {
    return null;
  }
  const lastSlash = clean.lastIndexOf('/');
  const dir = lastSlash >= 0 ? clean.slice(0, lastSlash + 1) : '';
  const base = lastSlash >= 0 ? clean.slice(lastSlash + 1) : clean;
  const dot = base.lastIndexOf('.');
  if (dot <= 0) {
    return `${dir}${base}.png`;
  }
  return `${dir}${base.slice(0, dot)}.png`;
}

function copySource(bucket, key) {
  return `${bucket}/${String(key)
    .replace(/^\/+/, '')
    .split('/')
    .map((part) => encodeURIComponent(part))
    .join('/')}`;
}

function isNotFound(error) {
  const status = error?.$metadata?.httpStatusCode;
  return (
    status === 404 ||
    error?.name === 'NotFound' ||
    error?.name === 'NoSuchKey' ||
    error?.Code === 'NotFound' ||
    error?.Code === 'NoSuchKey'
  );
}

async function headExists(client, bucket, key) {
  try {
    await client.send(new HeadObjectCommand({ Bucket: bucket, Key: key }));
    return true;
  } catch (error) {
    if (isNotFound(error)) {
      return false;
    }
    throw error;
  }
}

/**
 * Copy a live R2 object to originals/{key} once. Never overwrites an existing
 * backup. Never deletes the live key. Default on; set
 * ORACLE_IMAGE_BACKUP_ORIGINALS=0 to skip.
 */
async function backupExistingObject(client, { bucket, key, env = process.env }) {
  if (String(env.ORACLE_IMAGE_BACKUP_ORIGINALS || '1') === '0') {
    return { backedUp: false, reason: 'disabled' };
  }
  const sourceKey = String(key || '').replace(/^\/+/, '');
  const destKey = originalsKeyFor(sourceKey);
  if (!destKey) {
    return { backedUp: false, reason: 'skip' };
  }
  const exists = await headExists(client, bucket, sourceKey);
  if (!exists) {
    return { backedUp: false, reason: 'missing' };
  }
  const already = await headExists(client, bucket, destKey);
  if (already) {
    return { backedUp: false, reason: 'already-backed-up', originalsKey: destKey };
  }
  await client.send(
    new CopyObjectCommand({
      Bucket: bucket,
      CopySource: copySource(bucket, sourceKey),
      Key: destKey,
    }),
  );
  return { backedUp: true, originalsKey: destKey };
}

module.exports = {
  originalsKeyFor,
  siblingPngKey,
  copySource,
  isNotFound,
  backupExistingObject,
};
