const assert = require('node:assert/strict');
const test = require('node:test');
const {
  leftoverCdnObjectKey,
  jpegFallbackKey,
  jpegCatalogKey,
  rasterFallbackKeys,
} = require('./cdn-object-key');

test('maps public image prefixes to leftover ct_id object keys', () => {
  assert.equal(
    leftoverCdnObjectKey('598052_dachsbun-ex-full-art-160-142-stellar-crown.jpg'),
    '299026_dachsbun-ex-full-art-160-142-stellar-crown.jpg',
  );
  assert.equal(
    leftoverCdnObjectKey('previews/220962_espurr-58-122-breakpoint.jpg'),
    'previews/110481_espurr-58-122-breakpoint.jpg',
  );
  assert.equal(
    leftoverCdnObjectKey('703382_mega-lucario-ex_homepage.webp'),
    '351691_mega-lucario-ex_homepage.webp',
  );
});

test('does not invent a leftover key for odd prefixes or non-card paths', () => {
  assert.equal(leftoverCdnObjectKey('110481_espurr.jpg'), null);
  assert.equal(leftoverCdnObjectKey('expansions/symbols/mega-evolution.png'), null);
  assert.equal(leftoverCdnObjectKey('artist-profiles/akagi.png'), null);
  assert.equal(leftoverCdnObjectKey(''), null);
});

test('jpegFallbackKey maps retired PNG URLs to sibling JPEG', () => {
  assert.equal(jpegFallbackKey('105054_65-poke-doll-mythical-mania-sleeves.png'), '105054_65-poke-doll-mythical-mania-sleeves.jpg');
  assert.equal(
    jpegFallbackKey('expansions/symbols/mega-evolution.png'),
    'expansions/symbols/mega-evolution.jpg',
  );
  assert.equal(jpegFallbackKey('344538_tangela.jpg'), null);
});

test('jpegCatalogKey maps catalog png/webp URLs to JPEG and leaves derivatives', () => {
  assert.equal(jpegCatalogKey('349106_mega-gardevoir-ex.webp'), '349106_mega-gardevoir-ex.jpg');
  assert.equal(jpegCatalogKey('349106_mega-gardevoir-ex.png'), '349106_mega-gardevoir-ex.jpg');
  assert.equal(jpegCatalogKey('349106_mega-gardevoir-ex.jpg'), '349106_mega-gardevoir-ex.jpg');
  assert.equal(
    jpegCatalogKey('expansions/symbols/prismatic-evolutions.png'),
    'expansions/symbols/prismatic-evolutions.jpg',
  );
  assert.equal(
    jpegCatalogKey('previews/351691_mega-lucario-ex.webp'),
    'previews/351691_mega-lucario-ex.webp',
  );
  assert.equal(
    jpegCatalogKey('703382_mega-lucario-ex_homepage.webp'),
    '703382_mega-lucario-ex_homepage.webp',
  );
  assert.equal(
    jpegCatalogKey('competitive/scans/TWM_130_R_EN.png'),
    'competitive/scans/TWM_130_R_EN.png',
  );
  assert.equal(
    jpegCatalogKey('competitive/sprites/dragapult.png'),
    'competitive/sprites/dragapult.png',
  );
});

test('rasterFallbackKeys tries jpeg and webp when a PNG was deleted', () => {
  assert.deepEqual(rasterFallbackKeys('349106_mega-gardevoir-ex.png'), [
    '349106_mega-gardevoir-ex.jpg',
    '349106_mega-gardevoir-ex.jpeg',
    '349106_mega-gardevoir-ex.webp',
  ]);
  assert.deepEqual(rasterFallbackKeys('327135_cynthia-s-garchomp-ex.jpg'), [
    '327135_cynthia-s-garchomp-ex.jpeg',
    '327135_cynthia-s-garchomp-ex.png',
    '327135_cynthia-s-garchomp-ex.webp',
  ]);
  assert.deepEqual(rasterFallbackKeys('expansions/symbols/mega-evolution.png'), [
    'expansions/symbols/mega-evolution.jpg',
    'expansions/symbols/mega-evolution.jpeg',
    'expansions/symbols/mega-evolution.webp',
  ]);
  assert.deepEqual(rasterFallbackKeys(''), []);
});

test('overlap: Drifloon public 248768 halves; Nacli leftover key is even but Worker tries as-is first', () => {
  assert.equal(
    leftoverCdnObjectKey('248768_drifloon.jpg'),
    '124384_drifloon.jpg',
  );
  assert.equal(
    leftoverCdnObjectKey('497536_nacli.jpg'),
    '248768_nacli.jpg',
  );
});
