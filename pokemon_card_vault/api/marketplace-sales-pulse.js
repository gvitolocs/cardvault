'use strict';

const { marketplaceQuery } = require('./_marketplace_db');
const { setCorsHeaders, jsonOk } = require('./_marketplace_react_card');
const { readRails, publicizeCards } = require('./_marketplace_rails');

function boundedInteger(value, fallback, max) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(Math.max(Math.trunc(number), 1), max);
}

function metricName(value) {
  const metric = String(value || '').toLowerCase();
  return metric === 'quantity' || metric === 'units' ? 'quantity' : 'sales';
}

function integerValue(value) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.max(0, Math.trunc(number)) : 0;
}

function numberValue(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function leaderFrom(raw, card) {
  return {
    card,
    salesDay: String(raw?.salesDay || ''),
    observedSales: integerValue(raw?.dailySaleSamples),
    removedListingQuantity: integerValue(raw?.dailySoldQty),
    medianPkn: numberValue(raw?.dailyMedianPkn),
    minPkn: numberValue(raw?.dailyMinPkn),
    maxPkn: numberValue(raw?.dailyMaxPkn),
  };
}

function rankLeaders(rawCards, metric = 'sales', limit = 12) {
  const cards = publicizeCards(rawCards || []);
  const leaders = (rawCards || []).map((raw, index) => leaderFrom(raw, cards[index]));
  const field = metric === 'quantity' ? 'removedListingQuantity' : 'observedSales';
  return leaders
    .filter((leader) => leader.card?.id && leader[field] > 0)
    .sort((left, right) => (
      right[field] - left[field]
      || right.observedSales - left.observedSales
      || right.removedListingQuantity - left.removedListingQuantity
    ))
    .slice(0, limit)
    .map((leader, index) => ({ rank: index + 1, ...leader }));
}

async function readTrend(days, query = marketplaceQuery) {
  const result = await query(
    `
      with latest as (
        select max(observed_day) as day
        from public.cardtrader_sold_daily
      )
      select
        d.observed_day::text as day,
        sum(d.sold_qty)::bigint as removed_listing_quantity,
        sum(d.sample_count)::bigint as observed_sales,
        count(distinct d.blueprint_id)::integer as active_cards
      from public.cardtrader_sold_daily d, latest l
      where d.observed_day >= l.day - ($1::integer - 1)
      group by d.observed_day
      order by d.observed_day
    `,
    [days],
  );
  return (result.rows || []).map((row) => ({
    day: String(row.day || ''),
    observedSales: integerValue(row.observed_sales),
    removedListingQuantity: integerValue(row.removed_listing_quantity),
    activeCards: integerValue(row.active_cards),
  }));
}

module.exports = async function handler(req, res) {
  setCorsHeaders(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET, OPTIONS');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const url = new URL(req.url, `https://${req.headers.host || 'api.pokoin.com'}`);
    const metric = metricName(url.searchParams.get('metric'));
    const limit = boundedInteger(url.searchParams.get('limit'), 12, 24);
    const days = boundedInteger(url.searchParams.get('days'), 7, 30);
    const railId = metric === 'quantity' ? 'top_sold_quantity' : 'top_sold';
    const [rows, trend] = await Promise.all([
      readRails([railId]),
      readTrend(days),
    ]);
    const rail = rows[0];
    if (!rail) return res.status(503).json({ error: 'Daily sales rail is unavailable.' });

    const leaders = rankLeaders(rail.cards, metric, limit);
    res.setHeader('Cache-Control', 'public, max-age=30, s-maxage=300, stale-while-revalidate=600');
    return jsonOk(res, {
      dataDay: String(rail.meta?.day || leaders[0]?.salesDay || ''),
      refreshedAt: rail.updated_at || null,
      metric,
      totals: {
        observedSales: integerValue(rail.meta?.observedSales ?? rail.meta?.listingEvents),
        removedListingQuantity: integerValue(
          rail.meta?.removedListingQuantity ?? rail.meta?.soldQty,
        ),
        activeCards: integerValue(rail.meta?.activeCards),
      },
      leaders,
      trend,
      source: String(rail.meta?.source || 'cardtrader_removed_sale'),
      methodology: String(
        rail.meta?.methodology
        || 'Observed sales are counted from individual CardTrader removal samples. Removed listing quantity is diagnostic only and is not treated as confirmed sales.',
      ),
    }, 'public, max-age=30, s-maxage=300, stale-while-revalidate=600');
  } catch (error) {
    console.error('marketplace-sales-pulse failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Marketplace sales pulse failed.',
    });
  }
};

module.exports.metricName = metricName;
module.exports.rankLeaders = rankLeaders;
module.exports.readTrend = readTrend;
