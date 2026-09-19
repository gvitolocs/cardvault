const assert = require('node:assert/strict');
const test = require('node:test');
const {
  isHomepageWebp,
  isPreviewPath,
  parseIdList,
  parsePublicCardId,
  reactImageUrls,
  toReactCard,
} = require('./_marketplace_react_card');

test('React grid/hero never use /previews/ when a full jpg exists', () => {
  const images = reactImageUrls({
    card_id: 703382,
    ct_id: 351691,
    image_url: 'https://cdn.pokoin.com/351691_mega-lucario-ex.jpg',
    preview_image_url: 'https://cdn.pokoin.com/previews/351691_mega-lucario-ex.jpg',
    homepage_image_url: 'https://cdn.pokoin.com/previews/351691_mega-lucario-ex.jpg',
  });
  assert.equal(images.imageUrl, '/card-images/703382_mega-lucario-ex.jpg');
  assert.equal(images.gridImageUrl, '/card-images/703382_mega-lucario-ex.jpg');
  assert.equal(images.heroImageUrl, '/card-images/703382_mega-lucario-ex.jpg');
  assert.equal(images.tileImageUrl, '/card-images/703382_mega-lucario-ex.jpg');
  assert.equal(
    images.previewImageUrl,
    '/card-images/previews/703382_mega-lucario-ex.jpg',
  );
  assert.equal(isPreviewPath(images.gridImageUrl), false);
});

test('React tile uses _homepage.webp when it is a real homepage asset', () => {
  const images = reactImageUrls({
    card_id: 587148,
    ct_id: 293574,
    image_url: '/card-images/293574_magcargo.jpg',
    homepage_image_url: '/card-images/293574_magcargo_homepage.webp',
  });
  assert.equal(images.tileImageUrl, '/card-images/587148_magcargo_homepage.webp');
  assert.equal(images.heroImageUrl, '/card-images/587148_magcargo.jpg');
  assert.equal(isHomepageWebp(images.tileImageUrl), true);
});

test('React tile drops homepage webp whose slug is a different card (ct_id/public-id collision)', () => {
  const images = reactImageUrls({
    card_id: 241930,
    ct_id: 120965,
    image_url: '/card-images/120965_pikachu-non-holo-trainer-kit-16-30-hs-trainer-kit-raichu.jpg',
    homepage_image_url: '/card-images/241930_kirlia-212-198-scarlet-violet_homepage.webp',
  });
  assert.equal(
    images.tileImageUrl,
    '/card-images/241930_pikachu-non-holo-trainer-kit-16-30-hs-trainer-kit-raichu.jpg',
  );
  assert.equal(images.homepageImageUrl, '');
  assert.equal(isHomepageWebp(images.tileImageUrl), false);
});

test('toReactCard exposes public id only, never ct_id', () => {
  const card = toReactCard({
    card_id: 548832,
    name: 'Mew ex',
    set_name: 'Paldean Fates',
    card_number: '232/091',
    rarity: 'Special Illustration Rare',
    art_layout: 'bleed',
    image_url: 'https://cdn.pokoin.com/548832_mew-ex.jpg',
    canonical_path:
      '/marketplace/en/cards/548832/card-mew-ex-special-illustration-rare-232-091-paldean-fates',
    listed_quantity: 0,
    has_cardtrader_listing: false,
    artist: 'USGMEN',
    emoji: '🔮 ✨ 💎',
    card_identity_emojis: ['🔮', '✨'],
    rarity_variant_emoji: '💎',
  });
  assert.equal(card.id, '548832');
  assert.equal(card.ct_id, undefined);
  assert.equal(card.imageUrl, '/card-images/548832_mew-ex.jpg');
  assert.equal(card.gridImageUrl, card.imageUrl);
  assert.equal(card.artist, 'USGMEN');
  assert.equal(card.emoji, '🔮 ✨ 💎');
  assert.equal(card.cardIdentityEmoji, '🔮 ✨');
  assert.equal(card.isMarketAvailable, false);
  assert.equal(card.availabilityKnown, true);
  assert.equal(card.itemKind, 'single');
  assert.equal(card.artLayout, 'bleed');
});

test('toReactCard leaves search-page identity rows as availability unknown', () => {
  const card = toReactCard({
    card_id: 220962,
    name: 'Espurr',
    set_name: 'XY',
    card_number: '42/146',
    image_url: 'https://cdn.pokoin.com/110481_espurr.jpg',
  });
  assert.equal(card.isMarketAvailable, false);
  assert.equal(card.availabilityKnown, false);
});

test('parseIdList keeps public ids in order and caps length', () => {
  assert.deepEqual(parseIdList('703382, 587148, 703382, nope, 1'), [
    '703382',
    '587148',
    '1',
  ]);
  assert.equal(parsePublicCardId('0'), '');
});

test('CardTrader preview_ filenames are not used as React grid art when a full image exists', () => {
  const images = reactImageUrls({
    card_id: 713740,
    ct_id: 356870,
    image_url: 'https://cardtrader.com/uploads/blueprints/image/356870/mega-lopunny-ex.jpg',
    preview_image_url:
      'https://cardtrader.com/uploads/blueprints/image/356870/preview_mega-lopunny-ex-ultra-rare-084-094-phantasmal-flames(2).jpg',
  });
  assert.equal(isPreviewPath(images.gridImageUrl), false);
  assert.match(images.gridImageUrl, /mega-lopunny-ex\.jpg$/);
});

test('parseLimit treats missing query params as the fallback', () => {
  const { parseLimit } = require('./_marketplace_react_card');
  assert.equal(parseLimit(null, 100, 100), 100);
  assert.equal(parseLimit('', 100, 100), 100);
  assert.equal(parseLimit('40', 100, 100), 40);
});
