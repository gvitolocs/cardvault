'use strict';

/**
 * Apply recentCardIds onto a cached home snapshot without busting the 30s cache.
 */
const { parseIdList } = require('./_marketplace_react_card');

function mergeRecentIntoHome(snapshot, recentIds, extraCards = []) {
  const cards = Array.isArray(snapshot.cards) ? [...snapshot.cards] : [];
  const byId = new Map(cards.map((card) => [String(card.id), card]));
  for (const card of extraCards) {
    const id = String(card.id || '');
    if (id && !byId.has(id)) {
      byId.set(id, card);
      cards.push(card);
    }
  }
  const known = new Set(byId.keys());
  const sections = { ...(snapshot.sections || {}) };
  const recent = recentIds.filter((id) => known.has(String(id)));
  const previous = Array.isArray(sections.recentlySeenIds) ? sections.recentlySeenIds : [];
  sections.recentlySeenIds = [
    ...recent,
    ...previous.filter((id) => !recent.includes(String(id))),
  ].slice(0, 12);
  sections.spotlightIds = sections.recentlySeenIds;
  return {
    ...snapshot,
    cards,
    sections,
  };
}

function recentIdsFromUrl(url) {
  return parseIdList(
    url.searchParams.get('recentCardIds') || url.searchParams.get('recent'),
    24,
  );
}

function mergeHomeDisplayCards(newestCards, availableCards, limit = 140) {
  const byId = new Map();
  for (const card of newestCards || []) {
    const id = String(card?.id || '');
    if (id) {
      byId.set(id, card);
    }
  }
  for (const card of availableCards || []) {
    const id = String(card?.id || '');
    if (id && !byId.has(id)) {
      byId.set(id, card);
    }
  }
  return [...byId.values()].slice(0, limit);
}

module.exports = {
  mergeRecentIntoHome,
  recentIdsFromUrl,
  mergeHomeDisplayCards,
};
