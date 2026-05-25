const assert = require('node:assert/strict');
const test = require('node:test');

const {
  canonicalPathForCard,
  canonicalSlugForCard,
  htmlForCard,
  parseCardRoute,
  preferredCardImage,
  publicCardImageUrl,
} = require('./marketplace-card-seo');

test('marketplace SEO route decodes public number card paths', () => {
  const url = new URL(
    'https://pokoin.com/api/marketplace-card-seo?language=en&cardPath=779904/card-fennekin-011-086-chaos-rising',
  );

  assert.deepEqual(parseCardRoute(url), {
    cardId: '389952',
    cardSlug: 'card-fennekin-011-086-chaos-rising',
    decodedFromDoubledId: true,
  });
});

test('marketplace SEO cardPath wins over Vercel injected route params', () => {
  const url = new URL(
    'https://pokoin.com/api/marketplace-card-seo?language=en&cardId=248768&cardSlug=card-drifloon-lv-17-non-holo-promo-6-17-pop-series-6&cardPath=248768/card-drifloon-lv-17-non-holo-promo-6-17-pop-series-6',
  );

  assert.deepEqual(parseCardRoute(url), {
    cardId: '124384',
    cardSlug: 'card-drifloon-lv-17-non-holo-promo-6-17-pop-series-6',
    decodedFromDoubledId: true,
  });
});

test('marketplace SEO route accepts root card URL query params', () => {
  const url = new URL(
    'https://pokoin.com/api/marketplace-card-seo?cardId=274402&cardSlug=shiny-ultra-rare-mew-ex-shiny-ultra-rare-216-091-paldean-fates',
  );

  assert.deepEqual(parseCardRoute(url), {
    cardId: '274402',
    cardSlug: 'shiny-ultra-rare-mew-ex-shiny-ultra-rare-216-091-paldean-fates',
  });
});

test('marketplace SEO route parses rewritten root card URL path', () => {
  const url = new URL(
    'https://pokoin.com/139056/common-super-rod-gold-silver-to-a-new-world',
  );

  assert.deepEqual(parseCardRoute(url), {
    cardId: '139056',
    cardSlug: 'common-super-rod-gold-silver-to-a-new-world',
  });
});

test('marketplace SEO route parses legacy root card URL sample', () => {
  const url = new URL(
    'https://pokoin.com/124384/uncommon-drifloon-lv-17-non-holo-promo-6-17-pop-series-6',
  );

  assert.deepEqual(parseCardRoute(url), {
    cardId: '124384',
    cardSlug: 'uncommon-drifloon-lv-17-non-holo-promo-6-17-pop-series-6',
  });
});

test('marketplace SEO canonical path uses public-number marketplace URL', () => {
  const row = {
    card_id: '389952',
    name: 'Fennekin',
    expansion_number: '011/086',
    expansion_name: 'Chaos Rising',
    rarity: 'Card',
  };

  assert.equal(
    canonicalSlugForCard(row),
    'card-fennekin-011-086-chaos-rising',
  );
  assert.equal(
    canonicalPathForCard(row),
    '/marketplace/en/cards/779904/card-fennekin-011-086-chaos-rising',
  );
});

test('marketplace SEO canonical path does not invent collector number from id', () => {
  const row = {
    card_id: '139056',
    name: 'Super Rod',
    expansion_number: '',
    expansion_name: 'Gold, Silver, to a New World...',
    rarity: 'Card',
  };

  assert.equal(
    canonicalPathForCard(row),
    '/marketplace/en/cards/278112/card-super-rod-gold-silver-to-a-new-world',
  );
});

test('marketplace SEO image prefers full and homepage artwork before preview', () => {
  assert.equal(
    preferredCardImage({
      preview_image_url: 'https://cdn.pokoin.com/previews/card.webp',
      homepage_image_url: 'https://cdn.pokoin.com/card_homepage.webp',
      cdn_image_url: 'https://cdn.pokoin.com/card.jpg',
    }),
    'https://pokoin.com/card-images/card.jpg',
  );
  assert.equal(
    preferredCardImage({
      preview_image_url: 'https://cdn.pokoin.com/previews/card.webp',
      homepage_image_url: 'https://cdn.pokoin.com/card_homepage.webp',
    }),
    'https://pokoin.com/card-images/card_homepage.webp',
  );
});

