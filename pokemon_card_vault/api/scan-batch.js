'use strict';

// Desktop Scan Batch: snapshot, Batch Defaults, row edits, submit to
// inventory. Firebase bearer. Spec: pokoin-web docs/SCAN_LISTING_WORKFLOW.md.

const { getScanStore } = require('./_scan_store');
const { applyCors, queryParam, sendError, sendJson, verifyDesktop } = require('./_scan_http');

function sellerNameOf(decoded) {
  return decoded.name || (decoded.email ? String(decoded.email).split('@')[0] : '') || 'Pokoin seller';
}

module.exports = async function handler(req, res) {
  if (applyCors(req, res)) return;
  try {
    const decoded = await verifyDesktop(req);
    const store = getScanStore();
    const sellerUid = decoded.uid;
    const action = queryParam(req, 'action');

    if (req.method === 'GET') {
      if (action === 'image') {
        const image = await store.readImage({ sellerUid, itemId: queryParam(req, 'itemId') });
        res.statusCode = 200;
        res.setHeader('Content-Type', 'image/jpeg');
        res.setHeader('Cache-Control', 'private, max-age=86400, immutable');
        return res.end(image);
      }
      if (queryParam(req, 'list') === 'open') {
        return sendJson(res, 200, await store.listOpenBatches({ sellerUid }));
      }
      return sendJson(res, 200, await store.readBatchSnapshot({ sellerUid, batchId: queryParam(req, 'batchId') }));
    }
    if (req.method !== 'POST') {
      res.setHeader('Allow', 'GET, POST, OPTIONS');
      return sendJson(res, 405, { error: 'Method not allowed.' });
    }
    const body = req.body || {};
    switch (action) {
      case 'defaults':
        return sendJson(res, 200, await store.setDefaults({ sellerUid, batchId: body.batchId, defaults: body.defaults }));
      case 'item':
        return sendJson(res, 200, await store.patchItem({ sellerUid, itemId: body.itemId, patch: body.patch }));
      case 'add':
        return sendJson(res, 200, await store.addManual({ sellerUid, batchId: body.batchId, body }));
      case 'remove':
        return sendJson(res, 200, await store.removeItem({ sellerUid, itemId: body.itemId }));
      case 'restore':
        return sendJson(res, 200, await store.restoreItem({ sellerUid, itemId: body.itemId }));
      case 'duplicate':
        return sendJson(res, 200, await store.duplicateItem({ sellerUid, itemId: body.itemId }));
      case 'unmerge':
        return sendJson(res, 200, await store.unmergeItem({ sellerUid, itemId: body.itemId }));
      case 'submit':
        return sendJson(res, 200, await store.submitBatch({
          sellerUid,
          batchId: body.batchId,
          submitKey: body.submitKey,
          intent: body.intent,
          sellerName: sellerNameOf(decoded),
        }));
      case 'discard':
        return sendJson(res, 200, await store.discardBatch({ sellerUid, batchId: body.batchId }));
      default:
        return sendJson(res, 400, { error: 'Unknown action.' });
    }
  } catch (error) {
    return sendError(res, error, 'scan-batch');
  }
};
