// Prisma is pointed at the same Oracle Postgres primary used by the API.
// Keep secrets in .env.local / server env; do not commit database URLs.
import { config as loadEnv } from "dotenv";
import { defineConfig } from "prisma/config";

loadEnv({ path: ".env.local", override: false, quiet: true });
loadEnv({ path: ".env", override: false, quiet: true });

const databaseUrl =
  process.env["PRISMA_DATABASE_URL"] ||
  process.env["MARKETPLACE_DATABASE_URL"];

export default defineConfig({
  schema: "prisma/schema.prisma",
  migrations: {
    path: "prisma/migrations",
  },
  datasource: {
    url: databaseUrl,
  },
});
