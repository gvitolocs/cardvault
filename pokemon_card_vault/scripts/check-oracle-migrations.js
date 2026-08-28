#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');

const ROOT_DIR = path.resolve(__dirname, '..');
const SCHEMA_DIR = path.join(ROOT_DIR, 'oracle-postgres', 'schema');
const MANIFEST_PATH = path.join(ROOT_DIR, 'oracle-postgres', 'schema-manifest.json');
const MIGRATE_SCRIPT = path.join(ROOT_DIR, 'scripts', 'oracle-marketplace-migrate.js');

function migrationPrefix(file) {
  const match = file.match(/^(\d{3})_[a-z0-9_]+\.sql$/);
  return match ? match[1] : '';
}

function main() {
  const manifest = JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8'));
  const actualFiles = fs
    .readdirSync(SCHEMA_DIR)
    .filter((name) => name.endsWith('.sql'))
    .sort();
  const manifestFiles = manifest.files || [];
  const errors = [];

  if (JSON.stringify(actualFiles) !== JSON.stringify(manifestFiles)) {
    const actualSet = new Set(actualFiles);
    const manifestSet = new Set(manifestFiles);
    for (const file of actualFiles) {
      if (!manifestSet.has(file)) {
        errors.push(`${file} exists in oracle-postgres/schema but is missing from schema-manifest.json.`);
      }
    }
    for (const file of manifestFiles) {
      if (!actualSet.has(file)) {
        errors.push(`${file} is listed in schema-manifest.json but missing from oracle-postgres/schema.`);
      }
    }
    if (!errors.length) {
      errors.push('schema-manifest.json order differs from filesystem sorted apply order.');
    }
  }

  const prefixes = new Map();
  for (const file of manifestFiles) {
    const prefix = migrationPrefix(file);
    if (!prefix) {
      errors.push(`${file} must use a three-digit migration prefix and .sql suffix.`);
      continue;
    }
    const files = prefixes.get(prefix) || [];
    files.push(file);
    prefixes.set(prefix, files);
  }

  const allowedDuplicates = manifest.allowedDuplicatePrefixes || {};
  for (const [prefix, files] of prefixes.entries()) {
    if (files.length <= 1) continue;
    if (!allowedDuplicates[prefix]) {
      errors.push(`Migration prefix ${prefix} is duplicated by ${files.join(', ')} without an allowedDuplicatePrefixes reason.`);
    }
  }

  for (const prefix of Object.keys(allowedDuplicates)) {
    if ((prefixes.get(prefix) || []).length <= 1) {
      errors.push(`allowedDuplicatePrefixes.${prefix} is stale; the prefix is not duplicated.`);
    }
  }

  const migrateSource = fs.readFileSync(MIGRATE_SCRIPT, 'utf8');
  if (!/\.filter\(\(name\) => name\.endsWith\('\.sql'\)\)[\s\S]*\.sort\(\)/.test(migrateSource)) {
    errors.push('scripts/oracle-marketplace-migrate.js must keep applying oracle-postgres/schema/*.sql in sorted order.');
  }

  if (errors.length) {
    console.error('Oracle migration tracking check failed:');
    for (const error of errors) {
      console.error(`- ${error}`);
    }
    process.exit(1);
  }

  console.log(`Oracle migration tracking OK: ${manifestFiles.length} schema files listed in apply order.`);
}

main();
