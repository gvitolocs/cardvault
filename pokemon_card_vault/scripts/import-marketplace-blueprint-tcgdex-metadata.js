#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { Pool } = require('pg');

const ROOT_DIR = path.resolve(__dirname, '..');
const POKOINPOS_ROOT = process.env.POKOINPOS_ROOT || '/Users/giuseppe/pokoinpos';
const DEFAULT_ORACLE_ENV = path.join(POKOINPOS_ROOT, 'deploy/env/peer4-postgres.env');
const DEFAULT_TCGDEX_BASE_URL = 'https://api.tcgdex.net';
const DEFAULT_BATCH_SIZE = 100;
const DEFAULT_CONCURRENCY = 4;
const MAX_REMOTE_CONCURRENCY = 6;
const DEFAULT_MIN_INTERVAL_MS = 75;

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
    refreshExisting: false,
    reportMissing: false,
    writeMissingReport: '',
    reportSampleSize: 8,
    tcgdexMinIntervalMs: DEFAULT_MIN_INTERVAL_MS,
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
    } else if (key === 'refresh-existing') {
      options.refreshExisting = true;
    } else if (key === 'report-missing') {
      options.reportMissing = true;
    } else if (key === 'write-missing-report') {
      if (value === true) throw new Error('--write-missing-report requires a path.');
      options.reportMissing = true;
      options.writeMissingReport = String(value || '').trim();
    } else if (key === 'report-sample-size') {
      options.reportSampleSize = parsePositiveInt(value, 8, { min: 1, max: 100 });
    } else if (key === 'tcgdex-min-interval-ms') {
      options.tcgdexMinIntervalMs = parsePositiveInt(value, DEFAULT_MIN_INTERVAL_MS, { min: 0, max: 5000 });
    }
  }

  if (!/^[a-z]{2}(?:-[a-z]{2})?$/.test(options.language)) {
    throw new Error('--language must be a language code such as en.');
  }
  if (options.reportMissing && options.apply) {
    throw new Error('--report-missing is read-only and cannot be combined with --apply.');
  }
  return options;
}

