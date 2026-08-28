#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { Pool } = require('pg');

const ROOT_DIR = path.resolve(__dirname, '..');
const DEFAULT_TCGDEX_BASE_URL = 'https://api.tcgdex.net';
const DEFAULT_LANGUAGES = ['it', 'fr', 'de', 'es', 'pt', 'id', 'th', 'ja', 'zh-cn', 'zh-tw'];
const MAX_REMOTE_CONCURRENCY = 8;
const DEFAULT_BATCH_SIZE = 500;
const POKOINPOS_ROOT = process.env.POKOINPOS_ROOT || '/Users/giuseppe/pokoinpos';
const DEFAULT_ORACLE_ENV_FILE = path.join(POKOINPOS_ROOT, 'deploy/env/peer4-postgres.env');

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
  const resolved = path.resolve(filePath);
  if (!fs.existsSync(resolved)) return false;
  for (const line of fs.readFileSync(resolved, 'utf8').split(/\r?\n/)) {
    const stripped = line.trim();
    if (!stripped || stripped.startsWith('#') || !stripped.includes('=')) continue;
    const separator = stripped.indexOf('=');
    const key = stripped.slice(0, separator).replace(/^export\s+/, '').trim();
    if (!key || process.env[key]) continue;
    process.env[key] = cleanEnvValue(stripped.slice(separator + 1));
  }
  return true;
}

function parsePositiveInt(value, fallback, { min = 1, max = Number.MAX_SAFE_INTEGER } = {}) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(Math.max(Math.trunc(number), min), max);
}

function parseLimit(value, fallback = Infinity) {
  const text = String(value ?? '').trim().toLowerCase();
  if (!text) return fallback;
  if (text === 'all' || text === 'none' || text === 'infinity') return Infinity;
  return parsePositiveInt(text, fallback, { min: 1, max: 1_000_000 });
}

function normalizeLanguage(value) {
  const language = String(value || '').trim().toLowerCase();
  if (language === 'jp') return 'ja';
  if (language === 'zh') return 'zh-cn';
  return language;
}

function parseLanguages(value = DEFAULT_LANGUAGES.join(',')) {
  const languages = String(value || '')
    .split(',')
    .map(normalizeLanguage)
    .filter((language) => language && language !== 'en');
  const unique = [...new Set(languages)];
  const unsupported = unique.filter((language) => !DEFAULT_LANGUAGES.includes(language));
  if (unsupported.length > 0) {
    throw new Error(`Unsupported language(s): ${unsupported.join(', ')}. Use: ${DEFAULT_LANGUAGES.join(', ')}.`);
  }
  return unique.length > 0 ? unique : DEFAULT_LANGUAGES;
}

function parseArgs(argv) {
  const options = {
    apply: false,
    languages: DEFAULT_LANGUAGES,
    importCards: true,
    importExpansions: true,
    limit: Infinity,
    expansionLimit: Infinity,
    batchSize: DEFAULT_BATCH_SIZE,
    concurrency: 4,
    tcgdexBaseUrl: DEFAULT_TCGDEX_BASE_URL,
    envFile: process.env.TCGDEX_TRANSLATION_ENV_FILE || DEFAULT_ORACLE_ENV_FILE,
    limitlessFallback: true,
  };
  for (const arg of argv) {
    const [key, ...rest] = arg.replace(/^--/, '').split('=');
    const value = rest.join('=');
    if (arg === '--apply') options.apply = true;
    else if (arg === '--dry-run') options.apply = false;
    else if (key === 'languages') options.languages = parseLanguages(value);
    else if (key === 'language') options.languages = parseLanguages(value);
    else if (key === 'cards-only' && !value) options.importExpansions = false;
    else if (key === 'expansions-only' && !value) options.importCards = false;
    else if (key === 'limit') options.limit = parseLimit(value);
    else if (key === 'expansion-limit') options.expansionLimit = parseLimit(value);
    else if (key === 'batch-size') options.batchSize = parsePositiveInt(value, DEFAULT_BATCH_SIZE, { min: 1, max: 5000 });
    else if (key === 'concurrency') options.concurrency = parsePositiveInt(value, 4, { min: 1, max: MAX_REMOTE_CONCURRENCY });
    else if (key === 'tcgdex-base-url') options.tcgdexBaseUrl = String(value || '').replace(/\/+$/, '') || DEFAULT_TCGDEX_BASE_URL;
    else if (key === 'env-file') options.envFile = value;
    else if (key === 'no-limitless-fallback' && !value) options.limitlessFallback = false;
    else throw new Error(`Unknown option: ${arg}`);
  }
  if (!options.importCards && !options.importExpansions) {
    throw new Error('At least one of cards or expansions must be enabled.');
  }
  return options;
}

