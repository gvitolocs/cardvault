const {
  calculateWpknPknMarketQuote,
  geckoTerminalWpknUsd,
  pknUsdPrice,
} = require('../server/_wpkn_pkn_market_quote');

module.exports = async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store, max-age=0');
  res.setHeader('Pragma', 'no-cache');

  if (req.method !== 'GET' && req.method !== 'POST') {
    res.setHeader('Allow', 'GET, POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const direction = String(req.query?.direction || body.direction || '').trim();
    const amountIn = req.query?.amountIn ?? body.amountIn;
    const quotedAt = new Date().toISOString();
    const [wpknUsd, pknUsd] = await Promise.all([
      geckoTerminalWpknUsd(),
      Promise.resolve(pknUsdPrice()),
    ]);
    const quote = await calculateWpknPknMarketQuote({
      direction,
      amountIn,
      wpknUsd,
      pknUsd,
    });

    return res.status(200).json({
      ...quote,
      source: 'wpkn_market',
      assetIn: quote.fromAsset,
      assetOut: quote.toAsset,
      quotedAt,
      priceFetchedAt: quotedAt,
    });
  } catch (error) {
    console.error('wpkn-pkn-quote failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'wPKN market quote failed.',
    });
  }
};
