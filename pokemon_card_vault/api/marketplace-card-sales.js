const { getFirebaseAdmin } = require('./_firebase');
const { marketplaceQuery } = require('./_marketplace_db');

function cleanText(value, maxLength = 240) {
  return String(value || '').trim().slice(0, maxLength);
}

function cleanLimit(value, fallback = 200) {
  const limit = Number(value);
  if (!Number.isFinite(limit)) return fallback;
  return Math.min(Math.max(Math.trunc(limit), 1), 500);
}

function numberValue(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function timestampToIso(value) {
  if (!value) return null;
  if (typeof value === 'string') return value;
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return value.toISOString();
  }
  return value.toDate?.().toISOString?.() || value.toISOString?.() || null;
}

function normalizeSaleItem(orderId, paidAt, item) {
  const raw = item && typeof item === 'object' ? item : {};
  const card = raw.card && typeof raw.card === 'object' ? raw.card : {};
  const quantity = Math.max(1, Math.trunc(numberValue(raw.quantity, 1)));
  const unitPricePkn = numberValue(raw.unitPricePkn ?? raw.pricePkn ?? raw.price_pkn);
  const totalPricePkn = numberValue(
    raw.totalPricePkn ?? raw.total_pkn,
    unitPricePkn * quantity,
  );
  const effectiveUnitPrice = unitPricePkn > 0 ? unitPricePkn : totalPricePkn / quantity;

  return {
    orderId,
    cardId: cleanText(card.id || raw.cardId || raw.card_id, 80),
    condition: cleanText(raw.condition, 40) || 'NM',
    pricePkn: Number(effectiveUnitPrice.toFixed(6)),
    quantity,
    soldAt: paidAt,
    graded: raw.graded === true,
    gradingCompany: cleanText(raw.gradingCompany, 80),
    grade: cleanText(raw.grade, 40),
  };
}

function normalizeOracleSale(row = {}) {
  const observedAt = timestampToIso(row.observed_at) || timestampToIso(row.created_at);
  return {
    orderId: cleanText(row.source_item_id || `oracle-${row.id || ''}`, 160),
    cardId: cleanText(row.blueprint_id, 80),
    condition: cleanText(row.condition, 40) || 'NM',
    language: cleanText(row.language, 12).toUpperCase(),
    pricePkn: Number(numberValue(row.price_pkn).toFixed(6)),
    quantity: Math.max(1, Math.trunc(numberValue(row.quantity, 1))),
    soldAt: observedAt,
    graded: row.graded === true,
    gradingCompany: cleanText(row.grading_company, 80),
    grade: cleanText(row.grade, 40),
    source: cleanText(row.source, 80),
  };
}

function dayKey(value) {
  if (!value) return '';
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return value.toISOString().slice(0, 10);
  }
  const text = String(value);
  const match = text.match(/^(\d{4}-\d{2}-\d{2})/);
  return match ? match[1] : text.slice(0, 10);
}

function roundPkn(value) {
  return Number(numberValue(value).toFixed(2));
}

function sampleCountOf(row) {
  const source = row && typeof row === 'object' ? row : {};
  const samples = Math.max(0, Math.trunc(numberValue(source.sample_count ?? source.sampleCount)));
  if (samples > 0) {
    return samples;
  }
  const listings = Math.max(0, Math.trunc(numberValue(source.listings)));
  if (listings > 0) {
    return listings;
  }
  return Math.max(0, Math.trunc(numberValue(source.sold_qty ?? source.soldQty)));
}

function commentList(value) {
  const rows = Array.isArray(value) ? value : [];
  const seen = new Set();
  const comments = [];
  for (const row of rows) {
    const text = String(row || '').trim();
    if (text && !seen.has(text)) {
      seen.add(text);
      comments.push(text);
    }
  }
  return comments.slice(0, 8);
}

