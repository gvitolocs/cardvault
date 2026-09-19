'use strict';

// Desktop Scan Session: start/resume, pairing code, disconnect phone, pause,
// end. Firebase bearer. Spec: pokoin-web docs/SCAN_CONNECT.md.

const { getScanStore } = require('./_scan_store');
const { applyCors, sendError, sendJson, queryParam, verifyDesktop } = require('./_scan_http');

module.exports = async function handler(req, res) {
  if (applyCors(req, res)) return;
  try {
    const decoded = await verifyDesktop(req);
    const store = getScanStore();
    const sellerUid = decoded.uid;
    if (req.method === 'GET') {
      return sendJson(res, 200, await store.getSession({ sellerUid, sessionId: queryParam(req, 'sessionId') }));
    }
    if (req.method !== 'POST') {
      res.setHeader('Allow', 'GET, POST, OPTIONS');
      return sendJson(res, 405, { error: 'Method not allowed.' });
    }
    const body = req.body || {};
    const action = queryParam(req, 'action');
    if (action === 'start') {
      return sendJson(res, 200, await store.startSession({ sellerUid, batchId: body.batchId || '' }));
    }
    if (action === 'pairing') {
      return sendJson(res, 200, await store.regeneratePairing({ sellerUid, sessionId: body.sessionId }));
    }
    if (['disconnect', 'pause', 'end'].includes(action)) {
      return sendJson(res, 200, await store.updateSession({
        sellerUid,
        sessionId: body.sessionId,
        action,
        reason: body.reason,
        paused: body.paused,
      }));
    }
    return sendJson(res, 400, { error: 'Unknown action.' });
  } catch (error) {
    return sendError(res, error, 'scan-session');
  }
};