function marketplaceDatabaseUrl(env = process.env) {
  if (env.MARKETPLACE_DATABASE_URL) return env.MARKETPLACE_DATABASE_URL;
  if (env.MARKETPLACE_PEER4_DATABASE_URL) return env.MARKETPLACE_PEER4_DATABASE_URL;
  const user = env.MARKETPLACE_DB_USER;
  const password = env.MARKETPLACE_DB_PASSWORD;
  const host = env.MARKETPLACE_DB_PUBLIC_HOST;
  const database = env.MARKETPLACE_DB_NAME;
  if (!user || !password || !host || !database) {
    throw new Error('MARKETPLACE_DATABASE_URL or MARKETPLACE_DB_* connection fields are required.');
  }
  const port = env.MARKETPLACE_DB_PORT || '5432';
  return `postgresql://${encodeURIComponent(user)}:${encodeURIComponent(password)}@${host}:${port}/${encodeURIComponent(database)}`;
}

function createPool(env = process.env) {
  return new Pool({
    connectionString: marketplaceDatabaseUrl(env),
    max: 2,
    idleTimeoutMillis: 10_000,
    connectionTimeoutMillis: 10_000,
    ssl: { rejectUnauthorized: env.MARKETPLACE_DATABASE_SSL_VERIFY === '1' },
    application_name: 'tcgdex-card-name-translation-import',
  });
}

async function assertWritablePrimary(pool, apply) {
  const result = await pool.query('select pg_is_in_recovery() as in_recovery');
  if (apply && result.rows[0]?.in_recovery) {
    throw new Error('Refusing --apply because the configured marketplace database is in recovery/read-only mode.');
  }
}