function cleanText(value, maxLength = 500) {
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
    name: cleanText(row.name || row.display_name || blueprint.name, 240),
    setName: cleanText(row.set_name || expansion.name || blueprint.expansion_name, 240),
    setCode: cleanText(row.expansion_code || expansion.code || blueprint.expansion_code || blueprint.set_code, 80),
    collectorNumber: cleanText(
      row.card_number ||
        blueprint.number ||
        blueprint.collector_number ||
        blueprint.card_number ||
        row.version,
      120,
    ),
    rarity: cleanText(row.rarity || blueprint.rarity || blueprint.collector_rarity, 120),
    itemKind: cleanText(row.item_kind || 'single', 40),
    productType: cleanText(row.product_type || 'card', 40),
    hasMetadata: Boolean(row.metadata_blueprint_id),
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
      application_name: 'marketplace-blueprint-tcgdex-metadata-import',
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
    application_name: 'marketplace-blueprint-tcgdex-metadata-import',
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
        metadata.blueprint_id as metadata_blueprint_id,
        b.blueprint,
        b.expansion,
        b.version
      from public.cardtrader_pokemon_blueprints b
      left join public.marketplace_search_candidates c
        on c.card_id = b.id
      left join public.marketplace_blueprint_tcg_metadata metadata
        on metadata.blueprint_id = b.id
      where b.id > $1::bigint
        and ($2::boolean or metadata.blueprint_id is null)
      order by b.id asc
      limit $3::integer
    `,
    [startId, options.refreshExisting, limit],
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

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

class TcgDexClient {
  constructor(options) {
    this.baseUrl = options.tcgdexBaseUrl.replace(/\/+$/, '');
    this.language = options.language;
    this.limit = createLimiter(Math.min(options.concurrency, MAX_REMOTE_CONCURRENCY));
    this.cache = new Map();
    this.minIntervalMs = options.tcgdexMinIntervalMs;
    this.nextRequestAt = 0;
  }

  async throttle() {
    if (this.minIntervalMs <= 0) return;
    const now = Date.now();
    const waitMs = Math.max(0, this.nextRequestAt - now);
    this.nextRequestAt = Math.max(now, this.nextRequestAt) + this.minIntervalMs;
    if (waitMs > 0) await sleep(waitMs);
  }

  async getJson(pathname) {
    const key = pathname;
    if (!this.cache.has(key)) {
      this.cache.set(key, this.limit(async () => {
        await this.throttle();
        const url = `${this.baseUrl}/v2/${this.language}${pathname}`;
        const response = await fetch(url, {
          headers: { accept: 'application/json', 'user-agent': 'PokoinTcgMetadataImporter/1.0' },
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
  const byTcgOnline = new Map();
  for (const set of sets || []) {
    const normalized = {
      id: cleanText(set.id, 80),
      name: cleanText(set.name, 160),
      logo: cleanText(set.logo, 1000),
      symbol: cleanText(set.symbol, 1000),
      compactName: compactText(set.name),
      normalizedName: normalizeText(set.name),
      cardCount: set.cardCount || null,
      abbreviation: set.abbreviation || null,
      tcgOnline: cleanText(set.tcgOnline, 40),
    };
    if (!normalized.id) continue;
    byId.set(normalized.id.toLowerCase(), normalized);
    if (normalized.tcgOnline) byTcgOnline.set(compactText(normalized.tcgOnline), normalized);
    const officialAbbreviation = cleanText(normalized.abbreviation?.official, 40);
    if (officialAbbreviation) byTcgOnline.set(compactText(officialAbbreviation), normalized);
    const bucket = byCompactName.get(normalized.compactName) || [];
    bucket.push(normalized);
    byCompactName.set(normalized.compactName, bucket);
  }
  return { byCompactName, byId, byTcgOnline };
}

function findSetMatch(row, setIndex) {
  const code = compactText(row.setCode);
  if (code && setIndex.byId.has(code)) {
    return { set: setIndex.byId.get(code), reason: 'set_code_exact' };
  }
  if (code && setIndex.byTcgOnline.has(code)) {
    return { set: setIndex.byTcgOnline.get(code), reason: 'set_code_abbreviation' };
  }
  const compactName = compactText(row.setName);
  const exact = setIndex.byCompactName.get(compactName) || [];
  if (exact.length === 1) return { set: exact[0], reason: 'set_name_exact' };
  if (exact.length > 1) {
    const codeMatch = exact.find((set) => code && (
      compactText(set.id) === code ||
      compactText(set.tcgOnline) === code ||
      compactText(set.abbreviation?.official) === code
    ));
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
    (collectorMatches ? 0.46 : 0) +
    nameScore(row.name, detail.name) * 0.36 +
    rarityScore(row.rarity, detail.rarity) * 0.08 +
    (setReason === 'set_code_exact' || setReason === 'set_name_and_code' ? 0.08 : 0.04)
  );
  return Math.min(score, 1);
}

function bestCandidate(row, details, setReason) {
  const scored = details
    .map((detail) => ({
      detail,
      confidence: scoreCandidate(row, detail, setReason),
    }))
    .sort((a, b) => b.confidence - a.confidence);
  if (scored.length === 0) return { status: 'not_found', reason: 'card_not_found' };
  const [best, second] = scored;
  if (best.confidence < 0.78) {
    return { status: 'not_found', reason: 'low_confidence', best };
  }
  if (
    second &&
    second.confidence >= best.confidence - 0.04 &&
    second.detail.id !== best.detail.id
  ) {
    return { status: 'ambiguous', reason: 'close_candidate_scores', best, second };
  }
  return { status: 'matched', best };
}

function toInteger(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) return null;
  return Math.trunc(number);
}

function parseTimestamp(value) {
  const text = cleanText(value, 80);
  if (!text) return null;
  const date = new Date(text);
  if (Number.isNaN(date.getTime())) return null;
  return date.toISOString();
}

function setMetadataFromDetail(detail, setDetail) {
  const sourceSet = detail?.set || setDetail || {};
  const cardCount = sourceSet.cardCount || setDetail?.cardCount || {};
  return {
    id: cleanText(sourceSet.id || setDetail?.id, 80),
    name: cleanText(sourceSet.name || setDetail?.name, 240),
    logo: cleanText(sourceSet.logo || setDetail?.logo, 1000),
    symbol: cleanText(sourceSet.symbol || setDetail?.symbol, 1000),
    cardCount: {
      official: toInteger(cardCount.official),
      total: toInteger(cardCount.total),
    },
    legal: sourceSet.legal || setDetail?.legal || null,
    releaseDate: cleanText(sourceSet.releaseDate || setDetail?.releaseDate, 40),
    serie: sourceSet.serie || setDetail?.serie || null,
    abbreviation: sourceSet.abbreviation || setDetail?.abbreviation || null,
    tcgOnline: cleanText(sourceSet.tcgOnline || setDetail?.tcgOnline, 40),
  };
}

function metadataFromDetail(row, detail, setDetail, setMatch, confidence, options) {
  const setMetadata = setMetadataFromDetail(detail, setDetail);
  const description = cleanText(detail.description || detail.effect, 5000);
  const flavorText = cleanText(detail.flavorText || detail.flavourText, 5000);
  return {
    blueprintId: row.blueprintId,
    category: cleanText(detail.category, 80),
    setId: setMetadata.id,
    setName: setMetadata.name,
    setLogoUrl: setMetadata.logo,
    setSymbolUrl: setMetadata.symbol,
    setOfficialCardCount: setMetadata.cardCount.official,
    setTotalCardCount: setMetadata.cardCount.total,
    setMetadata,
    variants: detail.variants || {},
    types: Array.isArray(detail.types) ? detail.types : [],
    hp: toInteger(detail.hp),
    stage: cleanText(detail.stage, 80),
    evolveFrom: cleanText(detail.evolveFrom, 240),
    attacks: Array.isArray(detail.attacks) ? detail.attacks : [],
    abilities: Array.isArray(detail.abilities) ? detail.abilities : [],
    weaknesses: Array.isArray(detail.weaknesses) ? detail.weaknesses : [],
    resistances: Array.isArray(detail.resistances) ? detail.resistances : [],
    retreat: toInteger(detail.retreat),
    description,
    flavorText,
    regulationMark: cleanText(detail.regulationMark, 20),
    legal: detail.legal || {},
    source: 'tcgdex',
    sourceCardId: cleanText(detail.id, 120),
    sourceUrl: `${options.tcgdexBaseUrl.replace(/\/+$/, '')}/v2/${options.language}/cards/${encodeURIComponent(detail.id)}`,
    confidence,
    matchReason: [
      setMatch.reason,
      'collector_number',
      nameScore(row.name, detail.name) >= 0.96 ? 'name_exact' : 'name_similar',
      detail.rarity ? 'rarity_checked' : 'rarity_missing',
    ].join(';'),
    sourceUpdatedAt: parseTimestamp(detail.updated),
    rawMetadata: {
      sourceCard: detail,
      input: row,
      setMatch: {
        reason: setMatch.reason,
        id: setMatch.set?.id || '',
        name: setMatch.set?.name || '',
      },
    },
  };
}

async function matchMetadata(row, context) {
  const skipReason = shouldSkipBlueprint(row);
  if (skipReason) return { status: 'skipped', reason: skipReason };

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
  return {
    status: 'matched',
    ...metadataFromDetail(
      row,
      selected.best.detail,
      setDetail,
      setMatch,
      selected.best.confidence,
      context.options,
    ),
  };
}

function canonicalReason(status, reason) {
  const code = cleanText(reason || status || 'unknown', 120);
  if (status === 'matched') return 'matched';
  if (status === 'error') return 'errors';
  if (code === 'set_not_found') return 'set_not_found';
  if (code === 'card_not_found' || code === 'card_not_found_in_set') return 'card_not_found';
  if (code === 'low_confidence') return 'low_confidence';
  if (code === 'ambiguous_set_name' || code === 'ambiguous_set_name_contains') return 'ambiguous_set';
  if (code.startsWith('missing_')) return 'missing_field';
  if (code === 'non_card_product') return 'skipped';
  if (code === 'close_candidate_scores') return 'ambiguous_card';
  if (code === 'tcgdex_rate_limited' || code.includes('request failed')) return 'errors';
  return status || code;
}

function addCount(map, key, amount = 1) {
  map[key] = (map[key] || 0) + amount;
}

function initialCounts() {
  return {
    fetched: 0,
    matched: 0,
    inserted: 0,
    updated: 0,
    skipped: 0,
    ambiguous_set: 0,
    ambiguous_card: 0,
    set_not_found: 0,
    card_not_found: 0,
    low_confidence: 0,
    missing_field: 0,
    errors: 0,
    reasons: {},
  };
}

function sampleRow(row, result, canonical) {
  const sample = {
    blueprintId: row.blueprintId,
    name: row.name,
    setName: row.setName,
    setCode: row.setCode,
    collectorNumber: row.collectorNumber,
    rarity: row.rarity,
    status: result.status,
    reason: result.reason || '',
    canonicalReason: canonical,
  };
  if (result.sourceCardId) sample.sourceCardId = result.sourceCardId;
  if (result.setId) sample.tcgSetId = result.setId;
  if (result.confidence !== undefined) sample.confidence = Number(result.confidence.toFixed(3));
  if (result.best?.confidence !== undefined) sample.bestConfidence = Number(result.best.confidence.toFixed(3));
  if (result.best?.detail?.id) sample.bestSourceCardId = cleanText(result.best.detail.id, 120);
  return sample;
}

function upsertMetadataSql(rowCount) {
  const columns = [
    'blueprint_id',
    'category',
    'set_id',
    'set_name',
    'set_logo_url',
    'set_symbol_url',
    'set_official_card_count',
    'set_total_card_count',
    'set_metadata',
    'variants',
    'types',
    'hp',
    'stage',
    'evolve_from',
    'attacks',
    'abilities',
    'weaknesses',
    'resistances',
    'retreat',
    'description',
    'flavor_text',
    'regulation_mark',
    'legal',
    'source',
    'source_card_id',
    'source_url',
    'confidence',
    'match_reason',
    'source_updated_at',
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
    insert into public.marketplace_blueprint_tcg_metadata (${columns.join(', ')})
    values ${valueRows.join(', ')}
    on conflict (blueprint_id) do update set
      category = excluded.category,
      set_id = excluded.set_id,
      set_name = excluded.set_name,
      set_logo_url = excluded.set_logo_url,
      set_symbol_url = excluded.set_symbol_url,
      set_official_card_count = excluded.set_official_card_count,
      set_total_card_count = excluded.set_total_card_count,
      set_metadata = excluded.set_metadata,
      variants = excluded.variants,
      types = excluded.types,
      hp = excluded.hp,
      stage = excluded.stage,
      evolve_from = excluded.evolve_from,
      attacks = excluded.attacks,
      abilities = excluded.abilities,
      weaknesses = excluded.weaknesses,
      resistances = excluded.resistances,
      retreat = excluded.retreat,
      description = excluded.description,
      flavor_text = excluded.flavor_text,
      regulation_mark = excluded.regulation_mark,
      legal = excluded.legal,
      source = excluded.source,
      source_card_id = excluded.source_card_id,
      source_url = excluded.source_url,
      confidence = excluded.confidence,
      match_reason = excluded.match_reason,
      matched_at = now(),
      source_updated_at = excluded.source_updated_at,
      raw_metadata = excluded.raw_metadata,
      updated_at = now()
  `;
}

