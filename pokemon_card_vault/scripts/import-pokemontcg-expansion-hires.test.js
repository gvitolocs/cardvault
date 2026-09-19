'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const {
  isJapaneseExpansion,
  isPreviewUrl,
  preferCatalogImageUrl,
  leftoverKeyFromImageUrl,
  catalogObjectKey,
  previewObjectKey,
  loadDownloadExpansions,
  marketplaceDatabaseUrl,
  shouldReplaceCatalog,
} = require('./import-pokemontcg-expansion-hires');

test('JP expansion names are not imported from English pokemontcg scans', () => {
  assert.equal(isJapaneseExpansion('Forbidden Light JP'), true);
  assert.equal(isJapaneseExpansion('Mega Evolution'), false);
});

test('collector number filter matches 84 and 084', () => {
  const { collectorNumberMatches } = require('./import-pokemontcg-expansion-hires');
  assert.equal(collectorNumberMatches({ number: '84' }, { number: '084/094' }, '84'), true);
  assert.equal(collectorNumberMatches({ number: '84' }, {}, '084'), true);
  assert.equal(collectorNumberMatches({ number: '115' }, {}, '84'), false);
  assert.equal(collectorNumberMatches({ number: '84' }, {}, ''), true);
});

test('preview URLs are not treated as catalog heroes', () => {
  assert.equal(isPreviewUrl('https://cardtrader.com/uploads/blueprints/image/1/preview_victini.jpg'), true);
  assert.equal(isPreviewUrl('https://cdn.pokoin.com/previews/342603_victini.jpg'), true);
  assert.equal(isPreviewUrl('https://cdn.pokoin.com/342603_victini.jpg'), false);
});

test('prefer CDN full JPEG over CardTrader preview', () => {
  assert.equal(
    preferCatalogImageUrl({
      heroImageUrl: 'https://cardtrader.com/uploads/blueprints/image/342603/preview_victini.jpg',
      gridImageUrl: 'https://cdn.pokoin.com/685206_victini.jpg',
    }),
    'https://cdn.pokoin.com/685206_victini.jpg',
  );
});

test('leftover R2 keys stay on ct_id even when the live URL uses our id', () => {
  assert.equal(
    leftoverKeyFromImageUrl('https://cdn.pokoin.com/685206_victini-secret-rare.jpg', '342603'),
    '342603_victini-secret-rare.jpg',
  );
  assert.equal(
    leftoverKeyFromImageUrl('https://cdn.pokoin.com/342603_victini-secret-rare.jpg', '342603'),
    '342603_victini-secret-rare.jpg',
  );
  assert.equal(
    leftoverKeyFromImageUrl('https://cdn.pokoin.com/129834_gengar-mimikyu-gx.jpg', '129834'),
    '129834_gengar-mimikyu-gx.jpg',
  );
  assert.equal(
    leftoverKeyFromImageUrl('https://cdn.pokoin.com/259668_gengar-mimikyu-gx.jpg', '129834'),
    '129834_gengar-mimikyu-gx.jpg',
  );
  assert.equal(
    leftoverKeyFromImageUrl('https://cdn.pokoin.com/30091_wishiwashi-gx-full-v4.jpg', '120364'),
    '30091_wishiwashi-gx-full-v4.jpg',
  );
  assert.equal(
    leftoverKeyFromImageUrl('https://cardtrader.com/uploads/blueprints/image/342603/preview_victini.jpg', '342603'),
    null,
  );
});

test('new catalog objects use leftover ct_id_slug.jpg', () => {
  const card = {
    ct_id: 342603,
    name: 'Victini',
    heroImageUrl: 'https://cardtrader.com/uploads/blueprints/image/342603/preview_victini.jpg',
  };
  assert.equal(catalogObjectKey(card), '342603_victini.jpg');
  assert.equal(previewObjectKey(card), 'previews/342603_victini.jpg');
});

test('SSH tunnel override rewrites only host and port', () => {
  const url = marketplaceDatabaseUrl({
    MARKETPLACE_DATABASE_URL: 'postgresql://u:p@92.5.23.133:5432/pokoin_marketplace',
    MARKETPLACE_DB_HOST_OVERRIDE: '127.0.0.1',
    MARKETPLACE_DB_PORT_OVERRIDE: '15432',
  });
  assert.equal(url, 'postgresql://u:p@127.0.0.1:15432/pokoin_marketplace');
});

test('download list skips JP rows from the sample report', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'pokemontcg-report-'));
  const file = path.join(dir, 'report.json');
  fs.writeFileSync(
    file,
    JSON.stringify({
      rows: [
        { action: 'download', expansion: 'Black Bolt', setId: 'zsv10pt5', slug: 'black-bolt' },
        { action: 'download', expansion: 'Forbidden Light JP', setId: 'sm6', slug: 'forbidden-light-jp' },
        { action: 'keep', expansion: 'Fossil', setId: 'base3', slug: 'fossil' },
      ],
    }),
  );
  const listed = loadDownloadExpansions(file);
  assert.deepEqual(
    listed.map((row) => row.name),
    ['Black Bolt'],
  );
});

test('force re-encodes same-size CDN JPEGs but still skips a sharper catalog', () => {
  const api = { width: 733, height: 1024 };
  assert.equal(shouldReplaceCatalog(api, { width: 660, height: 920 }), true);
  assert.equal(shouldReplaceCatalog(api, { width: 733, height: 1024 }), false);
  assert.equal(shouldReplaceCatalog(api, { width: 733, height: 1024 }, { force: true }), true);
  assert.equal(shouldReplaceCatalog(api, { width: 800, height: 1114 }, { force: true }), false);
  assert.equal(shouldReplaceCatalog(api, { width: 120, height: 168, preview: true }, { force: true }), true);
  const pop = { width: 600, height: 825 };
  assert.equal(shouldReplaceCatalog(pop, { width: 622, height: 847 }), false);
  assert.equal(shouldReplaceCatalog(pop, { width: 622, height: 847 }, { force: true }), true);
});

test('expansion jpeg import sanitizes using the leftover key as filename', () => {
  const script = fs.readFileSync(path.join(__dirname, 'import-pokemontcg-expansion-hires.js'), 'utf8');
  assert.match(script, /sanitizeCardImage/);
  assert.match(script, /filename: catalogObjectKey\(job\.card\)/);
  assert.match(script, /--force/);
});
