const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.join(__dirname, '..');

test('cardscan HTML ownership stays delegated to pokoin-web', () => {
  const ignore = fs.readFileSync(path.join(root, '..', '.gitignore'), 'utf8');
  assert.match(ignore, /Public web .* HTML cardscan.* lives in pokoin-web/);
  assert.match(ignore, /^pokemon_card_vault\/web\/cardscan\.html$/m);
});

test('web vercel config proxies identify before the html rewrite', () => {
  const cfg = JSON.parse(
    fs.readFileSync(path.join(root, 'web', 'vercel.json'), 'utf8'),
  );
  const sources = cfg.rewrites.map((row) => row.source);
  const identifyAt = sources.indexOf('/cardscan/identify');
  const pageAt = sources.indexOf('/cardscan');
  assert.notEqual(identifyAt, -1);
  assert.notEqual(pageAt, -1);
  assert.ok(identifyAt < pageAt);
  assert.ok(sources.indexOf('/scancard') !== -1);
  const identify = cfg.rewrites[identifyAt];
  assert.equal(identify.destination, 'https://cardscan.pokoin.com/identify');
});
