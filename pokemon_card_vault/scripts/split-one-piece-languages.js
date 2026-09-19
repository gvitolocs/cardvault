#!/usr/bin/env node
/**
 * Hardlink One Piece CDN files into english/ and japanese/ (plus chinese/)
 * without copying bytes. R2-identical keys at one-piece/ root stay put.
 *
 * CardTrader names every expansion in English and often defaults
 * `onepiece_language` to en, even on Japanese printings. Classification is:
 *   1. Official EN cardlist (en.onepiece-cardgame.com, 2026-09-01): OP-01..17,
 *      ST-01..36, EB-01/02/03/05, PRB-01/02 → english unless the SKU is Asian.
 *   2. Expansions with no standalone EN product + JP photos: Asian Promos,
 *      Magazine Promos, EB-04 Egghead Crisis.
 *   3. Visual checks on mixed dumps (Championships, Premium collections, OP-18).
 *
 *   node scripts/split-one-piece-languages.js --dest=.../one-piece --apply
 */
const fs = require('node:fs');
const path = require('node:path');
const { Client } = require('pg');
const { URL } = require('url');

const ROOT = path.resolve(__dirname, '..');
const LANGUAGE_DIRS = ['english', 'japanese', 'chinese'];

function loadEnv() {
  const envPath = path.join(ROOT, '.env.local');
  if (!fs.existsSync(envPath)) return;
  for (const line of fs.readFileSync(envPath, 'utf8').split(/\n/)) {
    const s = line.trim();
    if (!s || s.startsWith('#') || !s.includes('=')) continue;
    const i = s.indexOf('=');
    const k = s.slice(0, i).replace(/^export\s+/, '').trim();
    let v = s.slice(i + 1).trim();
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
    if (!process.env[k]) process.env[k] = v;
  }
}

function parseArgs(argv) {
  const options = {
    dest: '',
    apply: false,
    databaseUrlEnv: 'MARKETPLACE_DATABASE_URL',
  };
  for (const arg of argv) {
    if (arg.startsWith('--dest=')) options.dest = arg.slice('--dest='.length);
    else if (arg === '--apply') options.apply = true;
    else if (arg.startsWith('--database-url-env=')) options.databaseUrlEnv = arg.slice('--database-url-env='.length);
  }
  return options;
}

/** CardTrader expansions that are Japanese products (no standalone EN SKU, JP photos). */
const JAPANESE_EXPANSIONS = new Set([
  'Asian Promos',
  'Magazine Promos',
  'EB-04: Egghead Crisis',
]);

/**
 * OP-18 dump is mixed: Asian boxes and Saint Gunko leader are Japanese;
 * Mini-Merry / Shamrock / OP08 reprints are English. Visual check 2026-09-01.
 */
const VISUAL_JAPANESE_IDS = new Set(['408462', '406521', '406523']);

function officialEnglishExpansion(expansionName) {
  const name = String(expansionName || '');
  const match = name.match(/^(OP|ST|EB|PRB)-(\d+)/i);
  if (!match) return false;
  const kind = match[1].toUpperCase();
  const n = Number(match[2]);
  if (kind === 'OP') return n >= 1 && n <= 17;
  if (kind === 'ST') return n >= 1 && n <= 36;
  if (kind === 'EB') return n === 1 || n === 2 || n === 3 || n === 5;
  if (kind === 'PRB') return n === 1 || n === 2;
  return false;
}

function classifyOnePieceLanguage(row) {
  const lang = row.defaultLang || null;
  const expansion = String(row.expansionName || '');
  const version = String(row.version || '');
  const blob = `${expansion} ${version}`.toLowerCase();
  const versionLc = version.toLowerCase();

  if (lang === 'zh-CN' || /\bchinese\b|mainland china/.test(blob)) return 'chinese';
  if (/\bfrench\b|première|premiere édition/.test(blob) || expansion === 'French Promos') {
    return 'english';
  }

  if (row.id && VISUAL_JAPANESE_IDS.has(String(row.id))) return 'japanese';

  const asianSku = /\basian\b/.test(versionLc);
  const japaneseSku = /\bjapanese\b/.test(blob) && !/\benglish version\b/.test(blob);
  const jpExclusiveProduct =
    /\bgirls edition\b/.test(blob) ||
    /\bpromotion pack ex\b/.test(blob) ||
    /\b(saikyo jump|v jump|shonen jump)\b/.test(blob);
  if (asianSku || japaneseSku || jpExclusiveProduct) return 'japanese';

  if (JAPANESE_EXPANSIONS.has(expansion)) return 'japanese';

  // Dual-language numbered sets: CardTrader photos are the English printing.
  if (officialEnglishExpansion(expansion)) return 'english';

  if (lang === 'jp') return 'japanese';
  return 'english';
}

