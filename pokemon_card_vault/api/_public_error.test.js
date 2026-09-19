'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  WORKING_MESSAGE,
  isPipelineFailure,
  publicErrorBody,
  publicErrorStatus,
  sanitizePublicJson,
} = require('./_public_error');

test('pipeline failures become 503 working copy, not host:port', () => {
  assert.equal(isPipelineFailure('connect ECONNREFUSED 127.0.0.1:5432'), true);
  assert.deepEqual(
    publicErrorBody(new Error('connect ECONNREFUSED 127.0.0.1:5432')),
    { error: WORKING_MESSAGE },
  );
  assert.equal(publicErrorStatus(new Error('connect ECONNREFUSED 127.0.0.1:5432')), 503);
  assert.deepEqual(
    sanitizePublicJson(500, { error: 'connect ECONNREFUSED 127.0.0.1:5432' }),
    { statusCode: 503, payload: { error: WORKING_MESSAGE } },
  );
  assert.equal(isPipelineFailure('Card not found'), false);
  assert.deepEqual(
    sanitizePublicJson(404, { error: 'Card not found' }),
    { statusCode: 404, payload: { error: 'Card not found' } },
  );
});

test('healthz keeps check names and strips localhost from check errors', () => {
  const out = sanitizePublicJson(503, {
    ok: false,
    service: 'pokoin-oracle-api',
    checks: { postgres: { ok: false, error: 'connect ECONNREFUSED 127.0.0.1:5432' } },
  });
  assert.equal(out.statusCode, 503);
  assert.equal(out.payload.ok, false);
  assert.equal(out.payload.checks.postgres.error, 'econnrefused');
});
