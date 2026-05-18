function env(name) {
  return process.env[name] || '';
}

function normalizeCardImages(card) {
  return {
    ...card,
    imageUrl: normalizeImageUrl(card.imageUrl),
    previewImageUrl: normalizeImageUrl(card.previewImageUrl || card.imageUrl),
  };
}

function normalizeSections(sections = {}) {
  const recentlySeenIds = Array.isArray(sections.recentlySeenIds)
    ? sections.recentlySeenIds
    : [];
  const bestSellerIds = Array.isArray(sections.bestSellerIds)
    ? sections.bestSellerIds
    : [];
  const featuredIds = Array.isArray(sections.featuredIds)
    ? sections.featuredIds
    : [];
  return {
    recentlySeenIds,
    bestSellerIds,
    featuredIds:
      featuredIds.length > 0
        ? featuredIds
        : bestSellerIds.length > 0
          ? bestSellerIds
          : recentlySeenIds,
  };
}

function normalizeImageUrl(value) {
  const text = String(value || '').trim();
  if (!text) {
    return '';
  }
  try {
    const url = new URL(text);
    if (url.hostname !== 'cdn.pokoin.com') {
      return text;
    }
    return `/card-images${url.pathname}${url.search}`;
  } catch (_) {
    return text;
  }
}

async function fetchSnapshot() {
  const supabaseUrl = env('SUPABASE_URL').replace(/\/$/, '');
  const anonKey = env('SUPABASE_ANON_KEY');
  if (!supabaseUrl || !anonKey) {
    return { cards: [], sections: {} };
  }
  const url = new URL(`${supabaseUrl}/rest/v1/rpc/get_marketplace_home_snapshot`);

  const response = await fetch(url, {
    method: 'POST',
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${anonKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ result_limit: 120 }),
  });

  if (!response.ok) {
    const body = await response.text().catch(() => '');
    throw new Error(
      `Supabase marketplace home failed ${response.status}: ${body.slice(0, 300)}`,
    );
  }
  const snapshot = await response.json();
  return {
    ...snapshot,
    cards: Array.isArray(snapshot.cards)
      ? snapshot.cards.map(normalizeCardImages)
      : [],
    sections: normalizeSections(snapshot.sections),
  };
}

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const snapshot = await fetchSnapshot();
    res.setHeader(
      'Cache-Control',
      'public, max-age=60, s-maxage=3600, stale-while-revalidate=86400',
    );
    return res.status(200).json(snapshot);
  } catch (error) {
    console.error('marketplace-home failed', error);
    return res.status(500).json({ error: 'Marketplace home failed.' });
  }
};
