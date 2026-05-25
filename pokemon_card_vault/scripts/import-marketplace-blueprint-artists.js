#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { Pool } = require('pg');

const ROOT_DIR = path.resolve(__dirname, '..');
const POKOINPOS_ROOT = process.env.POKOINPOS_ROOT || '/Users/giuseppe/pokoinpos';
const DEFAULT_ORACLE_ENV = path.join(POKOINPOS_ROOT, 'deploy/env/peer4-postgres.env');
const DEFAULT_TCGDEX_BASE_URL = 'https://api.tcgdex.net';
const DEFAULT_BATCH_SIZE = 100;
const DEFAULT_CONCURRENCY = 8;

function cleanEnvValue(value) {
  const trimmed = String(value || '').trim();
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1).replace(/\\n/g, '\n');
  }
  return trimmed;
}

function loadEnvFile(filePath) {
  if (!filePath || !fs.existsSync(filePath)) return;
  for (const line of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const stripped = line.trim();
    if (!stripped || stripped.startsWith('#') || !stripped.includes('=')) continue;
    const separator = stripped.indexOf('=');
    const key = stripped.slice(0, separator).replace(/^export\s+/, '').trim();
    if (!key || process.env[key]) continue;
    process.env[key] = cleanEnvValue(stripped.slice(separator + 1));
  }
}

function loadLocalEnv() {
  loadEnvFile(path.join(ROOT_DIR, '.env.local'));
  loadEnvFile(DEFAULT_ORACLE_ENV);
}

function parsePositiveInt(value, fallback, { min = 1, max = Number.MAX_SAFE_INTEGER } = {}) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(Math.max(Math.trunc(number), min), max);
}

function parseLimit(value) {
  const raw = String(value ?? '100').trim().toLowerCase();
  if (raw === 'all' || raw === 'none') return Infinity;
  const limit = Number(raw);
  if (!Number.isFinite(limit) || limit < 1) {
    throw new Error('--limit must be a positive number or all.');
  }
  return Math.trunc(limit);
}

function parseArgs(argv) {
  const options = {
    apply: false,
    limit: 100,
    batchSize: DEFAULT_BATCH_SIZE,
    concurrency: DEFAULT_CONCURRENCY,
    startId: 0,
    language: 'en',
    tcgdexBaseUrl: DEFAULT_TCGDEX_BASE_URL,
    pokemonTcgDataDir: '',
    source: 'tcgdex',
    refreshExisting: false,
    reportMissing: false,
    reportEligibleOnly: false,
    writeMissingReport: '',
    reportSampleSize: 8,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith('--')) continue;
    const [rawKey, inlineValue] = token.slice(2).split('=', 2);
    const key = rawKey.trim();
    const value = inlineValue !== undefined
      ? inlineValue
      : argv[index + 1] && !argv[index + 1].startsWith('--')
        ? argv[++index]
        : true;
    if (key === 'apply') {
      options.apply = true;
    } else if (key === 'dry-run') {
      options.apply = false;
    } else if (key === 'limit') {
      options.limit = parseLimit(value);
    } else if (key === 'batch-size') {
      options.batchSize = parsePositiveInt(value, DEFAULT_BATCH_SIZE, { min: 1, max: 1000 });
    } else if (key === 'concurrency') {
      options.concurrency = parsePositiveInt(value, DEFAULT_CONCURRENCY, { min: 1, max: 100 });
    } else if (key === 'start-id') {
      options.startId = parsePositiveInt(value, 0, { min: 0 });
    } else if (key === 'language') {
      options.language = cleanText(value, 12).toLowerCase() || 'en';
    } else if (key === 'tcgdex-base-url') {
      options.tcgdexBaseUrl = String(value || '').replace(/\/+$/, '') || DEFAULT_TCGDEX_BASE_URL;
    } else if (key === 'pokemon-tcg-data-dir') {
      options.pokemonTcgDataDir = String(value || '').trim();
    } else if (key === 'source') {
      options.source = cleanText(value, 40).toLowerCase() || 'tcgdex';
    } else if (key === 'refresh-existing') {
      options.refreshExisting = true;
    } else if (key === 'report-missing') {
      options.reportMissing = true;
    } else if (key === 'report-eligible-only') {
      options.reportMissing = true;
      options.reportEligibleOnly = true;
    } else if (key === 'write-missing-report') {
      if (value === true) throw new Error('--write-missing-report requires a path.');
      options.reportMissing = true;
      options.writeMissingReport = String(value || '').trim();
    } else if (key === 'report-sample-size') {
      options.reportSampleSize = parsePositiveInt(value, 8, { min: 1, max: 100 });
    }
  }

  if (!/^[a-z]{2}(?:-[a-z]{2})?$/.test(options.language)) {
    throw new Error('--language must be a language code such as en.');
  }
  if (!['tcgdex', 'pokemon_tcg_data', 'all'].includes(options.source)) {
    throw new Error('--source must be tcgdex, pokemon_tcg_data, or all.');
  }
  if (options.reportMissing && options.apply) {
    throw new Error('--report-missing is read-only and cannot be combined with --apply.');
  }
  return options;
}

function cleanText(value, maxLength = 160) {
  return String(value || '').trim().replace(/\s+/g, ' ').slice(0, maxLength);
}

