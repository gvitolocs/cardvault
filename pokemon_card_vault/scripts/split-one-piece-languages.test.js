const test = require('node:test');
const assert = require('node:assert/strict');
const {
  classifyOnePieceLanguage,
  idFromFilename,
  officialEnglishExpansion,
  parseArgs,
} = require('./split-one-piece-languages');

test('parseArgs requires dest and stays dry-run until --apply', () => {
  const options = parseArgs(['--dest=/tmp/one-piece']);
  assert.equal(options.dest, '/tmp/one-piece');
  assert.equal(options.apply, false);
  assert.equal(parseArgs(['--dest=/tmp/one-piece', '--apply']).apply, true);
});

test('idFromFilename reads CardTrader id prefix', () => {
  assert.equal(idFromFilename('244176_monkey-d-luffy.webp'), '244176');
  assert.equal(idFromFilename('244176_monkey-d-luffy_homepage.webp'), '244176');
  assert.equal(idFromFilename('readme.txt'), null);
});

test('official English cardlist covers OP-01..17, ST-01..36, EB-01/02/03/05, PRB', () => {
  assert.equal(officialEnglishExpansion('OP-01: Romance Dawn'), true);
  assert.equal(officialEnglishExpansion('OP-17: The World\'s Strongest Warriors'), true);
  assert.equal(officialEnglishExpansion('OP-18: The Dominance of God'), false);
  assert.equal(officialEnglishExpansion('ST-36: Starter Deck Yellow - Eustass"Captain"Kid'), true);
  assert.equal(officialEnglishExpansion('ST-37: Starter Deck'), false);
  assert.equal(officialEnglishExpansion('EB-03: Heroines Edition'), true);
  assert.equal(officialEnglishExpansion('EB-04: Egghead Crisis'), false);
  assert.equal(officialEnglishExpansion('EB-05: Heroines Edition Vol.2'), true);
  assert.equal(officialEnglishExpansion('PRB-02: The Best 2 - Premium Booster'), true);
  assert.equal(officialEnglishExpansion('Asian Promos'), false);
});

test('classify uses official expansions, then visual/SKU checks, not CardTrader default en', () => {
  assert.equal(classifyOnePieceLanguage({
    defaultLang: 'en',
    expansionName: 'OP-01: Romance Dawn',
  }), 'english');
  assert.equal(classifyOnePieceLanguage({
    defaultLang: 'jp',
    expansionName: 'OP-01: Romance Dawn',
    version: 'Asian',
  }), 'japanese');
  assert.equal(classifyOnePieceLanguage({
    defaultLang: 'en',
    expansionName: 'Asian Promos',
    version: 'Promo Vol.7',
  }), 'japanese');
  assert.equal(classifyOnePieceLanguage({
    defaultLang: 'en',
    expansionName: 'EB-04: Egghead Crisis',
  }), 'japanese');
  assert.equal(classifyOnePieceLanguage({
    defaultLang: 'en',
    expansionName: 'EB-05: Heroines Edition Vol.2',
  }), 'english');
  assert.equal(classifyOnePieceLanguage({
    defaultLang: 'en',
    expansionName: 'Magazine Promos',
    version: 'Shonen Jump Promo',
  }), 'japanese');
  assert.equal(classifyOnePieceLanguage({
    defaultLang: 'en',
    expansionName: 'Premium Bandai Products',
    version: '2nd Japanese Anniversary Set',
  }), 'japanese');
  assert.equal(classifyOnePieceLanguage({
    defaultLang: 'en',
    expansionName: 'Premium Bandai Products',
    version: '3rd Anniversary Set | English Version',
  }), 'english');
  assert.equal(classifyOnePieceLanguage({
    defaultLang: 'jp',
    expansionName: 'Premium Card Collection',
    version: 'Premium Card Collection - GIRLS EDITION',
  }), 'japanese');
  assert.equal(classifyOnePieceLanguage({
    defaultLang: 'en',
    expansionName: 'Premium Card Collection',
    version: '1st Anniversary Set',
  }), 'english');
  assert.equal(classifyOnePieceLanguage({
    id: '408462',
    defaultLang: 'en',
    expansionName: 'OP-18: The Dominance of God',
  }), 'japanese');
  assert.equal(classifyOnePieceLanguage({
    id: '408480',
    defaultLang: 'en',
    expansionName: 'OP-18: The Dominance of God',
  }), 'english');
  assert.equal(classifyOnePieceLanguage({
    defaultLang: 'en',
    expansionName: 'OP-18: The Dominance of God',
    version: 'Asian',
  }), 'japanese');
  assert.equal(classifyOnePieceLanguage({
    defaultLang: 'en',
    expansionName: 'Store Tournaments Promos',
    version: 'Offline Regional 2023 | Winner',
  }), 'english');
  assert.equal(classifyOnePieceLanguage({
    defaultLang: 'jp',
    expansionName: 'Championships Promo',
    version: 'Championship',
  }), 'japanese');
  assert.equal(classifyOnePieceLanguage({
    defaultLang: 'en',
    expansionName: 'Championships Promo',
    version: 'Limited Serial Numbered',
  }), 'english');
  assert.equal(classifyOnePieceLanguage({ defaultLang: 'zh-CN', expansionName: 'One Piece Promos' }), 'chinese');
  assert.equal(classifyOnePieceLanguage({
    defaultLang: null,
    expansionName: 'Chinese Exclusives',
    version: 'Chinese 1st Anniversary',
  }), 'chinese');
  assert.equal(classifyOnePieceLanguage({
    defaultLang: null,
    expansionName: 'French Promos',
    version: 'Première Édition',
  }), 'english');
});
