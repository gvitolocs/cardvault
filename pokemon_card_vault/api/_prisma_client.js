const { PrismaPg } = require('@prisma/adapter-pg');
const { PrismaClient } = require('@prisma/client');
const { config: loadEnv } = require('dotenv');

let prismaClient;
let envLoaded = false;

function loadPrismaEnv() {
  if (envLoaded) return;
  loadEnv({ path: '.env.local', override: false, quiet: true });
  loadEnv({ path: '.env', override: false, quiet: true });
  envLoaded = true;
}

function prismaDatabaseUrl(env = process.env) {
  return env.PRISMA_DATABASE_URL ||
    env.MARKETPLACE_DATABASE_URL ||
    env.MARKETPLACE_PEER4_DATABASE_URL ||
    '';
}

function sanitizeConnectionString(connectionString, sslVerify) {
  if (sslVerify) return connectionString;
  return String(connectionString || '')
    .replace(/([?&])sslmode=[^&]+&?/i, (match, prefix) =>
      prefix === '?' && match.endsWith('&') ? '?' : prefix === '?' ? '' : '')
    .replace(/[?&]$/, '');
}

function prismaPoolConfig(env = process.env) {
  loadPrismaEnv();
  const sslVerify = env.MARKETPLACE_DATABASE_SSL_VERIFY === '1' ||
    env.PRISMA_DATABASE_SSL_VERIFY === '1';
  const connectionString = sanitizeConnectionString(prismaDatabaseUrl(env), sslVerify);
  if (!connectionString) {
    const error = new Error('PRISMA_DATABASE_URL or MARKETPLACE_DATABASE_URL is required for Prisma.');
    error.statusCode = 500;
    throw error;
  }
  return {
    connectionString,
    max: Number(env.PRISMA_DATABASE_POOL_MAX || env.MARKETPLACE_DATABASE_POOL_MAX || 2),
    idleTimeoutMillis: Number(env.PRISMA_DATABASE_IDLE_MS || env.MARKETPLACE_DATABASE_IDLE_MS || 10_000),
    connectionTimeoutMillis: Number(env.PRISMA_DATABASE_CONNECT_MS || env.MARKETPLACE_DATABASE_CONNECT_MS || 8_000),
    application_name: env.PRISMA_DATABASE_APPLICATION_NAME || 'pokoin-prisma',
    ssl: { rejectUnauthorized: sslVerify },
  };
}

function createPrismaClient(options = {}) {
  const adapter = new PrismaPg(prismaPoolConfig(options.env || process.env));
  return new PrismaClient({
    adapter,
    errorFormat: options.errorFormat || 'minimal',
    log: options.log,
  });
}

function getPrismaClient() {
  if (!prismaClient) {
    prismaClient = createPrismaClient();
  }
  return prismaClient;
}

async function disconnectPrismaClient() {
  if (!prismaClient) return;
  await prismaClient.$disconnect();
  prismaClient = null;
}

module.exports = {
  createPrismaClient,
  disconnectPrismaClient,
  getPrismaClient,
  loadPrismaEnv,
  prismaDatabaseUrl,
  prismaPoolConfig,
};
