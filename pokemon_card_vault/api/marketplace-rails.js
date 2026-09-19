'use strict';

const { parseIdList, setCorsHeaders, jsonOk, cleanText } = require('./_marketplace_react_card');
const { readRails, readTiles, publicizeCards, cardId } = require('./_marketplace_rails');
const { publicErrorBody, publicErrorStatus } = require('./_public_error');

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
    if (ids.length) {
      const cards = publicizeCards(await readTiles(ids));
      const byId = new Map(cards.map((card) => [cardId(card), card]));
      return jsonOk(res, {
        source: 'pi',
        cards: ids.map((id) => byId.get(id)).filter(Boolean),
      }, 'public, max-age=30, s-maxage=120');
    }

    const id = cleanText(url.searchParams.get('id'), 180);
    if (!id) {
      return res.status(400).json({ error: 'id or ids required.' });
    }
    const rows = await readRails([id]);
    const row = rows[0];
    if (!row) {
      return res.status(404).json({ error: 'Rail not found.', id });
    }
    return jsonOk(res, {
      id: row.id,
      cards: publicizeCards(row.cards),
      meta: row.meta || {},
      updated_at: row.updated_at,
      source: 'pi',
    }, 'public, max-age=30, s-maxage=120');
  } catch (error) {
    console.error('marketplace-rails failed', error);
    return res.status(publicErrorStatus(error)).json(
      publicErrorBody(error, 'Marketplace rails failed.'),
    );
  }
};
