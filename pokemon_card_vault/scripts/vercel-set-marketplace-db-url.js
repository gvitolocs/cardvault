#!/usr/bin/env node

const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

function readEnvFile(filePath) {
  const values = {};
  const text = fs.readFileSync(filePath, 'utf8');
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) {
      continue;
    }
    const [rawKey, ...rest] = trimmed.split('=');
    const key = rawKey.replace(/^export\s+/, '').trim();
    const value = rest.join('=').trim().replace(/^['"]|['"]$/g, '');
    values[key] = value;
  }
  return values;
}

function required(values, key) {
  const value = values[key] || process.env[key] || '';
  if (!value) {
    throw new Error(`${key} is required.`);
  }
  return value;
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    stdio: options.input ? ['pipe', 'inherit', 'inherit'] : 'inherit',
    input: options.input,
    encoding: 'utf8',
  });
  if (result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} failed.`);
  }
}

function runOptional(command, args, options = {}) {
  const result = spawnSync(command, args, {
    stdio: options.input ? ['pipe', 'inherit', 'inherit'] : 'inherit',
    input: options.input,
    encoding: 'utf8',
  });
  return result.status === 0;
}

function main() {
  const envPath = process.argv[2] || '../pokoinpos/deploy/env/peer4-postgres.env';
  const resolvedEnvPath = path.resolve(process.cwd(), envPath);
  if (!fs.existsSync(resolvedEnvPath)) {
    throw new Error(`Env file not found: ${resolvedEnvPath}`);
  }

  const values = readEnvFile(resolvedEnvPath);
  const host = required(values, 'MARKETPLACE_DB_PUBLIC_HOST');
  const port = values.MARKETPLACE_DB_PORT || '5432';
  const database = values.MARKETPLACE_DB_NAME || 'pokoin_marketplace';
  const user = values.MARKETPLACE_DB_USER || 'pokoin_marketplace';
  const password = required(values, 'MARKETPLACE_DB_PASSWORD');
  const encodedUser = encodeURIComponent(user);
  const encodedPassword = encodeURIComponent(password);
  const encodedDatabase = encodeURIComponent(database);
  const databaseUrl = `postgresql://${encodedUser}:${encodedPassword}@${host}:${port}/${encodedDatabase}`;

  runOptional('vercel', ['env', 'rm', 'MARKETPLACE_DATABASE_URL', 'production', '--yes'], {
    input: '',
  });
  run('vercel', ['env', 'add', 'MARKETPLACE_DATABASE_URL', 'production'], {
    input: `${databaseUrl}\n`,
  });
  console.log('MARKETPLACE_DATABASE_URL set in Vercel production.');
}

main();
