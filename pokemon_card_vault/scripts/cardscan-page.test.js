const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.join(__dirname, '..');

test('cardscan page posts same-origin and has no Oracle footer', () => {
  const html = fs.readFileSync(
    path.join(root, 'web', 'cardscan.html'),
    'utf8',
  );
  assert.match(html, /return "\/cardscan\/identify"/);
  assert.doesNotMatch(html, /Always Free Oracle/);
  assert.doesNotMatch(html, /<footer>/);
  assert.match(html, /startCam\(\);\s*<\/script>/);
  assert.match(html, /scheduleLive/);
  assert.match(html, /data\.immediate/);
  assert.match(html, /63 \/ 88/);
  assert.doesNotMatch(html, /Live scan every 280/);
  assert.doesNotMatch(html, /YOLO detect \+ Milo 128-d/);
  assert.doesNotMatch(html, /Library never opens/);
  assert.doesNotMatch(html, /Camera stays off/);
  assert.doesNotMatch(html, /Camera closes after/);
  assert.doesNotMatch(html, /marketplace\?q=/);
  assert.match(html, /marketplace-autocomplete/);
  assert.match(html, /doubledPublicFromCtId/);
  assert.match(html, /tcgplayer\.com\/product\//);
});

test('vercel.json proxies identify before the html rewrite', () => {
  const cfg = JSON.parse(
    fs.readFileSync(path.join(root, 'vercel.json'), 'utf8'),
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
