#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { Pool } = require('pg');

const ROOT_DIR = path.resolve(__dirname, '..');

loadLocalEnv();

function loadLocalEnv() {
  const envPath = path.join(ROOT_DIR, '.env.local');
  if (!fs.existsSync(envPath)) return;
  for (const line of fs.readFileSync(envPath, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) continue;
    const separator = trimmed.indexOf('=');
    const key = trimmed.slice(0, separator).replace(/^export\s+/, '').trim();
    if (!key || process.env[key]) continue;
    let value = trimmed.slice(separator + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1).replace(/\\n/g, '\n');
    }
    process.env[key] = value;
  }
}

function databaseUrl() {
  if (!process.env.MARKETPLACE_DATABASE_URL) {
    throw new Error('MARKETPLACE_DATABASE_URL is required.');
  }
  return process.env.MARKETPLACE_DATABASE_URL;
}

function querySequence() {
  const args = process.argv.slice(2).filter(Boolean);
  if (args.length > 0) return args;
  return ['p', 'pi', 'pik', 'pika', 'pikachu', 'pikachu e', 'pikachu ex'];
}

function summarizePlan(planRows) {
  const text = planRows.map((row) => row['QUERY PLAN']).join('\n');
  const indexes = [...text.matchAll(/(?:Index|Bitmap Index) Scan using ([^\s]+)/g)]
    .map((match) => match[1]);
  const execution = text.match(/Execution Time: ([0-9.]+) ms/);
  const planning = text.match(/Planning Time: ([0-9.]+) ms/);
  return {
    planningMs: planning ? Number(planning[1]) : null,
    executionMs: execution ? Number(execution[1]) : null,
    indexes: [...new Set(indexes)],
    plan: text,
  };
}

async function explain(pool, label, sql, values) {
  const result = await pool.query(`explain (analyze, buffers, format text) ${sql}`, values);
  return { label, ...summarizePlan(result.rows) };
}

async function topRows(pool, sql, values) {
  const result = await pool.query(sql, values);
  return result.rows.map((row) => ({
    card_id: row.card_id,
    name: row.name,
    set_name: row.set_name,
    card_number: row.card_number,
    rarity: row.rarity,
    product_variant: row.product_variant,
    search_rank: Number(row.search_rank || 0),
  }));
}

async function main() {
  const pool = new Pool({
    connectionString: databaseUrl(),
    ssl: { rejectUnauthorized: process.env.MARKETPLACE_DATABASE_SSL_VERIFY === '1' },
    max: 1,
  });
  const report = {
    generatedAt: new Date().toISOString(),
    queries: [],
  };
  try {
    for (const query of querySequence()) {
      const values = [query, 20, 0, 'en'];
      const fullSql = 'select * from public.search_marketplace_blueprint_candidates_v2($1, $2, $3, $4)';
      const nameSql = 'select * from public.search_marketplace_blueprint_name_candidates($1, $2, $3, $4)';
      const nonNameSql = 'select * from public.search_marketplace_blueprint_non_name_candidates($1, $2, $3, $4)';
      report.queries.push({
        query,
        topRows: await topRows(pool, fullSql, values),
        explains: [
          await explain(pool, 'full', fullSql, values),
          await explain(pool, 'name', nameSql, values),
          await explain(pool, 'non_name', nonNameSql, values),
        ],
      });
    }
  } finally {
    await pool.end();
  }
  console.log(JSON.stringify(report, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
