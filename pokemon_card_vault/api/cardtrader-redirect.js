'use strict';

const { catalogIdsForAnyGame, cleanMarketplaceId } = require('./_marketplace_leftover');
const { parseGameFromRequest, runWithGame } = require('./_marketplace_game');

function cardtraderUrl(ctId) {
  return `https://www.cardtrader.com/en/cards/${ctId}`;
}

function sendRedirect(res, ctId, wantsJson) {
  const url = cardtraderUrl(ctId);
  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('X-Robots-Tag', 'noindex, nofollow');
  if (wantsJson) {
    return res.status(200).json({ url, ct_id: ctId });
  }
  res.setHeader('Location', url);
  return res.status(302).end();
}

function createHandler(deps = {}) {
  const lookup = deps.catalogIdsFor || catalogIdsForAnyGame;

  return async function handler(req, res) {
    if (req.method !== 'GET') {
      res.setHeader('Allow', 'GET');
      return res.status(405).json({ error: 'Method not allowed.' });
    }

    const game = parseGameFromRequest(req);
    return runWithGame(game, async () => {
      const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
      const id = cleanMarketplaceId(
        url.searchParams.get('id') || url.searchParams.get('cardId'),
      );
      const hinted = cleanMarketplaceId(
        url.searchParams.get('blueprintId') ||
          url.searchParams.get('ct_id') ||
          url.searchParams.get('ctId'),
      );
      if (!id && !hinted) {
        return res.status(400).json({ error: 'Missing or invalid CardTrader id.' });
      }

      const wantsJson = url.searchParams.get('format') === 'json';
      // Explicit leftover from the SPA (never a public id — those go in `id`).
      if (hinted && hinted !== id) {
        return sendRedirect(res, hinted, wantsJson);
      }

      try {
        const hit = await lookup(id || hinted);
        if (hit?.ctId) {
          return sendRedirect(res, hit.ctId, wantsJson);
        }
      } catch (error) {
        console.error('cardtrader-redirect lookup failed', error);
        return res.status(error.statusCode || 500).json({
          error: error.message || 'CardTrader redirect failed.',
        });
      }

      return res.status(404).json({
        error: 'CardTrader leftover id not found.',
        id: id || hinted,
      });
    });
  };
}

module.exports = createHandler();
module.exports.createHandler = createHandler;
module.exports.cleanBlueprintId = cleanMarketplaceId;
module.exports.cardtraderUrl = cardtraderUrl;
