const assert = require('node:assert/strict');
const test = require('node:test');

const { cardEmojiFields } = require('./_marketplace_card_emoji');

test('card emoji fields render two identity emojis before rarity variant', () => {
  assert.deepEqual(cardEmojiFields({
    name: 'Leafeon',
    rarity: 'Rare',
    emoji: '🦊 ✨ ⭐',
    card_identity_emojis: ['🦊', '✨'],
    rarity_variant_emoji: '⭐',
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

test('card emoji fields preserve database emoji without runtime repair', () => {
  assert.equal(cardEmojiFields({
    name: 'Mew ex',
    rarity: 'Special Illustration Rare',
    expansion_number: 'Special Illustration Rare | 232/091',
    emoji: '🔮  💎 💎',
  }).emoji, '🔮  💎 💎');
});

test('card emoji fields expose only structured fields already present', () => {
  assert.equal(cardEmojiFields({
    name: 'Drifloon Lv.17',
    rarity: 'Uncommon',
    expansion_number: 'Non-Holo Promo | 6/17',
    emoji: '👻 🌫️  ',
  }).rarityVariantEmoji, '');
});

test('card emoji fields do not backfill missing identity or variant emoji', () => {
  assert.equal(cardEmojiFields({
    name: 'Meltan',
    rarity: 'Promo',
    expansion_number: 'Holo Promo | SM177',
    emoji: '⚙️   ',
  }).emoji, '⚙️');
});

test('card emoji fields do not replace generic database values', () => {
  assert.equal(cardEmojiFields({
    name: 'Mega Camerupt ex',
    rarity: 'Promo',
    expansion_number: '022/132',
    emoji: '🃏 ✨ 🎟️',
  }).emoji, '🃏 ✨ 🎟️');

  assert.equal(cardEmojiFields({
    name: 'Mega Sharpedo ex',
    rarity: 'Special Illustration Rare',
    expansion_number: '127/094',
    emoji: '🃏 ✨ 🎨',
  }).emoji, '🃏 ✨ 🎨');

  assert.equal(cardEmojiFields({
    name: 'Regirock ex',
    rarity: 'Ultra Rare',
    expansion_number: '107/217',
    emoji: '🃏 ✨ 💎',
  }).emoji, '🃏 ✨ 💎');
});

test('card emoji fields keep legacy two-token rows unchanged', () => {
  assert.deepEqual(cardEmojiFields({
    name: 'Servine',
    rarity: 'Uncommon',
    expansion_number: '4/114',
    emoji: '🐍 🌿',
  }), {
    cardIdentityEmoji: '',
    card_identity_emoji: '',
    cardIdentityEmojis: [],
    card_identity_emojis: [],
    rarityVariantEmoji: '',
    rarity_variant_emoji: '',
    emoji: '🐍 🌿',
  });
});

test('card emoji fields leave missing emoji empty', () => {
  assert.equal(cardEmojiFields({
    name: 'Unknownmon',
    rarity: 'Card',
    expansion_number: '999/999',
  }).emoji, '');
});

test('card emoji fields preserve database owner and variant identity decisions', () => {
  assert.equal(cardEmojiFields({
    name: "Giovanni's Gyarados",
    rarity: 'Holo Rare',
    product_variant: 'Master Ball Reverse Holo | 005/132',
    emoji: '🐟 🌊 ✨',
  }).emoji, '🐟 🌊 ✨');

  assert.equal(cardEmojiFields({
    name: 'Aerodactyl',
    rarity: 'Reverse Holo',
    product_variant: 'Master Ball Reverse Holo | 142/165',
    emoji: '🦖 ✨',
  }).emoji, '🦖 ✨');
});