function compactSoldDailySlice(row = {}) {
  return {
    day: dayKey(row.day || row.observed_day),
    condition: String(row.condition || '').trim(),
    language: String(row.language || '').trim().toUpperCase(),
    reverse: Boolean(row.reverse),
    firstEdition: Boolean(row.first_edition ?? row.firstEdition),
    graded: Boolean(row.graded),
    medianPkn: roundPkn(row.median_pkn ?? row.medianPkn),
    minPkn: roundPkn(row.min_pkn ?? row.minPkn),
    maxPkn: roundPkn(row.max_pkn ?? row.maxPkn),
    soldQty: Math.max(0, Math.trunc(numberValue(row.sold_qty ?? row.soldQty))),
    listings: Math.max(0, Math.trunc(numberValue(row.listings))),
    sampleCount: sampleCountOf(row),
    comments: commentList(row.graded_comments ?? row.comments),
  };
}

function medianOf(values) {
  const list = values.map(Number).filter((n) => Number.isFinite(n) && n > 0).sort((a, b) => a - b);
  if (!list.length) {
    return 0;
  }
  const mid = Math.floor((list.length - 1) / 2);
  if (list.length % 2) {
    return list[mid];
  }
  return (list[mid] + list[mid + 1]) / 2;
}

function mergeSoldDailyRows(rows = []) {
  const byDay = new Map();
  for (const row of rows || []) {
    const day = dayKey(row.day || row.observed_day || row.observed_at);
    if (!day) {
      continue;
    }
    const bucket = byDay.get(day) || [];
    bucket.push(row);
    byDay.set(day, bucket);
  }
  return [...byDay.entries()].map(([day, slices]) => {
    const prices = [];
    const comments = [];
    let minPkn = Infinity;
    let maxPkn = 0;
    let soldQty = 0;
    let listings = 0;
    let sampleCount = 0;
    for (const slice of slices) {
      const median = numberValue(slice.median_pkn ?? slice.medianPkn);
      const qty = Math.max(1, Math.trunc(numberValue(slice.sold_qty ?? slice.soldQty, 1)));
      for (let i = 0; i < qty; i += 1) {
        prices.push(median);
      }
      minPkn = Math.min(minPkn, numberValue(slice.min_pkn ?? slice.minPkn, median));
      maxPkn = Math.max(maxPkn, numberValue(slice.max_pkn ?? slice.maxPkn, median));
      soldQty += Math.max(0, Math.trunc(numberValue(slice.sold_qty ?? slice.soldQty)));
      listings += Math.max(0, Math.trunc(numberValue(slice.listings)));
      sampleCount += sampleCountOf(slice);
      comments.push(...commentList(slice.graded_comments ?? slice.comments));
    }
    return {
      day,
      median_pkn: slices.length === 1 ? numberValue(slices[0].median_pkn ?? slices[0].medianPkn) : medianOf(prices),
      min_pkn: minPkn === Infinity ? 0 : minPkn,
      max_pkn: maxPkn,
      sold_qty: soldQty,
      listings,
      sample_count: sampleCount || listings,
      comments: commentList(comments),
    };
  });
}

function buildSalesSeries(dayRows = []) {
  const days = (Array.isArray(dayRows) ? dayRows : [])
    .map((row) => ({
      day: dayKey(row.day || row.observed_day || row.observed_at),
      medianPkn: roundPkn(row.median_pkn ?? row.medianPkn),
      minPkn: roundPkn(row.min_pkn ?? row.minPkn),
      maxPkn: roundPkn(row.max_pkn ?? row.maxPkn),
      soldQty: Math.max(0, Math.trunc(numberValue(row.sold_qty ?? row.soldQty))),
      listings: Math.max(0, Math.trunc(numberValue(row.listings, 0))),
      sampleCount: sampleCountOf(row),
      comments: commentList(row.comments ?? row.graded_comments),
    }))
    .filter((row) => row.day && row.medianPkn > 0)
    .sort((left, right) => left.day.localeCompare(right.day));

  let change24hPct = null;
  if (days.length >= 2) {
    const previous = days[days.length - 2].medianPkn;
    const latest = days[days.length - 1].medianPkn;
    if (previous > 0) {
      change24hPct = Number(((latest - previous) / previous).toFixed(6));
    }
  }

  return {
    days,
    sampleCount: days.reduce((sum, row) => sum + row.sampleCount, 0),
    change24hPct,
    firstDay: days[0]?.day || null,
    lastDay: days[days.length - 1]?.day || null,
    lastMedianPkn: days[days.length - 1]?.medianPkn || null,
  };
}

