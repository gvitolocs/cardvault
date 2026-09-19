const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');

const src = fs.readFileSync(path.join(__dirname, 'pokoin-cdn-card-images-worker.js'), 'utf8');

function keepOnR2(requestedKey) {
  const key = String(requestedKey || '').replace(/^\/+/, '');
  return key.startsWith('originals/') || key.startsWith('manifests/') || /_homepage\.webp$/i.test(key);
}

test('live origin is Pi; R2 is backup; Oracle is not used', () => {
  assert.equal(keepOnR2('351691_mega-lucario-ex_homepage.webp'), true);
  assert.equal(keepOnR2('351691_mega-lucario-ex.jpg'), false);
  assert.equal(keepOnR2('previews/351691_mega-lucario-ex.jpg'), false);
  assert.match(src, /export function keepOnR2/);
  assert.match(src, /PI_CDN_ORIGIN/);
  assert.match(src, /fromPi/);
  assert.match(src, /fromR2/);
  assert.match(src, /X-Pokoin-CDN-Origin/);
  assert.match(src, /key\.startsWith\("competitive\/"\)/);
  assert.doesNotMatch(src, /ORACLE_CDN_ORIGIN/);
  assert.doesNotMatch(src, /fromOracle/);
  assert.doesNotMatch(src, /api2\.pokoin\.com/);
  assert.doesNotMatch(src, /oracle-peer1/);
});

test('leftover JPEG requests never fall back to homepage webp', () => {
  assert.doesNotMatch(src, /replace\(\/\.jpe\?g\$\/i,\s*"_homepage\.webp"\)/);
  assert.match(src, /rejectMismatchedJpeg/);
  assert.match(src, /cacheTtl: 0/);
  assert.match(src, /from=pi/);
  assert.match(src, /private, no-store/);
});

test('public image responses use Cloudflare Cache API before Pi or R2', () => {
  assert.match(src, /const edgeCache = caches\.default/);
  assert.match(src, /cdn-e/);
  assert.match(src, /CACHE_EPOCH/);
  assert.match(src, /await edgeCache\.match\(cacheRequest\)/);
  assert.match(src, /ctx\.waitUntil\(edgeCache\.put\(cacheRequest, response\.clone\(\)\)/);
  assert.match(src, /X-Pokoin-CDN-Cache/);
  assert.match(src, /return forRequest\(cached, request\.method, "HIT"\)/);
  assert.match(src, /return forRequest\(response, request\.method, "MISS"\)/);
  assert.match(src, /headers\.delete\("CF-Cache-Status"\)/);

  const matchAt = src.indexOf('await edgeCache.match(cacheRequest)');
  const resolveAt = src.lastIndexOf('const hit = await resolveObject');
  assert.ok(matchAt > 0 && matchAt < resolveAt, 'edge lookup must happen before origin resolution');
});
