const fs = require('node:fs');
const path = require('node:path');
const { Pool } = require('pg');

const DEFAULT_LANGUAGES = ['it', 'fr', 'de', 'es', 'pt', 'ja', 'zh-cn', 'zh-tw'];

function readEnv(filePath) {
  const values = {};
  if (fs.existsSync(filePath)) {
    for (const line of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) {
        continue;
      }
      const index = trimmed.indexOf('=');
      const key = trimmed.slice(0, index).trim().replace(/^export\s+/, '');
      const value = trimmed.slice(index + 1).trim().replace(/^['"]|['"]$/g, '');
      values[key] = value;
    }
  }
  return values;
}

function required(env, key) {
  if (!env[key]) {
    throw new Error(`Missing ${key}`);
  }
  return env[key];
}

function marketplaceDatabaseUrl(env) {
  if (env.MARKETPLACE_DATABASE_URL) {
    return env.MARKETPLACE_DATABASE_URL;
  }
  const user = encodeURIComponent(required(env, 'MARKETPLACE_DB_USER'));
  const password = encodeURIComponent(required(env, 'MARKETPLACE_DB_PASSWORD'));
  const host = required(env, 'MARKETPLACE_DB_PUBLIC_HOST');
  const port = env.MARKETPLACE_DB_PORT || '5432';
  const database = encodeURIComponent(required(env, 'MARKETPLACE_DB_NAME'));
  return `postgresql://${user}:${password}@${host}:${port}/${database}`;
}

function normalizedLanguage(value) {
  const language = String(value || '').trim().toLowerCase();
  if (language === 'jp') return 'ja';
  if (language === 'zh') return 'zh-cn';
  return language;
}

async function fetchTcgdexCards(language) {
  const response = await fetch(`https://api.tcgdex.net/v2/${language}/cards`);
  if (!response.ok) {
    throw new Error(`TCGdex ${language} cards failed ${response.status}: ${await response.text()}`);
  }
  return response.json();
}

async function fetchTcgdexEnglishCard(id) {
  const response = await fetch(`https://api.tcgdex.net/v2/en/cards/${encodeURIComponent(id)}`);
  if (!response.ok) {
    return null;
  }
  return response.json();
}

async function loadMarketplaceNames(pool) {
  const result = await pool.query('select name from public.marketplace_card_names');
  return new Set(result.rows.map((row) => row.name));
}

async function upsertTranslations(pool, rows) {
  if (rows.length === 0) {
    return;
  }
  const dedupedRows = Array.from(
    new Map(rows.map((row) => [`${row.language}\u0000${row.name}`, row])).values(),
  );
  const values = [];
  const placeholders = [];
  let parameter = 1;
  for (const row of dedupedRows) {
    placeholders.push(`($${parameter++}, $${parameter++}, $${parameter++}, $${parameter++})`);
    values.push(row.language, row.name, row.localizedName, row.sourceCardId);
  }
  await pool.query(
    `
      insert into public.marketplace_card_name_translations (
        language,
        name,
        localized_name,
        normalized_localized_name,
        compact_localized_name,
        localized_name_tokens,
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
        'tcgdex',
        source.source_card_id,
        now()
      from (values ${placeholders.join(', ')}) as source(language, name, localized_name, source_card_id)
      on conflict (language, name) do update set
        localized_name = excluded.localized_name,
        normalized_localized_name = excluded.normalized_localized_name,
        compact_localized_name = excluded.compact_localized_name,
        localized_name_tokens = excluded.localized_name_tokens,
        source = excluded.source,
        source_card_id = excluded.source_card_id,
        updated_at = now()
    `,
    values,
  );
}

async function importLanguage(pool, language, options) {
  const marketplaceNames = await loadMarketplaceNames(pool);
  const localizedCards = await fetchTcgdexCards(language);
  const maxRows = Number(options.maxRows || 0);
  const batchSize = Number(options.batchSize || 200);
  const translations = [];
  let checked = 0;
  let matched = 0;
  let skipped = 0;

  for (const card of localizedCards) {
    if (!card?.id || !card?.name) {
      skipped += 1;
      continue;
    }
    checked += 1;
    const english = await fetchTcgdexEnglishCard(card.id);
    const englishName = typeof english?.name === 'string' ? english.name.trim() : '';
    const localizedName = String(card.name || '').trim();
    if (!englishName || !localizedName || !marketplaceNames.has(englishName)) {
      skipped += 1;
      continue;
    }
    if (localizedName.toLowerCase() === englishName.toLowerCase()) {
      skipped += 1;
      continue;
    }
    translations.push({
      language,
      name: englishName,
      localizedName,
      sourceCardId: card.id,
    });
    matched += 1;
    if (translations.length >= batchSize) {
      await upsertTranslations(pool, translations.splice(0));
      console.log(`${language}: checked ${checked}, matched ${matched}, skipped ${skipped}`);
    }
    if (maxRows > 0 && checked >= maxRows) {
      break;
    }
  }
  await upsertTranslations(pool, translations);
  console.log(`${language}: done checked ${checked}, matched ${matched}, skipped ${skipped}`);
}

async function main() {
  const localEnv = readEnv(path.resolve('.env.local'));
  const oracleEnv = readEnv(process.env.ORACLE_ENV_FILE || '/Users/giuseppe/pokoinpos/deploy/env/peer4-postgres.env');
  const env = { ...localEnv, ...oracleEnv, ...process.env };
  const languages = String(env.TCGDEX_LANGUAGES || DEFAULT_LANGUAGES.join(','))
    .split(',')
    .map(normalizedLanguage)
    .filter((language) => language && language !== 'en');
  const pool = new Pool({
    connectionString: marketplaceDatabaseUrl(env),
    max: 2,
    idleTimeoutMillis: 10_000,
    connectionTimeoutMillis: 10_000,
    ssl: { rejectUnauthorized: false },
  });
  try {
    for (const language of languages) {
      await importLanguage(pool, language, {
        maxRows: env.TCGDEX_MAX_ROWS,
        batchSize: env.TCGDEX_BATCH_SIZE,
      });
    }
  } finally {
    await pool.end();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
