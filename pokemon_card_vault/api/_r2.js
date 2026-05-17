const { DeleteObjectCommand, PutObjectCommand, S3Client } = require('@aws-sdk/client-s3');

function getR2Config() {
  const accountId = process.env.CLOUDFLARE_ACCOUNT_ID;
  const accessKeyId = process.env.R2_ACCESS_KEY_ID;
  const secretAccessKey = process.env.R2_SECRET_ACCESS_KEY;
  const bucket = process.env.R2_PROFILE_PICTURES_BUCKET || 'pokoin-profile-pictures';
  const publicBaseUrl = process.env.R2_PROFILE_PICTURES_PUBLIC_URL;

  if (!accountId || !accessKeyId || !secretAccessKey || !bucket || !publicBaseUrl) {
    return null;
  }

  return {
    accountId,
    accessKeyId,
    secretAccessKey,
    bucket,
    publicBaseUrl: publicBaseUrl.replace(/\/+$/, ''),
  };
}

function getR2Client(config) {
  return new S3Client({
    region: 'auto',
    endpoint: `https://${config.accountId}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: config.accessKeyId,
      secretAccessKey: config.secretAccessKey,
    },
  });
}

function publicUrlForKey(config, key) {
  return `${config.publicBaseUrl}/${key.split('/').map(encodeURIComponent).join('/')}`;
}

async function uploadProfilePictureToR2({ key, body }) {
  const config = getR2Config();
  if (!config) {
    return null;
  }

  const client = getR2Client(config);
  await client.send(
    new PutObjectCommand({
      Bucket: config.bucket,
      Key: key,
      Body: body,
      ContentType: 'image/webp',
      CacheControl: 'public, max-age=31536000, immutable',
    }),
  );

  return {
    key,
    url: publicUrlForKey(config, key),
  };
}

async function deleteProfilePictureFromR2(key) {
  const config = getR2Config();
  if (!config || typeof key !== 'string' || !key.startsWith('profile-pictures/')) {
    return;
  }

  const client = getR2Client(config);
  await client.send(
    new DeleteObjectCommand({
      Bucket: config.bucket,
      Key: key,
    }),
  );
}

module.exports = {
  deleteProfilePictureFromR2,
  uploadProfilePictureToR2,
};
