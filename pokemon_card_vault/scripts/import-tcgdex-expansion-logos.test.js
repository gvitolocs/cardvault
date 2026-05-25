const assert = require('node:assert/strict');
const test = require('node:test');

const {
  contentTypeForExtension,
  extensionForUrl,
  logoSourceCandidates,
  parseArgs,
  slugify,
} = require('./import-tcgdex-expansion-logos');

test('tcgdex expansion logo importer is dry-run by default', () => {
  assert.equal(parseArgs([]).apply, false);
  assert.equal(parseArgs(['--apply']).apply, true);
  assert.equal(parseArgs(['--limit=all']).limit, Infinity);
  assert.equal(parseArgs(['--refresh-existing']).onlyMissing, false);
});

test('logo importer builds stable CDN slugs and source URL candidates', () => {
  assert.equal(slugify('Pokémon TCG: Scarlet & Violet 151'), 'pokemon-tcg-scarlet-and-violet-151');
  assert.deepEqual(
    logoSourceCandidates('https://assets.tcgdex.net/en/swsh/swsh3/logo'),
    [
      'https://assets.tcgdex.net/en/swsh/swsh3/logo.png',
      'https://assets.tcgdex.net/en/swsh/swsh3/logo',
    ],
  );
  assert.deepEqual(
    logoSourceCandidates('https://assets.tcgdex.net/en/swsh/swsh3/logo.webp'),
    ['https://assets.tcgdex.net/en/swsh/swsh3/logo.webp'],
  );
});

test('logo importer preserves known image extensions', () => {
  assert.equal(extensionForUrl('https://assets.tcgdex.net/en/swsh/swsh3/logo'), 'png');
  assert.equal(extensionForUrl('https://cdn.example/logo.jpeg'), 'jpg');
  assert.equal(extensionForUrl('https://cdn.example/logo.webp'), 'webp');
  assert.equal(contentTypeForExtension('jpg'), 'image/jpeg');
  assert.equal(contentTypeForExtension('webp'), 'image/webp');
  assert.equal(contentTypeForExtension('png'), 'image/png');
});
