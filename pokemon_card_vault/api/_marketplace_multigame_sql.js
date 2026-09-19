'use strict';

const { marketplaceQuery } = require('./_marketplace_db');
const { toReactCards } = require('./_marketplace_react_card');
const sql = require('./_marketplace_react_sql');

function cleanQuery(value) {
  return String(value || '').trim().slice(0, 180);
}

async function rowsForMultigameCards({
  query = '',
  limit = 48,
  offset = 0,
  productType = '',
  productSearchOnly = false,
} = {}) {
  const term = cleanQuery(query);
  const cap = Math.min(Math.max(Number(limit) || 48, 1), 100);
  const skip = Math.max(Number(offset) || 0, 0);
  const values = [];
  const clauses = [
    'coalesce(c.cdn_image_url, c.preview_image_url, c.image_url) is not null',
  ];

  if (productSearchOnly || productType) {
    clauses.push("c.item_kind = 'product'");
    if (productType && productType !== 'sealed') {
      values.push(productType);
      clauses.push(`c.product_type = $${values.length}`);
    }
  } else if (!term) {
    clauses.push("c.item_kind = 'single'");
    clauses.push("c.product_type = 'card'");
  }

  let nameBoostSql = '0';
  if (term) {
    values.push(`%${term.toLowerCase()}%`);
    const likeIdx = values.length;
    clauses.push(`c.search_text like $${likeIdx}`);
    values.push(term.toLowerCase());
    nameBoostSql = `case when lower(c.name) = $${values.length} then 0 when lower(c.name) like $${likeIdx} then 1 else 2 end`;
  }

  values.push(cap);
  const lim = values.length;
  values.push(skip);
  const off = values.length;

  const result = await marketplaceQuery(
    `
      select
        c.card_id,
        c.ct_id,
        c.name,
        c.image_url,
        c.cdn_image_url,
        c.preview_image_url,
        c.homepage_image_url,
        c.set_name,
        c.rarity,
        c.card_number,
        c.product_variant,
        c.item_kind,
        c.product_type,
        c.imported_at,
        u.canonical_path
      from public.marketplace_search_candidates c
      left join public.marketplace_card_urls u
        on u.card_id = c.card_id and u.language = 'en'
      where ${clauses.join('\n        and ')}
      order by ${nameBoostSql},
        c.search_weight desc,
        c.imported_at desc nulls last,
        c.card_id desc
      limit $${lim}
      offset $${off}
    `,
    values,
  );
  return result.rows;
}

async function suggestMultigameGroups(query, groupLimit = 12) {
  const term = cleanQuery(query);
  if (!term) {
    return [];
  }
  const cap = Math.min(Math.max(Number(groupLimit) || 12, 1), 24);
  const like = `%${term.toLowerCase()}%`;
  const result = await marketplaceQuery(
    `
      select
        c.card_id,
        c.ct_id,
        c.name,
        c.image_url,
        c.cdn_image_url,
        c.preview_image_url,
        c.homepage_image_url,
        c.set_name,
        c.rarity,
        c.card_number,
        c.product_variant,
        c.item_kind,
        c.product_type,
        u.canonical_path
      from public.marketplace_search_candidates c
      left join public.marketplace_card_urls u
        on u.card_id = c.card_id and u.language = 'en'
      where coalesce(c.cdn_image_url, c.preview_image_url, c.image_url) is not null
        and c.search_text like $1
      order by
        case when lower(c.name) = lower($2) then 0
             when lower(c.name) like $1 then 1
             else 2 end,
        c.search_weight desc,
        c.card_id desc
      limit $3
    `,
    [like, term, Math.max(cap * 6, 36)],
  );
  const cards = toReactCards(result.rows);
  const groups = [];
  const byName = new Map();
  for (const card of cards) {
    const key = String(card.name || '').toLowerCase();
    if (!key) continue;
    let group = byName.get(key);
    if (!group) {
      if (groups.length >= cap) continue;
      group = {
        name: card.name,
        printings: [],
      };
      byName.set(key, group);
      groups.push(group);
    }
    if (group.printings.length < 6) {
      group.printings.push(card);
    }
  }
  return groups;
}

async function loadMultigameCardPage(cardId) {
  const row = await sql.readCandidateByCardId(cardId);
  if (!row) {
    return null;
  }
  const siblings = await sql.readSetSiblings(row, 8);
  const siblingPaths = await sql.readCanonicalPaths([
    cardId,
    ...siblings.map((entry) => entry.card_id),
  ]);
  const neighbors = await sql.readSetNeighbors(row.set_name, cardId, 3);
  const emptyCheapest = { byCardId: new Map(), byBlueprint: new Map() };
  return {
    row: sql.applyCanonicalAndCheapest([row], siblingPaths, emptyCheapest)[0],
    siblings: sql.applyCanonicalAndCheapest(siblings, siblingPaths, emptyCheapest),
    neighbors,
  };
}

module.exports = {
  rowsForMultigameCards,
  suggestMultigameGroups,
  loadMultigameCardPage,
};
