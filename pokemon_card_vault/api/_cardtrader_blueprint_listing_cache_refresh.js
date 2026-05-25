const { cleanToken, fetchMarketplaceProducts } = require('./_cardtrader_client');
const { marketplaceQuery } = require('./_marketplace_db');

const PROVIDER = 'cardtrader';
const CARDTRADER_MARKUP_PKN = 200;
const DEFAULT_MAX_BLUEPRINTS = 250;
const MAX_BLUEPRINTS_PER_RUN = 100_000;
const DEFAULT_REFRESH_BATCH_BLUEPRINTS = 700;
const MAX_REFRESH_BATCH_BLUEPRINTS = 10_000;
const DEFAULT_BLUEPRINT_CONCURRENCY = 1;
const MAX_BLUEPRINT_CONCURRENCY = 20;
const DEFAULT_REQUEST_DELAY_MS = 500;
const RATE_LIMIT_DELAY_MS = 5_000;
const MAX_RATE_LIMIT_RETRIES = 2;
const SUPPORTED_PRODUCT_TYPES = [
  'booster_box',
  'booster_bundle',
  'booster_pack',
  'championship_deck',
  'collection_box',
  'deck',
  'elite_trainer_box',
  'sealed_product',
  'tin',
];

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

function integerOrNull(value) {
  const number = Number(value);
  return Number.isSafeInteger(number) ? Math.trunc(number) : null;
}

