'use strict';

const { marketplaceQuery } = require('./_marketplace_db');
const { toReactCards, parseIdList, setCorsHeaders, jsonOk, cleanText } = require('./_marketplace_react_card');
const sql = require('./_marketplace_react_sql');

const NEW_CARDS_LIMIT = 20;
const FEATURED_LIMIT = 30;
const HOME_RAILS = [
  ['new_cards', 'newArrivalIds', NEW_CARDS_LIMIT],
  ['featured', 'featuredIds', FEATURED_LIMIT],
  ['best_sellers', 'bestSellerIds', 12],
  ['spotlight', 'spotlightIds', 16],
  ['top_sold', 'topSoldIds', 24],
];

function cardId(card) {
  return String(card?.id || card?.card_id || '');
}

function asCards(value) {
  return Array.isArray(value) ? value.filter((card) => card && cardId(card)) : [];
}

function publicizeCards(cards) {
  const sourceCards = asCards(cards);
  return toReactCards(sourceCards).map((card, index) => {
    const source = sourceCards[index] || {};
    const next = { ...card };
    if (source.salesDay) {
      next.salesDay = String(source.salesDay);
      next.dailySoldQty = Number(source.dailySoldQty) || 0;
      next.dailySaleSamples = Number(source.dailySaleSamples) || 0;
      next.dailyMedianPkn = Number(source.dailyMedianPkn) || null;
      next.dailyMinPkn = Number(source.dailyMinPkn) || null;
      next.dailyMaxPkn = Number(source.dailyMaxPkn) || null;
    }
    delete next.ct_id;
    delete next.ctId;
    return next;
  });
}

async function readRails(ids, query = marketplaceQuery) {
  if (!ids.length) {
    return [];
  }
  const result = await query(
    `
      select id, cards, meta, updated_at
      from public.marketplace_rails
      where id = any($1::text[])
    `,
    [ids],
  );
  return result.rows || [];
}

async function readTiles(ids, query = marketplaceQuery) {
  if (!ids.length) {
    return [];
  }
  const result = await query(
    `
      select card_id, payload
      from public.marketplace_card_tiles
      where card_id = any($1::text[])
    `,
    [ids],
  );
  return (result.rows || []).map((row) => row.payload).filter(Boolean);
}

function assembleHomeVector(rows, generatedAt = new Date().toISOString()) {
  const byRail = new Map((rows || []).map((row) => [String(row.id || ''), row]));
  const byId = new Map();
  const sections = {};
  let pknUsdt = 0.005;
  let updatedAt = '';

  function remember(cards) {
    for (const card of publicizeCards(cards)) {
      const id = cardId(card);
      if (!id) {
        continue;
      }
      byId.set(id, card);
    }
  }

  for (const [railId, sectionKey, limit] of HOME_RAILS) {
    const row = byRail.get(railId);
    const cards = asCards(row?.cards).slice(0, limit);
    remember(cards);
    sections[sectionKey] = cards.map(cardId).filter(Boolean);
    const rate = Number(row?.meta?.pknUsdt);
    if (Number.isFinite(rate) && rate > 0) {
      pknUsdt = rate;
    }
    const stamp = String(row?.updated_at || '');
    if (stamp && stamp > updatedAt) {
      updatedAt = stamp;
    }
  }

  return {
    source: 'pi',
    cacheTtl: 300,
    generatedAt,
    updatedAt,
    pknUsdt,
    cards: [...byId.values()],
    sections,
  };
}

module.exports = {
  HOME_RAILS,
  NEW_CARDS_LIMIT,
  FEATURED_LIMIT,
  cardId,
  asCards,
  publicizeCards,
  readRails,
  readTiles,
  assembleHomeVector,
  withThemePacks,
};

/** Attach compact theme packs (`vt`) to public card rows. One batched
 * lookup keyed by card id; the theme is the persisted artwork theme
 * (re-derived from the current shade when the persisted row is missing or
 * stale), so summaries carry the exact desk theme and the client installs
 * it synchronously without any color math. Failures resolve to the
 * unchanged rows — theme hints must never break a summary response. */
async function withThemePacks(cards, overlay = sql) {
  if (!Array.isArray(cards) || !cards.length) {
    return cards;
  }
  try {
    const ids = [...new Set(cards.map(cardId).filter((id) => /^\d+$/.test(id)))];
    const packs = await overlay.readCardThemePacks(ids);
    if (!packs.size) {
      return cards;
    }
    return cards.map((card) => {
      const vt = packs.get(cardId(card));
      return vt ? { ...card, vt } : card;
    });
  } catch (_) {
    return cards;
  }
}
