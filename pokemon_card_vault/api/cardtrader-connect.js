const { getFirebaseAdmin, verifyBearerToken } = require('./_firebase');
const { parseEncryptionKey } = require('./_cardtrader_crypto');
const { validateCardTraderToken } = require('./_cardtrader_client');
const {
  disconnectIntegration,
  readIntegrationDoc,
  safeStatusFromDoc,
  storeConnectedIntegration,
} = require('./_cardtrader_integration');

function setNoStore(res) {
  res.setHeader('Cache-Control', 'no-store');
}

async function connect(req, decoded, admin, firestore) {
  const token = String(req.body?.token || '').trim();
  parseEncryptionKey();
  const info = await validateCardTraderToken(token);
  await storeConnectedIntegration({
    admin,
    firestore,
    uid: decoded.uid,
    email: decoded.email || '',
    token,
    info,
  });
  const doc = await readIntegrationDoc(firestore, decoded.uid);
  return safeStatusFromDoc(doc);
}

module.exports = async function handler(req, res) {
  setNoStore(res);
  try {
    const decoded = await verifyBearerToken(req);
    const admin = getFirebaseAdmin();
    const firestore = admin.firestore();

    if (req.method === 'POST') {
      const status = await connect(req, decoded, admin, firestore);
      return res.status(200).json({ ok: true, status });
    }

    if (req.method === 'DELETE') {
      await disconnectIntegration({ admin, firestore, uid: decoded.uid });
      const doc = await readIntegrationDoc(firestore, decoded.uid);
      return res.status(200).json({ ok: true, status: safeStatusFromDoc(doc) });
    }

    res.setHeader('Allow', 'POST, DELETE');
    return res.status(405).json({ error: 'Method not allowed.' });
  } catch (error) {
    console.error('cardtrader-connect failed', {
      code: error.code || '',
      statusCode: error.statusCode || 500,
      message: error.message,
    });
    return res.status(error.statusCode || 500).json({
      error: error.message || 'CardTrader connection failed.',
      code: error.code,
    });
  }
};

module.exports._test = { connect };
