const { Pool } = require('pg');

let pool;

function marketplaceDatabaseUrl() {
  return process.env.MARKETPLACE_DATABASE_URL || '';
}

function getMarketplacePool() {
  const connectionString = marketplaceDatabaseUrl();
  if (!connectionString) {
    const error = new Error('MARKETPLACE_DATABASE_URL is not configured.');
    error.statusCode = 500;
    throw error;
  }
  if (!pool) {
    pool = new Pool({
      connectionString,
      max: Number(process.env.MARKETPLACE_DATABASE_POOL_MAX || 2),
      idleTimeoutMillis: Number(process.env.MARKETPLACE_DATABASE_IDLE_MS || 10_000),
      connectionTimeoutMillis: Number(process.env.MARKETPLACE_DATABASE_CONNECT_MS || 8_000),
      ssl: { rejectUnauthorized: process.env.MARKETPLACE_DATABASE_SSL_VERIFY === '1' },
    });
    pool.on('connect', (client) => {
      client.query('set jit = off').catch((error) => {
        console.error('Failed to disable marketplace database JIT', error);
      });
    });
  }
  return pool;
}

async function marketplaceQuery(text, values = []) {
  return getMarketplacePool().query(text, values);
}

module.exports = {
  getMarketplacePool,
  marketplaceDatabaseUrl,
  marketplaceQuery,
};