function normalizeText(value) {
  return cleanText(value, 500)
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[’']/g, '')
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/\b(pokemon|pokémon)\b/g, 'pokemon')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

function compactText(value) {
  return normalizeText(value).replace(/[^a-z0-9]/g, '');
}

function normalizeArtist(value) {
  return normalizeText(value)
    .replace(/\billus(?:trator)?\b/g, ' ')
    .replace(/\bartist\b/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function normalizeCollectorNumber(value) {
  let text = cleanText(value, 120);
  if (!text) return '';
  if (text.includes('|')) text = text.split('|').pop();
  text = text
    .replace(/^#/, '')
    .replace(/\b(no\.?|number)\b/gi, ' ')
    .trim();
  const slashMatch = text.match(/([A-Za-z]*\s*[0-9]+[A-Za-z]?)\s*\/\s*[0-9]+/);
  if (slashMatch) text = slashMatch[1];
  const codeMatch = text.match(/([A-Za-z]{1,8}\s*[0-9]+[A-Za-z]?)/);
  if (codeMatch) text = codeMatch[1];
  const numberMatch = text.match(/([0-9]+[A-Za-z]?)/);
  if (numberMatch && !/[A-Za-z]/.test(text.slice(0, 3))) text = numberMatch[1];
  return text.toUpperCase().replace(/[^A-Z0-9]/g, '').replace(/^0+(?=\d)/, '');
}

function normalizedRarity(value) {
  return normalizeText(value)
    .replace(/\billustration rare\b/g, 'illustration rare')
    .replace(/\bspecial illustration rare\b/g, 'special illustration rare');
}

function rowFromBlueprint(row) {
  const blueprint = row.blueprint && typeof row.blueprint === 'object' ? row.blueprint : {};
  const expansion = row.expansion && typeof row.expansion === 'object' ? row.expansion : {};
  return {
    blueprintId: String(row.blueprint_id || row.id || '').trim(),
    cardId: String(row.card_id || row.blueprint_id || row.id || '').trim(),
    name: cleanText(row.name || row.display_name || blueprint.name),
    setName: cleanText(row.set_name || expansion.name || blueprint.expansion_name),
    setCode: cleanText(row.expansion_code || expansion.code || blueprint.expansion_code || blueprint.set_code),
    collectorNumber: cleanText(
      row.card_number ||
        blueprint.number ||
        blueprint.collector_number ||
        blueprint.card_number ||
        row.version,
    ),
    rarity: cleanText(row.rarity || blueprint.rarity || blueprint.collector_rarity),
    itemKind: cleanText(row.item_kind || 'single', 40),
    productType: cleanText(row.product_type || 'card', 40),
    hasArtist: Boolean(row.artist_blueprint_id),
  };
}

function createPoolFromEnv() {
  const connectionString = process.env.MARKETPLACE_DATABASE_URL ||
    process.env.MARKETPLACE_PEER4_DATABASE_URL ||
    '';
  const sslVerify = process.env.MARKETPLACE_DATABASE_SSL_VERIFY === '1';
  if (connectionString) {
    const sanitizedConnectionString = sslVerify
      ? connectionString
      : connectionString.replace(/([?&])sslmode=[^&]+&?/i, (match, prefix) =>
          prefix === '?' && match.endsWith('&') ? '?' : prefix === '?' ? '' : '',
        ).replace(/[?&]$/, '');
    return new Pool({
      connectionString: sanitizedConnectionString,
      max: 4,
      idleTimeoutMillis: 10_000,
      connectionTimeoutMillis: 10_000,
      ssl: { rejectUnauthorized: sslVerify },
      application_name: 'marketplace-blueprint-artists-import',
    });
  }
  for (const key of [
    'MARKETPLACE_DB_PUBLIC_HOST',
    'MARKETPLACE_DB_USER',
    'MARKETPLACE_DB_PASSWORD',
    'MARKETPLACE_DB_NAME',
  ]) {
    if (!process.env[key]) {
      throw new Error('MARKETPLACE_DATABASE_URL or peer4 MARKETPLACE_DB_* env is required.');
    }
  }
  return new Pool({
    host: process.env.MARKETPLACE_DB_PUBLIC_HOST,
    port: Number(process.env.MARKETPLACE_DB_PORT || 5432),
    database: process.env.MARKETPLACE_DB_NAME,
    user: process.env.MARKETPLACE_DB_USER,
    password: process.env.MARKETPLACE_DB_PASSWORD,
    max: 4,
    idleTimeoutMillis: 10_000,
    connectionTimeoutMillis: 10_000,
    ssl: { rejectUnauthorized: sslVerify },
    application_name: 'marketplace-blueprint-artists-import',
  });
}

async function assertWritablePrimary(pool, { apply }) {
  const result = await pool.query(`
    select
      pg_is_in_recovery() as in_recovery,
      current_database() as database_name
  `);
  const status = result.rows[0] || {};
  if (apply && status.in_recovery) {
    throw new Error('Refusing --apply because the configured marketplace database is in recovery/read-only mode.');
  }
  return status;
}

async function fetchBlueprintRows(pool, options, startId, limit) {
  const result = await pool.query(
    `
      select
        b.id as blueprint_id,
        coalesce(c.card_id, b.id) as card_id,
        coalesce(nullif(c.display_name, ''), nullif(c.name, ''), b.name) as name,
        coalesce(nullif(c.set_name, ''), nullif(b.expansion->>'name', ''), nullif(b.blueprint->>'expansion_name', '')) as set_name,
        coalesce(nullif(b.expansion->>'code', ''), nullif(b.blueprint->>'expansion_code', ''), nullif(b.blueprint->>'set_code', '')) as expansion_code,
        coalesce(nullif(c.card_number, ''), nullif(b.blueprint->>'number', ''), nullif(b.blueprint->>'collector_number', ''), nullif(b.blueprint->>'card_number', ''), b.version, '') as card_number,
        coalesce(nullif(c.rarity, ''), nullif(b.blueprint->>'rarity', ''), nullif(b.blueprint->>'collector_rarity', ''), '') as rarity,
        coalesce(nullif(c.item_kind, ''), 'single') as item_kind,
        coalesce(nullif(c.product_type, ''), 'card') as product_type,
        b.blueprint,
        b.expansion,
        b.version
      from public.cardtrader_pokemon_blueprints b
      left join public.marketplace_search_candidates c
        on c.card_id = b.id
      left join public.marketplace_blueprint_artists artist
        on artist.blueprint_id = b.id
      where b.id > $1::bigint
        and ($2::boolean or artist.blueprint_id is null)
        and (
          $3::boolean = false
          or (
            coalesce(nullif(c.item_kind, ''), 'single') <> 'product'
            and coalesce(nullif(c.product_type, ''), 'card') = 'card'
            and coalesce(nullif(c.display_name, ''), nullif(c.name, ''), b.name, '') <> ''
            and (
              coalesce(nullif(c.set_name, ''), nullif(b.expansion->>'name', ''), nullif(b.blueprint->>'expansion_name', '')) <> ''
              or coalesce(nullif(b.expansion->>'code', ''), nullif(b.blueprint->>'expansion_code', ''), nullif(b.blueprint->>'set_code', '')) <> ''
            )
            and coalesce(nullif(c.card_number, ''), nullif(b.blueprint->>'number', ''), nullif(b.blueprint->>'collector_number', ''), nullif(b.blueprint->>'card_number', ''), b.version, '') <> ''
          )
        )
      order by b.id asc
      limit $4::integer
    `,
    [startId, options.refreshExisting, options.reportEligibleOnly, limit],
  );
  return result.rows.map(rowFromBlueprint);
}

async function fetchReportBlueprintRows(pool, options, startId, limit) {
  const result = await pool.query(
    `
      select
        b.id as blueprint_id,
        coalesce(c.card_id, b.id) as card_id,
        coalesce(nullif(c.display_name, ''), nullif(c.name, ''), b.name) as name,
        coalesce(nullif(c.set_name, ''), nullif(b.expansion->>'name', ''), nullif(b.blueprint->>'expansion_name', '')) as set_name,
        coalesce(nullif(b.expansion->>'code', ''), nullif(b.blueprint->>'expansion_code', ''), nullif(b.blueprint->>'set_code', '')) as expansion_code,
        coalesce(nullif(c.card_number, ''), nullif(b.blueprint->>'number', ''), nullif(b.blueprint->>'collector_number', ''), nullif(b.blueprint->>'card_number', ''), b.version, '') as card_number,
        coalesce(nullif(c.rarity, ''), nullif(b.blueprint->>'rarity', ''), nullif(b.blueprint->>'collector_rarity', ''), '') as rarity,
        coalesce(nullif(c.item_kind, ''), 'single') as item_kind,
        coalesce(nullif(c.product_type, ''), 'card') as product_type,
        artist.blueprint_id as artist_blueprint_id,
        b.blueprint,
        b.expansion,
        b.version
      from public.cardtrader_pokemon_blueprints b
      left join public.marketplace_search_candidates c
        on c.card_id = b.id
      left join public.marketplace_blueprint_artists artist
        on artist.blueprint_id = b.id
      where b.id > $1::bigint
        and ($2::boolean or artist.blueprint_id is null)
        and (
          $3::boolean = false
          or (
            coalesce(nullif(c.item_kind, ''), 'single') <> 'product'
            and coalesce(nullif(c.product_type, ''), 'card') = 'card'
            and coalesce(nullif(c.display_name, ''), nullif(c.name, ''), b.name, '') <> ''
            and (
              coalesce(nullif(c.set_name, ''), nullif(b.expansion->>'name', ''), nullif(b.blueprint->>'expansion_name', '')) <> ''
              or coalesce(nullif(b.expansion->>'code', ''), nullif(b.blueprint->>'expansion_code', ''), nullif(b.blueprint->>'set_code', '')) <> ''
            )
            and coalesce(nullif(c.card_number, ''), nullif(b.blueprint->>'number', ''), nullif(b.blueprint->>'collector_number', ''), nullif(b.blueprint->>'card_number', ''), b.version, '') <> ''
          )
        )
      order by b.id asc
      limit $4::integer
    `,
    [startId, options.refreshExisting, options.reportEligibleOnly, limit],
  );
  return result.rows.map(rowFromBlueprint);
}

function shouldSkipBlueprint(row) {
  if (!row.blueprintId) return 'missing_blueprint_id';
  if (row.itemKind === 'product' || row.productType !== 'card') return 'non_card_product';
  if (!row.name) return 'missing_name';
  if (!row.setName && !row.setCode) return 'missing_set';
  if (!row.collectorNumber) return 'missing_collector_number';
  return '';
}

function createLimiter(concurrency) {
  let active = 0;
  const queue = [];
  function drain() {
    while (active < concurrency && queue.length > 0) {
      const item = queue.shift();
      active += 1;
      item.fn()
        .then(item.resolve, item.reject)
        .finally(() => {
          active -= 1;
          drain();
        });
    }
  }
  return function limit(fn) {
    return new Promise((resolve, reject) => {
      queue.push({ fn, resolve, reject });
      drain();
    });
  };
}

class TcgDexClient {
  constructor(options) {
    this.baseUrl = options.tcgdexBaseUrl.replace(/\/+$/, '');
    this.language = options.language;
    this.limit = createLimiter(options.concurrency);
    this.cache = new Map();
  }

  async getJson(pathname) {
    const key = pathname;
    if (!this.cache.has(key)) {
      this.cache.set(key, this.limit(async () => {
        const url = `${this.baseUrl}/v2/${this.language}${pathname}`;
        const response = await fetch(url, {
          headers: { accept: 'application/json', 'user-agent': 'PokoinArtistImporter/1.0' },
        });
        if (response.status === 404) return null;
        if (response.status === 429) {
          const error = new Error(`TCGdex rate limited ${pathname}`);
          error.code = 'tcgdex_rate_limited';
          throw error;
        }
        if (!response.ok) {
          throw new Error(`TCGdex request failed ${response.status} for ${pathname}`);
        }
        return response.json();
      }));
    }
    return this.cache.get(key);
  }

  async sets() {
    return this.getJson('/sets');
  }

  async set(id) {
    return this.getJson(`/sets/${encodeURIComponent(id)}`);
  }

  async card(id) {
    return this.getJson(`/cards/${encodeURIComponent(id)}`);
  }
}

function buildSetIndex(sets) {
  const byCompactName = new Map();
  const byId = new Map();
  for (const set of sets || []) {
    const normalized = {
      id: cleanText(set.id, 80),
      name: cleanText(set.name, 160),
      compactName: compactText(set.name),
      normalizedName: normalizeText(set.name),
    };
    if (!normalized.id) continue;
    byId.set(normalized.id.toLowerCase(), normalized);
    const bucket = byCompactName.get(normalized.compactName) || [];
    bucket.push(normalized);
    byCompactName.set(normalized.compactName, bucket);
  }
  return { byCompactName, byId };
}

function findSetMatch(row, setIndex) {
  const code = compactText(row.setCode);
  if (code && setIndex.byId.has(code)) {
    return { set: setIndex.byId.get(code), reason: 'set_code_exact' };
  }
  const compactName = compactText(row.setName);
  const exact = setIndex.byCompactName.get(compactName) || [];
  if (exact.length === 1) return { set: exact[0], reason: 'set_name_exact' };
  if (exact.length > 1) {
    const codeMatch = exact.find((set) => code && compactText(set.id) === code);
    if (codeMatch) return { set: codeMatch, reason: 'set_name_and_code' };
    return { ambiguous: true, reason: 'ambiguous_set_name', candidates: exact };
  }
  const fuzzy = [];
  for (const bucket of setIndex.byCompactName.values()) {
    for (const set of bucket) {
      if (
        compactName &&
        (set.compactName.includes(compactName) || compactName.includes(set.compactName))
      ) {
        fuzzy.push(set);
      }
    }
  }
  if (fuzzy.length === 1) return { set: fuzzy[0], reason: 'set_name_contains' };
  if (fuzzy.length > 1) return { ambiguous: true, reason: 'ambiguous_set_name_contains', candidates: fuzzy };
  return { reason: 'set_not_found' };
}

function nameScore(sourceName, candidateName) {
  const source = normalizeText(sourceName);
  const candidate = normalizeText(candidateName);
  if (!source || !candidate) return 0;
  if (source === candidate) return 1;
  const sourceCompact = compactText(source);
  const candidateCompact = compactText(candidate);
  if (sourceCompact === candidateCompact) return 0.96;
  if (sourceCompact.includes(candidateCompact) || candidateCompact.includes(sourceCompact)) return 0.82;
  const sourceTokens = new Set(source.split(' ').filter(Boolean));
  const candidateTokens = candidate.split(' ').filter(Boolean);
  if (candidateTokens.length === 0) return 0;
  const hits = candidateTokens.filter((token) => sourceTokens.has(token)).length;
  return hits / Math.max(sourceTokens.size, candidateTokens.length);
}

function rarityScore(sourceRarity, candidateRarity) {
  const source = normalizedRarity(sourceRarity);
  const candidate = normalizedRarity(candidateRarity);
  if (!source || !candidate) return 0.04;
  if (source === candidate) return 1;
  if (source.includes(candidate) || candidate.includes(source)) return 0.75;
  return 0;
}

function scoreCandidate(row, detail, setReason) {
  const collectorMatches = normalizeCollectorNumber(row.collectorNumber) ===
    normalizeCollectorNumber(detail.localId);
  const score = (
    (collectorMatches ? 0.44 : 0) +
    nameScore(row.name, detail.name) * 0.34 +
    rarityScore(row.rarity, detail.rarity) * 0.10 +
    (setReason === 'set_code_exact' || setReason === 'set_name_and_code' ? 0.08 : 0.04)
  );
  return Math.min(score, 1);
}

function bestCandidate(row, details, setReason) {
  const scored = details
    .filter((detail) => cleanText(detail?.illustrator || detail?.artist))
    .map((detail) => ({
      detail,
      confidence: scoreCandidate(row, detail, setReason),
    }))
    .sort((a, b) => b.confidence - a.confidence);
  if (scored.length === 0) return { status: 'not_found', reason: 'missing_illustrator' };
  const [best, second] = scored;
  if (best.confidence < 0.78) {
    return { status: 'not_found', reason: 'low_confidence', best };
  }
  if (
    second &&
    second.confidence >= best.confidence - 0.04 &&
    second.detail.id !== best.detail.id &&
    cleanText(second.detail.illustrator) !== cleanText(best.detail.illustrator)
  ) {
    return { status: 'ambiguous', reason: 'close_candidate_scores', best, second };
  }
  return { status: 'matched', best };
}

async function matchWithTcgdex(row, context) {
  const setMatch = findSetMatch(row, context.tcgdex.setIndex);
  if (setMatch.ambiguous) {
    return { status: 'ambiguous', source: 'tcgdex', reason: setMatch.reason };
  }
  if (!setMatch.set) {
    return { status: 'not_found', source: 'tcgdex', reason: setMatch.reason };
  }

  const setDetail = await context.tcgdex.client.set(setMatch.set.id);
  const cards = Array.isArray(setDetail?.cards) ? setDetail.cards : [];
  const collector = normalizeCollectorNumber(row.collectorNumber);
  const candidates = cards.filter((card) => normalizeCollectorNumber(card.localId) === collector);
  const candidateCards = candidates.length > 0
    ? candidates
    : cards.filter((card) => nameScore(row.name, card.name) >= 0.96).slice(0, 8);
  if (candidateCards.length === 0) {
    return { status: 'not_found', source: 'tcgdex', reason: 'card_not_found_in_set' };
  }

  const details = (await Promise.all(
    candidateCards.slice(0, 8).map((card) => context.tcgdex.client.card(card.id)),
  )).filter(Boolean);
  const selected = bestCandidate(row, details, setMatch.reason);
  if (selected.status !== 'matched') {
    return { ...selected, source: 'tcgdex', reason: selected.reason };
  }
  const detail = selected.best.detail;
  const artist = cleanText(detail.illustrator || detail.artist, 180);
  return {
    status: 'matched',
    source: 'tcgdex',
    artist,
    illustrator: artist,
    normalizedArtist: normalizeArtist(artist),
    sourceCardId: cleanText(detail.id, 120),
    sourceUrl: `${context.options.tcgdexBaseUrl.replace(/\/+$/, '')}/v2/${context.options.language}/cards/${encodeURIComponent(detail.id)}`,
    confidence: selected.best.confidence,
    matchReason: [
      setMatch.reason,
      'collector_number',
      nameScore(row.name, detail.name) >= 0.96 ? 'name_exact' : 'name_similar',
      detail.rarity ? 'rarity_checked' : 'rarity_missing',
    ].join(';'),
    rawMetadata: {
      sourceCard: {
        id: detail.id,
        localId: detail.localId,
        name: detail.name,
        rarity: detail.rarity || '',
        set: detail.set || null,
      },
      input: row,
    },
  };
}

function collectJsonFiles(directory, results = []) {
  if (!directory || !fs.existsSync(directory)) return results;
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) collectJsonFiles(fullPath, results);
    if (entry.isFile() && entry.name.endsWith('.json')) results.push(fullPath);
  }
  return results;
}

function findPokemonTcgSetsFile(directory) {
  const candidates = [
    path.join(directory, 'sets', 'en.json'),
    path.join(directory, '..', 'sets', 'en.json'),
    path.join(directory, '..', '..', 'sets', 'en.json'),
  ];
  return candidates.find((candidate) => fs.existsSync(candidate)) || '';
}

function loadPokemonTcgSetIndex(directory) {
  const setsFile = findPokemonTcgSetsFile(directory);
  const byId = new Map();
  if (!setsFile) return { byId };
  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(setsFile, 'utf8'));
  } catch (_) {
    return { byId };
  }
  for (const set of Array.isArray(parsed) ? parsed : []) {
    const id = cleanText(set.id, 80);
    if (!id) continue;
    byId.set(id.toLowerCase(), {
      id,
      name: cleanText(set.name, 160),
      ptcgoCode: cleanText(set.ptcgoCode, 40),
    });
  }
  return { byId };
}

