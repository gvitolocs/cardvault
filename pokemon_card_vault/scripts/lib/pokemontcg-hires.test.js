'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const sharp = require('sharp');

const {
  CATALOG_JPEG_QUALITY,
  pokemontcgSetIdForExpansion,
  collectorNumberFromVersion,
  hiresPngUrl,
  pngDimensionsFromPrefix,
  isBetterDefinition,
  resolvePokemontcgHires,
  absoluteCdnUrl,
  catalogJpegFromPokemontcgPng,
} = require('./pokemontcg-hires');
const { sanitizeCardImage } = require('./sanitize-card-image');

test('Wizards English expansions map to pokemontcg set ids', () => {
  assert.equal(pokemontcgSetIdForExpansion('Neo Revelation'), 'neo3');
  assert.equal(pokemontcgSetIdForExpansion('Neo Revelation EN'), 'neo3');
  assert.equal(pokemontcgSetIdForExpansion('Base Set'), null);
  assert.equal(pokemontcgSetIdForExpansion('Base'), null);
  assert.equal(pokemontcgSetIdForExpansion('Expedition Base Set'), 'ecard1');
  assert.equal(pokemontcgSetIdForExpansion('Wizards Black Star Promos'), 'basep');
  assert.equal(pokemontcgSetIdForExpansion('Base Set Shadowless'), null);
  assert.equal(pokemontcgSetIdForExpansion('Pokémon Jungle'), null);
  assert.equal(pokemontcgSetIdForExpansion('Scarlet & Violet'), null);
});

test('collector numbers come from CardTrader version strings', () => {
  assert.equal(collectorNumberFromVersion('Shiny Rare | 65/64'), '65');
  assert.equal(collectorNumberFromVersion('Holo Rare | 1/64'), '1');
  assert.equal(collectorNumberFromVersion('H32/147'), 'H32');
  assert.equal(collectorNumberFromVersion('005 | English is Gold-Stamped | EU No Stamp'), '5');
  assert.equal(collectorNumberFromVersion('12'), '12');
  assert.equal(collectorNumberFromVersion('Neo Revelation Booster'), null);
});

test('resolvePokemontcgHires maps a marketplace card to the hires PNG', () => {
  const gyarados = resolvePokemontcgHires({
    set: 'Neo Revelation',
    number: '65/64',
    gridImageUrl: '/card-images/247524_shining-gyarados-65-64-neo-revelation.jpg',
  });
  assert.equal(gyarados.setId, 'neo3');
  assert.equal(gyarados.number, '65');
  assert.equal(gyarados.url, 'https://images.pokemontcg.io/neo3/65_hires.png');
  assert.equal(
    absoluteCdnUrl('/card-images/247524_shining-gyarados.jpg'),
    'https://cdn.pokoin.com/247524_shining-gyarados.jpg',
  );
});

test('PNG IHDR prefix yields width and height', async () => {
  const png = await sharp({
    create: { width: 600, height: 825, channels: 3, background: { r: 1, g: 2, b: 3 } },
  })
    .png()
    .toBuffer();
  assert.deepEqual(pngDimensionsFromPrefix(png.subarray(0, 32)), { width: 600, height: 825 });
});

test('API scan wins only when it is clearly larger', () => {
  assert.equal(isBetterDefinition({ width: 600, height: 825 }, { width: 285, height: 395 }), true);
  assert.equal(isBetterDefinition({ width: 600, height: 825 }, { width: 600, height: 825 }), false);
  assert.equal(isBetterDefinition({ width: 600, height: 825 }, { width: 734, height: 1024 }), false);
  assert.equal(isBetterDefinition({ width: 600, height: 825 }, null), true);
});

test('pokemontcg PNG encodes to JPEG q100 4:4:4', async () => {
  const png = await sharp({
    create: {
      width: 120,
      height: 168,
      channels: 3,
      background: { r: 246, g: 204, b: 0 },
    },
  })
    .png()
    .toBuffer();
  const result = await catalogJpegFromPokemontcgPng(png, { sharp, sanitizeCardImage });
  assert.equal(result.format, 'jpg');
  const meta = await sharp(result.body).metadata();
  assert.equal(meta.format, 'jpeg');
  assert.equal(meta.hasAlpha, false);
  assert.equal(CATALOG_JPEG_QUALITY, 100);
  assert.equal(meta.chromaSubsampling, '4:4:4');
});