const SOLD_CONDITION_ORDER = ['NM', 'SP', 'MP', 'PL', 'Poor'];
const SOLD_LANGUAGE_ORDER = [
  'EN', 'IT', 'JP', 'FR', 'DE', 'ES', 'KO', 'ZH', 'ZHT', 'PT', 'NL', 'PL', 'RU', 'ID', 'TH', 'VI',
];

/** Normalize CardTrader leftover strings to the desk condition keys. */
const SOLD_CONDITION_SQL = `
  case
    when lower(btrim(coalesce(condition, ''))) in ('nm', 'mint', 'near mint', 'near mint foil') then 'NM'
    when lower(btrim(coalesce(condition, ''))) in ('sp', 'slightly played', 'lightly played', 'lp', 'excellent', 'ex') then 'SP'
    when lower(btrim(coalesce(condition, ''))) in ('mp', 'moderately played', 'played good', 'good', 'gd') then 'MP'
    when lower(btrim(coalesce(condition, ''))) in ('poor', 'po', 'damaged', 'dmg') then 'Poor'
    when lower(btrim(coalesce(condition, ''))) in ('pl', 'played', 'poor played') then 'PL'
    else nullif(btrim(condition), '')
  end
`;

const SOLD_LANGUAGE_SQL = `
  case
    when lower(btrim(coalesce(language, ''))) in ('en', 'english') then 'EN'
    when lower(btrim(coalesce(language, ''))) in ('it', 'italian') then 'IT'
    when lower(btrim(coalesce(language, ''))) in ('fr', 'french') then 'FR'
    when lower(btrim(coalesce(language, ''))) in ('de', 'german') then 'DE'
    when lower(btrim(coalesce(language, ''))) in ('es', 'spanish') then 'ES'
    when lower(btrim(coalesce(language, ''))) in ('jp', 'ja', 'japanese') then 'JP'
    when lower(btrim(coalesce(language, ''))) in ('pt', 'portuguese') then 'PT'
    when lower(btrim(coalesce(language, ''))) in ('nl', 'dutch') then 'NL'
    when lower(btrim(coalesce(language, ''))) in ('pl', 'polish') then 'PL'
    when lower(btrim(coalesce(language, ''))) in ('ru', 'russian') then 'RU'
    when lower(btrim(coalesce(language, ''))) in ('ko', 'kr', 'korean') then 'KO'
    when lower(btrim(coalesce(language, ''))) in ('zh-tw', 'zht', 'zh_hant', 'zh-hant') then 'ZHT'
    when lower(btrim(coalesce(language, ''))) in ('zh', 'zh-cn', 'zh_hans', 'zh-hans', 'chinese') then 'ZH'
    when lower(btrim(coalesce(language, ''))) in ('id', 'indonesian', 'indonesia') then 'ID'
    else nullif(upper(btrim(language)), '')
  end
`;

function uniqueOrdered(values, order) {
  const seen = new Set();
  for (const value of values) {
    const key = String(value || '').trim();
    if (key) {
      seen.add(key);
    }
  }
  const ranked = order.filter((key) => seen.has(key));
  const rest = [...seen].filter((key) => !order.includes(key)).sort((left, right) => left.localeCompare(right));
  return [...ranked, ...rest];
}

function uniqueFlags(values = []) {
  const seen = new Set();
  for (const value of values) {
    if (value === true || value === false) {
      seen.add(value);
      continue;
    }
    const text = String(value ?? '').trim().toLowerCase();
    if (['true', 't', '1', 'yes'].includes(text)) {
      seen.add(true);
    } else if (['false', 'f', '0', 'no'].includes(text)) {
      seen.add(false);
    }
  }
  return [false, true].filter((flag) => seen.has(flag));
}

