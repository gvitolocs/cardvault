const crypto = require('crypto');

function secretKey() {
  const secret = process.env.SIGNUP_ENCRYPTION_SECRET ||
    process.env.FIREBASE_PRIVATE_KEY ||
    process.env.RESEND_API_KEY ||
    '';
  if (!secret) {
    throw Object.assign(new Error('Pending signup encryption secret is missing.'), {
      statusCode: 500,
    });
  }
  return crypto.createHash('sha256').update(secret).digest();
}

function hashValue(value) {
  return crypto.createHash('sha256').update(String(value || '')).digest('hex');
}

function newSignupToken() {
  return crypto.randomBytes(32).toString('base64url');
}

function encryptPassword(password) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', secretKey(), iv);
  const encrypted = Buffer.concat([
    cipher.update(String(password || ''), 'utf8'),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  return [
    iv.toString('base64url'),
    tag.toString('base64url'),
    encrypted.toString('base64url'),
  ].join('.');
}

function decryptPassword(payload) {
  const [ivRaw, tagRaw, encryptedRaw] = String(payload || '').split('.');
  if (!ivRaw || !tagRaw || !encryptedRaw) {
    throw Object.assign(new Error('Pending signup payload is invalid.'), {
      statusCode: 400,
    });
  }
  const decipher = crypto.createDecipheriv(
    'aes-256-gcm',
    secretKey(),
    Buffer.from(ivRaw, 'base64url'),
  );
  decipher.setAuthTag(Buffer.from(tagRaw, 'base64url'));
  return Buffer.concat([
    decipher.update(Buffer.from(encryptedRaw, 'base64url')),
    decipher.final(),
  ]).toString('utf8');
}

module.exports = {
  decryptPassword,
  encryptPassword,
  hashValue,
  newSignupToken,
};
