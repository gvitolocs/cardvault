const assert = require('node:assert/strict');
const test = require('node:test');
const { mergeRecentIntoHome } = require('./_marketplace_home_recent');

test('home recentCardIds prepend spotlight without dropping other cards', () => {
  const merged = mergeRecentIntoHome(
    {
      cards: [
        { id: '1', name: 'A' },
        { id: '2', name: 'B' },
      ],
      sections: {
        recentlySeenIds: ['2'],
        featuredIds: ['1'],
      },
    },
    ['9', '1'],
    [{ id: '9', name: 'Recent' }],
  );
  assert.deepEqual(merged.sections.recentlySeenIds, ['9', '1', '2']);
  assert.deepEqual(merged.sections.spotlightIds, ['9', '1', '2']);
  assert.equal(merged.cards.some((card) => card.id === '9'), true);
});

const { mergeHomeDisplayCards } = require('./_marketplace_home_recent');

test('mergeHomeDisplayCards keeps newest arrivals inside the 140 cap', () => {
  const newest = [{ id: '703382', name: 'Mega Lucario ex' }];
  const listed = Array.from({ length: 140 }, (_, i) => ({ id: String(i + 1), name: `Listed ${i}` }));
  const merged = mergeHomeDisplayCards(newest, listed, 140);
  assert.equal(merged[0].id, '703382');
  assert.equal(merged.length, 140);
  assert.equal(merged.some((card) => card.id === '140'), false);
});