function rowMatchesSoldSlice(row, slice = {}, omit = '') {
  const flags = soldSlicePayload(slice);
  if (omit !== 'condition' && flags.condition && String(row.condition || '') !== flags.condition) {
    return false;
  }
  if (omit !== 'language' && flags.language && String(row.language || '').toUpperCase() !== flags.language) {
    return false;
  }
  if (omit !== 'reverse' && flags.reverse !== null && Boolean(row.reverse) !== flags.reverse) {
    return false;
  }
  if (
    omit !== 'firstEdition'
    && flags.firstEdition !== null
    && Boolean(row.first_edition ?? row.firstEdition) !== flags.firstEdition
  ) {
    return false;
  }
  if (omit !== 'graded' && flags.graded !== null && Boolean(row.graded) !== flags.graded) {
    return false;
  }
  return true;
}

function buildSalesFilters(rows = [], slice = {}) {
  const list = Array.isArray(rows) ? rows : [];
  const facet = (omit) => list.filter((row) => rowMatchesSoldSlice(row, slice, omit));
  return {
    conditions: uniqueOrdered(facet('condition').map((row) => row.condition), SOLD_CONDITION_ORDER),
    languages: uniqueOrdered(facet('language').map((row) => row.language), SOLD_LANGUAGE_ORDER),
    reverse: uniqueFlags(facet('reverse').map((row) => row.reverse)),
    firstEdition: uniqueFlags(facet('firstEdition').map((row) => row.first_edition ?? row.firstEdition)),
    graded: uniqueFlags(facet('graded').map((row) => row.graded)),
  };
}

function cleanSoldCondition(value) {
  const text = String(value || '').trim();
  if (SOLD_CONDITION_ORDER.includes(text)) {
    return text;
  }
  const lowered = text.toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
  if (['nm', 'mint', 'near mint'].includes(lowered)) return 'NM';
  if (['sp', 'slightly played', 'lightly played', 'lp'].includes(lowered)) return 'SP';
  if (['mp', 'moderately played', 'good', 'gd'].includes(lowered)) return 'MP';
  if (['pl', 'played'].includes(lowered)) return 'PL';
  if (['poor', 'po', 'damaged'].includes(lowered)) return 'Poor';
  return '';
}

function cleanSoldLanguage(value) {
  const text = String(value || '').trim().toUpperCase();
  if (!text) {
    return '';
  }
  if (text === 'JA') return 'JP';
  if (text === 'KR') return 'KO';
  if (text === 'ZH-CN' || text === 'ZH_HANS') return 'ZH';
  if (text === 'ZH-TW' || text === 'ZH_HANT') return 'ZHT';
  if (text === 'ZHT' || /^[A-Z]{2,3}$/.test(text)) {
    return text;
  }
  return '';
}

function cleanSoldFlag(value) {
  if (value === true || value === false) {
    return value;
  }
  const text = String(value ?? '').trim().toLowerCase();
  if (!text) {
    return null;
  }
  if (['1', 'true', 'yes', 'reverse', 'graded', 'first', '1st', 'first edition'].includes(text)) {
    return true;
  }
  if (['0', 'false', 'no', 'standard', 'unlimited', 'raw', 'ungraded'].includes(text)) {
    return false;
  }
  return null;
}

function soldSlicePayload(slice = {}) {
  return {
    condition: cleanSoldCondition(slice.condition) || null,
    language: cleanSoldLanguage(slice.language) || null,
    reverse: cleanSoldFlag(slice.reverse),
    firstEdition: cleanSoldFlag(slice.firstEdition ?? slice.first_edition),
    graded: cleanSoldFlag(slice.graded),
  };
}

function lastMedianPayload(cardId, row = null, slice = {}) {
  const median = roundPkn(row?.median_pkn ?? row?.medianPkn);
  const day = dayKey(row?.day || row?.observed_day || row?.observed_at);
  const flags = soldSlicePayload(slice);
  const samples = sampleCountOf(row);
  return {
    card_id: String(cardId || ''),
    day: day && median > 0 ? day : null,
    median_pkn: day && median > 0 ? median : null,
    sample_count: day && median > 0 && samples > 0 ? samples : null,
    currency: 'PKN',
    source: 'cardtrader_removed_sale',
    ...flags,
  };
}

