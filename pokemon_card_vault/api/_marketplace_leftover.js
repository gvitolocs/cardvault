'use strict';

const { marketplaceQuery } = require('./_marketplace_db');
const { runWithGame, currentGame, GAMES } = require('./_marketplace_game');

function cleanMarketplaceId(value) {
  const id = String(value || '').trim();
  return /^\d{1,12}$/.test(id) ? id : '';
}

async function catalogIdsFor(id) {
  const key = cleanMarketplaceId(id);
  if (!key) {
    return null;
  }
  const result = await marketplaceQuery(
    `
      select
        card_id::text as card_id,
        ct_id::text as ct_id,
        name,
        set_name,
        card_number
      from public.marketplace_search_candidates
      where card_id = $1::bigint
         or ct_id = $1::bigint
      order by
        case when card_id = $1::bigint then 0 else 1 end,
        card_id
      limit 1
    `,
    [key],
  );
  // Prefer public card_id. Leftover even ct_id can collide with another
  // card's public id (Mew leftover 274416 = Kabutops public 274416).
  // SPA sends id=public and blueprintId=leftover so CT still hits Mew.
  const row = result.rows[0];
  if (!row) {
    return null;
  }
  const ctId = String(row.ct_id || '').trim();
  return {
    cardId: String(row.card_id || ''),
    ctId: /^\d+$/.test(ctId) ? ctId : '',
    name: String(row.name || ''),
    setName: String(row.set_name || ''),
    cardNumber: String(row.card_number || ''),
  };
}

async function catalogIdsForAnyGame(id) {
  const first = await catalogIdsFor(id);
  if (first?.ctId) {
    return { ...first, game: currentGame() };
  }
  const start = currentGame();
  for (const g of Object.keys(GAMES)) {
    if (g === start) {
      continue;
    }
    try {
      const hit = await runWithGame(g, () => catalogIdsFor(id));
      if (hit?.ctId) {
        return { ...hit, game: g };
      }
    } catch (_) {
      /* isolated DB may be unset */
    }
  }
  return first;
}

module.exports = {
  cleanMarketplaceId,
  catalogIdsFor,
  catalogIdsForAnyGame,
};
