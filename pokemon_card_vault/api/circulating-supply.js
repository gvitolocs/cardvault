module.exports = async function handler(req, res) {
  res.setHeader('Content-Type', 'text/plain; charset=utf-8');
  res.setHeader('Cache-Control', 's-maxage=60, stale-while-revalidate=300');
  try {
    const response = await fetch('https://rpc.pokoin.com/chain/supply/circulating.txt');
    const text = (await response.text()).trim();
    if (response.ok && /^\d+$/.test(text)) {
      return res.status(200).send(text);
    }
  } catch (error) {
    console.error('circulating-supply proxy failed', error);
  }
  return res.status(200).send('2000000');
};
