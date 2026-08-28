const assert = require('node:assert/strict');
const test = require('node:test');

const {
  prismaDatabaseUrl,
  prismaPoolConfig,
} = require('./_prisma_client');

test('prismaDatabaseUrl prefers Prisma override, then marketplace primary', () => {
  assert.equal(
    prismaDatabaseUrl({
      PRISMA_DATABASE_URL: 'postgres://prisma.example/db',
      MARKETPLACE_DATABASE_URL: 'postgres://marketplace.example/db',
    }),
    'postgres://prisma.example/db',
  );
  assert.equal(
    prismaDatabaseUrl({
      MARKETPLACE_DATABASE_URL: 'postgres://marketplace.example/db',
    }),
    'postgres://marketplace.example/db',
  );
  assert.equal(
    prismaDatabaseUrl({
      MARKETPLACE_PEER4_DATABASE_URL: 'postgres://peer4.example/db',
    }),
    'postgres://peer4.example/db',
  );
});

test('prismaPoolConfig follows marketplace SSL verification convention', () => {
  const config = prismaPoolConfig({
    MARKETPLACE_DATABASE_URL: 'postgres://marketplace.example/db?sslmode=require',
    MARKETPLACE_DATABASE_POOL_MAX: '4',
    MARKETPLACE_DATABASE_SSL_VERIFY: '0',
  });
  assert.equal(config.connectionString, 'postgres://marketplace.example/db');
  assert.equal(config.max, 4);
  assert.deepEqual(config.ssl, { rejectUnauthorized: false });

  const verified = prismaPoolConfig({
    MARKETPLACE_DATABASE_URL: 'postgres://marketplace.example/db?sslmode=require',
    PRISMA_DATABASE_SSL_VERIFY: '1',
  });
  assert.equal(verified.connectionString, 'postgres://marketplace.example/db?sslmode=require');
  assert.deepEqual(verified.ssl, { rejectUnauthorized: true });
});
