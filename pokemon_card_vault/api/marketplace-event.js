function env(name) {
  return process.env[name] || '';
}

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

  const supabaseUrl = env('SUPABASE_URL').replace(/\/$/, '');
  const anonKey = env('SUPABASE_ANON_KEY');
  if (!supabaseUrl || !anonKey) {
    return res.status(204).end();
  }

  const cardId = Number(req.body?.cardId);
  const eventType = String(req.body?.eventType || '').trim();
  if (!Number.isSafeInteger(cardId) || cardId <= 0 || !WEIGHTS[eventType]) {
    return res.status(400).json({ error: 'Invalid marketplace event.' });
  }

  try {
    const response = await fetch(
      `${supabaseUrl}/rest/v1/marketplace_card_events`,
      {
        method: 'POST',
        headers: {
          apikey: anonKey,
          Authorization: `Bearer ${anonKey}`,
          'Content-Type': 'application/json',
          Prefer: 'return=minimal',
        },
        body: JSON.stringify({
          card_id: cardId,
          event_type: eventType,
          weight: WEIGHTS[eventType],
          metadata: {
            source: String(req.body?.source || 'web').slice(0, 40),
          },
        }),
      },
    );

    if (!response.ok) {
      const body = await response.text().catch(() => '');
      console.warn(
        `marketplace-event insert failed ${response.status}: ${body.slice(0, 200)}`,
      );
      return res.status(204).end();
    }

    return res.status(204).end();
  } catch (error) {
    console.warn('marketplace-event failed', error);
    return res.status(204).end();
  }
};
