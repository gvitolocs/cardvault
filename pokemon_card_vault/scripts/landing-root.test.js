const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.join(__dirname, '..');

test('root rewrite serves static home.html before the Flutter catchall', () => {
  const cfg = JSON.parse(
    fs.readFileSync(path.join(root, 'vercel.json'), 'utf8'),
  );
  const sources = cfg.rewrites.map((row) => row.source);
  const rootAt = sources.indexOf('/');
  const catchAllAt = sources.lastIndexOf('/(.*)');
  assert.notEqual(rootAt, -1);
  assert.notEqual(catchAllAt, -1);
  assert.ok(rootAt < catchAllAt);
  assert.equal(cfg.rewrites[rootAt].destination, '/home.html');
  assert.equal(cfg.rewrites[catchAllAt].destination, '/app.html');
});

test('human marketplace routes rewrite to the React market SPA before Flutter catchall', () => {
  const cfg = JSON.parse(
    fs.readFileSync(path.join(root, 'vercel.json'), 'utf8'),
  );
  const sources = cfg.rewrites.map((row) => row.source);
  const catchAllAt = sources.lastIndexOf('/(.*)');
  const marketHome = cfg.rewrites.find((row) => row.source === '/marketplace' && !row.has);
  const marketSearch = cfg.rewrites.find((row) => row.source === '/marketplace/search');
  const marketCard = cfg.rewrites.find((row) => (
    row.source === '/marketplace/:language/cards/:cardId/:cardSlug' && !row.has
  ));
  const shortlink = cfg.rewrites.find((row) => row.source === '/marketplace/:cardId(\\d+)');
  assert.equal(marketHome.destination, '/market/index.html');
  assert.equal(marketSearch.destination, '/market/index.html');
  assert.equal(marketCard.destination, '/market/index.html');
  assert.ok(sources.indexOf('/marketplace/search') < catchAllAt);
  assert.ok(sources.lastIndexOf('/marketplace') < catchAllAt);
  assert.equal(shortlink.destination.includes('marketplace-card-shortlink'), true);
});

test('static landing files exist in web/', () => {
  const html = fs.readFileSync(path.join(root, 'web', 'home.html'), 'utf8');
  assert.match(html, /The marketplace belongs to the collectors/);
  assert.match(html, /Buy\. Sell\. Settle in PKN/);
  assert.match(html, /A global peer-to-peer marketplace built for Pokémon card collectors/);
  assert.match(html, /Explore/);
  assert.match(html, /selling/);
  assert.match(html, /PokoinPOS_Official_Security_Audit_2026-05-28\.pdf/);
  assert.match(html, /Not in the stores yet/);
  assert.match(html, /No App Store listing/);
  assert.match(html, /No Google Play listing/);
  assert.match(html, /there is no open intake form/);
  assert.doesNotMatch(html, /Open peer intake/);
  assert.doesNotMatch(html, /Scan and settle from your pocket/);
  assert.doesNotMatch(html, /wrapped liquidity/i);
  assert.doesNotMatch(html, /btn-lime/);
  assert.doesNotMatch(html, /aggregateRating/);
  assert.doesNotMatch(html, /Certified by/);
  assert.ok(fs.existsSync(path.join(root, 'web', 'home', 'landing.css')));
  assert.ok(fs.existsSync(path.join(root, 'web', 'home', 'landing.js')));
  const css = fs.readFileSync(path.join(root, 'web', 'home', 'landing.css'), 'utf8');
  assert.match(css, /#ffd33d/i);
  assert.doesNotMatch(css, /#cbf062/i);
  assert.match(html, /store-btn[\s\S]*icon/);
  assert.match(html, /<title>Pokoin:/);
  assert.match(html, /"@type": "WebPage"/);
  assert.match(html, /rel="sitemap"/);
  assert.match(html, /Frankfurt am Main, Germany \[DE\]/);
  assert.match(html, /peer-status\.json/);
  assert.doesNotMatch(html, /bootstrap-peers\.json/);
  assert.doesNotMatch(html, /pokoin-peer1/);
  assert.doesNotMatch(html, /pokoin-marketplace/);
  assert.doesNotMatch(html, /92\.5\.153/);
  assert.doesNotMatch(html, /130\.61\.251/);
  const js = fs.readFileSync(path.join(root, 'web', 'home', 'landing.js'), 'utf8');
  assert.match(js, /place \? ` \$\{place\}` : " peer"/);
  assert.match(js, /peer-status\.json/);
  assert.doesNotMatch(js, /bootstrap-peers\.json/);
  assert.doesNotMatch(js, /pokoin-peer1/);
  assert.doesNotMatch(js, /pokoin-marketplace/);
});
