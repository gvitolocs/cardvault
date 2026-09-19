'use strict';

// Phone claims a 4-digit pairing code (or QR secret). Public endpoint:
// rate limited in Postgres, identical answer for wrong / expired / used
// codes, returns a session-scoped phone token and no account data.

const { getScanStore } = require('./_scan_store');
const { applyCors, clientIp, header, sendError, sendJson } = require('./_scan_http');

module.exports = async function handler(req, res) {
  if (applyCors(req, res, 'POST, OPTIONS')) return;
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST, OPTIONS');
    return sendJson(res, 405, { error: 'Method not allowed.' });
  }
  try {
    const body = req.body || {};
    const result = await getScanStore().claimPairing({
      pin: typeof body.pin === 'string' ? body.pin : '',
      qr: typeof body.qr === 'string' ? body.qr : '',
      device: typeof body.device === 'string' ? body.device : '',
      ip: clientIp(req),
      userAgent: header(req, 'user-agent'),
    });
    return sendJson(res, 200, result);
  } catch (error) {
    return sendError(res, error, 'scan-pair');
  }
};