function pokemonTcgSetAliasesForFile(file, setIndex) {
  const aliases = new Set();
  const fileSetId = path.basename(file, '.json').toLowerCase();
  const set = setIndex.byId.get(fileSetId);
  for (const value of [fileSetId, set?.id, set?.name, set?.ptcgoCode]) {
    const alias = cleanText(value, 160);
    if (alias) aliases.add(alias);
  }
  return aliases;
}

function collectorNumberCandidates(value) {
  const text = cleanText(value, 120);
  const candidates = new Set([normalizeCollectorNumber(text)]);
  const afterPipe = text.includes('|') ? text.split('|').pop() : '';
  if (afterPipe) candidates.add(normalizeCollectorNumber(afterPipe));
  const slashMatch = text.match(/([0-9]+[A-Za-z]?)\s*\/\s*[0-9]+/);
  if (slashMatch) candidates.add(normalizeCollectorNumber(slashMatch[1]));
  const simpleMatch = text.match(/\b([0-9]+[A-Za-z]?)\b/);
  if (simpleMatch) candidates.add(normalizeCollectorNumber(simpleMatch[1]));
  return [...candidates].filter(Boolean);
}

function loadPokemonTcgDataIndex(directory) {
  const bySetNumber = new Map();
  const setIndex = loadPokemonTcgSetIndex(directory);
  for (const file of collectJsonFiles(directory)) {
    let parsed;
    try {
      parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch (_) {
      continue;
    }
    const fileSetAliases = pokemonTcgSetAliasesForFile(file, setIndex);
    const cards = Array.isArray(parsed) ? parsed : Array.isArray(parsed.data) ? parsed.data : [];
    for (const card of cards) {
      const artist = cleanText(card.artist || card.illustrator);
      const setNames = new Set(fileSetAliases);
      for (const value of [card.set?.name, card.setName, card.expansion, card.set?.id, card.set?.ptcgoCode]) {
        const setName = cleanText(value);
        if (setName) setNames.add(setName);
      }
      const numbers = collectorNumberCandidates(card.number || card.localId);
      if (!artist || setNames.size === 0 || numbers.length === 0) continue;
      for (const setName of setNames) {
        for (const number of numbers) {
          const key = `${compactText(setName)}:${number}`;
          const bucket = bySetNumber.get(key) || [];
          bucket.push(card);
          bySetNumber.set(key, bucket);
        }
      }
    }
  }
  return { bySetNumber };
}

function matchWithPokemonTcgData(row, index, knownArtists = new Set()) {
  if (!index) return { status: 'not_found', source: 'pokemon_tcg_data', reason: 'dataset_not_configured' };
  const setNames = [row.setName, row.setCode].map((value) => cleanText(value)).filter(Boolean);
  const numbers = collectorNumberCandidates(row.collectorNumber);
  const candidatesById = new Map();
  for (const setName of setNames) {
    for (const number of numbers) {
      const key = `${compactText(setName)}:${number}`;
      for (const card of index.bySetNumber.get(key) || []) {
        candidatesById.set(cleanText(card.id, 120) || `${card.name}:${card.number}`, card);
      }
    }
  }
  const candidates = [...candidatesById.values()];
  if (candidates.length === 0) {
    return { status: 'not_found', source: 'pokemon_tcg_data', reason: 'card_not_found' };
  }
  const scored = candidates
    .map((card) => ({
      card,
      confidence: 0.54 + nameScore(row.name, card.name) * 0.34 + rarityScore(row.rarity, card.rarity) * 0.08,
    }))
    .sort((a, b) => b.confidence - a.confidence);
  const [best, second] = scored;
  if (!best || best.confidence < 0.78) return { status: 'not_found', source: 'pokemon_tcg_data', reason: 'low_confidence' };
  const artist = cleanText(best.card.artist || best.card.illustrator, 180);
  const normalizedArtist = normalizeArtist(artist);
  if (!knownArtists.has(normalizedArtist)) {
    return {
      status: 'not_found',
      source: 'pokemon_tcg_data',
      reason: 'unknown_artist_not_in_artist_table',
      best,
    };
  }
  if (second && second.confidence >= best.confidence - 0.04 && cleanText(second.card.artist) !== artist) {
    return { status: 'ambiguous', source: 'pokemon_tcg_data', reason: 'close_candidate_scores' };
  }
  return {
    status: 'matched',
    source: 'pokemon_tcg_data',
    artist,
    illustrator: artist,
    normalizedArtist,
    sourceCardId: cleanText(best.card.id, 120),
    sourceUrl: cleanText(best.card.url || best.card.tcgplayer?.url || '', 1000),
    confidence: Math.min(best.confidence, 1),
    matchReason: 'local_dataset;set_number;name_checked',
    rawMetadata: {
      sourceCard: {
        id: best.card.id || '',
        number: best.card.number || '',
        name: best.card.name || '',
        rarity: best.card.rarity || '',
        set: best.card.set || null,
      },
      input: row,
    },
  };
}

async function matchArtist(row, context) {
  const skipReason = shouldSkipBlueprint(row);
  if (skipReason) return { status: 'skipped', reason: skipReason };
  const sources = context.options.source === 'all'
    ? ['tcgdex', 'pokemon_tcg_data']
    : [context.options.source];
  let lastResult = null;
  for (const source of sources) {
    const result = source === 'tcgdex'
      ? await matchWithTcgdex(row, context)
      : matchWithPokemonTcgData(row, context.pokemonTcgData, context.knownArtists);
    if (result.status === 'matched') return result;
    if (result.status === 'ambiguous') return result;
    lastResult = result;
  }
  return lastResult || { status: 'not_found', reason: 'no_sources' };
}

function upsertArtistsSql(rowCount) {
  const columns = [
    'blueprint_id',
    'artist',
    'illustrator',
    'normalized_artist',
    'source',
    'source_card_id',
    'source_url',
    'confidence',
    'match_reason',
    'raw_metadata',
  ];
  const valueRows = [];
  let parameter = 1;
  for (let rowIndex = 0; rowIndex < rowCount; rowIndex += 1) {
    const placeholders = [];
    for (let columnIndex = 0; columnIndex < columns.length; columnIndex += 1) {
      placeholders.push(`$${parameter++}`);
    }
    valueRows.push(`(${placeholders.join(', ')})`);
  }
  return `
    insert into public.marketplace_blueprint_artists (${columns.join(', ')})
    values ${valueRows.join(', ')}
    on conflict (blueprint_id) do update set
      artist = excluded.artist,
      illustrator = excluded.illustrator,
      normalized_artist = excluded.normalized_artist,
      source = excluded.source,
      source_card_id = excluded.source_card_id,
      source_url = excluded.source_url,
      confidence = excluded.confidence,
      match_reason = excluded.match_reason,
      matched_at = now(),
      raw_metadata = excluded.raw_metadata,
      updated_at = now()
  `;
}

function upsertValues(rows) {
  return rows.flatMap((row) => [
    row.blueprintId,
    row.artist,
    row.illustrator,
    row.normalizedArtist,
    row.source,
    row.sourceCardId || '',
    row.sourceUrl || '',
    row.confidence,
    row.matchReason || '',
    JSON.stringify(row.rawMetadata || {}),
  ]);
}

async function upsertArtistRows(pool, rows, batchSize) {
  let upserted = 0;
  for (let offset = 0; offset < rows.length; offset += batchSize) {
    const batch = rows.slice(offset, offset + batchSize);
    await pool.query(upsertArtistsSql(batch.length), upsertValues(batch));
    upserted += batch.length;
  }
  await pool.query('select public.refresh_marketplace_artist_card_counts()');
  return upserted;
}

async function verifyArtists(pool) {
  const result = await pool.query(`
    select
      count(*)::integer as artist_rows,
      count(*) filter (where source = 'tcgdex')::integer as tcgdex_rows,
      count(*) filter (where source = 'pokemon_tcg_data')::integer as pokemon_tcg_data_rows,
      count(distinct normalized_artist)::integer as distinct_artists,
      max(matched_at) as last_matched_at
    from public.marketplace_blueprint_artists
  `);
  return result.rows[0] || {};
}

async function fetchKnownArtists(pool) {
  const result = await pool.query(`
    select distinct normalized_artist
    from public.marketplace_blueprint_artists
    where coalesce(normalized_artist, '') <> ''
  `);
  return new Set(result.rows.map((row) => cleanText(row.normalized_artist, 240)));
}

async function fetchArtistCoverage(pool) {
  const result = await pool.query(`
    with rows as (
      select
        b.id,
        coalesce(c.card_id, b.id) as card_id,
        coalesce(nullif(c.display_name, ''), nullif(c.name, ''), b.name) as name,
        coalesce(nullif(c.set_name, ''), nullif(b.expansion->>'name', ''), nullif(b.blueprint->>'expansion_name', '')) as set_name,
        coalesce(nullif(b.expansion->>'code', ''), nullif(b.blueprint->>'expansion_code', ''), nullif(b.blueprint->>'set_code', '')) as expansion_code,
        coalesce(nullif(c.card_number, ''), nullif(b.blueprint->>'number', ''), nullif(b.blueprint->>'collector_number', ''), nullif(b.blueprint->>'card_number', ''), b.version, '') as card_number,
        coalesce(nullif(c.item_kind, ''), 'single') as item_kind,
        coalesce(nullif(c.product_type, ''), 'card') as product_type,
        artist.blueprint_id as artist_blueprint_id
      from public.cardtrader_pokemon_blueprints b
      left join public.marketplace_search_candidates c
        on c.card_id = b.id
      left join public.marketplace_blueprint_artists artist
        on artist.blueprint_id = b.id
    )
    select
      count(*)::integer as total_blueprints,
      count(*) filter (where artist_blueprint_id is not null)::integer as artist_rows,
      count(*) filter (where artist_blueprint_id is null)::integer as missing_artist_rows,
      count(*) filter (
        where artist_blueprint_id is null
          and item_kind <> 'product'
          and product_type = 'card'
          and coalesce(name, '') <> ''
          and (coalesce(set_name, '') <> '' or coalesce(expansion_code, '') <> '')
          and coalesce(card_number, '') <> ''
      )::integer as missing_eligible_rows,
      count(*) filter (where artist_blueprint_id is null and (item_kind = 'product' or product_type <> 'card'))::integer as missing_non_card_product_rows,
      count(*) filter (where artist_blueprint_id is null and coalesce(name, '') = '')::integer as missing_name_rows,
      count(*) filter (where artist_blueprint_id is null and coalesce(set_name, '') = '' and coalesce(expansion_code, '') = '')::integer as missing_set_rows,
      count(*) filter (where artist_blueprint_id is null and coalesce(card_number, '') = '')::integer as missing_collector_number_rows
    from rows
  `);
  return result.rows[0] || {};
}

function addCount(map, key, amount = 1) {
  map[key] = (map[key] || 0) + amount;
}

function canonicalMissingReason(status, reason) {
  const code = cleanText(reason || status || 'unknown', 120);
  if (status === 'matched') return 'would_match';
  if (status === 'error') return 'source_error';
  if (code === 'skipped_existing') return 'skipped_existing';
  if (code === 'set_not_found') return 'set_not_found';
  if (code === 'card_not_found' || code === 'card_not_found_in_set') return 'card_not_found';
  if (code === 'missing_illustrator') return 'missing_illustrator';
  if (code === 'low_confidence') return 'low_confidence';
  if (code === 'ambiguous_set_name' || code === 'ambiguous_set_name_contains') return 'ambiguous_set';
  if (code === 'close_candidate_scores') return 'ambiguous_card';
  if (code === 'tcgdex_rate_limited' || code === 'dataset_not_configured' || code.includes('request failed')) {
    return 'source_error';
  }
  if (code === 'unknown_artist_not_in_artist_table') return 'unknown_artist_not_in_artist_table';
  if (code.startsWith('missing_') || code === 'non_card_product') return code;
  return status || code;
}

function sampleMissingRow(row, result, canonicalReason) {
  const sample = {
    blueprintId: row.blueprintId,
    name: row.name,
    setName: row.setName,
    setCode: row.setCode,
    collectorNumber: row.collectorNumber,
    rarity: row.rarity,
    status: result.status,
    reason: result.reason || '',
    canonicalReason,
  };
  if (result.source) sample.source = result.source;
  if (result.confidence !== undefined) sample.confidence = Number(result.confidence.toFixed(3));
  if (result.best?.confidence !== undefined) sample.bestConfidence = Number(result.best.confidence.toFixed(3));
  if (result.best?.detail?.id) sample.bestSourceCardId = cleanText(result.best.detail.id, 120);
  if (result.second?.confidence !== undefined) sample.secondConfidence = Number(result.second.confidence.toFixed(3));
  if (result.second?.detail?.id) sample.secondSourceCardId = cleanText(result.second.detail.id, 120);
  if (result.artist) sample.artist = result.artist;
  return sample;
}

async function reportMissingArtists({ pool, options, context }) {
  const coverage = await fetchArtistCoverage(pool);
  const counts = {
    scanned: 0,
    wouldMatch: 0,
    ambiguous: 0,
    notFound: 0,
    skipped: 0,
    errors: 0,
    sources: {},
    reasons: {},
    canonicalReasons: {},
  };
  const samplesByReason = {};
  let cursor = options.startId;
  const limit = createLimiter(options.concurrency);

  while (counts.scanned < options.limit) {
    const remaining = options.limit === Infinity
      ? options.batchSize
      : Math.min(options.batchSize, options.limit - counts.scanned);
    if (remaining <= 0) break;
    const rows = await fetchReportBlueprintRows(pool, options, cursor, remaining);
    if (rows.length === 0) break;
    counts.scanned += rows.length;
    cursor = Math.max(cursor, ...rows.map((row) => Number(row.blueprintId || 0)));

    const results = await Promise.all(rows.map((row) => limit(async () => {
      try {
        if (row.hasArtist) {
          return { row, result: { status: 'skipped', reason: 'skipped_existing' } };
        }
        const result = await matchArtist(row, context);
        return { row, result };
      } catch (error) {
        return { row, result: { status: 'error', reason: error.code || error.message || 'error' } };
      }
    })));

    for (const { row, result } of results) {
      const canonicalReason = canonicalMissingReason(result.status, result.reason || result.matchReason);
      addCount(counts.reasons, result.reason || result.matchReason || result.status);
      addCount(counts.canonicalReasons, canonicalReason);
      if (result.status === 'matched') {
        counts.wouldMatch += 1;
        addCount(counts.sources, result.source);
      } else if (result.status === 'ambiguous') {
        counts.ambiguous += 1;
      } else if (result.status === 'skipped') {
        counts.skipped += 1;
      } else if (result.status === 'error') {
        counts.errors += 1;
      } else {
        counts.notFound += 1;
      }
      const bucket = samplesByReason[canonicalReason] || [];
      if (bucket.length < options.reportSampleSize) {
        bucket.push(sampleMissingRow(row, result, canonicalReason));
        samplesByReason[canonicalReason] = bucket;
      }
    }

    console.log(JSON.stringify({
      reportProgress: {
        scanned: counts.scanned,
        wouldMatch: counts.wouldMatch,
        ambiguous: counts.ambiguous,
        notFound: counts.notFound,
        skipped: counts.skipped,
        errors: counts.errors,
        nextStartId: cursor,
      },
    }));
  }

  return {
    coverage,
    counts,
    samplesByReason,
    lastBlueprintId: cursor,
    nextStartId: cursor,
  };
}

function writeJsonReport(reportPath, report) {
  const outputPath = path.isAbsolute(reportPath)
    ? reportPath
    : path.resolve(ROOT_DIR, reportPath);
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, `${JSON.stringify(report, null, 2)}\n`);
  return outputPath;
}

