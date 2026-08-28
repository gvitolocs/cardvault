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
  return value.toDate?.().toISOString?.() || null;
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
    pricePkn: Number(numberValue(row.price_pkn).toFixed(6)),
    quantity: Math.max(1, Math.trunc(numberValue(row.quantity, 1))),
    soldAt: observedAt,
    graded: row.graded === true,
    gradingCompany: cleanText(row.grading_company, 80),
    grade: cleanText(row.grade, 40),
    source: cleanText(row.source, 80),
  };
}

async function readOracleCardSales({ cardId, limit }) {
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
        graded,
        grading_company,
        grade,
        created_at
      from public.marketplace_price_observations
      where blueprint_id = $1::bigint
        and price_pkn > 0
        and source in ('cardtrader_snapshot', 'cardtrader_removed_sale')
      order by observed_at desc, created_at desc
      limit $2
    `,
    [cardId, limit],
  ).catch((error) => {
    if (error.code === '42P01' || error.code === '42703') {
      return { rows: [] };
    }
    throw error;
  });
  return result.rows
    .map(normalizeOracleSale)
    .filter((sale) => sale.cardId === cardId && sale.pricePkn > 0 && sale.soldAt);
}

async function readCardSales({ cardId, limit }) {
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

  const firebaseRows = rows
    .sort((left, right) => String(left.soldAt).localeCompare(String(right.soldAt)))
    .slice(-limit);
  const oracleRows = await readOracleCardSales({ cardId, limit });
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
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
    const cardId = cleanText(url.searchParams.get('cardId'), 80);
    if (!/^\d+$/.test(cardId)) {
      return res.status(400).json({ error: 'cardId is required.' });
    }

    const rows = await readCardSales({
      cardId,
      limit: cleanLimit(url.searchParams.get('limit'), 120),
    });
    res.setHeader('Cache-Control', 'public, max-age=20, s-maxage=120');
    return res.status(200).json({ rows });
  } catch (error) {
    console.error('marketplace-card-sales failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Marketplace card sales failed.',
    });
  }
};

module.exports.readCardSales = readCardSales;
module.exports.readOracleCardSales = readOracleCardSales;
module.exports.normalizeSaleItem = normalizeSaleItem;
module.exports.normalizeOracleSale = normalizeOracleSale;
