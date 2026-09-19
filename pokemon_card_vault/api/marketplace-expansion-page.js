'use strict';

const {
  rowsForExpansions,
  snapshotForExpansion,
} = require('./marketplace-expansions');
const { rowsForVersions } = require('./marketplace-card-versions');
const {
  toReactCards,
  parseLimit,
  parseOffset,
  setCorsHeaders,
  jsonOk,
  cleanText,
} = require('./_marketplace_react_card');
const sql = require('./_marketplace_react_sql');
const {
  parseGameFromRequest,
  runWithGame,
  isPokemonGame,
} = require('./_marketplace_game');

function slugify(value) {
  return String(value || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 140);
}

function createHandler(deps = {}) {
  const loadExpansions = deps.rowsForExpansions || rowsForExpansions;
  const loadSnapshot = deps.snapshotForExpansion || snapshotForExpansion;
  const loadVersions = deps.rowsForVersions || rowsForVersions;
  const loadSetCards = deps.readSetCards;
  const readSetCardCount = deps.readSetCardCount;
  const listExpansions = deps.listExpansions || (async (opts) => {
    if (!isPokemonGame()) {
      return sql.readExpansionsFromSetCounts(opts.limit);
    }
    return loadExpansions(opts);
  });

  return async function handler(req, res) {
    setCorsHeaders(res);
    if (req.method === 'OPTIONS') {
      return res.status(204).end();
    }
    if (req.method !== 'GET') {
      res.setHeader('Allow', 'GET, OPTIONS');
      return res.status(405).json({ error: 'Method not allowed.' });
    }

    const game = parseGameFromRequest(req);
    return runWithGame(game, async () => {
    try {
      const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
      const expansionName = cleanText(
        url.searchParams.get('expansionName') ||
          url.searchParams.get('set') ||
          url.searchParams.get('setName'),
        180,
      );
      const slug = cleanText(
        url.searchParams.get('slug') || (expansionName ? slugify(expansionName) : ''),
        180,
      );
      const productType = cleanText(url.searchParams.get('productType'), 60) || 'card';
      const limit = parseLimit(url.searchParams.get('limit'), 200, 400);
      const offset = parseOffset(url.searchParams.get('offset'));

      if (!slug && !expansionName) {
        const expansions = await listExpansions({
          limit: parseLimit(url.searchParams.get('limit'), 500, 2000),
        });
        return jsonOk(res, {
          expansions,
          expansion: null,
          cards: [],
          game,
          limit,
          offset: 0,
          hasMore: false,
        }, 'public, max-age=60, s-maxage=300');
      }

      let expansion = null;
      if (slug && !deps.rowsForExpansions) {
        try {
          expansion = await sql.readExpansionBySlug(slug);
        } catch (_) {
          expansion = null;
        }
      }
      if (!expansion) {
        const listed = await loadExpansions({ slug, limit: 1 });
        expansion = listed[0] || null;
      }
      if (!expansion && expansionName) {
        expansion = {
          name: expansionName,
          slug,
          symbolImageUrl: '',
          logoImageUrl: '',
          defaultSymbolUrl: slug
            ? `https://cdn.pokoin.com/expansions/symbols/${slug}.png`
            : '',
          cardCount: 0,
          nationality: '',
        };
      }
      if (!expansion) {
        return res.status(404).json({ error: 'Expansion not found.', slug, expansionName });
      }

      let rows;
      if (productType === 'card' && loadSetCards) {
        rows = await loadSetCards({
          setName: expansion.name,
          limit: limit + 1,
          offset,
        });
      } else if (productType === 'card' && offset === 0 && typeof loadSnapshot === 'function' && !url.searchParams.get('expansionName')) {
        const snapshot = await loadSnapshot({
          slug: expansion.slug || slug,
          limit: limit + 1,
        });
        rows = snapshot && Array.isArray(snapshot.cards) ? snapshot.cards : [];
        if (snapshot && snapshot.expansion) {
          expansion = snapshot.expansion;
        }
      } else {
        rows = await loadVersions({
          expansionName: expansion.name,
          productType,
          limit: offset + limit + 1,
        });
      }
      const fetched = Array.isArray(rows) ? rows : [];
      const fromSetSql = Boolean(productType === 'card' && loadSetCards);
      const page = fromSetSql ? fetched.slice(0, limit) : fetched.slice(offset, offset + limit);
      const print = String(expansion.nationality || '').trim();
      const cards = toReactCards(page).map((card) => (
        card.nationality || !print ? card : { ...card, nationality: print }
      ));
      let total = Number(expansion.cardCount) || 0;
      if (typeof readSetCardCount === 'function' && expansion.name) {
        try {
          const stored = await readSetCardCount(expansion.name);
          if (Number.isFinite(stored) && stored >= 0) {
            total = stored;
          }
        } catch (_) {
          /* keep expansion.cardCount */
        }
      }
      expansion = { ...expansion, cardCount: total };

      return jsonOk(res, {
        expansion,
        cards,
        productType,
        limit,
        offset,
        count: cards.length,
        total,
        hasMore: fromSetSql ? fetched.length > limit : fetched.length > offset + limit,
      }, 'public, max-age=30, s-maxage=120, stale-while-revalidate=300');
    } catch (error) {
      console.error('marketplace-expansion-page failed', error);
      return res.status(error.statusCode || 500).json({
        error: error.message || 'Marketplace expansion page failed.',
      });
    }
    });
  };
}

module.exports = createHandler({
  readSetCardCount: sql.readStoredCatalogCardCount,
  readSetCards: async ({ setName, limit, offset }) => {
    const rows = await sql.readCardsForSet(setName, limit, offset);
    const ids = rows.map((row) => row.card_id);
    const blueprintIds = rows
      .map((row) => Number(row.ct_id))
      .filter((id) => Number.isSafeInteger(id) && id > 0);
    const [paths, cheapest] = await Promise.all([
      sql.readCanonicalPaths(ids),
      sql.readCheapestMap(ids, blueprintIds),
    ]);
    return sql.applyCanonicalAndCheapest(rows, paths, cheapest);
  },
});
module.exports.createHandler = createHandler;
module.exports.slugify = slugify;
module.exports._test = { createHandler, slugify };
