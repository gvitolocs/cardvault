const VARIANT_EMOJIS = new Set([
  '👑',
  '🌟',
  '💥',
  '💎',
  '⬆️',
  '🛡️',
  '✨',
  '🌈',
  '🔺',
  '🔻',
  '🤝',
  '🏅',
  '⚡',
  '🎨',
  '🎟️',
  '🏆',
  '⭐',
  '🔷',
  '⚪',
]);

function textFromParts(...parts) {
  return parts.map((part) => String(part || '').toLowerCase()).join(' ');
}

function emojiTokens(value) {
  const text = String(value || '').trim();
  if (!text) return [];
  if (typeof Intl !== 'undefined' && Intl.Segmenter) {
    const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' });
    return Array.from(segmenter.segment(text), ({ segment }) => segment)
      .map((segment) => segment.trim())
      .filter(Boolean);
  }
  return Array.from(text.matchAll(/\p{Extended_Pictographic}\uFE0F?|\S/gu), (match) => match[0]);
}

function rarityVariantEmojiForCard(row = {}) {
  const text = textFromParts(
    row.rarity,
    row.product_variant || row.productVariant,
    row.number,
    row.card_number,
    row.expansion_number,
    row.name,
  );
  if (/(promo|stamped|stamp)/.test(text)) return '🎟️';
  if (/(special illustration rare|special art rare|illustration rare|art rare|alternate art|alt art|full[- ]?art)/.test(text)) return '🎨';
  if (/(gold secret|secret rare|hyper rare|gold)/.test(text)) return '🏆';
  if (/(shining|shiny|holo|foil|reverse)/.test(text)) return '✨';
  if (/(^|[^a-z0-9])(vmax|v max)([^a-z0-9]|$)/.test(text)) return '👑';
  if (/(^|[^a-z0-9])(vstar|v star)([^a-z0-9]|$)/.test(text)) return '🌟';
  if (/(^|[^a-z0-9])(gx|g x)([^a-z0-9]|$)/.test(text)) return '💥';
  if (/(^|[^a-z0-9])(ex|e x)([^a-z0-9]|$)/.test(text)) return '💎';
  if (/(^|[^a-z0-9])(lv\.?x|lv x|level x)([^a-z0-9]|$)/.test(text)) return '⬆️';
  if (/(^|[^a-z0-9])v([^a-z0-9]|$)/.test(text)) return '🛡️';
  if (/(radiant)/.test(text)) return '🌈';
  if (/(mega)/.test(text)) return '🔺';
  if (/(delta)/.test(text)) return '🔻';
  if (/(tag team|tagteam)/.test(text)) return '🤝';
  if (/(prime)/.test(text)) return '🏅';
  if (/(^|[^a-z0-9])break([^a-z0-9]|$)/.test(text)) return '⚡';
  if (/(^|[^a-z0-9])rare([^a-z0-9]|$)/.test(text)) return '⭐';
  if (/(^|[^a-z0-9])uncommon([^a-z0-9]|$)/.test(text)) return '🔷';
  if (/(^|[^a-z0-9])common([^a-z0-9]|$)/.test(text)) return '⚪';
  return '';
}

function fallbackIdentityForCard(row = {}) {
  const text = textFromParts(row.name, row.card_type || row.type);
  if (/leafeon|eevee|vaporeon|jolteon|flareon|espeon|umbreon|glaceon|sylveon/.test(text)) return ['🦊', '✨'];
  if (/drifloon|drifblim|gastly|haunter|gengar|mismagius|mimikyu|duskull|dusknoir/.test(text)) return ['👻', '🌫️'];
  if (/meltan|melmetal|magnemite|magneton|magnezone|beldum|metang|metagross|klink|klang|klinklang/.test(text)) return ['⚙️', '🔩'];
  if (/cresselia/.test(text)) return ['🌙', '🔮'];
  if (/mewtwo|mew|lunala|solgaleo|jirachi|celebi/.test(text)) return ['🔮', '✨'];
  if (/dragon|charizard|dragonite|rayquaza|salamence|garchomp|kyurem/.test(text)) return ['🐉', '🔥'];
  if (/grass|leaf|bulbasaur|venusaur|oddish|roserade/.test(text)) return ['🌿', '✨'];
  if (/water|squirtle|blastoise|psyduck|milotic/.test(text)) return ['🌊', '✨'];
  if (/lightning|electric|pikachu|raichu|pichu/.test(text)) return ['⚡', '✨'];
  if (/fire|charmander|charmeleon|vulpix|ninetales/.test(text)) return ['🔥', '✨'];
  if (/psychic|fairy/.test(text)) return ['🔮', '✨'];
  if (/metal|steel/.test(text)) return ['⚙️', '🔩'];
  if (/dark|darkness/.test(text)) return ['🌙', '✨'];
  if (/fighting|rock|ground/.test(text)) return ['🪨', '✨'];
  return ['🃏', '✨'];
}

function cardIdentityEmojisForCard(row = {}) {
  const structured = row.cardIdentityEmojis || row.card_identity_emojis;
  const tokens = Array.isArray(structured)
    ? structured.flatMap(emojiTokens)
    : emojiTokens(row.cardIdentityEmoji || row.card_identity_emoji);
  const fallback = fallbackIdentityForCard(row);
  const rawTokens = tokens.length > 0
    ? tokens
    : emojiTokens(row.emoji).filter((token) => !VARIANT_EMOJIS.has(token));
  const identity = [];
  for (const token of rawTokens) {
    if (!identity.includes(token)) identity.push(token);
    if (identity.length === 2) break;
  }
  for (const token of fallback) {
    if (!identity.includes(token)) identity.push(token);
    if (identity.length === 2) break;
  }
  return identity.slice(0, 2);
}

function cardEmojiFields(row = {}) {
  const identity = cardIdentityEmojisForCard(row);
  const variant = emojiTokens(
    row.rarityVariantEmoji ||
      row.rarity_variant_emoji ||
      row.variantEmoji ||
      row.variant_emoji,
  )[0] || rarityVariantEmojiForCard(row);
  const emoji = [...identity, variant].filter(Boolean).join(' ');
  return {
    cardIdentityEmoji: identity.join(' '),
    card_identity_emoji: identity.join(' '),
    cardIdentityEmojis: identity,
    card_identity_emojis: identity,
    rarityVariantEmoji: variant,
    rarity_variant_emoji: variant,
    emoji,
  };
}

function withCardEmojiFields(row = {}) {
  return {
    ...row,
    ...cardEmojiFields(row),
  };
}

module.exports = {
  cardEmojiFields,
  withCardEmojiFields,
  rarityVariantEmojiForCard,
  cardIdentityEmojisForCard,
};