async function importArtists({ pool, options, context }) {
  const counts = {
    fetched: 0,
    matched: 0,
    ambiguous: 0,
    not_found: 0,
    skipped: 0,
    errors: 0,
    upserted: 0,
    sources: {},
    reasons: {},
  };
  const matchedRows = [];
  const samples = [];
  let cursor = options.startId;
  const limit = createLimiter(options.concurrency);

  while (counts.fetched < options.limit) {
    const remaining = options.limit === Infinity
      ? options.batchSize
      : Math.min(options.batchSize, options.limit - counts.fetched);
    if (remaining <= 0) break;
    const rows = await fetchBlueprintRows(pool, options, cursor, remaining);
    if (rows.length === 0) break;
    counts.fetched += rows.length;
    cursor = Math.max(cursor, ...rows.map((row) => Number(row.blueprintId || 0)));

    const results = await Promise.all(rows.map((row) => limit(async () => {
      try {
        const result = await matchArtist(row, context);
        return { row, result };
      } catch (error) {
        return { row, result: { status: 'error', reason: error.code || error.message || 'error' } };
      }
    })));

    for (const { row, result } of results) {
      addCount(counts.reasons, result.reason || result.matchReason || result.status);
      if (result.status === 'matched') {
        counts.matched += 1;
        addCount(counts.sources, result.source);
        const matched = { ...result, blueprintId: row.blueprintId };
        matchedRows.push(matched);
        if (samples.length < 12) {
          samples.push({
            blueprintId: row.blueprintId,
            name: row.name,
            setName: row.setName,
            collectorNumber: row.collectorNumber,
            artist: result.artist,
            source: result.source,
            confidence: Number(result.confidence.toFixed(3)),
          });
        }
      } else if (result.status === 'ambiguous') {
        counts.ambiguous += 1;
      } else if (result.status === 'skipped') {
        counts.skipped += 1;
      } else if (result.status === 'error') {
        counts.errors += 1;
      } else {
        counts.not_found += 1;
      }
    }

    if (options.apply && matchedRows.length >= options.batchSize) {
      counts.upserted += await upsertArtistRows(pool, matchedRows.splice(0), options.batchSize);
    }
    console.log(JSON.stringify({
      progress: {
        fetched: counts.fetched,
        matched: counts.matched,
        ambiguous: counts.ambiguous,
        not_found: counts.not_found,
        skipped: counts.skipped,
        errors: counts.errors,
        upserted: counts.upserted,
        nextStartId: cursor,
      },
    }));
  }

  if (options.apply && matchedRows.length > 0) {
    counts.upserted += await upsertArtistRows(pool, matchedRows, options.batchSize);
  }
  return {
    counts,
    samples,
    lastBlueprintId: cursor,
    nextStartId: cursor,
  };
}

