const marketplaceDb = require('./_marketplace_db');
const { requestHeader, verifyBearerToken } = require('./_firebase');
const {
  recordCartChange,
} = require('./_marketplace_cart_analytics');

async function optionalUserUid(req) {
  const header = requestHeader(req, 'authorization');
  if (!String(header).startsWith('Bearer ')) {
    return '';
  }
  try {
    const decoded = await verifyBearerToken(req);
    return typeof decoded.uid === 'string' ? decoded.uid : '';
  } catch (error) {
    console.warn('marketplace-cart auth ignored', {
      message: error.message,
      code: error.code,
      statusCode: error.statusCode,
    });
    return '';
  }
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const userUid = await optionalUserUid(req);
    const result = await recordCartChange({
      query: marketplaceDb.marketplaceQuery,
      cardId: req.body?.cardId ?? req.body?.blueprintId,
      action: req.body?.action,
      userUid,
      anonymousId: req.body?.anonymousId ?? req.body?.sessionId,
    });
    return res.status(200).json(result);
  } catch (error) {
    if (error.statusCode === 400) {
      return res.status(400).json({ error: error.message });
    }
    console.warn('marketplace-cart failed', error);
    return res.status(204).end();
  }
};
