# Prisma Oracle Workflow

Use this workflow when adding or refreshing Prisma access to the Pokoin Oracle
Postgres marketplace database.

## Purpose

- Prisma is a secondary access layer for future migrations and easier database
  switching.
- Existing production APIs still use the established `pg` helpers in
  `api/_marketplace_db.js` unless a route is intentionally migrated.
- Prisma points at the same Oracle Postgres primary as the API:
  `MARKETPLACE_DATABASE_URL`.
- `PRISMA_DATABASE_URL` is an optional override for local experiments or future
  cutovers. Leave it blank for normal Oracle primary access.

## Secrets

- Store database URLs only in `.env.local`, Vercel/peer env, or the documented
  local operator env files.
- Do not commit `.env`, `.env.local`, peer env files, or copied connection
  strings.
- Prisma CLI loads `.env.local` through `prisma.config.ts`.

## Commands

From `pokemon_card_vault/`:

```bash
npm run prisma:validate
npm run prisma:sync
npm run prisma:smoke
```

Useful individual commands:

```bash
npm run prisma:pull      # introspect Oracle into prisma/schema.prisma
npm run prisma:generate  # regenerate @prisma/client
npm run prisma:studio    # inspect data locally, never mutate production casually
```

`npm run prisma:smoke` performs a read-only connection check and reports the
current database, schema, and public table count without printing secrets.

## Runtime Usage

Prisma 7 requires a driver adapter at runtime. Do not use a bare
`new PrismaClient()`. Use the local wrapper:

```js
const { getPrismaClient } = require('./_prisma_client');

const prisma = getPrismaClient();
const rows = await prisma.$queryRaw`select now()`;
```

For one-off scripts:

```js
const { createPrismaClient } = require('../api/_prisma_client');

const prisma = createPrismaClient();
try {
  const rows = await prisma.$queryRaw`select current_database()`;
  console.log(rows);
} finally {
  await prisma.$disconnect();
}
```

## Introspection Notes

The initial `prisma db pull` introspected 81 public models from
`pokoin_marketplace`.

Expected Prisma/Postgres limitations after pull:

- Check constraints are documented as comments in `schema.prisma`; Prisma Client
  does not enforce them.
- Expression indexes are not fully represented by Prisma.
- Some indexes use non-default `NULLS FIRST`/`NULLS LAST` ordering.
- Database comments are not fully represented.

Keep SQL migrations under `oracle-postgres/schema/` as the source of truth for
database DDL. Treat Prisma introspection as a generated view over the live schema
unless the project explicitly moves a table/migration workflow to Prisma.

## Migration Rule

Do not run `prisma migrate dev`, `prisma migrate deploy`, or Prisma Studio
writes against production Oracle unless the migration plan has been reviewed.
The current canonical migration path remains SQL under `oracle-postgres/schema/`
plus `npm run api:migrations:check`.
