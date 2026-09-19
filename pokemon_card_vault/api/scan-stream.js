'use strict';

// Desktop change stream for one Scan Batch: `text/event-stream` frames, replay
// from `after` (the batch cursor), closed by the server after 55 s so every
// proxy sees short requests and the client resumes from its cursor.
// The Oracle API awaits this handler and then calls res.end(), so the promise
// resolves only when the stream is over. Spec: pokoin-web docs/SCAN_CONNECT.md.

const { getScanStore } = require('./_scan_store');
const { onBatch } = require('./_scan_bus');
const rules = require('./_scan_connect');
const { applyCors, queryParam, sendError, verifyDesktop } = require('./_scan_http');

const STREAM_MS = Number(process.env.SCAN_STREAM_MS || 55_000);
const PING_MS = 15_000;
const PRESENCE_MS = 5_000;
const PAGE = 500;

function frame(event, data, id) {
  return `event: ${event}\n${id != null ? `id: ${id}\n` : ''}data: ${JSON.stringify(data)}\n\n`;
}

function sessionSignature(session) {
  return session ? `${session.id}:${session.version}:${session.phase}:${session.phoneLastSeenAt}` : 'none';
}

module.exports = async function handler(req, res) {
  if (applyCors(req, res, 'GET, OPTIONS')) return;
  let decoded;
  let batchRow;
  const store = getScanStore();
  try {
    decoded = await verifyDesktop(req);
    batchRow = await store.batchForStream({ sellerUid: decoded.uid, batchId: queryParam(req, 'batchId') });
  } catch (error) {
    return sendError(res, error, 'scan-stream');
  }

  const batchId = batchRow.id;
  let cursor = Math.max(0, Number.parseInt(queryParam(req, 'after') || '0', 10) || 0);
  let batchSig = `${batchRow.status}:${batchRow.defaults_version}`;
  let sessionSig = '';
  let closed = false;
  let running = false;
  let dirty = false;

  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/event-stream; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store, no-transform');
  res.setHeader('X-Accel-Buffering', 'no');
  res.setHeader('Connection', 'keep-alive');
  if (typeof res.flushHeaders === 'function') res.flushHeaders();

  const write = (text) => {
    if (!closed && !res.writableEnded) res.write(text);
  };

  const session = await store.latestSession(batchId).catch(() => null);
  sessionSig = sessionSignature(session);
  write(`retry: 1000\n${frame('hello', {
    serverTime: Date.now(),
    batch: rules.batchView(batchRow),
    session,
    cursor,
  })}`);

  async function pump() {
    if (closed) return;
    if (running) {
      dirty = true;
      return;
    }
    running = true;
    try {
      do {
        dirty = false;
        let items;
        do {
          items = await store.itemsAfter(batchId, cursor, PAGE);
          if (closed) return;
          if (items.length) {
            cursor = items[items.length - 1].seq;
            write(frame('items', { items, cursor }, cursor));
          }
        } while (items.length === PAGE);
        const fresh = await store.batchForStream({ sellerUid: decoded.uid, batchId });
        const nextBatchSig = `${fresh.status}:${fresh.defaults_version}`;
        if (nextBatchSig !== batchSig) {
          batchSig = nextBatchSig;
          write(frame('batch', { batch: rules.batchView(fresh) }));
        }
        const current = await store.latestSession(batchId);
        const nextSessionSig = sessionSignature(current);
        if (nextSessionSig !== sessionSig) {
          sessionSig = nextSessionSig;
          write(frame('session', { session: current, serverTime: Date.now() }));
        }
      } while (dirty && !closed);
    } catch (error) {
      console.error('scan-stream pump failed', { message: error.message });
      finish();
    } finally {
      running = false;
    }
  }

  let resolveDone;
  const done = new Promise((resolve) => {
    resolveDone = resolve;
  });
  const unsubscribe = onBatch(batchId, () => {
    pump();
  });
  const presence = setInterval(pump, PRESENCE_MS);
  const ping = setInterval(() => write(': ping\n\n'), PING_MS);
  const lifetime = setTimeout(() => {
    write(frame('bye', { cursor, reconnect: true }));
    finish();
  }, STREAM_MS);

  function finish() {
    if (closed) return;
    closed = true;
    unsubscribe();
    clearInterval(presence);
    clearInterval(ping);
    clearTimeout(lifetime);
    if (!res.writableEnded) res.end();
    resolveDone();
  }

  req.on('close', finish);
  res.on('close', finish);
  pump();
  await done;
};

module.exports._test = { frame, sessionSignature };
