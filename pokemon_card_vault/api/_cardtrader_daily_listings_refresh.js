const { cleanToken, fetchMarketplaceProducts } = require('./_cardtrader_client');
const { marketplaceQuery } = require('./_marketplace_db');

const PROVIDER = 'cardtrader';
const DEFAULT_MAX_BLUEPRINTS = 100_000;
const DEFAULT_MAX_PRODUCTS = 1_000_000;
const MAX_BLUEPRINTS_PER_RUN = 100_000;
const MAX_PRODUCTS_PER_RUN = 1_000_000;
const DEFAULT_BLUEPRINT_REQUEST_DELAY_MS = 300;
const DEFAULT_BLUEPRINT_BATCH_SIZE = 100;
const DEFAULT_BLUEPRINT_CONCURRENCY = 1;
const DEFAULT_REFRESH_BATCH_BLUEPRINTS = 0;
const MAX_BLUEPRINT_BATCH_SIZE = 1_000;
const MAX_BLUEPRINT_CONCURRENCY = 50;
const MAX_REFRESH_BATCH_BLUEPRINTS = 10_000;
const RATE_LIMIT_DELAY_MS = 5_000;
const MAX_RATE_LIMIT_RETRIES = 2;

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

function isCardTraderRateLimitError(error) {
  return error && error.statusCode === 502 && /HTTP 429\b/.test(String(error.message || ''));
}

