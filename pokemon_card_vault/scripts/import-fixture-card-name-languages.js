#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { Pool } = require('pg');

const ROOT_DIR = path.resolve(__dirname, '..');
const FIXTURE_PATH = path.join(
  ROOT_DIR,
  'test',
  'fixtures',
  'pokemon_card_names_by_generation.txt',
);
const SUPPORTED_LANGUAGES = ['en', 'it', 'fr', 'de', 'es', 'pt', 'ja', 'zh-cn', 'zh-tw'];
const LANGUAGE_TABLES = new Map([
  ['en', 'marketplace_card_names_en'],
  ['it', 'marketplace_card_names_it'],
  ['fr', 'marketplace_card_names_fr'],
  ['de', 'marketplace_card_names_de'],
  ['es', 'marketplace_card_names_es'],
  ['pt', 'marketplace_card_names_pt'],
  ['ja', 'marketplace_card_names_ja'],
  ['zh-cn', 'marketplace_card_names_zh_cn'],
  ['zh-tw', 'marketplace_card_names_zh_tw'],
]);
const BATCH_SIZE = Number(process.env.FIXTURE_LANGUAGE_IMPORT_BATCH_SIZE || 500);
const VARIANT_PREFIXES = [
  'Alolan',
  'Ancient',
  'Armored',
  'Captain',
  'Dark',
  'Detective',
  'Flying',
  'Galarian',
  'Hisuian',
  'Light',
  'M',
  'Mega',
  'Paldean',
  'Radiant',
  "Rocket's",
  'Sandy',
  'Shining',
  'Special Delivery',
  'Surfing',
  "Team Rocket's",
];
const VARIANT_SUFFIX_PATTERN = /\s*(?:-| )?(?:ex|gx|v|vmax|vstar|break|lv\.?\s*x|lv\.?\s*\d+|★|◇|prism star)\s*(?:δ)?\s*$/i;
const SINGLE_LETTER_SUFFIX_PATTERN = /\s+[A-Z]\s*(?:δ)?\s*$/;
const OWNER_PREFIX_PATTERN = /^(.+?)'s\s+(.+)$/;

