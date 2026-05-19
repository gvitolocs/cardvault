function cleanBlueprintId(value) {
  const id = String(value || '').trim();
  return /^\d{1,12}$/.test(id) ? id : '';
}

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
  const id = cleanBlueprintId(url.searchParams.get('id'));
  if (!id) {
    return res.status(400).json({ error: 'Missing or invalid CardTrader blueprint id.' });
  }

  res.setHeader('Cache-Control', 'no-store');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('X-Robots-Tag', 'noindex, nofollow');
  res.setHeader('Location', `https://www.cardtrader.com/en/cards/${id}`);
  return res.status(302).end();
};

module.exports.cleanBlueprintId = cleanBlueprintId;
