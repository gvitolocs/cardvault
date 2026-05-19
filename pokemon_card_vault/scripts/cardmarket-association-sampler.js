#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { Pool } = require('pg');

const ROOT_DIR = path.resolve(__dirname, '..');
const DEFAULT_SAMPLE_SIZE = 100;
const DEFAULT_LOCALE = 'en';

const KNOWN_CARDMARKET_SET_CODES = new Map([
  ['Call of Legends', 'CL'],
  ['Chaos Rising', 'CRI'],
  ['CSVH4pC: Reward Pack', 'CSVH4Cp'],
  ['Skyridge', 'SK'],
  ['Start Deck 100', 'sI100'],
]);

const KNOWN_CARDMARKET_EXPANSION_SLUGS = new Map([
  [
    'CSVH4pC: Reward Pack',
    'Happy-Set-Decidueye-Melmetal-Koraidon-Miraidon',
  ],
]);

const KNOWN_NAME_ONLY_TRAINER_EXPANSIONS = new Set([
  'Night Unison',
  'Rising Fist',
]);

function localExpansionCodeByName() {
  const filePath = path.join(ROOT_DIR, 'data', 'cardtrader', 'pokemon-expansions.json');
  if (!fs.existsSync(filePath)) return new Map();
  const rows = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  return new Map(
    rows.map((row) => [
      String(row.name || '').trim().toLowerCase(),
      String(row.code || '').trim(),
    ]),
  );
}

const LOCAL_EXPANSION_CODES = localExpansionCodeByName();

