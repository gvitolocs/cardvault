const assert = require('node:assert/strict');
const test = require('node:test');

const {
  calculateTopCenterSquareCrop,
  cardImageFetchUrl,
  classifyCardArt,
  parseArgs,
  sourceFullImageUrl,
} = require('./generate-artist-fallback-avatars');

test('fallback avatar generator is dry-run by default', () => {
  const options = parseArgs([]);

  assert.equal(options.apply, false);
  assert.equal(options.limit, 100);
  assert.equal(options.avatarSize, 512);
  assert.equal(options.cropYRatio, 0.1);
  assert.equal(options.includeMissing, true);
  assert.equal(options.includePlaceholders, true);
});

test('fallback avatar generator parses target filters', () => {
  const options = parseArgs([
    '--apply',
    '--limit=all',
    '--artist=Aky CG Works, No Image Artist',
    '--placeholders-only',
    '--avatar-size=768',
    '--crop-y-ratio=0.15',
  ]);

  assert.equal(options.apply, true);
  assert.equal(options.limit, Infinity);
  assert.deepEqual(options.artistKeys, ['aky cg works', 'no image artist']);
  assert.equal(options.includeMissing, false);
  assert.equal(options.includePlaceholders, true);
  assert.equal(options.avatarSize, 768);
  assert.equal(options.cropYRatio, 0.15);
});

test('card art classification prioritizes illustration before full and normal art', () => {
  assert.deepEqual(
    classifyCardArt({
      rarity: 'Special Illustration Rare',
      expansion_number: '232/091',
      product_variant: '',
      name: 'Mew ex',
    }),
    { category: 'illustration', priority: 0 },
  );
  assert.deepEqual(
    classifyCardArt({
      rarity: 'Ultra Rare',
      expansion_number: 'Full Art | 151/149',
      product_variant: '',
      name: 'Mewtwo EX',
    }),
    { category: 'full_art', priority: 1 },
  );
  assert.deepEqual(
    classifyCardArt({
      rarity: 'Rare',
      expansion_number: '15/102',
      product_variant: '',
      name: 'Venusaur',
    }),
    { category: 'normal_art', priority: 2 },
  );
});

test('top-center square crop avoids the middle of a portrait card', () => {
  const crop = calculateTopCenterSquareCrop({
    width: 734,
    height: 1024,
    yRatio: 0.1,
  });

  assert.deepEqual(crop, {
    left: 0,
    top: 102,
    width: 734,
    height: 734,
  });
});

test('top-center crop is centered for landscape images and clamped', () => {
  const crop = calculateTopCenterSquareCrop({
    width: 1200,
    height: 800,
    yRatio: 0.5,
  });

  assert.deepEqual(crop, {
    left: 200,
    top: 0,
    width: 800,
    height: 800,
  });
});

test('source image helpers prefer full-size same-origin card images', () => {
  assert.equal(
    sourceFullImageUrl({
      cdn_image_url: 'https://cdn.pokoin.com/cards/full.webp',
      image_url: 'https://cardtrader.test/full.jpg',
      preview_image_url: 'https://cdn.pokoin.com/previews/tiny.webp',
    }),
    'https://cdn.pokoin.com/cards/full.webp',
  );
  assert.equal(
    cardImageFetchUrl('https://cdn.pokoin.com/cards/full.webp'),
    'https://pokoin.com/card-images/cards/full.webp',
  );
});
