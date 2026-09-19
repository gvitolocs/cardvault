const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const {
  DEFAULT_DIGEST,
  siblingPngKey,
  ctIdFromKey,
  parseArgs,
} = require('./rewrite-local-digest-png');

const script = fs.readFileSync(path.join(__dirname, 'rewrite-local-digest-png.js'), 'utf8');

test('digest rewrite defaults to the local pokoincdn copy', () => {
  assert.equal(DEFAULT_DIGEST, '/home/nez/pokoincdn/cdn_images_digest/2026-08-30');
  assert.match(script, /backupExistingObject/);
  assert.match(script, /siblingPngKey/);
  assert.match(script, /PutObjectCommand/);
  assert.doesNotMatch(script, /DeleteObject/);
  assert.doesNotMatch(script, /refresh_marketplace_oracle_projections/);
});

test('ctIdFromKey reads leftover prefix, not public id', () => {
  assert.equal(ctIdFromKey('351691_mega-lucario-ex.jpg'), '351691');
  assert.equal(ctIdFromKey('previews/122576_mimikyu-gx.webp'), '122576');
  assert.equal(ctIdFromKey('expansions/symbols/mega.png'), null);
});

test('parseArgs is dry-run unless --apply', () => {
  assert.equal(parseArgs([]).apply, false);
  assert.equal(parseArgs(['--apply', '--limit', '2']).apply, true);
  assert.equal(parseArgs(['--apply', '--limit', '2']).limit, 2);
  assert.equal(parseArgs(['--no-db']).db, false);
  assert.deepEqual(parseArgs(['--only', 'a.jpg,b.jpg']).only, ['a.jpg', 'b.jpg']);
  assert.equal(parseArgs(['--catalog-log', '/tmp/rewrite.log.jsonl']).catalogLog, '/tmp/rewrite.log.jsonl');
});

test('rewrite script keeps leftover sibling names', () => {
  assert.equal(siblingPngKey('351691_mega-lucario-ex.jpg'), '351691_mega-lucario-ex.png');
});
