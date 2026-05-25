const assert = require('node:assert/strict');
const test = require('node:test');

const { cardEmojiFields } = require('./_marketplace_card_emoji');

test('card emoji fields render two identity emojis before rarity variant', () => {
  assert.deepEqual(cardEmojiFields({
    name: 'Leafeon',
    rarity: 'Rare',
    emoji: '🦊 ✨  ',
  }), {
    cardIdentityEmoji: '🦊 ✨',
    card_identity_emoji: '🦊 ✨',
    cardIdentityEmojis: ['🦊', '✨'],
    card_identity_emojis: ['🦊', '✨'],
    rarityVariantEmoji: '⭐',
    rarity_variant_emoji: '⭐',
    emoji: '🦊 ✨ ⭐',
  });
});

test('card emoji fields collapse duplicate variant symbols', () => {
  assert.equal(cardEmojiFields({
    name: 'Mew ex',
    rarity: 'Special Illustration Rare',
    expansion_number: 'Special Illustration Rare | 232/091',
    emoji: '🔮  💎 💎',
  }).emoji, '🔮 ✨ 🎨');
});

test('card emoji fields derive variant from collector labels', () => {
  assert.equal(cardEmojiFields({
    name: 'Drifloon Lv.17',
    rarity: 'Uncommon',
    expansion_number: 'Non-Holo Promo | 6/17',
    emoji: '👻 🌫️  ',
  }).emoji, '👻 🌫️ 🎟️');
});

test('card emoji fields backfill missing second identity emoji', () => {
  assert.equal(cardEmojiFields({
    name: 'Meltan',
    rarity: 'Promo',
    expansion_number: 'Holo Promo | SM177',
    emoji: '⚙️   ',
  }).emoji, '⚙️ 🔩 🎟️');
});

test('card emoji fields repair legacy two-token uncommon rows', () => {
  assert.deepEqual(cardEmojiFields({
    name: 'Servine',
    rarity: 'Uncommon',
    expansion_number: '4/114',
    emoji: '🐍 🌿',
  }), {
    cardIdentityEmoji: '🐍 🌿',
    card_identity_emoji: '🐍 🌿',
    cardIdentityEmojis: ['🐍', '🌿'],
    card_identity_emojis: ['🐍', '🌿'],
    rarityVariantEmoji: '🔷',
    rarity_variant_emoji: '🔷',
    emoji: '🐍 🌿 🔷',
  });
});

test('card emoji fields do not guess rarity when only generic Card is known', () => {
  assert.equal(cardEmojiFields({
    name: 'Servine',
    rarity: 'Card',
    expansion_number: '4/114',
    emoji: '🐍 🌿',
  }).emoji, '🐍 🌿');
});
