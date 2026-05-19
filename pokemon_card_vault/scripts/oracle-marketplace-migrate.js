#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { Pool } = require('pg');

const ROOT_DIR = path.resolve(__dirname, '..');
const SCHEMA_DIR = path.join(ROOT_DIR, 'oracle-postgres', 'schema');
const BATCH_SIZE = Number(process.env.MARKETPLACE_MIGRATION_BATCH_SIZE || 1000);

const SOURCE_TABLES = [
  'cardtrader_pokemon_blueprints',
  'cardtrader_pokemon_expansions',
  'marketplace_trainers',
  'marketplace_card_events',
];

function databaseUrl(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`${name} is required.`);
  }
  return value;
}

function createPool(name) {
  return new Pool({
    connectionString: databaseUrl(name),
    max: 2,
    idleTimeoutMillis: 10_000,
    connectionTimeoutMillis: 10_000,
    ssl: { rejectUnauthorized: false },
  });
}

function optionalEnv(name) {
  return process.env[name] || '';
}

async function closePools(...pools) {
  await Promise.all(pools.filter(Boolean).map((pool) => pool.end().catch(() => {})));
}

async function runSchema(targetPool) {
  const files = fs
    .readdirSync(SCHEMA_DIR)
    .filter((name) => name.endsWith('.sql'))
    .sort();

  for (const file of files) {
    const fullPath = path.join(SCHEMA_DIR, file);
    const sql = fs.readFileSync(fullPath, 'utf8');
    console.log(`Applying ${path.relative(ROOT_DIR, fullPath)}`);
    await targetPool.query(sql);
  }
}

async function getTableColumns(pool, tableName) {
  const result = await pool.query(
    `
      select column_name
      from information_schema.columns
      where table_schema = 'public'
        and table_name = $1
      order by ordinal_position
    `,
    [tableName],
  );
  return result.rows.map((row) => row.column_name);
}

async function getTableColumnTypes(pool, tableName) {
  const result = await pool.query(
    `
      select column_name, udt_name
      from information_schema.columns
      where table_schema = 'public'
        and table_name = $1
    `,
    [tableName],
  );
  return new Map(result.rows.map((row) => [row.column_name, row.udt_name]));
}

async function tableExists(pool, tableName) {
  const result = await pool.query('select to_regclass($1) as regclass', [
    `public.${tableName}`,
  ]);
  return Boolean(result.rows[0]?.regclass);
}

function supabaseRestClient() {
  const url = optionalEnv('SUPABASE_URL').replace(/\/$/, '');
  const key = optionalEnv('SUPABASE_SERVICE_ROLE_KEY') || optionalEnv('SUPABASE_ANON_KEY');
  if (!url || !key) {
    return null;
  }
  return { url, key };
}

async function fetchSupabaseRest(client, tableName, searchParams, headers = {}) {
  const url = new URL(`${client.url}/rest/v1/${tableName}`);
  for (const [key, value] of Object.entries(searchParams)) {
    url.searchParams.set(key, value);
  }
  const response = await fetch(url, {
    headers: {
      apikey: client.key,
      Authorization: `Bearer ${client.key}`,
      ...headers,
    },
  });
  if (!response.ok) {
    if (response.status === 404) {
      return null;
    }
    throw new Error(`Supabase REST ${tableName} failed: ${response.status} ${await response.text()}`);
  }
  return response;
}

async function copyTableFromRest(restClient, targetPool, tableName) {
  if (!(await tableExists(targetPool, tableName))) {
    console.log(`Skipping missing target table ${tableName}`);
    return;
  }

  const [targetColumns, columnTypes] = await Promise.all([
    getTableColumns(targetPool, tableName),
    getTableColumnTypes(targetPool, tableName),
  ]);
  if (targetColumns.length === 0) {
    console.log(`Skipping ${tableName}; no target columns`);
    return;
  }

  const countResponse = await fetchSupabaseRest(
    restClient,
    tableName,
    { select: targetColumns.join(','), limit: '1' },
    { Prefer: 'count=exact' },
  );
  if (!countResponse) {
    console.log(`Skipping missing source table ${tableName}`);
    return;
  }

  const contentRange = countResponse.headers.get('content-range') || '';
  const total = Number(contentRange.split('/').pop() || 0);
  console.log(`Copying ${total} rows from ${tableName} via Supabase REST`);

  await targetPool.query(`truncate table public.${quoteIdent(tableName)} cascade`);

  for (let offset = 0; offset < total; offset += BATCH_SIZE) {
    const response = await fetchSupabaseRest(restClient, tableName, {
      select: targetColumns.join(','),
      order: `${targetColumns[0]}.asc`,
      limit: String(BATCH_SIZE),
      offset: String(offset),
    });
    const rows = await response.json();
    if (!rows.length) {
      break;
    }
    const values = rows.flatMap((row) => rowValues(row, targetColumns, columnTypes));
    await targetPool.query(insertSql(tableName, targetColumns, rows.length), values);
    console.log(`  ${tableName}: ${Math.min(offset + rows.length, total)}/${total}`);
  }
}

function quoteIdent(value) {
  return `"${String(value).replaceAll('"', '""')}"`;
}

function parsePostgresArrayLiteral(value) {
  const text = String(value).trim();
  if (!text.startsWith('{') || !text.endsWith('}')) {
    return value;
  }
  const body = text.slice(1, -1);
  if (!body) {
    return [];
  }
  const items = [];
  let current = '';
  let quoted = false;
  let escaped = false;
  for (const char of body) {
    if (escaped) {
      current += char;
      escaped = false;
      continue;
    }
    if (char === '\\') {
      escaped = true;
      continue;
    }
    if (char === '"') {
      quoted = !quoted;
      continue;
    }
    if (char === ',' && !quoted) {
      items.push(current);
      current = '';
      continue;
    }
    current += char;
  }
  items.push(current);
  return items.map((item) => (item === 'NULL' ? null : item));
}