function soldSliceFromSearchParams(searchParams) {
  const params = searchParams && typeof searchParams.get === 'function'
    ? searchParams
    : new URLSearchParams(String(searchParams || ''));
  return {
    condition: cleanSoldCondition(params.get('condition') || params.get('cond')),
    language: cleanSoldLanguage(params.get('language') || params.get('lang')),
    reverse: cleanSoldFlag(params.get('reverse')),
    firstEdition: cleanSoldFlag(
      params.get('firstEdition') || params.get('first_edition') || params.get('edition'),
    ),
    graded: cleanSoldFlag(params.get('graded')),
  };
}

function soldSliceValues(slice = {}) {
  const flags = soldSlicePayload(slice);
  return [
    flags.condition || '',
    flags.language || '',
    flags.reverse,
    flags.firstEdition,
    flags.graded,
  ];
}

// Public cardId is leftover ct_id × 2, so it collides with other blueprints
// (Mew 242572 + Morpeko V-UNION ct_id 242572). Prefer our id; leftover ct_id
// only when that number is not a card_id. Same order as `_marketplace_leftover`.
const SALES_BLUEPRINT_SQL = `
  select ct_id
  from public.marketplace_search_candidates
  where card_id = $1::bigint
     or ct_id = $1::bigint
  order by
    case when card_id = $1::bigint then 0 else 1 end,
    card_id
  limit 1
`;

function soldSliceSql(startIndex) {
  return `
    and ($${startIndex}::text = '' or (${SOLD_CONDITION_SQL}) = $${startIndex})
    and ($${startIndex + 1}::text = '' or (${SOLD_LANGUAGE_SQL}) = $${startIndex + 1})
    and ($${startIndex + 2}::boolean is null or reverse = $${startIndex + 2})
    and ($${startIndex + 3}::boolean is null or first_edition = $${startIndex + 3})
    and ($${startIndex + 4}::boolean is null or graded = $${startIndex + 4})
  `;
}

function soldDailySliceSql(startIndex) {
  return `
    and ($${startIndex}::text = '' or condition = $${startIndex})
    and ($${startIndex + 1}::text = '' or language = $${startIndex + 1})
    and ($${startIndex + 2}::boolean is null or reverse = $${startIndex + 2})
    and ($${startIndex + 3}::boolean is null or first_edition = $${startIndex + 3})
    and ($${startIndex + 4}::boolean is null or graded = $${startIndex + 4})
  `;
}

function catchMissingRelation(error) {
  if (error && (error.code === '42P01' || error.code === '42703')) {
    return { rows: [], missing: true };
  }
  throw error;
}

/** Inferred_sale listing ids that only appear on one day. Repeats are snapshot flicker. */
const SOLD_ONCE_LISTING_SQL = `
  (
    split_part(source_item_id, ':', 4) = 'quantity_decreased'
    or split_part(source_item_id, ':', 2) in (
      select split_part(source_item_id, ':', 2)
      from public.marketplace_price_observations
      where source = 'cardtrader_removed_sale'
        and split_part(source_item_id, ':', 4) is distinct from 'quantity_decreased'
      group by 1
      having count(distinct (observed_at at time zone 'utc')::date) = 1
    )
  )
`;

async function readOracleCardSales({ cardId, limit, ...slice }) {
  const result = await marketplaceQuery(
    `
      select
        id,
        blueprint_id,
        source,
        source_item_id,
        observed_at,
        price_pkn,
        quantity,
        condition,
        language,
        graded,
        grading_company,
        grade,
        created_at
      from public.marketplace_price_observations
      where blueprint_id in (${SALES_BLUEPRINT_SQL})
        and price_pkn > 0
        and source = 'cardtrader_removed_sale'
        and ${SOLD_ONCE_LISTING_SQL}
        ${soldSliceSql(2)}
      order by observed_at desc, created_at desc
      limit $7
    `,
    [cardId, ...soldSliceValues(slice), limit],
  ).catch(catchMissingRelation);
  return result.rows
    .map((row) => ({
      ...normalizeOracleSale(row),
      cardId,
    }))
    .filter((sale) => sale.cardId === cardId && sale.pricePkn > 0 && sale.soldAt);
}