function upsertValues(rows) {
  return rows.flatMap((row) => [
    row.blueprintId,
    row.category,
    row.setId,
    row.setName,
    row.setLogoUrl,
    row.setSymbolUrl,
    row.setOfficialCardCount,
    row.setTotalCardCount,
    JSON.stringify(row.setMetadata || {}),
    JSON.stringify(row.variants || {}),
    JSON.stringify(row.types || []),
    row.hp,
    row.stage,
    row.evolveFrom,
    JSON.stringify(row.attacks || []),
    JSON.stringify(row.abilities || []),
    JSON.stringify(row.weaknesses || []),
    JSON.stringify(row.resistances || []),
    row.retreat,
    row.description,
    row.flavorText,
    row.regulationMark,
    JSON.stringify(row.legal || {}),
    row.source,
    row.sourceCardId || '',
    row.sourceUrl || '',
    row.confidence,
    row.matchReason || '',
    row.sourceUpdatedAt,
    JSON.stringify(row.rawMetadata || {}),
  ]);
}

async function upsertMetadataRows(pool, rows, batchSize) {
  const counts = { inserted: 0, updated: 0 };
  for (let offset = 0; offset < rows.length; offset += batchSize) {
    const batch = rows.slice(offset, offset + batchSize);
    const ids = batch.map((row) => row.blueprintId);
    const existing = await pool.query(
      'select blueprint_id::text from public.marketplace_blueprint_tcg_metadata where blueprint_id = any($1::bigint[])',
      [ids],
    );
    const existingIds = new Set(existing.rows.map((row) => String(row.blueprint_id)));
    counts.updated += batch.filter((row) => existingIds.has(String(row.blueprintId))).length;
    counts.inserted += batch.filter((row) => !existingIds.has(String(row.blueprintId))).length;
    await pool.query(upsertMetadataSql(batch.length), upsertValues(batch));
  }
  return counts;
}

