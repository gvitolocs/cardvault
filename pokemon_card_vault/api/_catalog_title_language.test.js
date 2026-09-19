'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {
  attachTitleLanguageOnGroups,
  cleanTitleLanguage,
  mapsFromRows,
  overlayExpansion,
  overlayTitleLanguageOnGroups,
  overlayTitleLanguageOnRows,
  resetTitleLanguageCache,
  titleLanguageFromSearchParams,
} = require('./_catalog_title_language');

test('title-language codes map TCGDex ja/zh onto UI jp/zht', () => {
  assert.equal(cleanTitleLanguage('IT'), 'it');
  assert.equal(cleanTitleLanguage('ja'), 'jp');
  assert.equal(cleanTitleLanguage('zh-tw'), 'zht');
  assert.equal(cleanTitleLanguage('xx'), 'en');
});

test('overlay keeps English identity and stamps localized display fields', () => {
  const maps = mapsFromRows({
    names: [['Ace Trainer', 'Fantallenatori'], ['Pikachu', 'Pikachu']],
    sets: [['Base Set', 'Set Base']],
    rarities: [['Rare', 'Rara']],
  });
  const groups = overlayTitleLanguageOnGroups([
    {
      name: 'Ace Trainer',
      printings: [{
        id: '1',
        name: 'Ace Trainer',
        set: 'Base Set',
        rarity: 'Rare',
      }],
    },
  ], maps);
  assert.equal(groups[0].name, 'Ace Trainer');
  assert.equal(groups[0].localized_name, 'Fantallenatori');
  assert.equal(groups[0].printings[0].name, 'Ace Trainer');
  assert.equal(groups[0].printings[0].localized_name, 'Fantallenatori');
  assert.equal(groups[0].printings[0].set, 'Base Set');
  assert.equal(groups[0].printings[0].localized_set, 'Set Base');
  assert.equal(groups[0].printings[0].localized_rarity, 'Rara');
});

test('overlay on search rows leaves English name for matching', () => {
  const maps = mapsFromRows({
    names: [['Dawn', 'Camilla']],
    sets: [['Ultra Prism', 'Prisma Lucente']],
  });
  const rows = overlayTitleLanguageOnRows([
    { card_id: 1, name: 'Dawn', set_name: 'Ultra Prism', rarity: 'Uncommon' },
  ], maps);
  assert.equal(rows[0].name, 'Dawn');
  assert.equal(rows[0].localized_name, 'Camilla');
  assert.equal(rows[0].localized_set, 'Prisma Lucente');
  assert.equal(rows[0].rarity, 'Uncommon');
});

test('expansion overlay stamps localized_name and keeps English identity', () => {
  const maps = mapsFromRows({
    sets: [['Ancient Origins', 'Origini Antiche']],
  });
  const expansion = overlayExpansion({ name: 'Ancient Origins', slug: 'ancient-origins' }, maps);
  assert.equal(expansion.name, 'Ancient Origins');
  assert.equal(expansion.slug, 'ancient-origins');
  assert.equal(expansion.localized_name, 'Origini Antiche');
});

test('titleLanguageFromSearchParams maps ja onto jp', () => {
  const params = new URLSearchParams({ search_language: 'ja' });
  assert.equal(titleLanguageFromSearchParams(params), 'jp');
  assert.equal(titleLanguageFromSearchParams(new URLSearchParams({ lang: 'IT' })), 'it');
});

test('English title language skips the catalog tables', async () => {
  resetTitleLanguageCache();
  let queried = false;
  const groups = await attachTitleLanguageOnGroups(
    [{ name: 'Pikachu', printings: [{ id: '1', name: 'Pikachu' }] }],
    'en',
    async () => {
      queried = true;
      return { rows: [] };
    },
  );
  assert.equal(queried, false);
  assert.equal(groups[0].localized_name, undefined);
});