async function readOracleSoldDailyRows(cardId, slice = {}) {
  const result = await marketplaceQuery(
    `
      select
        observed_day as day,
        condition,
        language,
        reverse,
        first_edition,
        graded,
        median_pkn,
        min_pkn,
        max_pkn,
        sold_qty,
        listings,
        sample_count,
        graded_comments
      from public.cardtrader_sold_daily
      where blueprint_id in (${SALES_BLUEPRINT_SQL})
        ${soldDailySliceSql(2)}
      order by 1
    `,
    [cardId, ...soldSliceValues(slice)],
  ).catch(catchMissingRelation);
  if (result.missing) {
    return { missing: true, rows: [] };
  }
  return { missing: false, rows: result.rows };
}

async function readOracleCardSalesSeries({ cardId, ...slice }) {
  const daily = await readOracleSoldDailyRows(cardId, slice);
  if (!daily.missing) {
    return buildSalesSeries(mergeSoldDailyRows(daily.rows));
  }
  const result = await marketplaceQuery(
    `
      select
        (observed_at at time zone 'utc')::date as day,
        percentile_cont(0.5) within group (order by price_pkn) as median_pkn,
        min(price_pkn) as min_pkn,
        max(price_pkn) as max_pkn,
        coalesce(sum(quantity), 0)::integer as sold_qty,
        count(*)::integer as listings,
        count(*)::integer as sample_count
      from public.marketplace_price_observations
      where blueprint_id in (${SALES_BLUEPRINT_SQL})
        and price_pkn > 0
        and source = 'cardtrader_removed_sale'
        and ${SOLD_ONCE_LISTING_SQL}
        ${soldSliceSql(2)}
      group by 1
      order by 1
    `,
    [cardId, ...soldSliceValues(slice)],
  ).catch(catchMissingRelation);
  return buildSalesSeries(result.rows);
}

async function readOracleSalesFilters({ cardId, ...slice }) {
  const daily = await marketplaceQuery(
    `
      select distinct
        condition,
        language,
        reverse,
        first_edition,
        graded
      from public.cardtrader_sold_daily
      where blueprint_id in (${SALES_BLUEPRINT_SQL})
    `,
    [cardId],
  ).catch(catchMissingRelation);
  if (!daily.missing) {
    return buildSalesFilters(daily.rows, slice);
  }
  const result = await marketplaceQuery(
    `
      select distinct
        ${SOLD_CONDITION_SQL} as condition,
        ${SOLD_LANGUAGE_SQL} as language,
        reverse,
        first_edition,
        graded
      from public.marketplace_price_observations
      where blueprint_id in (${SALES_BLUEPRINT_SQL})
        and price_pkn > 0
        and source = 'cardtrader_removed_sale'
        and ${SOLD_ONCE_LISTING_SQL}
    `,
    [cardId],
  ).catch(catchMissingRelation);
  return buildSalesFilters(result.rows, slice);
}

async function readOracleLastMedian({ cardId, ...slice }) {
  const series = await readOracleCardSalesSeries({ cardId, ...slice });
  return lastMedianPayload(cardId, {
    day: series.lastDay,
    median_pkn: series.lastMedianPkn,
    sample_count: series.days[series.days.length - 1]?.sampleCount || 0,
  }, slice);
}

async function readNativeCardSales({ cardId, limit }) {
  const admin = getFirebaseAdmin();
  const firestore = admin.firestore();
  const rows = [];
  const seenOrders = new Set();
  let queryLimit = Math.min(Math.max(limit * 12, 80), 500);

  while (rows.length < limit && queryLimit <= 500) {
    const snapshot = await firestore
      .collection('orders')
      .where('paymentStatus', '==', 'paid')
      .limit(queryLimit)
      .get();

    for (const doc of snapshot.docs) {
      if (seenOrders.has(doc.id)) continue;
      seenOrders.add(doc.id);
      const data = doc.data() || {};
      const paidAt = timestampToIso(data.paidAt || data.createdAt);
      const items = Array.isArray(data.items) ? data.items : [];
      for (const item of items) {
        const sale = normalizeSaleItem(doc.id, paidAt, item);
        if (sale.cardId === cardId && sale.pricePkn > 0 && sale.soldAt) {
          rows.push(sale);
          if (rows.length >= limit) break;
        }
      }
      if (rows.length >= limit) break;
    }

    if (snapshot.size < queryLimit || queryLimit >= 500) break;
    queryLimit = Math.min(queryLimit * 2, 500);
  }

  return rows
    .sort((left, right) => String(left.soldAt).localeCompare(String(right.soldAt)))
    .slice(-limit);
}

