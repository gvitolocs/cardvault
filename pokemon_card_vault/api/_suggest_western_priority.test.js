'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {
  applySuggestPrintPriority,
  preferWesternPrintings,
  filterGroupsByPrintLanguage,
  cleanPrintLanguage,
} = require('./_suggest_western_priority');

function printing(id, nationality, extra = {}) {
  return { id: String(id), set: extra.set || `Set ${id}`, nationality, ...extra };
}

function oshawottGroup() {
  return {
    name: 'Oshawott',
    printings: [
      printing(1, 'japanese', { _rank: 0.9 }),
      printing(2, 'japanese', { _rank: 0.9 }),
      printing(3, 'western', { _rank: 0.9 }),
      printing(4, 'western', { _rank: 0.9 }),
      printing(5, 'chinese', { _rank: 0.9 }),
    ],
  };
}

test('cleanPrintLanguage maps flag aliases and defaults to all', () => {
  assert.equal(cleanPrintLanguage('EU'), 'western');
  assert.equal(cleanPrintLanguage('jp'), 'japanese');
  assert.equal(cleanPrintLanguage('zht'), 'chinese');
  assert.equal(cleanPrintLanguage('nope'), 'all');
});

test('same Meili points: western before JP/CN, original order inside each bucket', () => {
  const [group] = preferWesternPrintings([oshawottGroup()]);
  assert.deepEqual(group.printings.map((row) => row.id), ['3', '4', '1', '2', '5']);
});

test('higher JP Meili points stay ahead of a lower-scoring western printing', () => {
  const [group] = preferWesternPrintings([{
    name: 'Oshawott',
    printings: [
      printing(1, 'japanese', { _rank: 0.95 }),
      printing(2, 'western', { _rank: 0.80 }),
      printing(3, 'japanese', { _rank: 0.80 }),
      printing(4, 'western', { _rank: 0.80 }),
    ],
  }]);
  assert.deepEqual(group.printings.map((row) => row.id), ['1', '2', '4', '3']);
});

test('tied scores fill the 20-cap western-first; unmatched JP still take leftover slots', () => {
  const printings = [];
  for (let index = 0; index < 24; index += 1) {
    printings.push(printing(`j${index}`, 'japanese', { _rank: 0.9 }));
  }
  for (let index = 0; index < 8; index += 1) {
    printings.push(printing(`w${index}`, 'western', { _rank: 0.9 }));
  }
  const capped = applySuggestPrintPriority(
    [{ name: 'Oshawott', printings }],
    { printLanguage: 'all', maxRows: 20 },
  );
  assert.equal(capped[0].printings.length, 20);
  assert.equal(capped[0].printings[0].id, 'w0');
  assert.ok(capped[0].printings.slice(0, 8).every((row) => row.nationality === 'western'));
  assert.ok(capped[0].printings.slice(8).every((row) => row.nationality === 'japanese'));
  assert.equal(capped[0].printings[0]._rank, undefined);
});

test('lower-scoring western printings do not steal the 20-cap from higher-scoring JP', () => {
  const printings = [
    ...Array.from({ length: 20 }, (_, index) => printing(`j${index}`, 'japanese', { _rank: 0.95 })),
    ...Array.from({ length: 8 }, (_, index) => printing(`w${index}`, 'western', { _rank: 0.70 })),
  ];
  const capped = applySuggestPrintPriority(
    [{ name: 'Oshawott', printings }],
    { printLanguage: 'all', maxRows: 20 },
  );
  assert.deepEqual(capped[0].printings.map((row) => row.id), Array.from({ length: 20 }, (_, index) => `j${index}`));
});

test('print_language=japanese filters before the 20-cap', () => {
  const printings = [
    ...Array.from({ length: 6 }, (_, index) => printing(`w${index}`, 'western', { _rank: 0.9 })),
    ...Array.from({ length: 4 }, (_, index) => printing(`j${index}`, 'japanese', { _rank: 0.9 })),
  ];
  const capped = applySuggestPrintPriority(
    [{ name: 'Oshawott', printings }],
    { printLanguage: 'japanese', maxRows: 20 },
  );
  assert.deepEqual(capped[0].printings.map((row) => row.id), ['j0', 'j1', 'j2', 'j3']);
});

test('filterGroupsByPrintLanguage treats empty nationality as unknown, not western', () => {
  const groups = filterGroupsByPrintLanguage(
    [{
      name: 'Pikachu',
      printings: [
        printing('1', 'japanese'),
        printing('2', ''),
        printing('3', 'western'),
      ],
    }],
    'western',
  );
  assert.deepEqual(groups[0].printings.map((row) => row.id), ['3']);
});

test('enabled:false caps without reordering (same as SUGGEST_PRINT_PRIORITY=0)', () => {
  const capped = applySuggestPrintPriority([oshawottGroup()], { maxRows: 3, enabled: false });
  assert.deepEqual(capped[0].printings.map((row) => row.id), ['1', '2', '3']);
});