async function verifyMetadata(pool) {
  const result = await pool.query(`
    select
      count(*)::integer as metadata_rows,
      count(*) filter (where source = 'tcgdex')::integer as tcgdex_rows,
      count(*) filter (where category = 'Pokemon')::integer as pokemon_rows,
      count(*) filter (where category = 'Trainer')::integer as trainer_rows,
      count(*) filter (where category = 'Energy')::integer as energy_rows,
      count(distinct set_id)::integer as distinct_sets,
      max(matched_at) as last_matched_at,
      max(source_updated_at) as latest_source_updated_at
    from public.marketplace_blueprint_tcg_metadata
  `);
  return result.rows[0] || {};
}

async function fetchMetadataCoverage(pool) {
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
        metadata.blueprint_id as metadata_blueprint_id
      from public.cardtrader_pokemon_blueprints b
      left join public.marketplace_search_candidates c
        on c.card_id = b.id
      left join public.marketplace_blueprint_tcg_metadata metadata
        on metadata.blueprint_id = b.id
    )
    select
      count(*)::integer as total_blueprints,
      count(*) filter (where metadata_blueprint_id is not null)::integer as metadata_rows,
      count(*) filter (where metadata_blueprint_id is null)::integer as missing_metadata_rows,
      count(*) filter (
        where metadata_blueprint_id is null
          and item_kind <> 'product'
          and product_type = 'card'
          and coalesce(name, '') <> ''
          and (coalesce(set_name, '') <> '' or coalesce(expansion_code, '') <> '')
          and coalesce(card_number, '') <> ''
      )::integer as missing_eligible_rows,
      count(*) filter (where metadata_blueprint_id is null and (item_kind = 'product' or product_type <> 'card'))::integer as missing_non_card_product_rows,
      count(*) filter (where metadata_blueprint_id is null and coalesce(name, '') = '')::integer as missing_name_rows,
      count(*) filter (where metadata_blueprint_id is null and coalesce(set_name, '') = '' and coalesce(expansion_code, '') = '')::integer as missing_set_rows,
      count(*) filter (where metadata_blueprint_id is null and coalesce(card_number, '') = '')::integer as missing_collector_number_rows
    from rows
  `);
  return result.rows[0] || {};
}

function writeJsonReport(reportPath, report) {
  const outputPath = path.isAbsolute(reportPath)
    ? reportPath
    : path.resolve(ROOT_DIR, reportPath);
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, `${JSON.stringify(report, null, 2)}\n`);
  return outputPath;
}

async function runImport({ pool, options, context }) {
  const counts = initialCounts();
  const samples = [];
  const matchedRows = [];
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
        const result = await matchMetadata(row, context);
        return { row, result };
      } catch (error) {
        return { row, result: { status: 'error', reason: error.code || error.message || 'error' } };
      }
    })));

    for (const { row, result } of results) {
      const canonical = canonicalReason(result.status, result.reason || result.matchReason);
      addCount(counts.reasons, result.reason || result.matchReason || result.status);
      if (Object.hasOwn(counts, canonical)) counts[canonical] += 1;
      if (result.status === 'matched') {
        matchedRows.push(result);
        if (samples.length < 12) samples.push(sampleRow(row, result, canonical));
      } else if (!Object.hasOwn(counts, canonical)) {
        counts.skipped += 1;
      }
    }

    if (options.apply && matchedRows.length >= options.batchSize) {
      const upserted = await upsertMetadataRows(pool, matchedRows.splice(0), options.batchSize);
      counts.inserted += upserted.inserted;
      counts.updated += upserted.updated;
    }

    console.log(JSON.stringify({
      progress: {
        fetched: counts.fetched,
        matched: counts.matched,
        inserted: counts.inserted,
        updated: counts.updated,
        skipped: counts.skipped,
        ambiguous_set: counts.ambiguous_set,
        set_not_found: counts.set_not_found,
        card_not_found: counts.card_not_found,
        low_confidence: counts.low_confidence,
        missing_field: counts.missing_field,
        errors: counts.errors,
        nextStartId: cursor,
      },
    }));
  }

  if (options.apply && matchedRows.length > 0) {
    const upserted = await upsertMetadataRows(pool, matchedRows, options.batchSize);
    counts.inserted += upserted.inserted;
    counts.updated += upserted.updated;
  }

  return {
    counts,
    samples,
    lastBlueprintId: cursor,
    nextStartId: cursor,
  };
}

async function reportMissingMetadata({ pool, options, context }) {
  const coverage = await fetchMetadataCoverage(pool);
  const counts = initialCounts();
  const samplesByReason = {};
  let cursor = options.startId;
  const limit = createLimiter(options.concurrency);

  while (counts.fetched < options.limit) {
    const remaining = options.limit === Infinity
      ? options.batchSize
      : Math.min(options.batchSize, options.limit - counts.fetched);
    if (remaining <= 0) break;
    const rows = await fetchBlueprintRows(pool, { ...options, refreshExisting: true }, cursor, remaining);
    if (rows.length === 0) break;
    counts.fetched += rows.length;
    cursor = Math.max(cursor, ...rows.map((row) => Number(row.blueprintId || 0)));

    const results = await Promise.all(rows.map((row) => limit(async () => {
      try {
        if (row.hasMetadata) {
          return { row, result: { status: 'skipped', reason: 'skipped_existing' } };
        }
        const result = await matchMetadata(row, context);
        return { row, result };
      } catch (error) {
        return { row, result: { status: 'error', reason: error.code || error.message || 'error' } };
      }
    })));

    for (const { row, result } of results) {
      const canonical = canonicalReason(result.status, result.reason || result.matchReason);
      addCount(counts.reasons, result.reason || result.matchReason || result.status);
      if (Object.hasOwn(counts, canonical)) counts[canonical] += 1;
      else counts.skipped += 1;
      const bucket = samplesByReason[canonical] || [];
      if (bucket.length < options.reportSampleSize) {
        bucket.push(sampleRow(row, result, canonical));
        samplesByReason[canonical] = bucket;
      }
    }

    console.log(JSON.stringify({
      reportProgress: {
        fetched: counts.fetched,
        matched: counts.matched,
        skipped: counts.skipped,
        ambiguous_set: counts.ambiguous_set,
        set_not_found: counts.set_not_found,
        card_not_found: counts.card_not_found,
        low_confidence: counts.low_confidence,
        missing_field: counts.missing_field,
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

async function buildContext(options) {
  const client = new TcgDexClient(options);
  const sets = await client.sets();
  return {
    options,
    tcgdex: {
      client,
      setIndex: buildSetIndex(sets),
    },
  };
}

async function main() {
  loadLocalEnv();
  const options = parseArgs(process.argv.slice(2));
  const pool = createPoolFromEnv();
  try {
    const primaryStatus = await assertWritablePrimary(pool, options);
    const context = await buildContext(options);
    if (options.reportMissing) {
      const result = await reportMissingMetadata({ pool, options, context });
      const output = {
        mode: 'missing-report',
        target: 'oracle-peer4:public.marketplace_blueprint_tcg_metadata',
        generatedAt: new Date().toISOString(),
        primary: {
          database: primaryStatus.database_name,
          inRecovery: primaryStatus.in_recovery,
        },
        options: {
          limit: options.limit === Infinity ? 'all' : options.limit,
          batchSize: options.batchSize,
          concurrency: options.concurrency,
          effectiveRemoteConcurrency: Math.min(options.concurrency, MAX_REMOTE_CONCURRENCY),
          startId: options.startId,
          language: options.language,
          refreshExisting: options.refreshExisting,
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

    const result = await runImport({ pool, options, context });
    const output = {
      mode: options.apply ? 'apply' : 'dry-run',
      target: 'oracle-peer4:public.marketplace_blueprint_tcg_metadata',
      primary: {
        database: primaryStatus.database_name,
        inRecovery: primaryStatus.in_recovery,
      },
      options: {
        limit: options.limit === Infinity ? 'all' : options.limit,
        batchSize: options.batchSize,
        concurrency: options.concurrency,
        effectiveRemoteConcurrency: Math.min(options.concurrency, MAX_REMOTE_CONCURRENCY),
        startId: options.startId,
        language: options.language,
        refreshExisting: options.refreshExisting,
      },
      ...result,
    };
    if (options.apply) {
      output.verification = await verifyMetadata(pool);
    }
    console.log(JSON.stringify(output, null, 2));
    if (!options.apply) {
      console.log('Dry run only; pass --apply to upsert matched TCGdex metadata into public.marketplace_blueprint_tcg_metadata.');
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
  canonicalReason,
  findSetMatch,
  metadataFromDetail,
  nameScore,
  normalizeCollectorNumber,
  parseArgs,
  rowFromBlueprint,
  scoreCandidate,
  shouldSkipBlueprint,
  upsertMetadataSql,
};
