'use strict';

// In-process change notifications for Scan Connect streams. Carries only
// "batch X changed"; streams re-read Postgres from their cursor, so a lost or
// duplicated notification cannot lose or duplicate a row. The Oracle API runs
// as one process (server/ecosystem.config.cjs). Scaling out means swapping
// this for Valkey pub/sub with the same interface.

const { EventEmitter } = require('events');

const emitter = new EventEmitter();
emitter.setMaxListeners(0);

function notifyBatch(batchId) {
  if (batchId) emitter.emit(`batch:${batchId}`);
}

function onBatch(batchId, listener) {
  const name = `batch:${batchId}`;
  emitter.on(name, listener);
  return () => emitter.off(name, listener);
}

function listenerCount(batchId) {
  return emitter.listenerCount(`batch:${batchId}`);
}

module.exports = { notifyBatch, onBatch, listenerCount };
