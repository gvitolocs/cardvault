#!/usr/bin/env node

const {
  createPrismaClient,
  loadPrismaEnv,
  prismaDatabaseUrl,
} = require('../api/_prisma_client');

async function main() {
  loadPrismaEnv();
  if (!prismaDatabaseUrl()) {
    throw new Error('PRISMA_DATABASE_URL or MARKETPLACE_DATABASE_URL is required.');
  }
  const prisma = createPrismaClient();
  try {
    const [databaseInfo] = await prisma.$queryRaw`
      select
        current_database() as database_name,
        current_schema() as schema_name
    `;
    const [tableInfo] = await prisma.$queryRaw`
      select count(*)::integer as table_count
      from information_schema.tables
      where table_schema = 'public'
        and table_type = 'BASE TABLE'
    `;
    console.log(JSON.stringify({
      ok: true,
      database: databaseInfo.database_name,
      schema: databaseInfo.schema_name,
      publicTables: tableInfo.table_count,
    }));
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
