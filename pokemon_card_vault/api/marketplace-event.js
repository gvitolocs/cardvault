const { marketplaceQuery } = require('./_marketplace_db');

const WEIGHTS = {
  view: 1,
  search: 2,
  click: 4,
  reserve: 10,
  cart_add: 8,
  sale: 20,
};

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  const cardId = Number(req.body?.cardId);
  const eventType = String(req.body?.eventType || '').trim();
  if (!Number.isSafeInteger(cardId) || cardId <= 0 || !WEIGHTS[eventType]) {
    return res.status(400).json({ error: 'Invalid marketplace event.' });
  }

  try {
    await marketplaceQuery(
      `
        insert into public.marketplace_card_events (card_id, event_type, weight, metadata)
        values ($1, $2, $3, $4::jsonb)
      `,
      [
        cardId,
        eventType,
        WEIGHTS[eventType],
        JSON.stringify({
          source: String(req.body?.source || 'web').slice(0, 40),
        }),
      ],
    );

    return res.status(204).end();
  } catch (error) {
    console.warn('marketplace-event failed', error);
    return res.status(204).end();
  }
};
