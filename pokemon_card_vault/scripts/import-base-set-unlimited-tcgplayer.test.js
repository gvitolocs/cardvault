'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {
  LISTED_BASE_SET_EXPANSION_ID,
  SHADOWLESS_EXPANSION_ID,
  isListedBaseSetSingle,
  firstTcgplayerId,
  tcgplayerUnlimitedUrl,
  leftoverJpegKey,
  catalogJpegFromTcgplayerPhoto,
  CATALOG_WIDTH,
  CATALOG_HEIGHT,
  homepageKeyFor,
  ctIdAliasKey,
  previewKeyFor,
  withCacheBust,
  parseArgs,
  assertSanitizeAllowed,
} = require('./import-base-set-unlimited-tcgplayer');
const { pokemontcgSetIdForExpansion } = require('./lib/pokemontcg-hires');

test('listed Base Set singles match n/102 versions only', () => {
  assert.equal(
    isListedBaseSetSingle({
      expansion_id: LISTED_BASE_SET_EXPANSION_ID,
      version: 'Holo Rare | 4/102',
    }),
    true,
  );
  assert.equal(
    isListedBaseSetSingle({ expansion_id: LISTED_BASE_SET_EXPANSION_ID, version: '58/102' }),
    true,
  );
  assert.equal(
    isListedBaseSetSingle({ expansion_id: LISTED_BASE_SET_EXPANSION_ID, version: '' }),
    false,
  );
  assert.equal(
    isListedBaseSetSingle({
      expansion_id: SHADOWLESS_EXPANSION_ID,
      version: 'Shadowless | Holo Rare 4/102',
    }),
    false,
  );
});

test('TCGPlayer unlimited URL uses the stored product id', () => {
  assert.equal(firstTcgplayerId([42382]), 42382);
  assert.equal(firstTcgplayerId({ ids: [42402] }), 42402);
  assert.equal(firstTcgplayerId([]), null);
  assert.equal(
    tcgplayerUnlimitedUrl(42382, 2000),
    'https://product-images.tcgplayer.com/fit-in/2000x2000/42382.jpg',
  );
});

test('leftover keys stay on the live object name, including remapped 555xx prefixes', () => {
  assert.equal(
    leftoverJpegKey({
      cdn_object_key: '55595_abra-43-102-base-set.jpg',
      cdn_image_url: 'https://cdn.pokoin.com/111190_abra.jpg',
    }),
    '55595_abra-43-102-base-set.jpg',
  );
  assert.equal(
    homepageKeyFor('111151_charizard-holo-rare-4-102-base-set.jpg'),
    '111151_charizard-holo-rare-4-102-base-set_homepage.webp',
  );
  assert.equal(
    ctIdAliasKey(111190, '55595_abra-43-102-base-set.jpg'),
    '111190_abra-43-102-base-set.jpg',
  );
  assert.equal(ctIdAliasKey(111151, '111151_charizard-holo-rare-4-102-base-set.jpg'), '');
  assert.equal(
    previewKeyFor('111151_charizard-holo-rare-4-102-base-set.jpg', 'previews/111151_charizard.jpg'),
    'previews/111151_charizard.jpg',
  );
  assert.equal(
    withCacheBust('https://cdn.pokoin.com/111151_charizard-holo-rare-4-102-base-set.jpg?v=old', 'bsu1'),
    'https://cdn.pokoin.com/111151_charizard-holo-rare-4-102-base-set.jpg?v=bsu1',
  );
});

test('CLI refuses to default at Shadowless and keeps cache-bust bsu1', () => {
  const options = parseArgs(['--apply', '--ids=111151']);
  assert.equal(options.expansionId, LISTED_BASE_SET_EXPANSION_ID);
  assert.equal(options.cacheBust, 'bsu1');
  assert.equal(options.sanitize, false);
  assert.deepEqual(options.ids, [111151]);
  assert.equal(pokemontcgSetIdForExpansion('Base Set'), null);
  assert.equal(pokemontcgSetIdForExpansion('Base Set Shadowless'), null);
  assert.equal(pokemontcgSetIdForExpansion('Base Set 2'), 'base4');
  assert.equal(parseArgs(['--sanitize']).sanitize, true);
  assert.throws(
    () => assertSanitizeAllowed(parseArgs(['--sanitize'])),
    /test with --ids/,
  );
  assert.doesNotThrow(() => assertSanitizeAllowed(parseArgs(['--sanitize', '--ids=111151'])));
});

test('TCGPlayer leftover is cover-fit to 63:88 without stretching', async () => {
  const sharp = require('sharp');
  const raw = await sharp({
    create: { width: 1422, height: 2000, channels: 3, background: { r: 40, g: 80, b: 40 } },
  }).jpeg().toBuffer();
  const encoded = await catalogJpegFromTcgplayerPhoto(raw);
  assert.equal(encoded.width, CATALOG_WIDTH);
  assert.equal(encoded.height, CATALOG_HEIGHT);
  assert.equal(Math.abs(encoded.width / encoded.height - 63 / 88) < 0.002, true);
  const meta = await sharp(encoded.body).metadata();
  assert.equal(meta.width, CATALOG_WIDTH);
  assert.equal(meta.height, CATALOG_HEIGHT);
});