function readEnv(filePath) {
  const env = {};
  if (!fs.existsSync(filePath)) return env;
  for (const line of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) continue;
    const index = trimmed.indexOf('=');
    const key = trimmed.slice(0, index).trim().replace(/^export\s+/, '');
    const value = trimmed.slice(index + 1).trim().replace(/^['"]|['"]$/g, '');
    env[key] = value;
  }
  return env;
}

function databaseUrl(env) {
  return (
    env.MARKETPLACE_DATABASE_URL ||
    env.SUPABASE_DB_URL ||
    env.DATABASE_URL ||
    env.POSTGRES_URL ||
    ''
  );
}

function oraclePeerEnvCandidates(args) {
  return unique([
    args.get('oracle-env'),
    process.env.MARKETPLACE_ORACLE_ENV_PATH,
    path.resolve(ROOT_DIR, '..', 'pokoinpos', 'deploy', 'env', 'peer4-postgres.env'),
    path.resolve(ROOT_DIR, '..', '..', 'pokoinpos', 'deploy', 'env', 'peer4-postgres.env'),
  ]);
}

function oracleDatabaseUrlFromPeerEnv(filePath) {
  if (!filePath || !fs.existsSync(filePath)) return '';
  const values = readEnv(filePath);
  const host = values.MARKETPLACE_DB_PUBLIC_HOST;
  const user = values.MARKETPLACE_DB_USER;
  const password = values.MARKETPLACE_DB_PASSWORD;
  const database = values.MARKETPLACE_DB_NAME;
  if (!host || !user || !password || !database) return '';
  const port = values.MARKETPLACE_DB_PORT || '5432';
  return `postgresql://${encodeURIComponent(user)}:${encodeURIComponent(password)}@${host}:${port}/${encodeURIComponent(database)}`;
}

function resolveDatabaseUrl(env, args) {
  for (const filePath of oraclePeerEnvCandidates(args)) {
    const url = oracleDatabaseUrlFromPeerEnv(filePath);
    if (url) return url;
  }
  return databaseUrl(env);
}

function cleanLimit(value, fallback = DEFAULT_SAMPLE_SIZE) {
  const limit = Number(value);
  if (!Number.isFinite(limit)) return fallback;
  return Math.min(Math.max(Math.trunc(limit), 1), 1000);
}

function slugPart(value) {
  return String(value || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/&/g, ' and ')
    .replace(/[^a-zA-Z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function expansionSlug(expansionName) {
  const known = KNOWN_CARDMARKET_EXPANSION_SLUGS.get(String(expansionName || '').trim());
  return known || slugPart(expansionName);
}

function cardNameSlug(name) {
  return slugPart(
    String(name || '')
      .replace(/\bShiny Rare\b/gi, '')
      .replace(/\bRare Holo\b/gi, '')
      .replace(/\bHolo\b/gi, '')
      .replace(/\s+/g, ' ')
      .trim(),
  );
}

function maybeCardmarketSetCode(expansionName, cardtraderCode) {
  const known = KNOWN_CARDMARKET_SET_CODES.get(String(expansionName || '').trim());
  if (known) return known;
  const raw =
    String(cardtraderCode || '').trim() ||
    LOCAL_EXPANSION_CODES.get(String(expansionName || '').trim().toLowerCase()) ||
    '';
  if (!raw) return '';
  return raw.replace(/[^a-z0-9]/gi, '').toUpperCase();
}

async function fetchLiveApiRows(limit) {
  const expansionsResponse = await fetch('https://pokoin.com/api/marketplace-expansions?limit=2000');
  if (!expansionsResponse.ok) {
    throw new Error(`Live expansions API failed: ${expansionsResponse.status}`);
  }
  const expansionPayload = await expansionsResponse.json();
  const expansions = Array.isArray(expansionPayload)
    ? expansionPayload
    : Array.isArray(expansionPayload.expansions)
      ? expansionPayload.expansions
      : [];
  const shuffled = [...expansions].sort(() => Math.random() - 0.5);
  const rows = [];
  for (const expansion of shuffled) {
    if (rows.length >= limit) break;
    const slug = expansion.slug;
    if (!slug) continue;
    const snapshotUrl =
      `https://pokoin.com/api/marketplace-expansions?slug=${encodeURIComponent(slug)}&includeCards=1&limit=80`;
    const response = await fetch(snapshotUrl);
    if (!response.ok) continue;
    const snapshot = await response.json();
    const cards = Array.isArray(snapshot.cards) ? snapshot.cards : [];
    for (const card of cards.sort(() => Math.random() - 0.5)) {
      if (rows.length >= limit) break;
      rows.push({
        card_id: card.card_id || card.id,
        name: card.name,
        expansion_name: card.expansion_name || expansion.name,
        expansion_number: normalizedCollectorNumber(card.expansion_number || card.card_number),
        product_variant: card.product_variant || '',
        product_type: card.product_type || 'card',
        card_type: card.card_type || card.type || '',
        expansion_code:
          LOCAL_EXPANSION_CODES.get(
            String(card.expansion_name || expansion.name || '').trim().toLowerCase(),
          ) || '',
      });
    }
  }
  return rows;
}

function collectorCandidates(collectorNumber, setCode) {
  const raw = normalizedCollectorNumber(collectorNumber);
  if (!raw || !setCode) return [];
  const clean = raw.replace(/\s+/g, '').replace(/\/.*$/, '').toUpperCase();
  if (!/\d/.test(clean)) return [];
  const special = /^([A-Z]+)(\d+)$/.exec(clean);
  if (special) {
    const [, prefix, numeric] = special;
    const value = Number(numeric);
    const padded2 = Number.isFinite(value) ? String(value).padStart(2, '0') : numeric;
    const padded3 = Number.isFinite(value) ? String(value).padStart(3, '0') : numeric;
    return unique([
      `${setCode}${prefix}${padded2}`,
      `${setCode}${prefix}${numeric}`,
      `${setCode}${prefix}${padded3}`,
    ]);
  }
  const numeric = /^0*(\d+)[A-Z]?$/.exec(clean);
  if (numeric) {
    const value = Number(numeric[1]);
    const suffix = clean.replace(/^\d+/, '');
    const unpadded = `${setCode}${value}${suffix}`;
    const padded3 = `${setCode}${String(value).padStart(3, '0')}${suffix}`;
    const padded2 = `${setCode}${String(value).padStart(2, '0')}${suffix}`;
    return clean.startsWith('0')
      ? unique([padded3, unpadded, padded2])
      : unique([unpadded, padded3, padded2]);
  }
  return [`${setCode}${clean}`];
}

function normalizedCollectorNumber(value) {
  const text = String(value || '').replace(/\|\|/g, '|').trim();
  const slashNumber = /([A-Z]*\d+[A-Z]?\s*\/\s*\d+)/i.exec(text);
  if (slashNumber) return slashNumber[1].replace(/\s+/g, '');
  const specialNumber = /\b([A-Z]{1,4}\s*\d+)\b/i.exec(text);
  if (specialNumber) return specialNumber[1].replace(/\s+/g, '');
  const stampNumber = /\bStamp Number\s+(\d+)\b/i.exec(text);
  if (stampNumber) return stampNumber[1];
  const plainNumber = /\b(?:No\.)?0*(\d{1,4})\b/i.exec(text);
  return plainNumber ? plainNumber[1] : text;
}

function unique(values) {
  return [...new Set(values.filter(Boolean))];
}

function candidateUrls(row, locale) {
  const setCode = maybeCardmarketSetCode(row.expansion_name, row.expansion_code);
  const expansion = expansionSlug(row.expansion_name);
  const name = cardNameSlug(row.name);
  const productCodes = collectorCandidates(row.expansion_number, setCode);
  const version = String(row.product_variant || '').trim();
  const versionMarkers =
    version && /^v\d+$/i.test(version) ? [version.toUpperCase(), ''] : [''];
  const nameOnlyCandidate =
    `https://www.cardmarket.com/${locale}/Pokemon/Products/Singles/${expansion}/${name}`;
  const candidates = likelyNameOnlyCardmarketSlug(row) ? [nameOnlyCandidate] : [];
  for (const productCode of productCodes) {
    for (const marker of versionMarkers) {
      const productSlug = [name, marker, productCode].filter(Boolean).join('-');
      candidates.push(
        `https://www.cardmarket.com/${locale}/Pokemon/Products/Singles/${expansion}/${productSlug}`,
      );
    }
  }
  candidates.push(nameOnlyCandidate);
  return unique(candidates);
}

function likelyNameOnlyCardmarketSlug(row) {
  const type = String(row.card_type || '').toLowerCase();
  if (/\b(trainer|supporter|item|stadium|tool|special energy|energy)\b/.test(type)) {
    return KNOWN_NAME_ONLY_TRAINER_EXPANSIONS.has(String(row.expansion_name || '').trim());
  }
  return (
    !type &&
    KNOWN_NAME_ONLY_TRAINER_EXPANSIONS.has(String(row.expansion_name || '').trim()) &&
    likelyTrainerName(row.name)
  );
}

function likelyTrainerName(name) {
  return /\b(box|center|stadium|machine|energy|switch|catcher|research|professor|potion|ball|rod|belt|badge|map|mail|ticket|search|gear|scrapper|blower|rope|hammer|patch|candy|vitality|schoolboy|youngster|shauna|janine|serena|copycat|switch|surprise)\b/i.test(String(name || ''));
}

async function verifyUrl(url) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8000);
  try {
    const response = await fetch(url, {
      method: 'HEAD',
      redirect: 'manual',
      signal: controller.signal,
      headers: {
        'user-agent':
          'Mozilla/5.0 (compatible; PokoinCardmarketAssociation/1.0; +https://pokoin.com)',
      },
    });
    return {
      status: response.status,
      ok: response.status >= 200 && response.status < 400,
      location: response.headers.get('location') || '',
    };
  } catch (error) {
    return { status: 0, ok: false, error: error.message };
  } finally {
    clearTimeout(timeout);
  }
}

async function sampleBlueprints(pool, limit) {
  const result = await pool.query(
    `
      select
        versions.card_id,
        versions.name,
        versions.expansion_name,
        versions.expansion_number,
        coalesce(nullif(versions.product_variant, ''), versions.inferred_product_variant) as product_variant,
        versions.product_type,
        expansions.code as expansion_code,
        cards.card_type
      from (
        select *
        from (
          select
            card_id,
            name,
            expansion_name,
            expansion_number,
            product_variant,
            case
              when count(*) over (partition by expansion_name, name) > 1
                then concat(
                  'v',
                  row_number() over (
                    partition by expansion_name, name
                    order by expansion_number_int nulls last, expansion_number, card_id
                  )
                )
              else ''
            end as inferred_product_variant,
            product_type
          from public.marketplace_card_versions
          where product_type = 'card'
            and expansion_name is not null
            and expansion_number is not null
            and name is not null
        ) ranked_versions
        order by random()
        limit $1
      ) versions
      left join public.cardtrader_pokemon_expansions expansions
        on expansions.name = versions.expansion_name
      left join public.marketplace_cards cards
        on cards.card_id = versions.card_id
    `,
    [limit],
  );
  return result.rows;
}

async function verifiedProductParsingByBlueprint(pool, rows, locale) {
  const blueprintIds = unique(rows.map((row) => String(row.card_id || '').trim()));
  if (!blueprintIds.length) return new Map();

  const result = await pool.query(
    `
      select
        blueprint_id,
        cardmarket_url,
        match_status
      from public.marketplace_cm_product_parsing
      where blueprint_id = any($1::bigint[])
        and cardmarket_locale = $2
        and match_status in ('verified', 'manual')
      order by verified_at desc nulls last, updated_at desc
    `,
    [blueprintIds, locale],
  );

  const byBlueprint = new Map();
  for (const row of result.rows) {
    const key = String(row.blueprint_id);
    if (!byBlueprint.has(key)) {
      byBlueprint.set(key, row);
    }
  }
  return byBlueprint;
}

function writeReport(rows, outputPath) {
  const confirmed = rows.filter((row) => row.verifiedUrl);
  const lines = [
    '# Cardmarket Association Sample Report',
    '',
    `Generated: ${new Date().toISOString()}`,
    `Sample size: ${rows.length}`,
    `Confirmed candidates: ${confirmed.length}`,
    '',
    '## Summary',
    '',
    '- Candidate URLs are generated from Oracle marketplace metadata.',
    '- Confirmation uses HTTP HEAD and may fail if Cardmarket blocks automated checks.',
    '- Unconfirmed rows should be manually checked before persisting mappings.',
    '',
    '## Rows',
    '',
    '| Blueprint ID | Card | Expansion | Number | Set code | Verified URL | First candidate | Status |',
    '| --- | --- | --- | --- | --- | --- | --- | --- |',
  ];
  for (const row of rows) {
    lines.push(
      [
        row.card_id,
        escapeCell(row.name),
        escapeCell(row.expansion_name),
        escapeCell(row.expansion_number),
        escapeCell(row.expansion_code || ''),
        row.verifiedUrl ? `[open](${row.verifiedUrl})` : '',
        row.candidates[0] ? `[candidate](${row.candidates[0]})` : '',
        row.verificationStatus,
      ].join(' | ').replace(/^/, '| ').replace(/$/, ' |'),
    );
  }
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, `${lines.join('\n')}\n`);
}

function escapeCell(value) {
  return String(value || '').replace(/\|/g, '\\|');
}

async function main() {
  const args = new Map();
  for (let index = 2; index < process.argv.length; index += 1) {
    const [key, value = '1'] = process.argv[index].split('=', 2);
    args.set(key.replace(/^--/, ''), value);
  }
  const env = { ...readEnv(path.join(ROOT_DIR, '.env.local')), ...process.env };
  const limit = cleanLimit(args.get('limit'));
  const connectionString = resolveDatabaseUrl(env, args);
  const locale = args.get('locale') || DEFAULT_LOCALE;
  const verify = args.get('verify') !== '0';
  const output =
    args.get('output') ||
    path.join(
      ROOT_DIR,
      'workflows',
      'reports',
      `cardmarket-association-sample-${new Date().toISOString().replace(/[:.]/g, '-')}.md`,
    );

  let pool = null;
  try {
    let rows = [];
    if (args.get('source') === 'api' || !connectionString) {
      rows = await fetchLiveApiRows(limit);
    } else {
      pool = new Pool({
        connectionString,
        max: 2,
        idleTimeoutMillis: 10_000,
        connectionTimeoutMillis: 10_000,
        ssl: { rejectUnauthorized: false },
      });
      try {
        rows = await sampleBlueprints(pool, limit);
      } catch (error) {
        console.warn(`Database sampling failed (${error.message}); falling back to live API.`);
        rows = await fetchLiveApiRows(limit);
      }
    }
    const verifiedMappings =
      pool && rows.length ? await verifiedProductParsingByBlueprint(pool, rows, locale) : new Map();
    const enriched = [];
    for (const row of rows) {
      const storedMapping = verifiedMappings.get(String(row.card_id));
      const candidates = unique([
        storedMapping?.cardmarket_url,
        ...candidateUrls(row, locale),
      ]);
      let verifiedUrl = storedMapping?.cardmarket_url || '';
      let verificationStatus = storedMapping
        ? `stored ${storedMapping.match_status}`
        : 'not verified';
      if (verify && !storedMapping) {
        verificationStatus = 'no candidate';
        for (const candidate of candidates.slice(0, 6)) {
          const result = await verifyUrl(candidate);
          verificationStatus = String(result.status || result.error || 'failed');
          if (result.ok) {
            verifiedUrl = candidate;
            break;
          }
        }
      }
      enriched.push({ ...row, candidates, verifiedUrl, verificationStatus });
    }
    writeReport(enriched, output);
    console.log(`Wrote ${path.relative(ROOT_DIR, output)}`);
    console.log(`Confirmed ${enriched.filter((row) => row.verifiedUrl).length}/${enriched.length}`);
  } finally {
    if (pool) {
      await pool.end();
    }
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message || error);
    process.exit(1);
  });
}

module.exports = {
  cardNameSlug,
  normalizedCollectorNumber,
  collectorCandidates,
  candidateUrls,
  maybeCardmarketSetCode,
};