test('marketplace SEO image normalizes CDN URLs to public card image route', () => {
  assert.equal(
    publicCardImageUrl('https://cdn.pokoin.com/124384_drifloon-lv-17.jpg'),
    'https://pokoin.com/card-images/124384_drifloon-lv-17.jpg',
  );
  assert.equal(
    publicCardImageUrl('https://cdn.pokoin.com/card-images/leafeon.webp'),
    'https://pokoin.com/card-images/leafeon.webp',
  );
  assert.equal(
    publicCardImageUrl('https://pokoin.com/card-images/card-images/leafeon.webp'),
    'https://pokoin.com/card-images/leafeon.webp',
  );
});

test('marketplace SEO HTML emits large image preview tags', () => {
  const html = htmlForCard(
    { headers: { host: 'pokoin.com' } },
    {
      card_id: '316600',
      name: 'Leafeon',
      expansion_number: '005/131',
      expansion_name: 'Prismatic Evolutions',
      rarity: 'Rare',
      cdn_image_url: 'https://cdn.pokoin.com/card-images/leafeon.webp',
    },
    '/marketplace/en/cards/633200/rare-leafeon-005-131-prismatic-evolutions',
  );

  assert.match(html, /<meta property="og:image" content="https:\/\/pokoin\.com\/card-images\/leafeon\.webp">/);
  assert.match(html, /<meta property="og:image:secure_url" content="https:\/\/pokoin\.com\/card-images\/leafeon\.webp">/);
  assert.match(html, /<meta property="og:image:type" content="image\/webp">/);
  assert.match(html, /<meta name="twitter:card" content="summary_large_image">/);
  assert.match(html, /<meta name="twitter:image" content="https:\/\/pokoin\.com\/card-images\/leafeon\.webp">/);
  assert.match(html, /<meta property="og:url" content="https:\/\/pokoin\.com\/marketplace\/en\/cards\/633200\/rare-leafeon-005-131-prismatic-evolutions">/);
  assert.doesNotMatch(html, /https:\/\/cdn\.pokoin\.com\/card-images\//);
});

test('marketplace SEO HTML canonicalizes legacy root previews to public-number URL', () => {
  const html = htmlForCard(
    { headers: { host: 'pokoin.com' } },
    {
      card_id: '124384',
      name: 'Drifloon Lv.17',
      expansion_number: '6/17',
      expansion_name: 'POP Series 6',
      rarity: 'Card',
      cdn_image_url: 'https://cdn.pokoin.com/124384_drifloon-lv-17.jpg',
    },
    canonicalPathForCard({
      card_id: '124384',
      name: 'Drifloon Lv.17',
      expansion_number: '6/17',
      expansion_name: 'POP Series 6',
      rarity: 'Card',
    }),
  );

  assert.match(html, /<link rel="canonical" href="https:\/\/pokoin\.com\/marketplace\/en\/cards\/248768\/card-drifloon-lv-17-6-17-pop-series-6">/);
  assert.match(html, /<meta property="og:url" content="https:\/\/pokoin\.com\/marketplace\/en\/cards\/248768\/card-drifloon-lv-17-6-17-pop-series-6">/);
  assert.doesNotMatch(html, /https:\/\/pokoin\.com\/124384\//);
});

test('marketplace SEO preview decodes public number after direct lookup misses', async () => {
  const { rowsForCardPreview } = require('./marketplace-card-seo');
  const calls = [];
  const fetchRowsForVersions = async (args) => {
    calls.push(args);
    if (args.cardId === '137799') {
      return [{
        card_id: '137799',
        name: 'Exeggutor',
        expansion_name: 'Emerald Break',
        expansion_number: '002/078',
        canonical_path:
          '/marketplace/en/cards/275598/card-exeggutor-2-078-emerald-break',
      }];
    }
    return [];
  };

  const rows = await rowsForCardPreview({
    cardId: '275598',
    cardSlug: 'card-exeggutor-2-078-emerald-break',
  }, fetchRowsForVersions);

  assert.equal(rows[0].card_id, '137799');
  assert.deepEqual(
    calls.map((call) => ({
      cardId: call.cardId,
      cardSlug: call.cardSlug,
    })),
    [
      {
        cardId: '275598',
        cardSlug: 'card-exeggutor-2-078-emerald-break',
      },
      {
        cardId: '275598',
        cardSlug: undefined,
      },
      {
        cardId: '137799',
        cardSlug: 'card-exeggutor-2-078-emerald-break',
      },
    ],
  );
});