function numericOrNull(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function integerOrNull(value) {
  const number = Number(value);
  return Number.isSafeInteger(Number(value)) ? Math.trunc(number) : null;
}

function parseIntegerList(value) {
  return String(value || '')
    .split(',')
    .map((item) => integerOrNull(item.trim()))
    .filter((item) => item != null && item > 0);
}

function optionValue(input, name) {
  if (typeof input === 'function') return input(name);
  return input && typeof input === 'object' ? input[name] : undefined;
}

function normalizeRefreshOptions(input = {}) {
  const get = (name) => optionValue(input, name);
  const dryRun = cleanBoolean(get('dryRun'), false);
  const blueprintIds = parseIntegerList(get('blueprintIds') ?? get('blueprint_ids'));
  const singleBlueprintId = integerOrNull(get('blueprintId') ?? get('blueprint_id'));
  if (singleBlueprintId != null) blueprintIds.unshift(singleBlueprintId);
  return {
    dryRun,
    archiveMissing: cleanBoolean(get('archiveMissing'), !dryRun),
    maxBlueprints: cleanPositiveInteger(
      get('maxBlueprints') ?? get('maxBlueprintsPerRun'),
      DEFAULT_MAX_BLUEPRINTS,
      1,
      MAX_BLUEPRINTS_PER_RUN,
    ),
    maxProducts: cleanPositiveInteger(get('maxProducts'), DEFAULT_MAX_PRODUCTS, 1, MAX_PRODUCTS_PER_RUN),
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
    refreshBatchBlueprints: cleanPositiveInteger(
      get('refreshBatchBlueprints') ?? get('refresh_batch_blueprints') ?? get('refresh-batch-blueprints'),
      DEFAULT_REFRESH_BATCH_BLUEPRINTS,
      0,
      MAX_REFRESH_BATCH_BLUEPRINTS,
    ),
    removedDay: cleanDate(get('removedDay')),
    blueprintIds: [...new Set(blueprintIds)].slice(0, MAX_BLUEPRINTS_PER_RUN),
    expansionId: integerOrNull(get('expansionId') ?? get('expansion_id')),
    language: cleanText(get('language'), 8),
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

function normalizeCardTraderMarketProduct(product = {}, fallbackBlueprintId = null) {
  const properties = objectOrEmpty(product.properties_hash || product.properties);
  const priceObject = objectOrEmpty(product.price);
  const user = objectOrEmpty(product.user || product.seller);
  const externalListingId = cleanText(
    product.id ??
      product.product_id ??
      product.productId ??
      product.listing_id ??
      product.listingId,
    160,
  );
  const productId = cleanText(product.product_id ?? product.productId ?? product.id, 160);
  const blueprintId = numericOrNull(product.blueprint_id ?? product.blueprintId ?? fallbackBlueprintId);
  const priceCents = integerOrNull(product.price_cents ?? product.priceCents ?? priceObject.cents);
  const price = numericOrNull(product.price ?? product.price_amount ?? product.priceAmount ?? priceObject.amount) ??
    (priceCents == null ? null : priceCents / 100);
  return {
    externalListingId,
    externalProductId: productId,
    sellerAccountId: cleanText(user.id ?? user.user_id ?? product.seller_id, 160),
    sellerAccountName: firstText(user.username, user.name, product.seller_name),
    sellerCountry: cleanText(user.country_code ?? user.country ?? product.seller_country, 40),
    sellerType: cleanText(user.user_type ?? product.seller_type, 80),
    blueprintId,
    cardtraderBlueprintId: blueprintId,
    pokoinCardId: blueprintId == null ? '' : String(blueprintId),
    quantity: Math.max(integerOrNull(product.quantity ?? product.qty) ?? 0, 0),
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
    currency: cleanText(
      product.currency ?? product.price_currency ?? product.priceCurrency ?? priceObject.currency ?? 'EUR',
      12,
    ),
    properties,
    rawMetadata: product,
  };
}

function safeRefreshSample(row = {}) {
  return {
    externalListingId: row.externalListingId || '',
    blueprintId: row.blueprintId,
    quantity: row.quantity,
    condition: row.condition,
    language: row.language,
    priceCents: row.priceCents,
    currency: row.currency,
  };
}

function rowsFromMarketplacePayload(payload = {}, productLimit = DEFAULT_MAX_PRODUCTS) {
  const rows = [];
  const blueprintIds = new Set();
  if (Array.isArray(payload)) {
    for (const product of payload) {
      const row = normalizeCardTraderMarketProduct(product);
      if (row.blueprintId != null) blueprintIds.add(row.blueprintId);
      if (row.externalListingId) rows.push(row);
      if (rows.length >= productLimit) break;
    }
    return { rows, blueprintIds: [...blueprintIds] };
  }

  for (const [blueprintIdText, products] of Object.entries(objectOrEmpty(payload))) {
    const blueprintId = numericOrNull(blueprintIdText);
    if (blueprintId != null) blueprintIds.add(blueprintId);
    if (!Array.isArray(products)) continue;
    for (const product of products) {
      const row = normalizeCardTraderMarketProduct(product, blueprintId);
      if (row.blueprintId != null) blueprintIds.add(row.blueprintId);
      if (row.externalListingId && rows.length < productLimit) rows.push(row);
    }
  }
  return { rows, blueprintIds: [...blueprintIds] };
}

async function readBlueprintIdsFromOracle(limit) {
  const result = await marketplaceQuery(
    `
      select card_id::bigint as blueprint_id
      from public.marketplace_search_candidates
      where card_id is not null
      order by search_weight desc, imported_at desc nulls last, card_id desc
      limit $1
    `,
    [limit],
  );
  return result.rows
    .map((row) => Number(row.blueprint_id))
    .filter((id) => Number.isSafeInteger(id) && id > 0);
}

async function refreshOracleSnapshots({
  rows,
  scopeBlueprintIds,
  removedDay,
  archiveMissing,
  env = process.env,
  query = marketplaceQuery,
}) {
  const pknReferencePrice = Number(env.PKN_CHECKOUT_USDT_PRICE || 0.005);
  const result = await query(
    `
      with settings as (
        select set_config('app.pkn_usdt_price', $6::text, true)
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
        now()
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
    ],
  );
  const row = result.rows[0] || {};
  return {
    archivedCount: Number(row.archived_count || 0),
    deletedCount: Number(row.deleted_count || 0),
    upsertedCount: Number(row.upserted_count || 0),
    cacheRefreshedCount: Number(row.cache_refreshed_count || 0),
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

async function fetchMarketplaceRowsForBlueprints(token, blueprintIds, options) {
  const rows = [];
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
    let payload;
    for (let attempt = 0; attempt <= MAX_RATE_LIMIT_RETRIES; attempt += 1) {
      try {
        payload = await fetchMarketplaceProducts(token, {
          blueprint_id: blueprintId,
          language: options.language,
        });
        break;
      } catch (error) {
        if (!isCardTraderRateLimitError(error) || attempt === MAX_RATE_LIMIT_RETRIES) {
          throw error;
        }
        await sleep(RATE_LIMIT_DELAY_MS * (attempt + 1));
      }
    }
    return rowsFromMarketplacePayload(payload, options.maxProducts).rows;
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
        const fetchedRows = await fetchBlueprintRows(blueprintId);
        const remainingProducts = options.maxProducts - rows.length;
        if (remainingProducts > 0) {
          rows.push(...fetchedRows.slice(0, remainingProducts));
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
  return { rows, fetchedBlueprintIds };
}

async function fetchMarketplaceRows(token, options) {
  if (options.expansionId != null) {
    const payload = await fetchMarketplaceProducts(token, {
      expansion_id: options.expansionId,
      language: options.language,
    });
    const shaped = rowsFromMarketplacePayload(payload, options.maxProducts);
    return {
      rows: shaped.rows,
      fetchedBlueprintIds: shaped.blueprintIds.slice(0, options.maxBlueprints),
      sourceMode: 'expansion_id',
    };
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

async function fetchAndRefreshBlueprintBatches(token, blueprintIds, sourceMode, options, env) {
  const batchSize = Math.min(options.refreshBatchBlueprints, blueprintIds.length);
  const totals = {
    blueprintCount: 0,
    fetchedProducts: 0,
    shapedRows: 0,
    truncated: false,
    archivedCount: 0,
    deletedCount: 0,
    upsertedCount: 0,
    cacheRefreshedCount: 0,
  };
  const totalBatches = Math.ceil(blueprintIds.length / batchSize);

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
      maxBlueprints: batchBlueprintIds.length,
      maxProducts: options.maxProducts - totals.fetchedProducts,
    };
    const fetched = await fetchMarketplaceRowsForBlueprints(token, batchBlueprintIds, batchOptions);
    const rows = fetched.rows.slice(0, batchOptions.maxProducts);
    const scopeBlueprintIds = [...new Set(fetched.fetchedBlueprintIds
      .map((id) => Number(id))
      .filter((id) => Number.isSafeInteger(id) && id > 0))];

    emitRefreshProgress(options, 'database_refresh_start', {
      batchIndex,
      totalBatches,
      blueprintCount: scopeBlueprintIds.length,
      fetchedProducts: fetched.rows.length,
      shapedRows: rows.length,
    });

    const counts = await refreshOracleSnapshots({
      rows,
      scopeBlueprintIds,
      removedDay: options.removedDay,
      archiveMissing: options.archiveMissing,
      env,
    });

    totals.blueprintCount += scopeBlueprintIds.length;
    totals.fetchedProducts += fetched.rows.length;
    totals.shapedRows += rows.length;
    totals.truncated ||= fetched.rows.length > rows.length;
    totals.archivedCount += counts.archivedCount;
    totals.deletedCount += counts.deletedCount;
    totals.upsertedCount += counts.upsertedCount;
    totals.cacheRefreshedCount += counts.cacheRefreshedCount;
    emitRefreshProgress(options, 'refresh_batch_done', {
      batchIndex,
      totalBatches,
      ...counts,
      totals,
    });
  }

  return {
    sourceMode,
    ...totals,
  };
}

async function runRefresh(inputOptions, env = process.env) {
  const options = normalizeRefreshOptions(inputOptions);
  const token = requireCardTraderApiToken(env);
  if (!options.dryRun && options.refreshBatchBlueprints > 0 && options.expansionId == null) {
    const requestedBlueprintIds = options.blueprintIds.length > 0 ? options.blueprintIds : null;
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
    const sourceMode = requestedBlueprintIds ? 'explicit_blueprint_ids' : 'oracle_blueprint_pool';
    emitRefreshProgress(options, 'blueprint_pool_ready', {
      sourceMode,
      totalBlueprints: blueprintIds.length,
    });
    return fetchAndRefreshBlueprintBatches(token, blueprintIds, sourceMode, options, env);
  }
  const fetched = await fetchMarketplaceRows(token, options);
  const rows = fetched.rows.slice(0, options.maxProducts);
  const scopeBlueprintIds = [...new Set(fetched.fetchedBlueprintIds
    .map((id) => Number(id))
    .filter((id) => Number.isSafeInteger(id) && id > 0))]
    .slice(0, options.maxBlueprints);
  emitRefreshProgress(options, 'database_refresh_start', {
    blueprintCount: scopeBlueprintIds.length,
    fetchedProducts: fetched.rows.length,
    shapedRows: rows.length,
  });

  if (options.dryRun) {
    return {
      sourceMode: fetched.sourceMode,
      blueprintCount: scopeBlueprintIds.length,
      fetchedProducts: fetched.rows.length,
      shapedRows: rows.length,
      truncated: fetched.rows.length > rows.length,
      sample: rows.slice(0, 5).map(safeRefreshSample),
      archivedCount: 0,
      deletedCount: 0,
      upsertedCount: 0,
    };
  }

  const counts = await refreshOracleSnapshots({
    rows,
    scopeBlueprintIds,
    removedDay: options.removedDay,
    archiveMissing: options.archiveMissing,
    env,
  });
  emitRefreshProgress(options, 'database_refresh_done', counts);
  return {
    sourceMode: fetched.sourceMode,
    blueprintCount: scopeBlueprintIds.length,
    fetchedProducts: fetched.rows.length,
    shapedRows: rows.length,
    truncated: fetched.rows.length > rows.length,
    ...counts,
  };
}

module.exports = {
  DEFAULT_BLUEPRINT_BATCH_SIZE,
  DEFAULT_BLUEPRINT_CONCURRENCY,
  DEFAULT_MAX_BLUEPRINTS,
  DEFAULT_MAX_PRODUCTS,
  DEFAULT_REFRESH_BATCH_BLUEPRINTS,
  MAX_BLUEPRINT_BATCH_SIZE,
  MAX_BLUEPRINT_CONCURRENCY,
  MAX_REFRESH_BATCH_BLUEPRINTS,
  PROVIDER,
  cleanBoolean,
  cleanDate,
  cleanPositiveInteger,
  cleanText,
  configuredCardTraderApiToken,
  fetchMarketplaceRows,
  integerOrNull,
  normalizeCardTraderMarketProduct,
  normalizeRefreshOptions,
  parseIntegerList,
  readBlueprintIdsFromOracle,
  refreshOracleSnapshots,
  removedDayForRefreshDate,
  requireCardTraderApiToken,
  rowsFromMarketplacePayload,
  runRefresh,
  safeRefreshSample,
};