function numericOrNull(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function objectOrEmpty(value) {
  return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
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

function cleanProductType(value) {
  const normalized = cleanText(value || 'card', 40).toLowerCase();
  if (normalized === 'product' || normalized === 'products') return 'product';
  if (normalized === 'all' || normalized === 'cards_and_products') return 'all';
  return 'card';
}

function normalizeCacheRefreshOptions(input = {}) {
  const get = (name) => optionValue(input, name);
  const blueprintIds = parseIntegerList(get('blueprintIds') ?? get('blueprint_ids'));
  const singleBlueprintId = integerOrNull(get('blueprintId') ?? get('blueprint_id'));
  if (singleBlueprintId != null) blueprintIds.unshift(singleBlueprintId);
  return {
    dryRun: cleanBoolean(get('dryRun'), false),
    maxBlueprints: cleanPositiveInteger(
      get('maxBlueprints') ?? get('maxBlueprintsPerRun'),
      DEFAULT_MAX_BLUEPRINTS,
      1,
      MAX_BLUEPRINTS_PER_RUN,
    ),
    refreshBatchBlueprints: cleanPositiveInteger(
      get('refreshBatchBlueprints') ?? get('refresh_batch_blueprints') ?? get('refresh-batch-blueprints'),
      DEFAULT_REFRESH_BATCH_BLUEPRINTS,
      1,
      MAX_REFRESH_BATCH_BLUEPRINTS,
    ),
    blueprintConcurrency: cleanPositiveInteger(
      get('blueprintConcurrency') ?? get('blueprint_concurrency') ?? get('blueprint-concurrency'),
      DEFAULT_BLUEPRINT_CONCURRENCY,
      1,
      MAX_BLUEPRINT_CONCURRENCY,
    ),
    requestDelayMs: cleanPositiveInteger(
      get('requestDelayMs') ?? get('request_delay_ms') ?? get('request-delay-ms'),
      DEFAULT_REQUEST_DELAY_MS,
      0,
      30_000,
    ),
    productType: cleanProductType(get('productType') ?? get('product_type') ?? get('product-type')),
    language: cleanText(get('language'), 8),
    blueprintIds: [...new Set(blueprintIds)].slice(0, MAX_BLUEPRINTS_PER_RUN),
    onProgress: typeof get('onProgress') === 'function' ? get('onProgress') : undefined,
  };
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

function pknReferencePrice(env = process.env) {
  const referencePrice = Number(env.PKN_CHECKOUT_USDT_PRICE || 0.005);
  return Number.isFinite(referencePrice) && referencePrice > 0 ? referencePrice : 0.005;
}

function marketplacePricePknFromCardTrader(amount, amountCents, currency, env = process.env) {
  const fiatAmount = numericOrNull(amount) ?? (
    integerOrNull(amountCents) == null ? null : integerOrNull(amountCents) / 100
  );
  if (fiatAmount == null || fiatAmount <= 0) return null;
  const normalizedCurrency = cleanText(currency || 'EUR', 12).toUpperCase();
  if (normalizedCurrency === 'PKN' || normalizedCurrency === 'POKOIN') return fiatAmount;
  return fiatAmount / pknReferencePrice(env);
}

function booleanFlagMatchesDatabase(value) {
  return ['true', '1', 'yes', 'y'].includes(String(value ?? '').trim().toLowerCase());
}

function rawFlagValue(product = {}, key) {
  const user = objectOrEmpty(product.user);
  return user[key] == null ? product[key] : user[key];
}

function isTrueCardTraderZeroProduct(product = {}) {
  return booleanFlagMatchesDatabase(rawFlagValue(product, 'can_sell_via_hub')) ||
    booleanFlagMatchesDatabase(rawFlagValue(product, 'can_sell_sealed_with_ct_zero'));
}

function cardTraderShippingMode(product = {}) {
  if (isTrueCardTraderZeroProduct(product)) return 'zero';
  const user = objectOrEmpty(product.user || product.seller);
  const text = [
    user.username,
    user.name,
    user.display_name,
    user.public_name,
    product.seller_name,
    product.seller_display_name,
    product.name,
    product.name_en,
    product.description,
  ].map((value) => String(value || '')).join(' ');
  return /(^|[^a-z0-9])((1|one)[\s-]*day[\s-]*ready)([^a-z0-9]|$)/i.test(text)
    ? 'one_day_ready'
    : '';
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

function normalizeCardTraderCacheProduct(product = {}, fallbackBlueprintId = null) {
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
    sellerCountry: cleanText(user.country_code ?? user.country ?? product.seller_country, 40),
    shippingMode: cardTraderShippingMode(product),
    properties,
    rawMetadata: product,
  };
}

function cacheRowsFromMarketplacePayload(payload = {}, fallbackBlueprintId = null) {
  const rows = [];
  const grouped = Array.isArray(payload)
    ? { [fallbackBlueprintId || '']: payload }
    : objectOrEmpty(payload);
  for (const [blueprintIdText, products] of Object.entries(grouped)) {
    const blueprintId = numericOrNull(blueprintIdText) ?? fallbackBlueprintId;
    if (!Array.isArray(products)) continue;
    for (const product of products) {
      if (!cardTraderShippingMode(product)) continue;
      const row = normalizeCardTraderCacheProduct(product, blueprintId);
      if (row.externalListingId && row.blueprintId != null) rows.push(row);
    }
  }
  return rows;
}

function isCacheEligibleRow(row = {}, env = process.env) {
  return row.quantity > 0 &&
    cleanText(row.currency || 'EUR', 12).toUpperCase() === 'EUR' &&
    marketplacePricePknFromCardTrader(row.price, row.priceCents, row.currency, env) != null;
}

function summarizeDryRunCacheRows(rows, scopeBlueprintIds, env = process.env) {
  const byBlueprint = new Map();
  for (const row of rows) {
    if (!isCacheEligibleRow(row, env)) continue;
    const blueprintId = Number(row.blueprintId);
    const pricePkn = marketplacePricePknFromCardTrader(row.price, row.priceCents, row.currency, env) +
      CARDTRADER_MARKUP_PKN;
    const existing = byBlueprint.get(blueprintId);
    if (!existing || pricePkn < existing.cheapestPricePkn) {
      byBlueprint.set(blueprintId, {
        blueprintId,
        cheapestPricePkn: pricePkn,
        sampleListingId: row.externalListingId,
      });
    }
  }
  return {
    scopedCount: scopeBlueprintIds.length,
    eligibleBlueprintCount: byBlueprint.size,
    staleClearCount: scopeBlueprintIds.filter((id) => !byBlueprint.has(Number(id))).length,
    sample: [...byBlueprint.values()].slice(0, 5),
  };
}

function productScopeClause(productType, values) {
  if (productType === 'product') {
    values.push(SUPPORTED_PRODUCT_TYPES);
    return `
      and item_kind = 'product'
      and product_type = any($${values.length}::text[])
    `;
  }
  if (productType === 'all') {
    values.push(SUPPORTED_PRODUCT_TYPES);
    return `
      and (
        (item_kind = 'single' and product_type = 'card')
        or (item_kind = 'product' and product_type = any($${values.length}::text[]))
      )
    `;
  }
  return `
    and item_kind = 'single'
    and product_type = 'card'
  `;
}

async function readBlueprintIdsFromCandidates(limit, options = {}, query = marketplaceQuery) {
  const values = [cleanPositiveInteger(limit, DEFAULT_MAX_BLUEPRINTS, 1, MAX_BLUEPRINTS_PER_RUN)];
  const productType = cleanProductType(options.productType);
  const result = await query(
    `
      select card_id::bigint as blueprint_id
      from public.marketplace_search_candidates
      where card_id is not null
        and coalesce(preview_image_url, homepage_image_url, cdn_image_url, image_url) is not null
        ${productScopeClause(productType, values)}
      order by
        case when item_kind = 'single' and product_type = 'card' then 0 else 1 end,
        search_weight desc,
        imported_at desc nulls last,
        card_id desc
      limit $1
    `,
    values,
  );
  return result.rows
    .map((row) => Number(row.blueprint_id))
    .filter((id) => Number.isSafeInteger(id) && id > 0);
}

function emitCacheRefreshProgress(options, event, payload = {}) {
  if (typeof options.onProgress !== 'function') return;
  options.onProgress({
    event,
    at: new Date().toISOString(),
    ...payload,
  });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isCardTraderRateLimitError(error) {
  return error && error.statusCode === 502 && /HTTP 429\b/.test(String(error.message || ''));
}

async function fetchCacheRowsForBlueprints(token, blueprintIds, options) {
  const rows = [];
  const fetchedBlueprintIds = [];
  let launchedBlueprints = 0;
  let completedBlueprints = 0;
  let requestTurn = Promise.resolve();

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
    return cacheRowsFromMarketplacePayload(payload, blueprintId);
  }

  function emitFetchProgress(blueprintId, force = false) {
    if (
      force ||
      completedBlueprints === 1 ||
      completedBlueprints % 100 === 0 ||
      completedBlueprints === blueprintIds.length
    ) {
      emitCacheRefreshProgress(options, 'blueprint_fetch_progress', {
        fetchedBlueprints: completedBlueprints,
        totalBlueprints: blueprintIds.length,
        eligibleRows: rows.length,
        lastBlueprintId: blueprintId,
      });
    }
  }

  emitCacheRefreshProgress(options, 'blueprint_fetch_start', {
    totalBlueprints: blueprintIds.length,
    blueprintConcurrency: options.blueprintConcurrency,
    requestDelayMs: options.requestDelayMs,
  });

  let nextIndex = 0;
  async function runWorker() {
    while (nextIndex < blueprintIds.length) {
      const blueprintId = blueprintIds[nextIndex];
      nextIndex += 1;
      const fetchedRows = await fetchBlueprintRows(blueprintId);
      rows.push(...fetchedRows);
      fetchedBlueprintIds.push(blueprintId);
      completedBlueprints += 1;
      emitFetchProgress(blueprintId);
    }
  }

  const workerCount = Math.min(options.blueprintConcurrency, blueprintIds.length);
  await Promise.all(Array.from({ length: workerCount }, runWorker));
  emitCacheRefreshProgress(options, 'blueprint_fetch_done', {
    fetchedBlueprints: fetchedBlueprintIds.length,
    totalBlueprints: blueprintIds.length,
    eligibleRows: rows.length,
  });
  return { rows, fetchedBlueprintIds };
}

async function refreshOracleBlueprintListingCache({
  rows,
  scopeBlueprintIds,
  env = process.env,
  query = marketplaceQuery,
  refreshedAt = new Date(),
}) {
  const pknReference = pknReferencePrice(env);
  const result = await query(
    `
      with settings as (
        select set_config('app.pkn_usdt_price', $4::text, true)
      ),
      scope as (
        select distinct unnest($2::bigint[]) as blueprint_id
      ),
      incoming as (
        select
          $3::text as provider,
          left(coalesce(row_data->>'externalListingId', row_data->>'external_listing_id', row_data->>'id', ''), 160) as external_listing_id,
          left(coalesce(row_data->>'externalProductId', row_data->>'external_product_id', row_data->>'productId', row_data->>'product_id', ''), 160) as external_product_id,
          nullif(coalesce(row_data->>'blueprintId', row_data->>'blueprint_id', ''), '')::bigint as blueprint_id,
          nullif(coalesce(row_data->>'cardtraderBlueprintId', row_data->>'cardtrader_blueprint_id', row_data->>'blueprintId', row_data->>'blueprint_id', ''), '')::bigint as cardtrader_blueprint_id,
          left(coalesce(row_data->>'pokoinCardId', row_data->>'pokoin_card_id', row_data->>'blueprintId', row_data->>'blueprint_id', ''), 80) as pokoin_card_id,
          greatest(coalesce(nullif(coalesce(row_data->>'quantity', row_data->>'qty', ''), '')::integer, 0), 0) as quantity,
          nullif(coalesce(row_data->>'price', row_data->>'priceAmount', row_data->>'price_amount', ''), '')::numeric as price,
          nullif(coalesce(row_data->>'priceCents', row_data->>'price_cents', ''), '')::integer as price_cents,
          left(coalesce(row_data->>'currency', ''), 12) as currency,
          left(coalesce(row_data->>'sellerCountry', row_data->>'seller_country', ''), 40) as seller_country,
          left(coalesce(row_data->>'shippingMode', row_data->>'shipping_mode', ''), 40) as shipping_mode,
          coalesce(row_data->'rawMetadata', row_data->'raw_metadata', row_data, '{}'::jsonb) as raw_metadata
        from jsonb_array_elements($1::jsonb) as payload(row_data)
      ),
      eligible as (
        select
          incoming.provider,
          coalesce(incoming.blueprint_id, incoming.cardtrader_blueprint_id) as blueprint_id,
          incoming.pokoin_card_id,
          incoming.external_listing_id,
          incoming.external_product_id,
          case
            when upper(coalesce(nullif(incoming.currency, ''), 'EUR')) = 'EUR'
            then coalesce(incoming.price, incoming.price_cents::numeric / 100)
            else null
          end as price_eur,
          public.marketplace_price_pkn_from_cardtrader(
            incoming.price,
            incoming.price_cents,
            incoming.currency
          ) + 200 as price_pkn,
          incoming.quantity,
          incoming.seller_country,
          case
            when incoming.shipping_mode = 'one_day_ready' then 'one_day_ready'
            else 'zero'
          end as shipping_mode,
          $5::timestamptz as source_snapshot_at
        from incoming
        join scope on scope.blueprint_id = coalesce(incoming.blueprint_id, incoming.cardtrader_blueprint_id)
        where incoming.external_listing_id <> ''
          and coalesce(incoming.blueprint_id, incoming.cardtrader_blueprint_id) is not null
          and coalesce(incoming.quantity, 0) > 0
          and upper(coalesce(nullif(incoming.currency, ''), 'EUR')) = 'EUR'
          and public.marketplace_price_pkn_from_cardtrader(
            incoming.price,
            incoming.price_cents,
            incoming.currency
          ) is not null
          and (
            lower(coalesce(incoming.raw_metadata->'user'->>'can_sell_via_hub', incoming.raw_metadata->>'can_sell_via_hub', '')) in ('true', '1', 'yes', 'y')
            or lower(coalesce(incoming.raw_metadata->'user'->>'can_sell_sealed_with_ct_zero', incoming.raw_metadata->>'can_sell_sealed_with_ct_zero', '')) in ('true', '1', 'yes', 'y')
            or incoming.shipping_mode = 'one_day_ready'
          )
      ),
      ranked as (
        select
          eligible.*,
          count(*) over (partition by eligible.blueprint_id)::integer as eligible_listing_count,
          coalesce(sum(eligible.quantity) over (partition by eligible.blueprint_id), 0)::integer as eligible_quantity,
          row_number() over (
            partition by eligible.blueprint_id
            order by eligible.price_pkn asc, eligible.external_listing_id asc
          ) as price_rank
        from eligible
      ),
      upserted as (
        insert into public.cardtrader_blueprint_listing_cache (
          provider,
          blueprint_id,
          pokoin_card_id,
          cheapest_price_eur,
          cheapest_price_pkn,
          eligible_listing_count,
          eligible_quantity,
          sample_listing_id,
          sample_product_id,
          shipping_mode,
          seller_country_code,
          source_snapshot_at,
          updated_at
        )
        select
          provider,
          blueprint_id,
          left(coalesce(nullif(pokoin_card_id, ''), blueprint_id::text), 80),
          price_eur,
          price_pkn,
          eligible_listing_count,
          eligible_quantity,
          left(external_listing_id, 160),
          left(external_product_id, 160),
          shipping_mode,
          left(coalesce(seller_country, ''), 40),
          source_snapshot_at,
          $5::timestamptz
        from ranked
        where price_rank = 1
        on conflict (blueprint_id) do update set
          provider = excluded.provider,
          pokoin_card_id = excluded.pokoin_card_id,
          cheapest_price_eur = excluded.cheapest_price_eur,
          cheapest_price_pkn = excluded.cheapest_price_pkn,
          eligible_listing_count = excluded.eligible_listing_count,
          eligible_quantity = excluded.eligible_quantity,
          sample_listing_id = excluded.sample_listing_id,
          sample_product_id = excluded.sample_product_id,
          shipping_mode = excluded.shipping_mode,
          seller_country_code = excluded.seller_country_code,
          source_snapshot_at = excluded.source_snapshot_at,
          updated_at = excluded.updated_at
        returning blueprint_id
      ),
      deleted as (
        delete from public.cardtrader_blueprint_listing_cache cache
        using scope
        where cache.provider = $3::text
          and cache.blueprint_id = scope.blueprint_id
          and not exists (
            select 1
            from ranked
            where ranked.price_rank = 1
              and ranked.blueprint_id = cache.blueprint_id
          )
        returning cache.blueprint_id
      )
      select
        (select count(*) from scope)::integer as scoped_count,
        (select count(*) from incoming)::integer as incoming_count,
        (select count(*) from eligible)::integer as eligible_listing_count,
        (select count(distinct blueprint_id) from eligible)::integer as eligible_blueprint_count,
        (select count(*) from upserted)::integer as upserted_count,
        (select count(*) from deleted)::integer as deleted_count
      from settings
    `,
    [
      JSON.stringify(rows),
      scopeBlueprintIds,
      PROVIDER,
      String(pknReference),
      refreshedAt instanceof Date ? refreshedAt.toISOString() : refreshedAt,
    ],
  );
  const row = result.rows[0] || {};
  return {
    scopedCount: Number(row.scoped_count || 0),
    incomingCount: Number(row.incoming_count || 0),
    eligibleListingCount: Number(row.eligible_listing_count || 0),
    eligibleBlueprintCount: Number(row.eligible_blueprint_count || 0),
    upsertedCount: Number(row.upserted_count || 0),
    deletedCount: Number(row.deleted_count || 0),
  };
}

async function runCacheRefresh(inputOptions = {}, env = process.env) {
  const options = normalizeCacheRefreshOptions(inputOptions);
  const token = requireCardTraderApiToken(env);
  const requestedBlueprintIds = options.blueprintIds.length > 0 ? options.blueprintIds : null;
  emitCacheRefreshProgress(options, requestedBlueprintIds ? 'blueprint_pool_ready' : 'blueprint_pool_read_start', {
    sourceMode: requestedBlueprintIds ? 'explicit_blueprint_ids' : 'marketplace_search_candidates',
    maxBlueprints: options.maxBlueprints,
    productType: options.productType,
    totalBlueprints: requestedBlueprintIds ? requestedBlueprintIds.length : undefined,
  });
  const blueprintIds = requestedBlueprintIds ||
    await readBlueprintIdsFromCandidates(options.maxBlueprints, options);
  emitCacheRefreshProgress(options, 'blueprint_pool_ready', {
    sourceMode: requestedBlueprintIds ? 'explicit_blueprint_ids' : 'marketplace_search_candidates',
    totalBlueprints: blueprintIds.length,
    productType: options.productType,
  });

  const totals = {
    sourceMode: requestedBlueprintIds ? 'explicit_blueprint_ids' : 'marketplace_search_candidates',
    productType: options.productType,
    blueprintCount: 0,
    fetchedRows: 0,
    eligibleBlueprintCount: 0,
    eligibleListingCount: 0,
    upsertedCount: 0,
    deletedCount: 0,
  };
  const batchSize = Math.min(options.refreshBatchBlueprints, blueprintIds.length || 1);
  const totalBatches = Math.ceil(blueprintIds.length / batchSize);

  for (let batchStart = 0; batchStart < blueprintIds.length; batchStart += batchSize) {
    const batchIndex = Math.floor(batchStart / batchSize) + 1;
    const batchBlueprintIds = blueprintIds.slice(batchStart, batchStart + batchSize);
    emitCacheRefreshProgress(options, 'refresh_batch_start', {
      batchIndex,
      totalBatches,
      batchBlueprints: batchBlueprintIds.length,
      offset: batchStart,
    });
    const fetched = await fetchCacheRowsForBlueprints(token, batchBlueprintIds, options);
    const scopeBlueprintIds = [...new Set(fetched.fetchedBlueprintIds
      .map((id) => Number(id))
      .filter((id) => Number.isSafeInteger(id) && id > 0))];
    let counts;
    if (options.dryRun) {
      counts = {
        ...summarizeDryRunCacheRows(fetched.rows, scopeBlueprintIds, env),
        incomingCount: fetched.rows.length,
        upsertedCount: 0,
        deletedCount: 0,
      };
    } else {
      counts = await refreshOracleBlueprintListingCache({
        rows: fetched.rows,
        scopeBlueprintIds,
        env,
      });
    }

    totals.blueprintCount += scopeBlueprintIds.length;
    totals.fetchedRows += fetched.rows.length;
    totals.eligibleBlueprintCount += counts.eligibleBlueprintCount;
    totals.eligibleListingCount += counts.eligibleListingCount || 0;
    totals.upsertedCount += counts.upsertedCount;
    totals.deletedCount += counts.deletedCount;
    emitCacheRefreshProgress(options, 'refresh_batch_done', {
      batchIndex,
      totalBatches,
      ...counts,
      totals,
    });
  }

  return totals;
}

module.exports = {
  CARDTRADER_MARKUP_PKN,
  DEFAULT_BLUEPRINT_CONCURRENCY,
  DEFAULT_MAX_BLUEPRINTS,
  DEFAULT_REFRESH_BATCH_BLUEPRINTS,
  DEFAULT_REQUEST_DELAY_MS,
  MAX_BLUEPRINT_CONCURRENCY,
  MAX_REFRESH_BATCH_BLUEPRINTS,
  PROVIDER,
  SUPPORTED_PRODUCT_TYPES,
  cacheRowsFromMarketplacePayload,
  cleanProductType,
  configuredCardTraderApiToken,
  fetchCacheRowsForBlueprints,
  isTrueCardTraderZeroProduct,
  marketplacePricePknFromCardTrader,
  normalizeCacheRefreshOptions,
  readBlueprintIdsFromCandidates,
  refreshOracleBlueprintListingCache,
  requireCardTraderApiToken,
  runCacheRefresh,
  summarizeDryRunCacheRows,
};