function idFromFilename(name) {
  const match = String(name).match(/^(\d+)_/);
  return match ? match[1] : null;
}

function listImageFiles(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir, { withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => entry.name);
}

function hardlink(src, dest) {
  try {
    fs.linkSync(src, dest);
    return 'linked';
  } catch (error) {
    if (error && error.code === 'EEXIST') return 'exists';
    throw error;
  }
}

async function loadClassifiedIds(databaseUrl) {
  const url = new URL(databaseUrl);
  url.pathname = '/pokoin_one_piece';
  const client = new Client({
    connectionString: url.toString(),
    ssl: { rejectUnauthorized: false },
  });
  await client.connect();
  try {
    const result = await client.query(`
      select
        id::text as id,
        name,
        version,
        expansion->>'name' as expansion_name,
        (
          select e->>'default_value'
          from jsonb_array_elements(coalesce(editable_properties, '[]'::jsonb)) e
          where e->>'name' = 'onepiece_language'
          limit 1
        ) as default_lang
      from marketplace_one_piece.cardtrader_blueprints
    `);
    const byId = new Map();
    const counts = { english: 0, japanese: 0, chinese: 0 };
    for (const row of result.rows) {
      const language = classifyOnePieceLanguage({
        id: row.id,
        defaultLang: row.default_lang,
        expansionName: row.expansion_name,
        version: row.version,
      });
      byId.set(row.id, language);
      counts[language] += 1;
    }
    return { byId, counts };
  } finally {
    await client.end();
  }
}

async function run(argv = process.argv.slice(2), env = process.env) {
  loadEnv();
  const options = parseArgs(argv);
  const dest = path.resolve(options.dest || '');
  if (!dest || !fs.existsSync(dest)) {
    throw new Error('--dest must be an existing one-piece directory');
  }
  const databaseUrl = env[options.databaseUrlEnv];
  if (!databaseUrl) throw new Error(`${options.databaseUrlEnv} is required`);

  const { byId, counts } = await loadClassifiedIds(databaseUrl);
  const summary = {
    dest,
    apply: options.apply,
    blueprints: counts,
    files: { english: 0, japanese: 0, chinese: 0, unmatched: 0, linked: 0, exists: 0 },
  };

  if (options.apply) {
    for (const language of LANGUAGE_DIRS) {
      const dir = path.join(dest, language);
      fs.rmSync(dir, { recursive: true, force: true });
      fs.mkdirSync(path.join(dir, 'previews'), { recursive: true });
    }
  }

  const jobs = [
    { from: dest, into: (language, name) => path.join(dest, language, name) },
    {
      from: path.join(dest, 'previews'),
      into: (language, name) => path.join(dest, language, 'previews', name),
    },
  ];

  for (const job of jobs) {
    for (const name of listImageFiles(job.from)) {
      const id = idFromFilename(name);
      if (!id) continue;
      const language = byId.get(id);
      if (!language) {
        summary.files.unmatched += 1;
        continue;
      }
      summary.files[language] += 1;
      if (!options.apply) continue;
      const result = hardlink(path.join(job.from, name), job.into(language, name));
      summary.files[result] += 1;
    }
  }

  return summary;
}

if (require.main === module) {
  run().then((summary) => {
    console.log(JSON.stringify(summary, null, 2));
  }).catch((error) => {
    console.error(error.message || error);
    process.exit(1);
  });
}

module.exports = {
  JAPANESE_EXPANSIONS,
  VISUAL_JAPANESE_IDS,
  classifyOnePieceLanguage,
  idFromFilename,
  officialEnglishExpansion,
  parseArgs,
  run,
};
