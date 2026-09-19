const { cleanToken, fetchMarketplaceProducts } = require('./_cardtrader_client');
const { getMarketplacePool, marketplaceQuery } = require('./_marketplace_db');
const { publicSellerComment } = require('./_seller_comment_filter');

const PROVIDER = 'cardtrader';
const DEFAULT_MAX_BLUEPRINTS = 100_000;
const DEFAULT_MAX_PRODUCTS = 1_000_000;
const DEFAULT_MAX_EXPANSIONS = 10_000;
const MAX_BLUEPRINTS_PER_RUN = 100_000;
const MAX_PRODUCTS_PER_RUN = 1_000_000;
const MAX_EXPANSIONS_PER_RUN = 10_000;
const DEFAULT_BLUEPRINT_REQUEST_DELAY_MS = 200;
const DEFAULT_BLUEPRINT_BATCH_SIZE = 100;
const DEFAULT_BLUEPRINT_CONCURRENCY = 1;
const DEFAULT_EXPANSION_CONCURRENCY = 1;
const DEFAULT_PERSIST_CONCURRENCY = 1;
const DEFAULT_REFRESH_BATCH_BLUEPRINTS = 0;
const MAX_BLUEPRINT_BATCH_SIZE = 1_000;
const MAX_BLUEPRINT_CONCURRENCY = 50;
const MAX_EXPANSION_CONCURRENCY = 16;
const MAX_PERSIST_CONCURRENCY = 4;
const MAX_REFRESH_BATCH_BLUEPRINTS = 10_000;
const MAX_EXPANSION_SHARD_COUNT = 8;
const RATE_LIMIT_DELAY_MS = 5_000;
const MAX_RATE_LIMIT_RETRIES = 5;
const CARDTRADER_CHEAPEST_LISTING_LIMIT = 25;
const CARDTRADER_REFRESH_ADVISORY_LOCK = 872014433;

function cleanText(value, maxLength = 240) {
  return String(value || '').trim().slice(0, maxLength);
}

function cleanPositiveInteger(value, fallback, min, max) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(Math.max(Math.trunc(number), min), max);
}

function cleanBoolean(value, fallback = false) {
  if (value === true || value === 'true' || value === '1' || value === 1) return true;
  if (value === false || value === 'false' || value === '0' || value === 0) return false;
  return fallback;
}

function configuredCardTraderApiToken(env = process.env) {
  return cleanToken(env.CARDTRADER_AUTH_TOKEN || env.CARDTRADER_API_TOKEN || '');
}

function requireCardTraderApiToken(env = process.env) {
  const token = configuredCardTraderApiToken(env);
  if (!token) {
    const error = new Error(
      'Global CardTrader API token is not configured. Set CARDTRADER_AUTH_TOKEN or CARDTRADER_API_TOKEN.',
    );
    error.statusCode = 503;
    error.code = 'CARDTRADER_GLOBAL_API_TOKEN_MISSING';
    throw error;
  }
  return token;
}

function dateOnly(value) {
  return value.toISOString().slice(0, 10);
}

function removedDayForRefreshDate(value = new Date()) {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return dateOnly(new Date(Date.now() - 86_400_000));
  const previous = new Date(Date.UTC(
    date.getUTCFullYear(),
    date.getUTCMonth(),
    date.getUTCDate() - 1,
  ));
  return dateOnly(previous);
}

