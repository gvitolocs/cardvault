'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {
  cleanPrintLanguage,
  effectivePrintBucket,
  mergePrintingFields,
  printBucket,
} = require('./_print_bucket');
const { mapMarketplaceMeiliDoc } = require('./_meili_document');

test('printBucket: empty is unknown, never western', () => {
  assert.equal(printBucket(''), 'unknown');
  assert.equal(printBucket('western'), 'western');
  assert.equal(printBucket('japanese'), 'japanese');
});

test('effectivePrintBucket prefers explicit then expansion lookup', () => {
  assert.equal(effectivePrintBucket({ nationality: 'japanese' }), 'japanese');
  assert.equal(
    effectivePrintBucket({ nationality: '', set: 'X' }, () => 'chinese'),
    'chinese',
  );
  assert.equal(effectivePrintBucket({ nationality: '' }), 'unknown');
});

test('mergePrintingFields preserves known nationality', () => {
  const merged = mergePrintingFields(
    { nationality: 'japanese', number: '014/103' },
    { nationality: '', number: '' },
  );
  assert.equal(merged.nationality, 'japanese');
  assert.equal(merged.number, '014/103');
});

test('mapMarketplaceMeiliDoc stamps effective_print_bucket without empty→western', () => {
  const doc = mapMarketplaceMeiliDoc({
    card_id: '1',
    language: 'en',
    name: 'Palkia',
    set_name: 'Mystery',
    nationality: '',
  });
  assert.equal(doc.effective_print_bucket, 'unknown');
  assert.equal(doc.nationality, '');
  const jp = mapMarketplaceMeiliDoc({
    card_id: '2',
    language: 'en',
    name: 'Palkia',
    set_name: '30th Celebration JP',
    nationality: 'japanese',
  });
  assert.equal(jp.effective_print_bucket, 'japanese');
});

test('cleanPrintLanguage aliases', () => {
  assert.equal(cleanPrintLanguage('EU'), 'western');
  assert.equal(cleanPrintLanguage('jp'), 'japanese');
  assert.equal(cleanPrintLanguage('nope'), 'all');
});
