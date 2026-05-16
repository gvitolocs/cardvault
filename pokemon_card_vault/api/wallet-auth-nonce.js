const crypto = require('crypto');
const { getFirebaseAdmin } = require('./_firebase');

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const { address } = req.body || {};
    const normalized = String(address || '').trim().toLowerCase();
    if (!/^0x[a-f0-9]{40}$/.test(normalized)) {
      return res.status(400).json({ error: 'Enter a valid wallet address.' });
    }

    const admin = getFirebaseAdmin();
    const nonce = crypto.randomBytes(16).toString('hex');
    const issuedAt = new Date().toISOString();
    const message = [
      'Sign in to Pokoin',
      '',
      `Wallet: ${normalized}`,
      `Nonce: ${nonce}`,
      `Issued At: ${issuedAt}`,
      'Domain: pokoin.com',
    ].join('\n');

    await admin.firestore().collection('wallet_auth_nonces').doc(normalized).set({
      address: normalized,
      nonce,
      message,
      issuedAt,
      used: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return res.status(200).json({ address: normalized, message });
  } catch (error) {
    console.error('wallet-auth-nonce failed', error);
    return res.status(500).json({ error: error.message || 'Wallet nonce failed.' });
  }
};