async function buildContext(options, pool) {
  const context = { options };
  if (options.source === 'tcgdex' || options.source === 'all') {
    const client = new TcgDexClient(options);
    const sets = await client.sets();
    context.tcgdex = { client, setIndex: buildSetIndex(sets) };
  }
  if ((options.source === 'pokemon_tcg_data' || options.source === 'all') && options.pokemonTcgDataDir) {
    context.pokemonTcgData = loadPokemonTcgDataIndex(options.pokemonTcgDataDir);
    context.knownArtists = await fetchKnownArtists(pool);
  }
  return context;
}

async function main() {
  loadLocalEnv();
  const options = parseArgs(process.argv.slice(2));
  const pool = createPoolFromEnv();
  try {
    const primaryStatus = await assertWritablePrimary(pool, options);
    const context = await buildContext(options, pool);
    if (options.reportMissing) {
      const result = await reportMissingArtists({ pool, options, context });
      const output = {
        mode: 'missing-report',
        target: 'oracle-peer4:public.marketplace_blueprint_artists',
        generatedAt: new Date().toISOString(),
        primary: {
          database: primaryStatus.database_name,
          inRecovery: primaryStatus.in_recovery,
        },
        options: {
          limit: options.limit === Infinity ? 'all' : options.limit,
          batchSize: options.batchSize,
          concurrency: options.concurrency,
          startId: options.startId,
          language: options.language,
          source: options.source,
          refreshExisting: options.refreshExisting,
          reportEligibleOnly: options.reportEligibleOnly,
          reportSampleSize: options.reportSampleSize,
        },
        ...result,
      };
      if (options.writeMissingReport) {
        output.reportPath = writeJsonReport(options.writeMissingReport, output);
      }
      console.log(JSON.stringify(output, null, 2));
      return;
    }
    const result = await importArtists({ pool, options, context });
    const output = {
      mode: options.apply ? 'apply' : 'dry-run',
      target: 'oracle-peer4:public.marketplace_blueprint_artists',
      primary: {
        database: primaryStatus.database_name,
        inRecovery: primaryStatus.in_recovery,
      },
      options: {
        limit: options.limit === Infinity ? 'all' : options.limit,
        batchSize: options.batchSize,
        concurrency: options.concurrency,
        startId: options.startId,
        language: options.language,
        source: options.source,
        refreshExisting: options.refreshExisting,
      },
      ...result,
    };
    if (options.apply) {
      output.verification = await verifyArtists(pool);
    }
    console.log(JSON.stringify(output, null, 2));
    if (!options.apply) {
      console.log('Dry run only; pass --apply to upsert matched artists into public.marketplace_blueprint_artists.');
    }
  } finally {
    await pool.end().catch(() => {});
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message || error);
    process.exitCode = 1;
  });
}

module.exports = {
  bestCandidate,
  buildSetIndex,
  findSetMatch,
  matchWithPokemonTcgData,
  nameScore,
  normalizeArtist,
  normalizeCollectorNumber,
  parseArgs,
  canonicalMissingReason,
  reportMissingArtists,
  rowFromBlueprint,
  scoreCandidate,
  shouldSkipBlueprint,
  upsertArtistsSql,
};
