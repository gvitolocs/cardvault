'use strict';

const { marketplaceQuery } = require('./_marketplace_db');
const {
  toReactCard,
  parsePublicCardId,
  setCorsHeaders,
  jsonOk,
} = require('./_marketplace_react_card');
const sql = require('./_marketplace_react_sql');

const PRINTING_SQL = `
  select
    c.card_id,
    c.ct_id,
    c.name,
    c.set_name,
    c.card_number,
    c.rarity,
    c.cdn_image_url,
    c.image_url,
    c.preview_image_url,
    c.homepage_image_url,
    c.version,
    e.nationality,
    s.member_count,
    u.canonical_path
  from public.marketplace_search_candidates c
  join public.pokoin_version_sets s on s.version = c.version
  left join public.pokoin_pokemon_expansions e on e.name = c.set_name
  left join public.marketplace_card_urls u
    on u.card_id = c.card_id and u.language = 'en'
  where c.item_kind = 'single'
    and c.product_type = 'card'
    and c.version is not null
    and c.version = (
      select version
      from public.marketplace_search_candidates
      where card_id = $1::bigint
    )
  order by
    case e.nationality
      when 'japanese' then 0
      when 'western' then 1
      when 'chinese' then 2
      else 3
    end,
    c.card_id
  limit 128
`;

function createHandler(deps = {}) {
  const loadPrintings = deps.readVersionPrintings || (async (cardId) => {
    const result = await marketplaceQuery(PRINTING_SQL, [cardId]);
    return result.rows;
  });
  const overlayCheapest = deps.overlayCheapestOnRows || sql.overlayCheapestOnRows;

  return async function handler(req, res) {
    setCorsHeaders(res);
    if (req.method === 'OPTIONS') {
      return res.status(204).end();
    }
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      return res.status(405).json({ error: 'GET only.' });
    }
    const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
    const cardId = parsePublicCardId(url.searchParams.get('cardId'));
    if (!cardId) {
      return res.status(400).json({ error: 'cardId is required (public marketplace id).' });
    }
    try {
      const rows = await overlayCheapest(await loadPrintings(cardId));
      if (!rows.length) {
        return res.status(404).json({ error: 'Card not found.', cardId });
      }
      const printings = rows.map((row) => {
        const card = toReactCard(row);
        card.nationality = String(row.nationality || '').trim().toLowerCase();
        card.version = String(row.version || '');
        return card;
      });
      const versionCount = Number(rows[0].member_count) || printings.length;
      return jsonOk(res, {
        cardId,
        version: String(rows[0].version || ''),
        versionCount,
        printings,
      }, 'public, max-age=30, s-maxage=60, stale-while-revalidate=300');
    } catch (error) {
      console.error('marketplace-version-set failed', error);
      return res.status(500).json({ error: error.message || 'Version set failed.' });
    }
  };
}

module.exports = createHandler();
module.exports.createHandler = createHandler;
module.exports.PRINTING_SQL = PRINTING_SQL;