function normalizeValueForTarget(value, udtName) {
  if (value == null) {
    return null;
  }
  if (udtName === 'json' || udtName === 'jsonb') {
    if (Array.isArray(value) || (typeof value === 'object' && value !== null)) {
      return JSON.stringify(value);
    }
    const parsed = parsePostgresArrayLiteral(value);
    if (parsed !== value) {
      return JSON.stringify(parsed);
    }
  }
  return value;
}

function rowValues(row, columns, columnTypes = new Map()) {
  return columns.map(
    (column) => normalizeValueForTarget(row[column], columnTypes.get(column)) ?? null,
  );
}

function insertSql(tableName, columns, rowCount) {
  const columnSql = columns.map(quoteIdent).join(', ');
  const placeholders = [];
  let parameter = 1;
  for (let rowIndex = 0; rowIndex < rowCount; rowIndex += 1) {
    const rowPlaceholders = [];
    for (let columnIndex = 0; columnIndex < columns.length; columnIndex += 1) {
      rowPlaceholders.push(`$${parameter}`);
      parameter += 1;
    }
    placeholders.push(`(${rowPlaceholders.join(', ')})`);
  }
  return `
    insert into public.${quoteIdent(tableName)} (${columnSql})
    values ${placeholders.join(', ')}
    on conflict do nothing
  `;
}

async function copyTable(sourcePool, targetPool, tableName) {
  if (!(await tableExists(sourcePool, tableName))) {
    console.log(`Skipping missing source table ${tableName}`);
    return;
  }
  if (!(await tableExists(targetPool, tableName))) {
    console.log(`Skipping missing target table ${tableName}`);
    return;
  }

  const [sourceColumns, targetColumns] = await Promise.all([
    getTableColumns(sourcePool, tableName),
    getTableColumns(targetPool, tableName),
  ]);
  const columns = sourceColumns.filter((column) => targetColumns.includes(column));
  if (columns.length === 0) {
    console.log(`Skipping ${tableName}; no shared columns`);
    return;
  }

  const countResult = await sourcePool.query(
    `select count(*)::integer as count from public.${quoteIdent(tableName)}`,
  );
  const total = countResult.rows[0]?.count || 0;
  console.log(`Copying ${total} rows from ${tableName}`);

  await targetPool.query(`truncate table public.${quoteIdent(tableName)} cascade`);

  for (let offset = 0; offset < total; offset += BATCH_SIZE) {
    const page = await sourcePool.query(
      `
        select ${columns.map(quoteIdent).join(', ')}
        from public.${quoteIdent(tableName)}
        order by 1
        limit $1 offset $2
      `,
      [BATCH_SIZE, offset],
    );
    if (page.rows.length === 0) {
      break;
    }
    const values = page.rows.flatMap((row) => rowValues(row, columns));
    await targetPool.query(insertSql(tableName, columns, page.rows.length), values);
    console.log(`  ${tableName}: ${Math.min(offset + page.rows.length, total)}/${total}`);
  }
}

async function copyTables(sourcePool, targetPool) {
  for (const tableName of SOURCE_TABLES) {
    await copyTable(sourcePool, targetPool, tableName);
  }
}

async function copyTablesWithRestFallback(sourcePool, targetPool) {
  try {
    await copyTables(sourcePool, targetPool);
  } catch (error) {
    const restClient = supabaseRestClient();
    if (!restClient) {
      throw error;
    }
    console.log(`Supabase DB copy failed (${error.code || error.message}); retrying via Supabase REST`);
    for (const tableName of SOURCE_TABLES) {
      await copyTableFromRest(restClient, targetPool, tableName);
    }
  }
}

async function refreshTarget(targetPool) {
  console.log('Refreshing Oracle marketplace projections');
  const result = await targetPool.query('select public.refresh_marketplace_oracle_projections() as result');
  console.log(JSON.stringify(result.rows[0]?.result || {}, null, 2));
}

async function verifySearch(targetPool) {
  const queries = ['porygon', 'piachu 151', 'char ex'];
  for (const query of queries) {
    const result = await targetPool.query(
      'select card_id, name, set_name, card_number, search_rank from public.search_marketplace_blueprint_candidates_v2($1, 10, 0)',
      [query],
    );
    console.log(`Search "${query}" returned ${result.rowCount} rows`);
    console.log(
      result.rows
        .slice(0, 3)
        .map((row) => `${row.card_id}:${row.name} (${row.set_name} ${row.card_number})`)
        .join(' | '),
    );
  }
}

async function main() {
  const command = process.argv[2] || 'all';
  const sourcePool = ['copy', 'all'].includes(command) ? createPool('SUPABASE_DB_URL') : null;
  const targetPool = createPool('MARKETPLACE_DATABASE_URL');

  try {
    if (['schema', 'all'].includes(command)) {
      await runSchema(targetPool);
    }
    if (['copy', 'all'].includes(command)) {
      await copyTablesWithRestFallback(sourcePool, targetPool);
    }
    if (['refresh', 'all'].includes(command)) {
      await refreshTarget(targetPool);
    }
    if (['verify', 'all'].includes(command)) {
      await verifySearch(targetPool);
    }
  } finally {
    await closePools(sourcePool, targetPool);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