function readEnv(filePath) {
  const values = {};
  if (!fs.existsSync(filePath)) return values;
  for (const line of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) continue;
    const index = trimmed.indexOf('=');
    const key = trimmed.slice(0, index).trim().replace(/^export\s+/, '');
    const value = trimmed.slice(index + 1).trim().replace(/^['"]|['"]$/g, '');
    values[key] = value;
  }
  return values;
}

function loadEnv() {
  const localEnv = readEnv(path.join(ROOT_DIR, '.env.local'));
  return { ...localEnv, ...process.env };
}

function databaseUrl(env) {
  if (!env.MARKETPLACE_DATABASE_URL) {
    throw new Error('MARKETPLACE_DATABASE_URL is required.');
  }
  return env.MARKETPLACE_DATABASE_URL;
}

function stripEnglishIndex(line) {
  return line.replace(/^\s*\[(\d+)]\s+/, '').trim();
}

function parseFixture(contents) {
  const englishByIndex = new Map();
  const rowsByLanguage = new Map(SUPPORTED_LANGUAGES.map((language) => [language, []]));
  const seenByLanguage = new Map(SUPPORTED_LANGUAGES.map((language) => [language, new Set()]));
  let inTranslations = false;

  for (const line of contents.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (trimmed === '## TCGdex localized name variants') {
      inTranslations = true;
      continue;
    }
    if (!trimmed || trimmed.startsWith('#')) continue;
    if (trimmed.startsWith('## ') || trimmed.startsWith('### ')) continue;

    if (!inTranslations) {
      const match = trimmed.match(/^\[(\d+)]\s+(.+)$/);
      if (!match) continue;
      const index = match[1];
      const name = stripEnglishIndex(trimmed);
      englishByIndex.set(index, name);
      rowsByLanguage.get('en').push({
        language: 'en',
        name,
        localizedName: name,
        source: 'fixture',
        sourceCardId: `fixture:${index}`,
      });
      seenByLanguage.get('en').add(name);
      continue;
    }

    const match = trimmed.match(/^\[(\d+)]\s+([a-z]{2}(?:-[a-z]{2})?)\s+\|\s+(.+?)\s+\|\s+(.+)$/i);
    if (!match) continue;
    const [, index, rawLanguage, localizedName, sourceCardId] = match;
    const language = rawLanguage.toLowerCase();
    if (!rowsByLanguage.has(language)) continue;
    const name = englishByIndex.get(index);
    if (!name) continue;
    const seen = seenByLanguage.get(language);
    if (seen.has(name)) continue;
    seen.add(name);
    rowsByLanguage.get(language).push({
      language,
      name,
      localizedName: localizedName.trim(),
      source: 'fixture-tcgdex',
      sourceCardId: sourceCardId.trim(),
    });
  }

  return rowsByLanguage;
}

function fixtureEnglishPokemonNames(contents) {
  const names = [];
  let inPokemonSection = false;
  for (const line of contents.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (trimmed === '## Trainers' || trimmed === '## TCGdex localized name variants') break;
    if (trimmed.startsWith('## Generation ') || trimmed === '## Unknown Generation') {
      inPokemonSection = true;
      continue;
    }
    if (!inPokemonSection || !trimmed || trimmed.startsWith('#')) continue;
    const match = trimmed.match(/^\[(\d+)]\s+(.+)$/);
    if (match) names.push(match[2].trim());
  }
  return names;
}

function stripKnownVariantText(name) {
  let root = name
    .replace(/δ/g, '')
    .replace(VARIANT_SUFFIX_PATTERN, '')
    .replace(SINGLE_LETTER_SUFFIX_PATTERN, '')
    .trim();
  const ownerMatch = root.match(OWNER_PREFIX_PATTERN);
  if (ownerMatch) root = ownerMatch[2].trim();

  let changed = true;
  while (changed) {
    changed = false;
    for (const prefix of VARIANT_PREFIXES) {
      const pattern = new RegExp(`^${prefix}\\s+`, 'i');
      if (pattern.test(root)) {
        root = root.replace(pattern, '').trim();
        changed = true;
      }
    }
  }

  return root;
}

function canonicalPokemonRoots(contents) {
  const englishNames = fixtureEnglishPokemonNames(contents);
  const roots = new Set();

  for (const name of englishNames) {
    const root = stripKnownVariantText(name);
    if (!root || root.includes(':') || root.toLowerCase().includes('trainer kit')) continue;
    roots.add(root);
  }
  return [...roots].sort((left, right) => right.length - left.length || left.localeCompare(right));
}

function normalizedName(value) {
  return String(value || '')
    .toLowerCase()
    .replaceAll('&', ' tagteam ')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function compactName(value) {
  return String(value || '').toLowerCase().replace(/[^a-z0-9]/g, '');
}

function parseCanonicalCardName(cardName, pokemonRoots, options = {}) {
  const sourceName = String(cardName || '').trim();
  const normalizedSource = normalizedName(sourceName);
  const roots = [...pokemonRoots]
    .filter(Boolean)
    .sort((left, right) => compactName(right).length - compactName(left).length || left.localeCompare(right));
  const root = roots.find((candidate) => {
    const normalizedRoot = normalizedName(candidate);
    return new RegExp(`(^| )${normalizedRoot.replace(/[\\^$.|?*+()[\]{}]/g, '\\$&')}( |$)`).test(normalizedSource);
  });
  const productType = String(options.productType || 'card').toLowerCase();
  if (productType !== 'card' || !root) {
    return {
      sourceName,
      displayName: sourceName,
      canonicalName: sourceName,
      productVariant: '',
      trainerName: String(options.trainerName || ''),
    };
  }

  const variantParts = [];
  const addVariant = (label, pattern) => {
    if (pattern.test(sourceName) && !variantParts.includes(label)) variantParts.push(label);
  };
  addVariant('Mega', /(^|[^a-z0-9])(m|mega)([^a-z0-9]|$)/i);
  addVariant('Surfing', /(^|[^a-z0-9])surfing([^a-z0-9]|$)/i);
  addVariant('Flying', /(^|[^a-z0-9])flying([^a-z0-9]|$)/i);
  addVariant('Radiant', /(^|[^a-z0-9])radiant([^a-z0-9]|$)/i);
  addVariant('Shining', /(^|[^a-z0-9])shining([^a-z0-9]|$)/i);
  addVariant('VMAX', /(^|[^a-z0-9])vmax([^a-z0-9]|$)/i);
  addVariant('VSTAR', /(^|[^a-z0-9])vstar([^a-z0-9]|$)/i);
  addVariant('GX', /(^|[^a-z0-9])gx([^a-z0-9]|$)/i);
  addVariant('EX', /(^|[^a-z0-9])ex([^a-z0-9]|$)/i);
  addVariant('V', /(^|[^a-z0-9])v([^a-z0-9]|$)/i);
  addVariant('BREAK', /(^|[^a-z0-9])break([^a-z0-9]|$)/i);
  addVariant('LV.X', /(^|[^a-z0-9])(lv\.?x|lv x|level x)([^a-z0-9]|$)/i);

  const ownerMatch = sourceName.match(OWNER_PREFIX_PATTERN);
  return {
    sourceName,
    displayName: sourceName,
    canonicalName: root,
    productVariant: variantParts.join(' '),
    trainerName: String(options.trainerName || ownerMatch?.[1] || ''),
  };
}

function quoteIdent(value) {
  return `"${String(value).replaceAll('"', '""')}"`;
}

async function insertRows(pool, tableName, rows) {
  const dedupedRows = [...new Map(rows.map((row) => [row.name, row])).values()];
  if (dedupedRows.length === 0) return;
  for (let offset = 0; offset < dedupedRows.length; offset += BATCH_SIZE) {
    const chunk = dedupedRows.slice(offset, offset + BATCH_SIZE);
    const values = [];
    const placeholders = [];
    let parameter = 1;
    for (const row of chunk) {
      placeholders.push(
        `($${parameter++}, $${parameter++}, $${parameter++}, $${parameter++}, $${parameter++})`,
      );
      values.push(row.language, row.name, row.localizedName, row.source, row.sourceCardId);
    }
    await pool.query(
      `
        insert into public.${quoteIdent(tableName)} (
          language,
          name,
          localized_name,
          normalized_name,
          compact_name,
          name_tokens,
          source,
          source_card_id,
          updated_at
        )
        select
          source.language,
          source.name,
          source.localized_name,
          public.marketplace_search_normalize(source.localized_name),
          public.marketplace_search_compact(source.localized_name),
          public.marketplace_search_tokenize(source.localized_name),
          source.source,
          source.source_card_id,
          now()
        from (values ${placeholders.join(', ')})
          as source(language, name, localized_name, source, source_card_id)
        join public.marketplace_card_names canonical on canonical.name = source.name
        on conflict (name) do update set
          language = excluded.language,
          localized_name = excluded.localized_name,
          normalized_name = excluded.normalized_name,
          compact_name = excluded.compact_name,
          name_tokens = excluded.name_tokens,
          source = excluded.source,
          source_card_id = excluded.source_card_id,
          updated_at = now()
      `,
      values,
    );
  }
}

async function importPokemonRoots(pool, contents) {
  const roots = canonicalPokemonRoots(contents);
  await pool.query('truncate table public.marketplace_pokemon_name_roots');
  if (roots.length === 0) return;

  for (let offset = 0; offset < roots.length; offset += BATCH_SIZE) {
    const chunk = roots.slice(offset, offset + BATCH_SIZE);
    const values = [];
    const placeholders = [];
    let parameter = 1;
    for (const root of chunk) {
      placeholders.push(
        `($${parameter++}, $${parameter++}, $${parameter++}, $${parameter++}, $${parameter++}, now())`,
      );
      values.push(root, normalizedName(root), compactName(root), normalizedName(root).split(/\s+/).filter(Boolean), 'fixture');
    }
    await pool.query(
      `
        insert into public.marketplace_pokemon_name_roots (
          pokemon_name,
          normalized_name,
          compact_name,
          name_tokens,
          source,
          updated_at
        )
        values ${placeholders.join(', ')}
        on conflict (pokemon_name) do update set
          normalized_name = excluded.normalized_name,
          compact_name = excluded.compact_name,
          name_tokens = excluded.name_tokens,
          source = excluded.source,
          updated_at = now()
      `,
      values,
    );
  }
  console.log(`pokemon-roots: imported ${roots.length} canonical Pokémon roots`);
}

async function main() {
  const env = loadEnv();
  const fixtureContents = fs.readFileSync(FIXTURE_PATH, 'utf8');
  const rowsByLanguage = parseFixture(fixtureContents);
  const languages = String(env.FIXTURE_CARD_NAME_LANGUAGES || SUPPORTED_LANGUAGES.join(','))
    .split(',')
    .map((language) => language.trim().toLowerCase())
    .filter((language) => LANGUAGE_TABLES.has(language));
  const pool = new Pool({
    connectionString: databaseUrl(env),
    max: 2,
    idleTimeoutMillis: 10_000,
    connectionTimeoutMillis: 10_000,
    ssl: { rejectUnauthorized: false },
  });

  try {
    for (const language of languages) {
      const tableName = LANGUAGE_TABLES.get(language);
      const rows = rowsByLanguage.get(language) || [];
      await pool.query(`truncate table public.${quoteIdent(tableName)}`);
      await insertRows(pool, tableName, rows);
      console.log(`${language}: imported ${rows.length} fixture name rows into ${tableName}`);
    }
    if (env.FIXTURE_IMPORT_POKEMON_ROOTS !== '0') {
      await importPokemonRoots(pool, fixtureContents);
    }
  } finally {
    await pool.end();
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}

module.exports = {
  canonicalPokemonRoots,
  fixtureEnglishPokemonNames,
  parseCanonicalCardName,
  parseFixture,
  stripKnownVariantText,
  SUPPORTED_LANGUAGES,
};