function cleanDate(value, fallback = removedDayForRefreshDate()) {
  const text = cleanText(value, 20);
  return /^\d{4}-\d{2}-\d{2}$/.test(text) ? text : fallback;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function createExclusiveLock() {
  let chain = Promise.resolve();
  return async function runExclusive(fn) {
    const previous = chain;
    let release = () => {};
    chain = new Promise((resolve) => {
      release = resolve;
    });
    await previous;
    try {
      return await fn();
    } finally {
      release();
    }
  };
}

function createSemaphore(limit) {
  const max = Math.max(1, Number(limit) || 1);
  let active = 0;
  const waiters = [];
  return async function runLimited(fn) {
    if (active >= max) {
      await new Promise((resolve) => waiters.push(resolve));
    }
    active += 1;
    try {
      return await fn();
    } finally {
      active -= 1;
      const next = waiters.shift();
      if (next) next();
    }
  };
}

async function queryWithDisabledStatementTimeout(query, text, values = [], options = {}) {
  if (query !== marketplaceQuery) {
    return query(text, values);
  }
  const advisoryLockKey = Number.isFinite(Number(options.advisoryLockKey))
    ? Math.trunc(Number(options.advisoryLockKey))
    : null;
  const client = await getMarketplacePool().connect();
  if (typeof client.on === 'function') {
    client.on('error', () => {});
  }
  let locked = false;
  try {
    // Session timeouts must die before pg_advisory_lock: the 1 GB primary uses
    // statement_timeout=30s and idle_in_transaction_session_timeout=15s, and
    // the other Oracle micro can hold this lock for minutes on a large set.
    await client.query('SET statement_timeout = 0');
    await client.query('SET lock_timeout = 0');
    await client.query('SET idle_in_transaction_session_timeout = 0');
    if (advisoryLockKey != null) {
      await client.query('SELECT pg_advisory_lock($1::bigint)', [advisoryLockKey]);
      locked = true;
    }
    await client.query('BEGIN');
    await client.query('SET LOCAL statement_timeout = 0');
    await client.query('SET LOCAL lock_timeout = 0');
    await client.query('SET LOCAL idle_in_transaction_session_timeout = 0');
    const result = await client.query(text, values);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch {
      // Keep the original query error.
    }
    throw error;
  } finally {
    if (locked) {
      try {
        await client.query('SELECT pg_advisory_unlock($1::bigint)', [advisoryLockKey]);
      } catch {
        // Connection drop releases session locks.
      }
    }
    client.release();
  }
}

function isCardTraderRateLimitError(error) {
  return error && error.statusCode === 502 && /HTTP 429\b/.test(String(error.message || ''));
}

function isTransientCardTraderFetchError(error) {
  if (isCardTraderRateLimitError(error)) return true;
  const message = String(error && error.message ? error.message : '');
  const code = String((error && error.cause && error.cause.code) || error.code || '');
  return message === 'fetch failed'
    || /ECONNRESET|ETIMEDOUT|EAI_AGAIN|UND_ERR|socket hang up/i.test(`${message} ${code}`);
}

function isTransientPostgresError(error) {
  const message = String(error && error.message ? error.message : '');
  const code = String(error && error.code ? error.code : '');
  return code === '57014'
    || code === '25P03'
    || code === '55P03'
    || /Connection terminated|not yet accepting connections|in recovery mode|ECONNRESET|connection refused|statement timeout|idle-in-transaction timeout/i.test(`${message} ${code}`);
}

function numericOrNull(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function integerOrNull(value) {
  if (value == null || value === '') return null;
  const number = Number(value);
  return Number.isSafeInteger(number) ? Math.trunc(number) : null;
}

function uniquePositiveIntegers(values) {
  return [...new Set((Array.isArray(values) ? values : [])
    .map((value) => integerOrNull(value))
    .filter((value) => value != null && value > 0))];
}

function parseIntegerList(value) {
  if (Array.isArray(value)) return uniquePositiveIntegers(value);
  return uniquePositiveIntegers(String(value || '').split(',').map((item) => item.trim()));
}

function optionValue(input, name) {
  if (typeof input === 'function') return input(name);
  return input && typeof input === 'object' ? input[name] : undefined;
}

function pokoinPublicNumber(blueprintId) {
  return blueprintId == null ? '' : String(blueprintId * 2);
}

function normalizeRefreshOptions(input = {}) {
  const get = (name) => optionValue(input, name);
  const dryRun = cleanBoolean(get('dryRun'), false);
  const blueprintIds = parseIntegerList(get('blueprintIds') ?? get('blueprint_ids'));
  const singleBlueprintId = integerOrNull(get('blueprintId') ?? get('blueprint_id'));
  if (singleBlueprintId != null) blueprintIds.unshift(singleBlueprintId);
  const expansionIds = parseIntegerList(get('expansionIds') ?? get('expansion_ids'));
  const singleExpansionId = integerOrNull(get('expansionId') ?? get('expansion_id'));
  if (singleExpansionId != null) expansionIds.unshift(singleExpansionId);
  const uniqueExpansionIds = uniquePositiveIntegers(expansionIds);
  const byBlueprint = cleanBoolean(get('byBlueprint') ?? get('by_blueprint'), false);
  const completeBook = byBlueprint || cleanBoolean(get('completeBook') ?? get('complete_book'), false);
  return {
    dryRun,
    byBlueprint,
    completeBook,
    finalize: cleanBoolean(get('finalize'), !dryRun),
    recordAskObservations: cleanBoolean(
      get('recordAskObservations') ?? get('record_ask_observations'),
      false,
    ),
    archiveMissing: cleanBoolean(get('archiveMissing'), !dryRun),
    maxBlueprints: cleanPositiveInteger(
      get('maxBlueprints') ?? get('maxBlueprintsPerRun'),
      DEFAULT_MAX_BLUEPRINTS,
      1,
      MAX_BLUEPRINTS_PER_RUN,
    ),
    maxProducts: cleanPositiveInteger(
      get('maxProducts'),
      completeBook ? 20_000_000 : DEFAULT_MAX_PRODUCTS,
      1,
      20_000_000,
    ),
    cheapestListingLimit: completeBook ? 0 : CARDTRADER_CHEAPEST_LISTING_LIMIT,
    maxExpansions: cleanPositiveInteger(
      get('maxExpansions') ?? get('max_expansions'),
      dryRun && uniqueExpansionIds.length === 0 && blueprintIds.length === 0 ? 1 : DEFAULT_MAX_EXPANSIONS,
      1,
      MAX_EXPANSIONS_PER_RUN,
    ),
    requestDelayMs: cleanPositiveInteger(
      get('requestDelayMs') ?? get('request_delay_ms'),
      DEFAULT_BLUEPRINT_REQUEST_DELAY_MS,
      0,
      10_000,
    ),
    blueprintBatchSize: cleanPositiveInteger(
      get('blueprintBatchSize') ?? get('blueprint_batch_size') ?? get('blueprint-batch-size'),
      DEFAULT_BLUEPRINT_BATCH_SIZE,
      1,
      MAX_BLUEPRINT_BATCH_SIZE,
    ),
    blueprintConcurrency: cleanPositiveInteger(
      get('blueprintConcurrency') ?? get('blueprint_concurrency') ?? get('blueprint-concurrency'),
      DEFAULT_BLUEPRINT_CONCURRENCY,
      1,
      MAX_BLUEPRINT_CONCURRENCY,
    ),
    expansionConcurrency: cleanPositiveInteger(
      get('expansionConcurrency') ?? get('expansion_concurrency') ?? get('expansion-concurrency'),
      DEFAULT_EXPANSION_CONCURRENCY,
      1,
      MAX_EXPANSION_CONCURRENCY,
    ),
    persistConcurrency: cleanPositiveInteger(
      get('persistConcurrency') ?? get('persist_concurrency') ?? get('persist-concurrency'),
      DEFAULT_PERSIST_CONCURRENCY,
      1,
      MAX_PERSIST_CONCURRENCY,
    ),
    refreshBatchBlueprints: cleanPositiveInteger(
      get('refreshBatchBlueprints') ?? get('refresh_batch_blueprints') ?? get('refresh-batch-blueprints'),
      DEFAULT_REFRESH_BATCH_BLUEPRINTS,
      0,
      MAX_REFRESH_BATCH_BLUEPRINTS,
    ),
    removedDay: cleanDate(get('removedDay')),
    blueprintIds: uniquePositiveIntegers(blueprintIds).slice(0, MAX_BLUEPRINTS_PER_RUN),
    expansionIds: uniqueExpansionIds.slice(0, MAX_EXPANSIONS_PER_RUN),
    expansionId: uniqueExpansionIds.length === 1 ? uniqueExpansionIds[0] : null,
    minExpansionId: integerOrNull(get('minExpansionId') ?? get('min_expansion_id') ?? get('min-expansion-id')),
    expansionShardCount: cleanPositiveInteger(
      get('expansionShardCount') ?? get('expansion_shard_count') ?? get('shard-count') ?? get('shardCount'),
      1,
      1,
      MAX_EXPANSION_SHARD_COUNT,
    ),
    expansionShardIndex: cleanPositiveInteger(
      get('expansionShardIndex') ?? get('expansion_shard_index') ?? get('shard-index') ?? get('shardIndex'),
      0,
      0,
      MAX_EXPANSION_SHARD_COUNT - 1,
    ),
    language: cleanText(get('language'), 8),
    catalogBlueprintIds: uniquePositiveIntegers(
      get('catalogBlueprintIds') ?? get('catalog_blueprint_ids'),
    ),
    onProgress: typeof get('onProgress') === 'function' ? get('onProgress') : undefined,
  };
}

function objectOrEmpty(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
}

function firstText(...values) {
  for (const value of values) {
    const text = cleanText(value, 240);
    if (text) return text;
  }
  return '';
}

function normalizeLanguage(value) {
  const text = cleanText(value, 40);
  if (!text) return '';
  const lowered = text.toLowerCase();
  if (lowered === 'english') return 'en';
  if (lowered === 'italian') return 'it';
  if (lowered === 'japanese') return 'ja';
  if (lowered === 'french') return 'fr';
  if (lowered === 'german') return 'de';
  if (lowered === 'spanish') return 'es';
  if (lowered === 'korean') return 'ko';
  if (lowered === 'chinese') return 'zh';
  return text;
}

function cardTraderShippingMode(product = {}, user = {}) {
  const text = [
    user.username,
    user.name,
    user.display_name,
    product.seller_name,
    product.name_en,
    product.description,
  ].map((value) => String(value || '')).join(' ');
  return /(^|[^a-z0-9])((1|one)[\s-]*day[\s-]*ready)([^a-z0-9]|$)/i.test(text)
    ? 'one_day_ready'
    : '';
}

function isTruthyProp(value) {
  if (value === true || value === 1) return true;
  return ['true', '1', 'yes'].includes(String(value || '').trim().toLowerCase());
}

function isReverseProduct(properties = {}) {
  return isTruthyProp(properties.pokemon_reverse)
    || String(properties.foil_state || properties.foilState || '').trim().toLowerCase() === 'reverse';
}

function isFirstEditionProduct(properties = {}) {
  return isTruthyProp(properties.first_edition)
    || isTruthyProp(properties.firstEdition)
    || isTruthyProp(properties.pokemon_first_edition);
}

function isGradedProduct(product = {}, properties = {}) {
  return isTruthyProp(product.graded) || isTruthyProp(properties.graded);
}

function gradedOnlyComment(product = {}, properties = {}) {
  if (!isGradedProduct(product, properties)) {
    return '';
  }
  return publicSellerComment(firstText(
    product.seller_comment,
    product.sellerComment,
    product.description,
    properties.seller_comment,
    properties.sellerComment,
  ));
}

function slimCardTraderMarketProduct(product = {}, fallbackBlueprintId = null) {
  const user = objectOrEmpty(product.user || product.seller);
  const expansion = objectOrEmpty(product.expansion);
  const properties = objectOrEmpty(product.properties_hash || product.properties);
  const priceObject = objectOrEmpty(product.price);
  const shippingMode = cardTraderShippingMode(product, user);
  const reverse = isReverseProduct(properties);
  const firstEdition = isFirstEditionProduct(properties);
  const comment = gradedOnlyComment(product, properties);
  return {
    id: product.id ?? product.product_id ?? product.listing_id,
    blueprint_id: product.blueprint_id ?? product.blueprintId ?? fallbackBlueprintId,
    quantity: product.quantity ?? product.qty,
    price: product.price && typeof product.price === 'object'
      ? { cents: priceObject.cents, currency: priceObject.currency }
      : product.price,
    price_cents: product.price_cents ?? product.priceCents ?? priceObject.cents,
    currency: product.currency ?? product.price_currency ?? priceObject.currency,
    description: product.description,
    graded: product.graded,
    on_vacation: product.on_vacation,
    bundle_size: product.bundle_size,
    properties_hash: {
      ...properties,
      ...(shippingMode ? { shipping_mode: shippingMode } : {}),
      ...(reverse ? { foil_state: 'reverse' } : {}),
      ...(firstEdition ? { first_edition: true } : {}),
      ...(comment ? { seller_comment: comment } : {}),
    },
    expansion: expansion.id == null ? undefined : {
      id: expansion.id,
      code: expansion.code,
      name_en: expansion.name_en,
    },
    user: {
      id: user.id ?? user.user_id,
      username: user.username ?? user.name,
      country_code: user.country_code ?? user.country,
      user_type: user.user_type,
      can_sell_via_hub: user.can_sell_via_hub,
      can_sell_sealed_with_ct_zero: user.can_sell_sealed_with_ct_zero,
    },
  };
}

function normalizeCardTraderMarketProduct(product = {}, fallbackBlueprintId = null) {
  const slim = slimCardTraderMarketProduct(product, fallbackBlueprintId);
  const properties = objectOrEmpty(slim.properties_hash);
  const priceObject = objectOrEmpty(slim.price);
  const user = objectOrEmpty(slim.user);
  const externalListingId = cleanText(slim.id, 160);
  const blueprintId = numericOrNull(slim.blueprint_id ?? fallbackBlueprintId);
  const priceCents = integerOrNull(slim.price_cents ?? priceObject.cents);
  const price = numericOrNull(typeof slim.price === 'number' ? slim.price : slim.price_amount) ??
    (priceCents == null ? null : priceCents / 100);
  return {
    externalListingId,
    externalProductId: cleanText(slim.id, 160),
    sellerAccountId: cleanText(user.id, 160),
    sellerAccountName: firstText(user.username, user.name),
    sellerCountry: cleanText(user.country_code, 40),
    sellerType: cleanText(user.user_type, 80),
    blueprintId,
    cardtraderBlueprintId: blueprintId,
    pokoinCardId: pokoinPublicNumber(blueprintId),
    quantity: Math.max(integerOrNull(slim.quantity) ?? 0, 0),
    condition: firstText(product.condition, product.state, properties.condition, properties.pokemon_condition),
    language: normalizeLanguage(firstText(
      product.language,
      product.lang,
      properties.language,
      properties.pokemon_language,
      properties.mtg_language,
    )),
    price,
    priceCents,
    currency: cleanText(slim.currency ?? priceObject.currency ?? 'EUR', 12),
    properties,
    rawMetadata: slim,
  };
}

function safeRefreshSample(row = {}) {
  return {
    externalListingId: row.externalListingId || '',
    blueprintId: row.blueprintId,
    pokoinCardId: row.pokoinCardId || '',
    quantity: row.quantity,
    condition: row.condition,
    language: row.language,
    priceCents: row.priceCents,
    currency: row.currency,
  };
}

function listingPriceCents(row = {}) {
  if (Number.isFinite(row.priceCents)) return row.priceCents;
  if (Number.isFinite(row.price)) return Math.round(row.price * 100);
  return Number.POSITIVE_INFINITY;
}

function populationFromListingRows(rows = [], blueprintId = null) {
  const sellers = new Set();
  let listedQuantity = 0;
  let listingCount = 0;
  for (const row of rows) {
    listingCount += 1;
    listedQuantity += Math.max(0, Number(row.quantity) || 0);
    const seller = cleanText(row.sellerAccountId, 160);
    if (seller) sellers.add(seller);
  }
  return {
    blueprintId: blueprintId == null ? null : blueprintId,
    listingCount,
    listedQuantity,
    sellerCount: sellers.size,
    capped: listingCount >= CARDTRADER_CHEAPEST_LISTING_LIMIT,
  };
}

function takeCheapestRows(rows, limit = CARDTRADER_CHEAPEST_LISTING_LIMIT) {
  if (!limit || !Array.isArray(rows) || rows.length <= limit) return rows || [];
  return rows
    .slice()
    .sort((left, right) => {
      const priceDelta = listingPriceCents(left) - listingPriceCents(right);
      if (priceDelta !== 0) return priceDelta;
      return String(left.externalListingId || '').localeCompare(String(right.externalListingId || ''));
    })
    .slice(0, limit);
}

function appendCappedRows(
  target,
  incoming,
  productLimit,
  cheapestListingLimit = CARDTRADER_CHEAPEST_LISTING_LIMIT,
) {
  let truncated = false;
  for (const row of takeCheapestRows(incoming, cheapestListingLimit)) {
    if (target.length >= productLimit) {
      truncated = true;
      break;
    }
    target.push(row);
  }
  return truncated;
}

function rowsFromMarketplacePayload(
  payload = {},
  productLimit = DEFAULT_MAX_PRODUCTS,
  cheapestListingLimit = CARDTRADER_CHEAPEST_LISTING_LIMIT,
) {
  const rows = [];
  const blueprintIds = new Set();
  const populations = [];
  let truncated = false;
  if (Array.isArray(payload)) {
    const byBlueprint = new Map();
    for (const product of payload) {
      const row = normalizeCardTraderMarketProduct(product);
      if (row.blueprintId != null) blueprintIds.add(row.blueprintId);
      if (!row.externalListingId) continue;
      const key = row.blueprintId == null ? `none:${row.externalListingId}` : row.blueprintId;
      if (!byBlueprint.has(key)) byBlueprint.set(key, []);
      byBlueprint.get(key).push(row);
    }
    for (const [key, group] of byBlueprint.entries()) {
      const blueprintId = typeof key === 'number' ? key : numericOrNull(key);
      if (blueprintId != null) {
        populations.push(populationFromListingRows(group, blueprintId));
      }
      if (appendCappedRows(rows, group, productLimit, cheapestListingLimit)) {
        truncated = true;
        break;
      }
    }
    return { rows, blueprintIds: [...blueprintIds], truncated, populations };
  }

  for (const [blueprintIdText, products] of Object.entries(objectOrEmpty(payload))) {
    const blueprintId = numericOrNull(blueprintIdText);
    if (blueprintId != null) blueprintIds.add(blueprintId);
    if (!Array.isArray(products)) continue;
    const group = [];
    for (const product of products) {
      const row = normalizeCardTraderMarketProduct(product, blueprintId);
      if (row.blueprintId != null) blueprintIds.add(row.blueprintId);
      if (!row.externalListingId) continue;
      group.push(row);
    }
    if (blueprintId != null) {
      populations.push(populationFromListingRows(group, blueprintId));
    }
    if (appendCappedRows(rows, group, productLimit, cheapestListingLimit)) {
      truncated = true;
      break;
    }
  }
  return { rows, blueprintIds: [...blueprintIds], truncated, populations };
}

async function readBlueprintIdsFromOracle(limit, query = marketplaceQuery) {
  const result = await query(
    `
      select ct_id as blueprint_id
      from public.marketplace_search_candidates
      where ct_id is not null
      order by search_weight desc, imported_at desc nulls last, ct_id desc
      limit $1
    `,
    [limit],
  );
  return uniquePositiveIntegers(result.rows.map((row) => row.blueprint_id));
}

async function readCatalogExpansionsFromOracle(query = marketplaceQuery) {
  const result = await query(
    `
      select
        expansion_id,
        coalesce(array_agg(id order by id), '{}'::bigint[]) as blueprint_ids
      from public.pokoin_pokemon_blueprints
      where expansion_id is not null
      group by expansion_id
      order by expansion_id
    `,
  );
  return result.rows
    .map((row) => ({
      expansionId: integerOrNull(row.expansion_id),
      blueprintIds: uniquePositiveIntegers(row.blueprint_ids),
    }))
    .filter((row) => row.expansionId != null);
}

async function readUngroupedBlueprintIdsFromOracle(limit = DEFAULT_MAX_BLUEPRINTS, query = marketplaceQuery) {
  const result = await query(
    `
      select id as blueprint_id
      from public.pokoin_pokemon_blueprints
      where expansion_id is null
      order by id
      limit $1
    `,
    [limit],
  );
  return uniquePositiveIntegers(result.rows.map((row) => row.blueprint_id));
}

async function refreshOracleSnapshots({
  rows,
  scopeBlueprintIds,
  removedDay,
  archiveMissing,
  finalize = true,
  recordAskObservations = false,
  completeBook = false,
  env = process.env,
  query = marketplaceQuery,
}) {
  const pknReferencePrice = Number(env.PKN_CHECKOUT_USDT_PRICE || 0.005);
  const result = await queryWithDisabledStatementTimeout(
    query,
    `
      with settings as (
        select set_config('app.pkn_usdt_price', $6::text, true),
               set_config('app.cardtrader_complete_book', $9::text, true)
      )
      select *
      from settings,
      lateral (
      select *
      from public.refresh_cardtrader_market_listing_snapshots(
        $1::text,
        $2::jsonb,
        $3::jsonb,
        $4::date,
        $5::boolean,
        now(),
        $7::boolean,
        $8::boolean
      )
      ) refreshed
    `,
    [
      PROVIDER,
      JSON.stringify(rows),
      JSON.stringify(scopeBlueprintIds),
      removedDay,
      archiveMissing,
      String(Number.isFinite(pknReferencePrice) && pknReferencePrice > 0 ? pknReferencePrice : 0.005),
      finalize,
      recordAskObservations,
      completeBook ? '1' : '',
    ],
    { advisoryLockKey: CARDTRADER_REFRESH_ADVISORY_LOCK },
  );
  const row = result.rows[0] || {};
  return {
    archivedCount: Number(row.archived_count || 0),
    deletedCount: Number(row.deleted_count || 0),
    upsertedCount: Number(row.upserted_count || 0),
    cacheRefreshedCount: Number(row.cache_refreshed_count || 0),
  };
}

async function upsertCardTraderBlueprintPopulation({
  populations,
  observedDay,
  query = marketplaceQuery,
} = {}) {
  const rows = (Array.isArray(populations) ? populations : [])
    .filter((row) => row && row.blueprintId != null)
    .map((row) => ({
      blueprint_id: row.blueprintId,
      listing_count: Math.max(0, Number(row.listingCount) || 0),
      listed_quantity: Math.max(0, Number(row.listedQuantity) || 0),
      seller_count: Math.max(0, Number(row.sellerCount) || 0),
      new_listings: Math.max(0, Number(row.newListings) || 0),
      new_quantity: Math.max(0, Number(row.newQuantity) || 0),
      capped: Boolean(row.capped),
    }));
  if (!rows.length) return 0;
  const result = await query(
    `
      select public.upsert_cardtrader_blueprint_population($1::date, $2::jsonb) as upserted_count
    `,
    [observedDay || dateOnly(new Date()), JSON.stringify(rows)],
  );
  return Number(result.rows[0]?.upserted_count || 0);
}

async function finalizeDailyRefresh({
  removedDay,
  env = process.env,
  query = marketplaceQuery,
} = {}) {
  const pknReferencePrice = Number(env.PKN_CHECKOUT_USDT_PRICE || 0.005);
  const result = await queryWithDisabledStatementTimeout(
    query,
    `
      with settings as (
        select set_config('app.pkn_usdt_price', $2::text, true)
      )
      select *
      from settings,
      lateral (
        select *
        from public.finalize_cardtrader_daily_market_refresh(
          $3::text,
          $1::date,
          now()
        )
      ) finalized
    `,
    [
      removedDay || removedDayForRefreshDate(),
      String(Number.isFinite(pknReferencePrice) && pknReferencePrice > 0 ? pknReferencePrice : 0.005),
      PROVIDER,
    ],
  );
  const row = result.rows[0] || {};
  return {
    cacheRefreshedCount: Number(row.cache_refreshed_count || 0),
    analyticsCount: Number(row.analytics_count || 0),
    priceSummaryCount: Number(row.price_summary_count || 0),
  };
}

function emitRefreshProgress(options, event, payload = {}) {
  if (typeof options.onProgress !== 'function') return;
  options.onProgress({
    event,
    at: new Date().toISOString(),
    ...payload,
  });
}

async function fetchMarketplaceProductsWithRetry(token, params, options) {
  let payload;
  for (let attempt = 0; attempt <= MAX_RATE_LIMIT_RETRIES; attempt += 1) {
    try {
      payload = await fetchMarketplaceProducts(token, params);
      break;
    } catch (error) {
      if (!isTransientCardTraderFetchError(error) || attempt === MAX_RATE_LIMIT_RETRIES) {
        throw error;
      }
      await sleep(RATE_LIMIT_DELAY_MS * (attempt + 1));
    }
  }
  return payload;
}

async function fetchMarketplaceRowsForBlueprints(token, blueprintIds, options) {
  const rows = [];
  const populations = [];
  const fetchedBlueprintIds = [];
  const scopedBlueprintIds = blueprintIds.slice(0, options.maxBlueprints);
  const totalBatches = Math.ceil(scopedBlueprintIds.length / options.blueprintBatchSize);
  let launchedBlueprints = 0;
  let completedBlueprints = 0;
  let requestTurn = Promise.resolve();
  emitRefreshProgress(options, 'blueprint_fetch_start', {
    totalBlueprints: scopedBlueprintIds.length,
    maxProducts: options.maxProducts,
    blueprintBatchSize: options.blueprintBatchSize,
    blueprintConcurrency: options.blueprintConcurrency,
    requestDelayMs: options.requestDelayMs,
  });

  async function waitForRequestTurn() {
    const previousTurn = requestTurn;
    requestTurn = previousTurn.then(async () => {
      if (launchedBlueprints > 0 && options.requestDelayMs > 0) {
        await sleep(options.requestDelayMs);
      }
      launchedBlueprints += 1;
    });
    await requestTurn;
  }

  async function fetchBlueprintRows(blueprintId) {
    await waitForRequestTurn();
    const payload = await fetchMarketplaceProductsWithRetry(token, {
      blueprint_id: blueprintId,
      language: options.language,
    }, options);
    return rowsFromMarketplacePayload(
      payload,
      options.maxProducts,
      options.cheapestListingLimit ?? CARDTRADER_CHEAPEST_LISTING_LIMIT,
    );
  }

  function emitFetchProgress(blueprintId, completedBatches = 0, force = false) {
    if (
      force ||
      completedBlueprints === 1 ||
      completedBlueprints % 100 === 0 ||
      rows.length >= options.maxProducts ||
      completedBlueprints === scopedBlueprintIds.length
    ) {
      emitRefreshProgress(options, 'blueprint_fetch_progress', {
        fetchedBlueprints: completedBlueprints,
        totalBlueprints: scopedBlueprintIds.length,
        fetchedProducts: rows.length,
        lastBlueprintId: blueprintId,
        completedBatches,
        totalBatches,
      });
    }
  }

  for (let batchStart = 0; batchStart < scopedBlueprintIds.length; batchStart += options.blueprintBatchSize) {
    if (rows.length >= options.maxProducts) break;
    const batchIds = scopedBlueprintIds.slice(batchStart, batchStart + options.blueprintBatchSize);
    const completedBatches = Math.floor(batchStart / options.blueprintBatchSize) + 1;
    let nextBatchIndex = 0;
    let completedInBatch = 0;

    async function runWorker() {
      while (nextBatchIndex < batchIds.length && rows.length < options.maxProducts) {
        const blueprintId = batchIds[nextBatchIndex];
        nextBatchIndex += 1;
        const shaped = await fetchBlueprintRows(blueprintId);
        const fetchedRows = shaped.rows || [];
        const remainingProducts = options.maxProducts - rows.length;
        if (remainingProducts > 0) {
          rows.push(...fetchedRows.slice(0, remainingProducts));
        }
        if (Array.isArray(shaped.populations) && shaped.populations.length) {
          populations.push(...shaped.populations);
        } else if (blueprintId != null) {
          populations.push(populationFromListingRows(fetchedRows, blueprintId));
        }
        fetchedBlueprintIds.push(blueprintId);
        completedBlueprints += 1;
        completedInBatch += 1;
        emitFetchProgress(
          blueprintId,
          completedBatches,
          completedInBatch === batchIds.length || rows.length >= options.maxProducts,
        );
      }
    }

    const workerCount = Math.min(options.blueprintConcurrency, batchIds.length);
    await Promise.all(Array.from({ length: workerCount }, runWorker));
  }
  emitRefreshProgress(options, 'blueprint_fetch_done', {
    fetchedBlueprints: fetchedBlueprintIds.length,
    totalBlueprints: scopedBlueprintIds.length,
    fetchedProducts: rows.length,
  });
  return { rows, fetchedBlueprintIds, truncated: rows.length >= options.maxProducts, populations };
}

async function fetchMarketplaceRowsForExpansion(token, expansionId, options) {
  emitRefreshProgress(options, 'expansion_fetch_start', {
    expansionId,
    maxProducts: options.maxProducts,
    cheapestListingLimit: CARDTRADER_CHEAPEST_LISTING_LIMIT,
  });
  const payload = await fetchMarketplaceProductsWithRetry(token, {
    expansion_id: expansionId,
    language: options.language,
  }, options);
  const shaped = rowsFromMarketplacePayload(
    payload,
    options.maxProducts,
    options.cheapestListingLimit ?? CARDTRADER_CHEAPEST_LISTING_LIMIT,
  );
  const catalogBlueprintIds = options.catalogBlueprintIds.length > 0
    ? options.catalogBlueprintIds
    : [];
  const scopeBlueprintIds = uniquePositiveIntegers([
    ...catalogBlueprintIds,
    ...shaped.blueprintIds,
  ]).slice(0, options.maxBlueprints);
  emitRefreshProgress(options, 'expansion_fetch_done', {
    expansionId,
    fetchedProducts: shaped.rows.length,
    returnedBlueprints: shaped.blueprintIds.length,
    scopedBlueprints: scopeBlueprintIds.length,
    truncated: shaped.truncated,
  });
  return {
    rows: shaped.rows,
    fetchedBlueprintIds: scopeBlueprintIds,
    truncated: shaped.truncated,
    sourceMode: 'expansion_id',
    populations: shaped.populations || [],
  };
}

async function fetchMarketplaceRows(token, options) {
  if (options.expansionId != null && !options.byBlueprint) {
    return fetchMarketplaceRowsForExpansion(token, options.expansionId, options);
  }

  const requestedBlueprintIds = options.blueprintIds.length > 0
    ? options.blueprintIds
    : null;
  if (requestedBlueprintIds) {
    emitRefreshProgress(options, 'blueprint_pool_ready', {
      sourceMode: 'explicit_blueprint_ids',
      totalBlueprints: requestedBlueprintIds.length,
    });
  } else {
    emitRefreshProgress(options, 'blueprint_pool_read_start', {
      maxBlueprints: options.maxBlueprints,
    });
  }
  const blueprintIds = requestedBlueprintIds || await readBlueprintIdsFromOracle(options.maxBlueprints);
  emitRefreshProgress(options, 'blueprint_pool_ready', {
    sourceMode: requestedBlueprintIds ? 'explicit_blueprint_ids' : 'oracle_blueprint_pool',
    totalBlueprints: blueprintIds.length,
  });
  return {
    ...(await fetchMarketplaceRowsForBlueprints(token, blueprintIds, options)),
    sourceMode: requestedBlueprintIds ? 'explicit_blueprint_ids' : 'oracle_blueprint_pool',
  };
}

function emptyRefreshTotals() {
  return {
    expansionCount: 0,
    blueprintCount: 0,
    fetchedProducts: 0,
    shapedRows: 0,
    truncated: false,
    archivedCount: 0,
    deletedCount: 0,
    upsertedCount: 0,
    cacheRefreshedCount: 0,
  };
}

function addRefreshCounts(totals, counts, extra = {}) {
  totals.expansionCount += extra.expansionCount || 0;
  totals.blueprintCount += extra.blueprintCount || counts.blueprintCount || 0;
  totals.fetchedProducts += extra.fetchedProducts || 0;
  totals.shapedRows += extra.shapedRows || 0;
  totals.truncated ||= Boolean(extra.truncated);
  totals.archivedCount += counts.archivedCount || 0;
  totals.deletedCount += counts.deletedCount || 0;
  totals.upsertedCount += counts.upsertedCount || 0;
  totals.cacheRefreshedCount += counts.cacheRefreshedCount || 0;
  return totals;
}

function shouldArchiveMissingSales(options = {}, fetched = {}) {
  // D000070: disappearance from a VALID complete-book observation is an
  // inferred sale by default. Validity = the observation is flagged
  // complete-book AND the fetch was not truncated. Per-blueprint sanity
  // (stripped-quantity signatures vs population history) is enforced inside
  // refresh_cardtrader_market_listing_snapshots (086), which downgrades those
  // vanish rows to status='pending' instead of sales.
  return Boolean(options.archiveMissing)
    && !Boolean(fetched.truncated)
    && Boolean(options.completeBook);
}

async function persistFetchedRows(fetched, options, env) {
  const rows = fetched.rows.slice(0, options.maxProducts);
  const scopeBlueprintIds = uniquePositiveIntegers(fetched.fetchedBlueprintIds)
    .slice(0, options.maxBlueprints);
  // D000070: vanished stacks from a complete-book observation are inferred
  // sales unless the SQL-level sanity gate flags the blueprint (stripped
  // quantities, status='pending'). Cheap-25/partial fetches never archive.
  const archiveMissing = shouldArchiveMissingSales(options, fetched);
  emitRefreshProgress(options, 'database_refresh_start', {
    blueprintCount: scopeBlueprintIds.length,
    fetchedProducts: fetched.rows.length,
    shapedRows: rows.length,
    archiveMissing,
    truncated: Boolean(fetched.truncated),
  });
  if (options.dryRun) {
    return {
      sourceMode: fetched.sourceMode,
      blueprintCount: scopeBlueprintIds.length,
      fetchedProducts: fetched.rows.length,
      shapedRows: rows.length,
      truncated: Boolean(fetched.truncated),
      sample: rows.slice(0, 5).map(safeRefreshSample),
      archivedCount: 0,
      deletedCount: 0,
      upsertedCount: 0,
      cacheRefreshedCount: 0,
    };
  }
  const counts = await refreshOracleSnapshots({
    rows,
    scopeBlueprintIds,
    removedDay: options.removedDay,
    archiveMissing,
    finalize: options.finalize,
    recordAskObservations: options.recordAskObservations,
    completeBook: Boolean(options.completeBook),
    env,
  });
  let populationUpsertedCount = 0;
  try {
    populationUpsertedCount = await upsertCardTraderBlueprintPopulation({
      populations: fetched.populations,
      observedDay: dateOnly(new Date()),
    });
  } catch (error) {
    emitRefreshProgress(options, 'population_upsert_failed', {
      message: String(error && error.message ? error.message : error),
    });
  }
  counts.populationUpsertedCount = populationUpsertedCount;
  emitRefreshProgress(options, 'database_refresh_done', counts);
  return {
    sourceMode: fetched.sourceMode,
    blueprintCount: scopeBlueprintIds.length,
    fetchedProducts: fetched.rows.length,
    shapedRows: rows.length,
    truncated: Boolean(fetched.truncated) || fetched.rows.length > rows.length,
    ...counts,
  };
}

async function fetchAndRefreshBlueprintBatches(token, blueprintIds, sourceMode, options, env) {
  const batchSize = Math.min(options.refreshBatchBlueprints || options.blueprintBatchSize, blueprintIds.length);
  const totals = emptyRefreshTotals();
  const totalBatches = Math.ceil(blueprintIds.length / Math.max(batchSize, 1));

  for (let batchStart = 0; batchStart < blueprintIds.length; batchStart += batchSize) {
    if (totals.fetchedProducts >= options.maxProducts) {
      totals.truncated = true;
      break;
    }
    const batchIndex = Math.floor(batchStart / batchSize) + 1;
    const batchBlueprintIds = blueprintIds.slice(batchStart, batchStart + batchSize);
    emitRefreshProgress(options, 'refresh_batch_start', {
      batchIndex,
      totalBatches,
      batchBlueprints: batchBlueprintIds.length,
      offset: batchStart,
      totalBlueprints: blueprintIds.length,
    });

    const batchOptions = {
      ...options,
      finalize: false,
      maxBlueprints: batchBlueprintIds.length,
      maxProducts: options.maxProducts - totals.fetchedProducts,
    };
    const fetched = await fetchMarketplaceRowsForBlueprints(token, batchBlueprintIds, batchOptions);
    const persisted = await persistFetchedRows({ ...fetched, sourceMode }, batchOptions, env);
    addRefreshCounts(totals, persisted, {
      blueprintCount: persisted.blueprintCount,
      fetchedProducts: persisted.fetchedProducts,
      shapedRows: persisted.shapedRows,
      truncated: persisted.truncated,
    });
    emitRefreshProgress(options, 'refresh_batch_done', {
      batchIndex,
      totalBatches,
      ...persisted,
      totals,
    });
  }

  return {
    sourceMode,
    ...totals,
  };
}

async function runCatalogExpansionRefresh(token, options, env) {
  const catalog = await readCatalogExpansionsFromOracle();
  const wanted = new Set(options.expansionIds);
  const minExpansionId = options.minExpansionId != null && options.minExpansionId > 0
    ? options.minExpansionId
    : null;
  const shardCount = Math.max(1, options.expansionShardCount || 1);
  const shardIndex = ((options.expansionShardIndex || 0) % shardCount + shardCount) % shardCount;
  const expansions = (wanted.size > 0
    ? catalog.filter((row) => wanted.has(row.expansionId))
    : catalog
  ).filter((row) => minExpansionId == null || row.expansionId >= minExpansionId)
    .filter((row) => shardCount <= 1 || ((row.expansionId % shardCount) + shardCount) % shardCount === shardIndex)
    .slice(0, options.maxExpansions);
  const totals = emptyRefreshTotals();
  emitRefreshProgress(options, 'expansion_catalog_ready', {
    sourceMode: 'oracle_expansions',
    totalExpansions: expansions.length,
    catalogExpansions: catalog.length,
    expansionConcurrency: options.expansionConcurrency,
    persistConcurrency: options.persistConcurrency,
    minExpansionId,
    expansionShardCount: shardCount,
    expansionShardIndex: shardIndex,
  });

  let requestTurn = Promise.resolve();
  let launchedExpansions = 0;
  async function waitForExpansionRequestTurn() {
    const previousTurn = requestTurn;
    requestTurn = previousTurn.then(async () => {
      if (launchedExpansions > 0 && options.requestDelayMs > 0) {
        await sleep(options.requestDelayMs);
      }
      launchedExpansions += 1;
    });
    await requestTurn;
  }

  const totalsLock = createExclusiveLock();
  const persistGate = createSemaphore(options.persistConcurrency || DEFAULT_PERSIST_CONCURRENCY);
  let nextIndex = 0;
  const workerCount = Math.min(options.expansionConcurrency || 1, Math.max(expansions.length, 1));

  async function persistWithRetry(fetched, expansion) {
    let lastError;
    for (let attempt = 0; attempt <= MAX_RATE_LIMIT_RETRIES; attempt += 1) {
      try {
        return await persistGate(async () => persistFetchedRows({
          ...fetched,
          sourceMode: 'oracle_expansions',
        }, {
          ...options,
          finalize: false,
          catalogBlueprintIds: expansion.blueprintIds,
        }, env));
      } catch (error) {
        lastError = error;
        if (!isTransientPostgresError(error) || attempt === MAX_RATE_LIMIT_RETRIES) {
          throw error;
        }
        emitRefreshProgress(options, 'database_refresh_retry', {
          expansionId: expansion.expansionId,
          attempt: attempt + 1,
          message: String(error && error.message ? error.message : error),
        });
        await sleep(RATE_LIMIT_DELAY_MS * (attempt + 1));
      }
    }
    throw lastError;
  }

  async function refreshOneExpansion(index) {
    const expansion = expansions[index];
    emitRefreshProgress(options, 'expansion_refresh_start', {
      expansionId: expansion.expansionId,
      expansionIndex: index + 1,
      totalExpansions: expansions.length,
      catalogBlueprints: expansion.blueprintIds.length,
    });
    await waitForExpansionRequestTurn();
    const fetched = await fetchMarketplaceRowsForExpansion(token, expansion.expansionId, {
      ...options,
      catalogBlueprintIds: expansion.blueprintIds,
      maxProducts: Math.max(options.maxProducts - totals.fetchedProducts, 1),
    });
    if (totals.fetchedProducts >= options.maxProducts) {
      await totalsLock(async () => {
        totals.truncated = true;
      });
      return;
    }
    const persisted = await persistWithRetry(fetched, expansion);
    await totalsLock(async () => {
      addRefreshCounts(totals, persisted, {
        expansionCount: 1,
        blueprintCount: persisted.blueprintCount,
        fetchedProducts: persisted.fetchedProducts,
        shapedRows: persisted.shapedRows,
        truncated: persisted.truncated,
      });
      emitRefreshProgress(options, 'expansion_refresh_done', {
        expansionId: expansion.expansionId,
        expansionIndex: index + 1,
        totalExpansions: expansions.length,
        ...persisted,
        totals,
      });
    });
  }

  async function expansionWorker() {
    while (nextIndex < expansions.length && totals.fetchedProducts < options.maxProducts) {
      const index = nextIndex;
      nextIndex += 1;
      await refreshOneExpansion(index);
    }
  }

  await Promise.all(Array.from({ length: workerCount }, expansionWorker));

  if (wanted.size === 0 && totals.fetchedProducts < options.maxProducts) {
    const ungroupedIds = await readUngroupedBlueprintIdsFromOracle(
      Math.min(options.maxBlueprints, 5_000),
    );
    if (ungroupedIds.length > 0) {
      if (options.requestDelayMs > 0) await sleep(options.requestDelayMs);
      const fetched = await fetchMarketplaceRowsForBlueprints(token, ungroupedIds, {
        ...options,
        maxProducts: options.maxProducts - totals.fetchedProducts,
      });
      const persisted = await persistFetchedRows({
        ...fetched,
        sourceMode: 'ungrouped_blueprints',
      }, { ...options, finalize: false }, env);
      addRefreshCounts(totals, persisted, {
        blueprintCount: persisted.blueprintCount,
        fetchedProducts: persisted.fetchedProducts,
        shapedRows: persisted.shapedRows,
        truncated: persisted.truncated,
      });
    }
  }

  let finalized = null;
  if (!options.dryRun && options.finalize) {
    emitRefreshProgress(options, 'finalize_start', { removedDay: options.removedDay });
    finalized = await finalizeDailyRefresh({ removedDay: options.removedDay, env });
    emitRefreshProgress(options, 'finalize_done', finalized);
  }

  return {
    sourceMode: 'oracle_expansions',
    cheapestListingLimit: CARDTRADER_CHEAPEST_LISTING_LIMIT,
    ...totals,
    finalized,
  };
}

async function runRefresh(inputOptions, env = process.env) {
  const options = normalizeRefreshOptions(inputOptions);
  const token = requireCardTraderApiToken(env);
  const scopedToIds = options.blueprintIds.length > 0 || options.expansionIds.length > 0;

  if (options.byBlueprint || (options.blueprintIds.length > 0 && options.expansionIds.length === 0)) {
    if (!options.dryRun && options.refreshBatchBlueprints > 0 && options.expansionId == null) {
      const requestedBlueprintIds = options.blueprintIds.length > 0 ? options.blueprintIds : null;
      const blueprintIds = requestedBlueprintIds || await readBlueprintIdsFromOracle(options.maxBlueprints);
      const sourceMode = requestedBlueprintIds ? 'explicit_blueprint_ids' : 'oracle_blueprint_pool';
      emitRefreshProgress(options, 'blueprint_pool_ready', {
        sourceMode,
        totalBlueprints: blueprintIds.length,
      });
      const batched = await fetchAndRefreshBlueprintBatches(
        token,
        blueprintIds,
        sourceMode,
        { ...options, finalize: false },
        env,
      );
      if (!options.dryRun && options.finalize) {
        batched.finalized = await finalizeDailyRefresh({ removedDay: options.removedDay, env });
      }
      return batched;
    }
    return persistFetchedRows(await fetchMarketplaceRows(token, options), options, env);
  }

  if (options.expansionIds.length === 1 && scopedToIds) {
    const expansionId = options.expansionIds[0];
    const catalog = options.catalogBlueprintIds.length > 0
      ? [{ expansionId, blueprintIds: options.catalogBlueprintIds }]
      : await readCatalogExpansionsFromOracle();
    const match = catalog.find((row) => row.expansionId === expansionId);
    const fetched = await fetchMarketplaceRowsForExpansion(token, expansionId, {
      ...options,
      catalogBlueprintIds: match ? match.blueprintIds : options.catalogBlueprintIds,
    });
    return persistFetchedRows(fetched, options, env);
  }

  return runCatalogExpansionRefresh(token, options, env);
}

module.exports = {
  CARDTRADER_CHEAPEST_LISTING_LIMIT,
  DEFAULT_BLUEPRINT_BATCH_SIZE,
  DEFAULT_BLUEPRINT_CONCURRENCY,
  DEFAULT_BLUEPRINT_REQUEST_DELAY_MS,
  DEFAULT_EXPANSION_CONCURRENCY,
  DEFAULT_PERSIST_CONCURRENCY,
  DEFAULT_MAX_BLUEPRINTS,
  DEFAULT_MAX_EXPANSIONS,
  DEFAULT_MAX_PRODUCTS,
  DEFAULT_REFRESH_BATCH_BLUEPRINTS,
  MAX_BLUEPRINT_BATCH_SIZE,
  MAX_BLUEPRINT_CONCURRENCY,
  MAX_EXPANSION_CONCURRENCY,
  MAX_PERSIST_CONCURRENCY,
  MAX_REFRESH_BATCH_BLUEPRINTS,
  PROVIDER,
  cleanBoolean,
  cleanDate,
  cleanPositiveInteger,
  cleanText,
  configuredCardTraderApiToken,
  fetchMarketplaceRows,
  fetchMarketplaceRowsForExpansion,
  finalizeDailyRefresh,
  integerOrNull,
  normalizeCardTraderMarketProduct,
  normalizeRefreshOptions,
  parseIntegerList,
  pokoinPublicNumber,
  readBlueprintIdsFromOracle,
  readCatalogExpansionsFromOracle,
  readUngroupedBlueprintIdsFromOracle,
  refreshOracleSnapshots,
  removedDayForRefreshDate,
  requireCardTraderApiToken,
  rowsFromMarketplacePayload,
  populationFromListingRows,
  upsertCardTraderBlueprintPopulation,
  runRefresh,
  safeRefreshSample,
  shouldArchiveMissingSales,
  slimCardTraderMarketProduct,
  takeCheapestRows,
};
