# Oracle Marketplace Postgres

This directory contains the repeatable schema and migration tooling for moving
marketplace/catalog/search data out of Supabase and into the peer4 Oracle
Postgres instance.

## Environment

Set these locally or in Vercel/CI before running migration commands:

```bash
export SUPABASE_DB_URL='postgresql://...'
export MARKETPLACE_DATABASE_URL='postgresql://pokoin_marketplace:...@peer4-host:5432/pokoin_marketplace?sslmode=require'
```

`SUPABASE_DB_URL` is only used by the copy step. `MARKETPLACE_DATABASE_URL` is
used by migration, verification, and the Vercel marketplace APIs.

## Commands

```bash
node scripts/oracle-marketplace-migrate.js schema
node scripts/oracle-marketplace-migrate.js copy
node scripts/oracle-marketplace-migrate.js refresh
node scripts/oracle-marketplace-migrate.js verify
```

Or run the complete flow:

```bash
node scripts/oracle-marketplace-migrate.js all
```

Forum tables remain in Supabase and are intentionally not included here.
