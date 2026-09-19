'use strict';

const { parseIdList, setCorsHeaders, jsonOk } = require('./_marketplace_react_card');
const rails = require('./_marketplace_rails');

module.exports = async function handler(req, res) {
  setCorsHeaders(res);
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET, OPTIONS');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const url = new URL(req.url, `https://${req.headers.host || 'api.pokoin.com'}`);
    const ids = parseIdList(url.searchParams.get('ids'), 80);
    // Theme packs ride the tile summaries so a tile → desk navigation paints
    // themed on first paint (the desk payload later confirms the same theme).
    const cards = await rails.withThemePacks(rails.publicizeCards(await rails.readTiles(ids)));
    const byId = new Map(cards.map((card) => [rails.cardId(card), card]));
    return jsonOk(res, {
      source: 'pi',
      cards: ids.map((id) => byId.get(id)).filter(Boolean),
    }, 'public, max-age=30, s-maxage=120');
  } catch (error) {
    console.error('marketplace-card-tiles failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Marketplace card tiles failed.',
    });
  }
};