function normalizeText(value) {
  return String(value || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

function compactText(value) {
  return normalizeText(value).replace(/[^a-z0-9]/g, '');
}

function normalizeCollectorNumber(value) {
  const text = String(value || '').trim().toLowerCase();
  const slashMatch = text.match(/0*([0-9]+[a-z]?)(?=\s*\/)/);
  if (slashMatch) return slashMatch[1];
  const localMatch = text.match(/^[a-z]*0*([0-9]+[a-z]?)$/);
  return localMatch ? localMatch[1] : text.replace(/[^a-z0-9]+/g, '');
}

function createLimiter(limit) {
  let active = 0;
  const queue = [];
  function drain() {
    while (active < limit && queue.length > 0) {
      const item = queue.shift();
      active += 1;
      Promise.resolve()
        .then(item.fn)
        .then(item.resolve, item.reject)
        .finally(() => {
          active -= 1;
          drain();
        });
    }
  }
  return (fn) => new Promise((resolve, reject) => {
    queue.push({ fn, resolve, reject });
    drain();
  });
}

class TcgDexClient {
  constructor(options) {
    this.baseUrl = options.tcgdexBaseUrl.replace(/\/+$/, '');
    this.language = options.language;
    this.limit = createLimiter(options.concurrency);
    this.cache = new Map();
  }

  async getJson(pathname) {
    const key = `${this.language}:${pathname}`;
    if (!this.cache.has(key)) {
      this.cache.set(key, this.limit(async () => {
        const url = `${this.baseUrl}/v2/${this.language}${pathname}`;
        const response = await fetch(url, {
          headers: { accept: 'application/json', 'user-agent': 'PokoinTcgTranslationImporter/1.0' },
        });
        if (response.status === 404) return null;
        if (!response.ok) {
          throw new Error(`TCGdex request failed ${response.status} for ${pathname}`);
        }
        return response.json();
      }));
    }
    return this.cache.get(key);
  }

  async cards() {
    return this.getJson('/cards');
  }

  async card(id) {
    return this.getJson(`/cards/${encodeURIComponent(id)}`);
  }

  async sets() {
    return this.getJson('/sets');
  }
}

async function loadMarketplaceCards(pool, limit, options = {}) {
  const limitlessColumns = options.limitlessFallback ? `
        coalesce(nullif(limitless.set_code, ''), '') as limitless_set_code,
        coalesce(nullif(limitless.collector_number, ''), '') as limitless_collector_number,
        coalesce(nullif(limitless.limitless_card_key, ''), '') as limitless_card_key,
        coalesce(nullif(limitless.limitless_card_name, ''), '') as limitless_card_name,
        coalesce(nullif(limitless.source_card_id, ''), '') as limitless_source_card_id,
        coalesce(nullif(limitless.limitless_expansion_name, ''), '') as limitless_expansion_name,
        coalesce(nullif(limitless.limitless_expansion_code, ''), '') as limitless_expansion_code,
        coalesce(limitless.match_confidence, 0) as limitless_match_confidence,
        coalesce(nullif(limitless.match_reason, ''), '') as limitless_match_reason`
    : `
        '' as limitless_set_code,
        '' as limitless_collector_number,
        '' as limitless_card_key,
        '' as limitless_card_name,
        '' as limitless_source_card_id,
        '' as limitless_expansion_name,
        '' as limitless_expansion_code,
        0 as limitless_match_confidence,
        '' as limitless_match_reason`;
  const limitlessJoin = options.limitlessFallback ? `
      left join lateral (
        select
          b.set_code,
          b.collector_number,
          b.limitless_card_key,
          b.limitless_card_name,
          b.source_card_id,
          b.match_confidence,
          b.match_reason,
          x.limitless_expansion_name,
          x.limitless_expansion_code
        from public.limitless_marketplace_expansion_blueprints b
        left join public.limitless_marketplace_expansions x
          on x.expansion_key = b.expansion_key
        where b.blueprint_id = c.card_id
        order by b.match_confidence desc, b.updated_at desc nulls last, b.expansion_key asc
        limit 1
      ) limitless on true`
    : '';
  const result = await pool.query(
    `
      select
        c.card_id,
        coalesce(nullif(c.canonical_name, ''), c.name) as name,
        c.name as display_name,
        c.set_name,
        c.card_number,
        c.rarity,
        c.item_kind,
        c.product_type,
        coalesce(nullif(e.set_id, ''), '') as tcgdex_set_id,
        coalesce(nullif(e.source_card_id, ''), '') as tcgdex_card_id,
${limitlessColumns}
      from public.marketplace_cards c
      left join public.marketplace_blueprint_tcg_metadata e
        on e.blueprint_id = c.card_id
       and e.source = 'tcgdex'
${limitlessJoin}
      where c.name <> ''
        and c.item_kind <> 'product'
        and c.product_type = 'card'
      order by
        (coalesce(nullif(e.source_card_id, ''), '') <> '') desc,
        c.imported_at desc nulls last,
        c.card_id desc
      limit $1
    `,
    [limit === Infinity ? 1_000_000 : limit],
  );
  return result.rows.map((row) => ({
    cardId: String(row.card_id || ''),
    name: String(row.name || '').trim(),
    displayName: String(row.display_name || '').trim(),
    setName: String(row.set_name || '').trim(),
    collectorNumber: String(row.card_number || '').trim(),
    rarity: String(row.rarity || '').trim(),
    tcgdexSetId: String(row.tcgdex_set_id || '').trim(),
    tcgdexCardId: String(row.tcgdex_card_id || '').trim(),
    limitlessSetCode: String(row.limitless_set_code || '').trim(),
    limitlessCollectorNumber: String(row.limitless_collector_number || '').trim(),
    limitlessCardKey: String(row.limitless_card_key || '').trim(),
    limitlessCardName: String(row.limitless_card_name || '').trim(),
    limitlessSourceCardId: String(row.limitless_source_card_id || '').trim(),
    limitlessExpansionName: String(row.limitless_expansion_name || '').trim(),
    limitlessExpansionCode: String(row.limitless_expansion_code || '').trim(),
    limitlessMatchConfidence: Number(row.limitless_match_confidence || 0),
    limitlessMatchReason: String(row.limitless_match_reason || '').trim(),
  })).filter((row) => row.cardId && row.name);
}

async function loadMarketplaceExpansions(pool, limit, options = {}) {
  const limitlessColumns = options.limitlessFallback ? `
        coalesce(nullif(limitless.limitless_expansion_name, ''), '') as limitless_expansion_name,
        coalesce(nullif(limitless.limitless_expansion_code, ''), '') as limitless_expansion_code,
        coalesce(limitless.aliases, '{}'::text[]) as limitless_aliases`
    : `
        '' as limitless_expansion_name,
        '' as limitless_expansion_code,
        '{}'::text[] as limitless_aliases`;
  const limitlessJoin = options.limitlessFallback ? `
      left join lateral (
        select
          x.limitless_expansion_name,
          x.limitless_expansion_code,
          x.aliases
        from public.limitless_marketplace_expansions x
        where public.marketplace_search_compact(x.pokoin_expansion_name) = public.marketplace_search_compact(e.name)
          or lower(x.pokoin_expansion_code) = lower(e.code)
          or lower(x.limitless_expansion_code) = lower(e.code)
        order by x.updated_at desc nulls last, x.expansion_key asc
        limit 1
      ) limitless on true`
    : '';
  const result = await pool.query(
    `
      select distinct on (e.normalized_name)
        e.name,
        e.code,
        coalesce(nullif(m.set_id, ''), '') as tcgdex_set_id,
${limitlessColumns}
      from public.cardtrader_pokemon_expansions e
      left join public.marketplace_blueprint_tcg_metadata m
        on public.marketplace_search_normalize(m.set_name) = e.normalized_name
       and m.source = 'tcgdex'
${limitlessJoin}
      where e.name <> ''
      order by e.normalized_name, m.matched_at desc nulls last
      limit $1
    `,
    [limit === Infinity ? 100_000 : limit],
  );
  return result.rows.map((row) => ({
    name: String(row.name || '').trim(),
    code: String(row.code || '').trim(),
    tcgdexSetId: String(row.tcgdex_set_id || '').trim(),
    limitlessExpansionName: String(row.limitless_expansion_name || '').trim(),
    limitlessExpansionCode: String(row.limitless_expansion_code || '').trim(),
    limitlessAliases: Array.isArray(row.limitless_aliases) ? row.limitless_aliases.map(String) : [],
  })).filter((row) => row.name);
}

function indexLocalizedCards(cards) {
  const byId = new Map();
  const bySetNumber = new Map();
  for (const card of cards || []) {
    const id = String(card?.id || '').trim();
    const name = String(card?.name || '').trim();
    if (!id || !name) continue;
    byId.set(id, { id, name, raw: card });
    const setId = String(card.set?.id || card.setId || id.split('-').slice(0, -1).join('-') || '').trim();
    const localId = normalizeCollectorNumber(card.localId || card.localID || card.number || '');
    if (setId && localId) {
      const key = `${setId.toLowerCase()}\0${localId}`;
      const bucket = bySetNumber.get(key) || [];
      bucket.push({ id, name, raw: card });
      bySetNumber.set(key, bucket);
    }
  }
  return { byId, bySetNumber };
}

function addBucket(map, key, value) {
  if (!key) return;
  const bucket = map.get(key) || [];
  bucket.push(value);
  map.set(key, bucket);
}

function singleCandidate(candidates) {
  const unique = [...new Map((candidates || []).map((candidate) => [candidate.id, candidate])).values()];
  return unique.length === 1 ? unique[0] : null;
}

function indexEnglishCards(cards) {
  const bySetNameNumberName = new Map();
  const byNameNumber = new Map();
  for (const card of cards || []) {
    const id = String(card?.id || '').trim();
    const name = String(card?.name || '').trim();
    const localId = normalizeCollectorNumber(card?.localId || card?.localID || card?.number || '');
    if (!id || !name || !localId) continue;
    const indexed = { id, name, raw: card };
    const compactName = compactText(name);
    const setNames = [
      card?.set?.name,
      card?.setName,
    ].map(compactText).filter(Boolean);
    addBucket(byNameNumber, `${compactName}\0${localId}`, indexed);
    for (const setName of setNames) {
      addBucket(bySetNameNumberName, `${setName}\0${localId}\0${compactName}`, indexed);
    }
  }
  return { bySetNameNumberName, byNameNumber };
}

function localizedLimitlessFallbackCardForRow(row, localizedIndex, englishIndex) {
  if (!englishIndex || !row.limitlessSourceCardId && !row.limitlessCardKey && !row.limitlessSetCode) return null;
  if (Number(row.limitlessMatchConfidence || 0) < 0.95) return null;
  const collector = normalizeCollectorNumber(row.collectorNumber || row.limitlessCollectorNumber);
  if (!collector) return null;
  const names = [...new Set([
    row.limitlessCardName,
    row.name,
    row.displayName,
  ].map(compactText).filter(Boolean))];
  if (names.length === 0) return null;
  const setNames = [...new Set([
    row.setName,
    row.limitlessExpansionName,
  ].map(compactText).filter(Boolean))];

  for (const setName of setNames) {
    for (const name of names) {
      const englishCard = singleCandidate(englishIndex.bySetNameNumberName.get(`${setName}\0${collector}\0${name}`));
      const localizedCard = englishCard && localizedIndex.byId.get(englishCard.id);
      if (localizedCard) {
        return {
          card: localizedCard,
          confidence: 0.88,
          reason: 'limitless_set_name_collector_name',
          source: 'tcgdex+limitless',
          support: englishCard,
        };
      }
    }
  }

  for (const name of names) {
    const englishCard = singleCandidate(englishIndex.byNameNumber.get(`${name}\0${collector}`));
    const localizedCard = englishCard && localizedIndex.byId.get(englishCard.id);
    if (localizedCard) {
      return {
        card: localizedCard,
        confidence: 0.84,
        reason: 'limitless_unique_collector_name',
        source: 'tcgdex+limitless',
        support: englishCard,
      };
    }
  }
  return null;
}

function localizedCardForRow(row, localizedIndex, englishIndex = null) {
  if (row.tcgdexCardId && localizedIndex.byId.has(row.tcgdexCardId)) {
    return { card: localizedIndex.byId.get(row.tcgdexCardId), confidence: 1, reason: 'tcgdex_card_id', source: 'tcgdex' };
  }
  const setId = row.tcgdexSetId.toLowerCase();
  const collector = normalizeCollectorNumber(row.collectorNumber);
  if (setId && collector) {
    const candidates = localizedIndex.bySetNumber.get(`${setId}\0${collector}`) || [];
    if (candidates.length === 1) {
      return { card: candidates[0], confidence: 0.94, reason: 'tcgdex_set_id_collector', source: 'tcgdex' };
    }
    const exactName = candidates.find((candidate) =>
      compactText(candidate.raw?.name) === compactText(row.name) ||
      compactText(candidate.raw?.name) === compactText(row.displayName));
    if (exactName) {
      return { card: exactName, confidence: 0.9, reason: 'tcgdex_set_id_collector_name', source: 'tcgdex' };
    }
  }
  return localizedLimitlessFallbackCardForRow(row, localizedIndex, englishIndex);
}

function indexEnglishSets(sets) {
  const byCompactName = new Map();
  for (const set of sets || []) {
    const id = String(set?.id || '').trim();
    const name = String(set?.name || '').trim();
    if (!id || !name) continue;
    addBucket(byCompactName, compactText(name), { id, name, raw: set });
  }
  return { byCompactName };
}

function limitlessFallbackSetForRow(row, byId, englishSetIndex) {
  if (!englishSetIndex || !row.limitlessExpansionName && !row.limitlessExpansionCode && (!row.limitlessAliases || row.limitlessAliases.length === 0)) {
    return null;
  }
  const names = [...new Set([
    row.limitlessExpansionName,
    row.name,
    ...(row.limitlessAliases || []),
  ].map(compactText).filter(Boolean))];
  for (const name of names) {
    const englishSet = singleCandidate(englishSetIndex.byCompactName.get(name));
    const localizedSet = englishSet && byId.get(englishSet.id.toLowerCase());
    if (localizedSet) {
      return {
        set: localizedSet,
        confidence: 0.86,
        reason: 'limitless_expansion_name',
        source: 'tcgdex+limitless',
        support: englishSet,
      };
    }
  }
  return null;
}

function expansionTranslationsForLanguage(rows, localizedSets, language, options = {}) {
  const byId = new Map();
  const byCompactName = new Map();
  const englishSetIndex = options.englishSets ? indexEnglishSets(options.englishSets) : null;
  for (const set of localizedSets || []) {
    const id = String(set?.id || '').trim();
    const name = String(set?.name || '').trim();
    if (!id || !name) continue;
    byId.set(id.toLowerCase(), set);
    const bucket = byCompactName.get(compactText(name)) || [];
    bucket.push(set);
    byCompactName.set(compactText(name), bucket);
  }
  const translations = [];
  const counts = { checked: 0, matched: 0, skipped: 0, bySource: {} };
  for (const row of rows) {
    counts.checked += 1;
    let set = row.tcgdexSetId ? byId.get(row.tcgdexSetId.toLowerCase()) : null;
    let reason = set ? 'tcgdex_set_id' : '';
    let confidence = set ? 1 : 0;
    let source = set ? 'tcgdex' : '';
    let support = null;
    if (!set) {
      const limitlessMatch = options.limitlessFallback === false
        ? null
        : limitlessFallbackSetForRow(row, byId, englishSetIndex);
      if (limitlessMatch) {
        set = limitlessMatch.set;
        reason = limitlessMatch.reason;
        confidence = limitlessMatch.confidence;
        source = limitlessMatch.source;
        support = limitlessMatch.support;
      }
    }
    if (!set) {
      const matches = byCompactName.get(compactText(row.name)) || [];
      if (matches.length === 1) {
        set = matches[0];
        reason = 'set_name_exact';
        confidence = 0.82;
        source = 'tcgdex';
      }
    }
    const localizedName = String(set?.name || '').trim();
    if (!localizedName || compactText(localizedName) === compactText(row.name)) {
      counts.skipped += 1;
      continue;
    }
    translations.push({
      language,
      expansionName: row.name,
      localizedName,
      sourceSetId: String(set.id || ''),
      matchConfidence: confidence,
      matchReason: reason,
      source,
      rawMetadata: { set, limitlessSupport: support?.raw || null, input: row },
    });
    counts.matched += 1;
    counts.bySource[source] = (counts.bySource[source] || 0) + 1;
  }
  return { translations, counts };
}

function cardTranslationsForLanguage(rows, localizedCards, language, options = {}) {
  const localizedIndex = indexLocalizedCards(localizedCards);
  const englishIndex = options.englishCards ? indexEnglishCards(options.englishCards) : null;
  const translations = [];
  const counts = { checked: 0, matched: 0, skipped: 0, ambiguous: 0, bySource: {} };
  for (const row of rows) {
    counts.checked += 1;
    const match = localizedCardForRow(
      row,
      localizedIndex,
      options.limitlessFallback === false ? null : englishIndex,
    );
    if (!match) {
      counts.skipped += 1;
      continue;
    }
    const localizedName = String(match.card.name || '').trim();
    if (!localizedName || compactText(localizedName) === compactText(row.name)) {
      counts.skipped += 1;
      continue;
    }
    translations.push({
      language,
      name: row.name,
      localizedName,
      sourceCardId: match.card.id,
      matchConfidence: match.confidence,
      matchReason: match.reason,
      source: match.source || 'tcgdex',
      rawMetadata: {
        sourceCard: match.card.raw,
        limitlessSupport: match.support?.raw || null,
        input: row,
      },
    });
    counts.matched += 1;
    counts.bySource[match.source || 'tcgdex'] = (counts.bySource[match.source || 'tcgdex'] || 0) + 1;
  }
  return { translations, counts };
}

function uniqueRows(rows, keyFn) {
  return [...new Map(rows.map((row) => [keyFn(row), row])).values()];
}

function upsertCardTranslationsSql(rowCount) {
  const rows = Array.from({ length: rowCount }, (_, index) => {
    const base = index * 8;
    return `($${base + 1}, $${base + 2}, $${base + 3}, $${base + 4}, $${base + 5}, $${base + 6}::numeric, $${base + 7}, $${base + 8}::jsonb)`;
  }).join(', ');
  return `
    insert into public.marketplace_card_name_translations (
      language,
      name,
      localized_name,
      normalized_localized_name,
      compact_localized_name,
      localized_name_tokens,
      source,
      source_card_id,
      match_confidence,
      match_reason,
      raw_metadata,
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
      source.match_confidence,
      source.match_reason,
      source.raw_metadata,
      now()
    from (values ${rows}) as source(language, name, localized_name, source, source_card_id, match_confidence, match_reason, raw_metadata)
    on conflict (language, name) do update set
      localized_name = excluded.localized_name,
      normalized_localized_name = excluded.normalized_localized_name,
      compact_localized_name = excluded.compact_localized_name,
      localized_name_tokens = excluded.localized_name_tokens,
      source = excluded.source,
      source_card_id = excluded.source_card_id,
      match_confidence = excluded.match_confidence,
      match_reason = excluded.match_reason,
      raw_metadata = excluded.raw_metadata,
      updated_at = now()
    where public.marketplace_card_name_translations.source <> 'tcgdex'
       or excluded.source = 'tcgdex'
  `;
}

function cardTranslationValues(rows) {
  return rows.flatMap((row) => [
    row.language,
    row.name,
    row.localizedName,
    row.source || 'tcgdex',
    row.sourceCardId,
    row.matchConfidence,
    row.matchReason,
    JSON.stringify(row.rawMetadata || {}),
  ]);
}

function upsertExpansionTranslationsSql(rowCount) {
  const rows = Array.from({ length: rowCount }, (_, index) => {
    const base = index * 8;
    return `($${base + 1}, $${base + 2}, $${base + 3}, $${base + 4}, $${base + 5}, $${base + 6}::numeric, $${base + 7}, $${base + 8}::jsonb)`;
  }).join(', ');
  return `
    insert into public.marketplace_expansion_name_translations (
      language,
      expansion_name,
      localized_name,
      normalized_localized_name,
      compact_localized_name,
      localized_name_tokens,
      source,
      source_set_id,
      match_confidence,
      match_reason,
      raw_metadata,
      updated_at
    )
    select
      source.language,
      source.expansion_name,
      source.localized_name,
      public.marketplace_search_normalize(source.localized_name),
      public.marketplace_search_compact(source.localized_name),
      public.marketplace_search_tokenize(source.localized_name),
      source.source,
      source.source_set_id,
      source.match_confidence,
      source.match_reason,
      source.raw_metadata,
      now()
    from (values ${rows}) as source(language, expansion_name, localized_name, source, source_set_id, match_confidence, match_reason, raw_metadata)
    on conflict (language, expansion_name, localized_name) do update set
      normalized_localized_name = excluded.normalized_localized_name,
      compact_localized_name = excluded.compact_localized_name,
      localized_name_tokens = excluded.localized_name_tokens,
      source = excluded.source,
      source_set_id = excluded.source_set_id,
      match_confidence = excluded.match_confidence,
      match_reason = excluded.match_reason,
      raw_metadata = excluded.raw_metadata,
      updated_at = now()
    where public.marketplace_expansion_name_translations.source <> 'tcgdex'
       or excluded.source = 'tcgdex'
  `;
}

function expansionTranslationValues(rows) {
  return rows.flatMap((row) => [
    row.language,
    row.expansionName,
    row.localizedName,
    row.source || 'tcgdex',
    row.sourceSetId,
    row.matchConfidence,
    row.matchReason,
    JSON.stringify(row.rawMetadata || {}),
  ]);
}

async function upsertRows(pool, rows, batchSize, sqlFn, valuesFn) {
  let upserted = 0;
  for (let offset = 0; offset < rows.length; offset += batchSize) {
    const batch = rows.slice(offset, offset + batchSize);
    await pool.query(sqlFn(batch.length), valuesFn(batch));
    upserted += batch.length;
  }
  return upserted;
}

function mergeCounts(target, language, kind, counts, upserted = 0) {
  target.languages[language] ||= {};
  target.languages[language][kind] = {
    ...counts,
    upserted,
  };
}

async function importTranslations({ pool, options }) {
  const counts = {
    mode: options.apply ? 'apply' : 'dry-run',
    source: 'tcgdex',
    limitlessFallback: options.limitlessFallback,
    languages: {},
  };
  const marketplaceCards = options.importCards
    ? await loadMarketplaceCards(pool, options.limit, options)
    : [];
  const marketplaceExpansions = options.importExpansions
    ? await loadMarketplaceExpansions(pool, options.expansionLimit, options)
    : [];
  let englishCardsPromise = null;
  let englishSetsPromise = null;
  const loadEnglishCards = () => {
    englishCardsPromise ||= new TcgDexClient({ ...options, language: 'en' }).cards();
    return englishCardsPromise;
  };
  const loadEnglishSets = () => {
    englishSetsPromise ||= new TcgDexClient({ ...options, language: 'en' }).sets();
    return englishSetsPromise;
  };
  const needsLimitlessCardFallback = options.limitlessFallback && marketplaceCards.some((row) =>
    (!row.tcgdexCardId || !row.tcgdexSetId) &&
    (row.limitlessSourceCardId || row.limitlessCardKey || row.limitlessSetCode));
  const needsLimitlessExpansionFallback = options.limitlessFallback && marketplaceExpansions.some((row) =>
    !row.tcgdexSetId &&
    (row.limitlessExpansionName || row.limitlessExpansionCode || row.limitlessAliases.length > 0));

  for (const language of options.languages) {
    const client = new TcgDexClient({ ...options, language });
    if (options.importCards) {
      const localizedCards = await client.cards();
      const englishCards = needsLimitlessCardFallback ? await loadEnglishCards() : null;
      const { translations, counts: cardCounts } = cardTranslationsForLanguage(
        marketplaceCards,
        localizedCards,
        language,
        { englishCards, limitlessFallback: options.limitlessFallback },
      );
      const unique = uniqueRows(translations, (row) => `${row.language}\0${row.name}`);
      const upserted = options.apply
        ? await upsertRows(pool, unique, options.batchSize, upsertCardTranslationsSql, cardTranslationValues)
        : 0;
      mergeCounts(counts, language, 'cards', { ...cardCounts, unique: unique.length }, upserted);
    }
    if (options.importExpansions) {
      const localizedSets = await client.sets();
      const englishSets = needsLimitlessExpansionFallback ? await loadEnglishSets() : null;
      const { translations, counts: expansionCounts } = expansionTranslationsForLanguage(
        marketplaceExpansions,
        localizedSets,
        language,
        { englishSets, limitlessFallback: options.limitlessFallback },
      );
      const unique = uniqueRows(translations, (row) => `${row.language}\0${row.expansionName}\0${row.localizedName}`);
      const upserted = options.apply
        ? await upsertRows(pool, unique, options.batchSize, upsertExpansionTranslationsSql, expansionTranslationValues)
        : 0;
      mergeCounts(counts, language, 'expansions', { ...expansionCounts, unique: unique.length }, upserted);
    }
  }
  return counts;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  loadEnvFile(path.join(ROOT_DIR, '.env.local'));
  loadEnvFile(options.envFile);
  const pool = createPool();
  try {
    await assertWritablePrimary(pool, options.apply);
    const counts = await importTranslations({ pool, options });
    console.log(JSON.stringify(counts, null, 2));
    if (!options.apply) {
      console.log('Dry run only; pass --apply after reviewing counts and sample mapping quality.');
    }
  } finally {
    await pool.end();
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error && error.stack ? error.stack : error);
    process.exitCode = 1;
  });
}

module.exports = {
  TcgDexClient,
  cardTranslationsForLanguage,
  compactText,
  expansionTranslationsForLanguage,
  indexEnglishCards,
  indexEnglishSets,
  indexLocalizedCards,
  localizedCardForRow,
  normalizeCollectorNumber,
  normalizeLanguage,
  normalizeText,
  parseArgs,
  parseLanguages,
  upsertCardTranslationsSql,
  upsertExpansionTranslationsSql,
};
