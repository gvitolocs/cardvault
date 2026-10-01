'use strict';

// Paired phone: heartbeat, printing choice, scan events, leave.
// `Authorization: Scan <token>`. The token cannot read batches, listings or
// account data; `printings` answers only with public catalog printings.

const { getScanStore } = require('./_scan_store');
const { applyCors, phoneToken, queryParam, sendError, sendJson } = require('./_scan_http');

module.exports = async function handler(req, res) {
  if (applyCors(req, res, 'POST, OPTIONS')) return;
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST, OPTIONS');
    return sendJson(res, 405, { error: 'Method not allowed.' });
  }
  try {
    const token = phoneToken(req);
    if (!token) return sendJson(res, 401, { error: 'This scanner is no longer connected.', code: 'session_ended' });
    const store = getScanStore();
    const action = queryParam(req, 'action');
    if (action === 'heartbeat') return sendJson(res, 200, await store.heartbeat({ token }));
    if (action === 'printings') return sendJson(res, 200, await store.resolvePrintingsForPhone({ token, body: req.body || {} }));
    if (action === 'scan') return sendJson(res, 200, await store.ingestScan({ token, body: req.body || {} }));
    if (action === 'leave') return sendJson(res, 200, await store.leave({ token }));
    return sendJson(res, 400, { error: 'Unknown action.' });
  } catch (error) {
    return sendError(res, error, 'scan-phone');
  }
};
