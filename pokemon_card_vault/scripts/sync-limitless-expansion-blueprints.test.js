const assert = require('node:assert/strict');
const test = require('node:test');

const {
  compactText,
  normalizeCollectorNumber,
  normalizeText,
} = require('./sync-limitless-expansion-blueprints');

test('Limitless expansion blueprint sync normalizes collector numbers', () => {
  assert.equal(normalizeCollectorNumber('128/167'), '128');
  assert.equal(normalizeCollectorNumber('TWM 128'), '128');
  assert.equal(normalizeCollectorNumber('001a'), '1a');
});

test('Limitless expansion blueprint sync compacts expansion names', () => {
  assert.equal(normalizeText('Twilight Masquerade'), 'twilight masquerade');
  assert.equal(compactText('Twilight Masquerade'), 'twilightmasquerade');
});