async function readCardSales({ cardId, limit, includeNative = false, ...slice }) {
  const oracleRows = await readOracleCardSales({ cardId, limit, ...slice });
  if (!includeNative) {
    return oracleRows
      .sort((left, right) => String(left.soldAt).localeCompare(String(right.soldAt)))
      .slice(-limit);
  }
  const firebaseRows = await readNativeCardSales({ cardId, limit });
  const merged = new Map();
  for (const sale of [...firebaseRows, ...oracleRows]) {
    const key = `${sale.orderId}|${sale.cardId}|${sale.soldAt}|${sale.pricePkn}|${sale.condition}`;
    merged.set(key, sale);
  }
  return [...merged.values()]
    .sort((left, right) => String(left.soldAt).localeCompare(String(right.soldAt)))
    .slice(-limit);
}

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET, OPTIONS');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
    const cardId = cleanText(url.searchParams.get('cardId'), 80);
    if (!/^\d+$/.test(cardId)) {
      return res.status(400).json({ error: 'cardId is required.' });
    }

    const includeNative = String(url.searchParams.get('includeNative') || '').trim() === '1';
    const includeRows = includeNative
      || String(url.searchParams.get('includeRows') || '').trim() === '1';
    const wantSlices = String(url.searchParams.get('slices') || '').trim() === '1';
    if (wantSlices) {
      const daily = await readOracleSoldDailyRows(cardId, {});
      res.setHeader('Cache-Control', 'public, max-age=20, s-maxage=120');
      return res.status(200).json({
        slices: (daily.rows || []).map(compactSoldDailySlice),
        source: 'cardtrader_removed_sale',
      });
    }
    const slice = soldSliceFromSearchParams(url.searchParams);
    const [rows, series, filters] = await Promise.all([
      includeRows
        ? readCardSales({
          cardId,
          limit: cleanLimit(url.searchParams.get('limit'), 120),
          includeNative,
          ...slice,
        })
        : Promise.resolve([]),
      readOracleCardSalesSeries({ cardId, ...slice }),
      readOracleSalesFilters({ cardId, ...slice }),
    ]);
    res.setHeader('Cache-Control', 'public, max-age=20, s-maxage=120');
    return res.status(200).json({
      rows,
      series,
      filters,
      slice: soldSlicePayload(slice),
      source: 'cardtrader_removed_sale',
    });
  } catch (error) {
    console.error('marketplace-card-sales failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Marketplace card sales failed.',
    });
  }
};

module.exports.readCardSales = readCardSales;
module.exports.readOracleCardSales = readOracleCardSales;
module.exports.readOracleCardSalesSeries = readOracleCardSalesSeries;
module.exports.readOracleLastMedian = readOracleLastMedian;
module.exports.readOracleSalesFilters = readOracleSalesFilters;
module.exports.buildSalesSeries = buildSalesSeries;
module.exports.buildSalesFilters = buildSalesFilters;
module.exports.mergeSoldDailyRows = mergeSoldDailyRows;
module.exports.cleanSoldCondition = cleanSoldCondition;
module.exports.cleanSoldLanguage = cleanSoldLanguage;
module.exports.cleanSoldFlag = cleanSoldFlag;
module.exports.soldSliceFromSearchParams = soldSliceFromSearchParams;
module.exports.soldSlicePayload = soldSlicePayload;
module.exports.lastMedianPayload = lastMedianPayload;
module.exports.sampleCountOf = sampleCountOf;
module.exports.compactSoldDailySlice = compactSoldDailySlice;
module.exports.normalizeSaleItem = normalizeSaleItem;
module.exports.normalizeOracleSale = normalizeOracleSale;
