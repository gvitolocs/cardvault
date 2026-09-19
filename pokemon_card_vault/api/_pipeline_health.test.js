'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { apiServiceName, pipelineHealth } = require('./_pipeline_health');

test('api service name defaults to pokoin-oracle-api', () => {
  assert.equal(apiServiceName(), 'pokoin-oracle-api');
});

test('pipeline health reports postgres and sibling pipeline checks', async () => {
  const health = await pipelineHealth();
  assert.equal(health.service, process.env.POKOIN_API_SERVICE_NAME || 'pokoin-oracle-api');
  assert.equal(typeof health.ok, 'boolean');
  assert.equal(typeof health.checks.postgres.ok, 'boolean');
  assert.equal(typeof health.checks.valkey.ok, 'boolean');
  assert.equal(typeof health.checks.meili.ok, 'boolean');
  assert.equal(typeof health.checks.cdn.ok, 'boolean');
  if (!health.ok) {
    assert.ok(
      Object.values(health.checks).some((row) => row.ok === false),
      'failed healthz must name a down check',
    );
  }
});

test('PIPELINE_HEALTH_SKIP ignores optional checks', async () => {
  const previous = process.env.PIPELINE_HEALTH_SKIP;
  process.env.PIPELINE_HEALTH_SKIP = 'valkey,meili,cdn';
  try {
    const health = await pipelineHealth();
    assert.equal(health.ok, health.checks.postgres.ok);
  } finally {
    if (previous == null) delete process.env.PIPELINE_HEALTH_SKIP;
    else process.env.PIPELINE_HEALTH_SKIP = previous;
  }
});

test('POKOIN_API_SERVICE_NAME labels cardtrader-oracle-api', () => {
  const previous = process.env.POKOIN_API_SERVICE_NAME;
  process.env.POKOIN_API_SERVICE_NAME = 'cardtrader-oracle-api';
  try {
    assert.equal(apiServiceName(), 'cardtrader-oracle-api');
  } finally {
    if (previous == null) delete process.env.POKOIN_API_SERVICE_NAME;
    else process.env.POKOIN_API_SERVICE_NAME = previous;
  }
});
