const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');

const sql = fs.readFileSync(
  path.join(
    __dirname,
    '..',
    'oracle-postgres',
    'schema',
    '004_marketplace_home.sql',
  ),
  'utf8',
);
const {
  cardTilePrice,
  cardTileStock,
  hasCardTraderAvailability,
  normalizeHomeCard,
  projectedCollectorNumber,
  projectedRarity,
  toCardJson,
} = require('./marketplace-home');
const apiSource = fs.readFileSync(
  path.join(__dirname, 'marketplace-home.js'),
  'utf8',
);

test('marketplace home Featured rotates slowly within a bounded scored pool', () => {
  assert.match(sql, /where pool_rank <= 36/);
  assert.match(sql, /floor\(extract\(epoch from now\(\)\) \/ 21600\)/);
  assert.match(sql, /% 6\) \* 6/);
  assert.match(sql, /limit 12/);
});

test('marketplace home Featured still uses curated eligible card signals', () => {
  assert.match(sql, /rarity ilike '%rare%'/);
  assert.match(sql, /rarity ilike '%promo%'/);
  assert.match(
    sql,
    /name ~\* '\(\^\|\[\^a-z0-9\]\)\(ex\|vmax\|vstar\|gx\|lv\\\.x\)\(\[\^a-z0-9\]\|\$\)'/,
  );
  assert.match(
    sql,
    /order by spotlight_score desc, imported_at desc nulls last, card_id desc/,
  );
});

test('marketplace home snapshot exposes homepage image fallback', () => {
  assert.match(
    sql,
    /'homepageImageUrl', coalesce\(homepage_image_url, preview_image_url, cdn_image_url, image_url, ''\)/,
  );
});

test('marketplace home snapshot includes CardTrader analytics signals', () => {
  assert.match(sql, /cardtraderSales24h/);
  assert.match(sql, /cardtraderListingCount/);
  assert.match(sql, /cardtraderEligibleListingCount/);
  assert.match(sql, /hasCardTraderListing/);
  assert.match(sql, /cardtraderListedQuantity/);
  assert.match(sql, /cardtraderSellThrough7d/);
  assert.match(sql, /cheapest_homepage_cache_blueprint/);
  assert.match(sql, /left join lateral/);
  assert.match(sql, /cache\.blueprint_id = c\.card_id/);
  assert.match(sql, /cache\.pokoin_card_id = c\.card_id::text/);
  assert.match(sql, /as cardtrader_eligible_listing_count/);
  assert.match(sql, /cache\.provider in \('cardtrader', 'pokoin_native'\)/);
  assert.match(sql, /or cardtrader_cache\.cheapest_price_pkn <= price_summary\.lowest_ask_pkn/);
  assert.match(sql, /'priceSource', homepage_cheapest_source/);
  assert.doesNotMatch(sql, /from public\.cardtrader_market_listing_snapshots/);
  assert.match(sql, /cardtraderSales24h'\)::integer, 0\) \* 3/);
});

test('marketplace home snapshot exposes watchlist analytics count as tile rating', () => {
  assert.match(sql, /marketplace_card_watchlist_analytics/);
  assert.match(sql, /coalesce\(watchlist_analytics\.watchlist_count, 0\) as watchlist_count/);
  assert.match(sql, /'rating', watchlist_count/);
  assert.match(sql, /'watchlistCount', watchlist_count/);
});

test('marketplace home snapshot exposes cart holder analytics count', () => {
  assert.match(sql, /marketplace_card_cart_analytics/);
  assert.match(sql, /coalesce\(cart_analytics\.cart_holder_count, 0\) as cart_holder_count/);
  assert.match(sql, /'cartHolderCount', cart_holder_count/);
});

test('marketplace home hot blueprint refresh is best effort', () => {
  assert.match(apiSource, /async function refreshHotBlueprintsIfStale\(\) \{/);
  assert.match(apiSource, /catch \(error\) \{/);
  assert.match(apiSource, /marketplace-home hot blueprint refresh skipped/);
});

test('marketplace home section hydration qualifies joined card id columns', () => {
  assert.match(apiSource, /marketplace_search_candidates\.card_id/);
  assert.match(apiSource, /marketplace_search_candidates\.name/);
  assert.match(apiSource, /cardTraderAvailabilityJoin\('marketplace_search_candidates', cheapestCacheRelation\)/);
  assert.match(apiSource, /or cardtrader\.cheapest_price_pkn <= price_summary\.lowest_ask_pkn/);
  assert.match(
    apiSource,
    /where marketplace_search_candidates\.card_id = any\(\$1::bigint\[\]\)/,
  );
  assert.doesNotMatch(apiSource, /where card_id = any\(\$1::bigint\[\]\)/);
});

test('marketplace home snapshot exposes projected collector number fields', () => {
  assert.match(sql, /as projected_card_number/);
  assert.match(sql, /'number', projected_card_number/);
  assert.match(sql, /'card_number', projected_card_number/);
  assert.match(sql, /'expansion_number', projected_card_number/);
  assert.match(sql, /from '\(\[0-9\]\{1,4\}\[A-Za-z\]\?\[-\/\]\[0-9\]\{1,4\}\)'/);
});

test('marketplace home snapshot enriches generic rarity from blueprint fields', () => {
  assert.match(sql, /as projected_rarity/);
  assert.match(sql, /lower\(nullif\(c\.rarity, ''\)\) <> 'card'/);
  assert.match(sql, /b\.blueprint->>'collector_rarity'/);
  assert.match(sql, /'rarity', projected_rarity/);
});

test('marketplace home API derives collector number from CDN image fallback', () => {
  const row = {
    card_id: 316698,
    name: 'Fan Rotom',
    set_name: 'Prismatic Evolutions',
    rarity: 'Common',
    card_type: 'Pokemon',
    item_kind: 'product',
    product_type: 'sealed_product',
    cdn_image_url: 'https://cdn.pokoin.com/cards/fan-rotom-085-131.webp',
  };

  assert.equal(projectedCollectorNumber(row), '085/131');
  const card = toCardJson(row);
  assert.equal(card.number, '085/131');
  assert.equal(card.card_number, '085/131');
  assert.equal(card.expansion_number, '085/131');
  assert.equal(card.rarity, 'Common');
  assert.equal(card.itemKind, 'single');
  assert.equal(card.productType, 'card');
});

test('marketplace home API prefers blueprint rarity over generic Card', () => {
  assert.equal(projectedRarity({
    rarity: 'Card',
    collector_rarity: 'Rare',
  }), 'Rare');
  assert.equal(projectedRarity({
    rarity: 'Common',
    collector_rarity: 'Rare',
  }), 'Common');
});

test('marketplace home API normalizes card emoji contract', () => {
  const card = toCardJson({
    card_id: 274416,
    name: 'Mew ex',
    set_name: 'Paldean Fates',
    card_number: 'Special Illustration Rare | 232/091',
    rarity: 'Special Illustration Rare',
    card_type: 'Trading card',
    emoji: '🔮  💎 💎',
  });

  assert.deepEqual(card.cardIdentityEmojis, ['🔮', '✨']);
  assert.equal(card.rarityVariantEmoji, '🎨');
  assert.equal(card.emoji, '🔮 ✨ 🎨');
});

test('marketplace home card payload uses CardTrader stock and +200 PKN price', () => {
  const card = toCardJson({
    card_id: 316600,
    name: 'Leafeon',
    set_name: 'Prismatic Evolutions',
    card_number: '144/131',
    rarity: 'Rare',
    card_type: 'Trading card',
    listed_quantity: 2,
    lowest_price_pkn: 900,
    has_cardtrader_listing: true,
    cardtrader_eligible_listing_count: 1,
    cardtrader_listed_quantity: 1,
    cardtrader_lowest_price_pkn: 800,
    watchlist_count: 12,
    cart_holder_count: 5,
  });

  assert.equal(card.stock, 2);
  assert.equal(card.price, 800);
  assert.equal(card.rating, 12);
  assert.equal(card.cartHolderCount, 5);
  assert.equal(card.hasCardTraderListing, true);
  assert.equal(card.cardtraderEligibleListingCount, 1);
  assert.equal(card.cardtraderListedQuantity, 1);
  assert.equal(card.cardtraderLowestPricePkn, 800);
  assert.equal(card.tags.includes('NFT'), false);
  assert.equal(cardTileStock({ stock: 0, listed_quantity: 1 }), 1);
  assert.equal(cardTilePrice({ lowest_price_pkn: 800 }), 800);
});

test('marketplace home card payload does not synthesize placeholder prices', () => {
  const card = toCardJson({
    card_id: 391257,
    name: 'Teal Mask Ogerpon ex',
    set_name: 'CSVNC: Land of Kitakami Special Pack',
    card_number: '043/040',
    rarity: 'Card',
    card_type: 'Trading card',
    listed_quantity: 0,
    lowest_price_pkn: null,
    has_cardtrader_listing: false,
    cardtrader_eligible_listing_count: 0,
    cardtrader_listed_quantity: 0,
    cardtrader_lowest_price_pkn: null,
  });

  assert.equal(card.stock, 0);
  assert.equal(card.price, null);
  assert.equal(cardTilePrice({ card_id: 391257 }), null);
});

test('marketplace home canonical CardTrader cache price wins tile display', () => {
  const card = toCardJson({
    card_id: 111409,
    name: 'Servine',
    set_name: 'Black & White',
    card_number: '4/114',
    rarity: 'Uncommon',
    card_type: 'Trading card',
    listed_quantity: 0,
    lowest_price_pkn: 900,
    has_cardtrader_listing: true,
    cardtrader_eligible_listing_count: 56,
    cardtrader_listed_quantity: 70,
    cardtrader_lowest_price_pkn: 238,
  });

  assert.equal(card.stock, 70);
  assert.equal(card.price, 238);
  assert.equal(card.hasCardTraderListing, true);
  assert.equal(card.cardtraderEligibleListingCount, 56);
});

test('marketplace home native cheaper than CardTrader wins tile display', () => {
  const card = toCardJson({
    card_id: 111409,
    name: 'Servine',
    set_name: 'Black & White',
    card_number: '4/114',
    rarity: 'Uncommon',
    card_type: 'Trading card',
    listed_quantity: 2,
    lowest_price_pkn: 500,
    has_cardtrader_listing: true,
    cardtrader_eligible_listing_count: 56,
    cardtrader_listed_quantity: 70,
    cardtrader_lowest_price_pkn: 800,
  });

  assert.equal(card.stock, 70);
  assert.equal(card.price, 500);
  assert.equal(card.hasCardTraderListing, true);
  assert.equal(card.cardtraderLowestPricePkn, 800);
});

test('marketplace home cached cards are repaired with CardTrader availability', () => {
  const card = normalizeHomeCard({
    id: '316600',
    name: 'Leafeon',
    imageUrl: '/card-images/leafeon.webp',
    previewImageUrl: '/card-images/leafeon-preview.webp',
    homepageImageUrl: '/card-images/leafeon-home.webp',
    price: 1000,
    stock: 0,
    tags: ['Pokemon'],
    cardtraderListedQuantity: 3,
    cardtraderLowestPricePkn: 780,
  });

  assert.equal(card.stock, 3);
  assert.equal(card.price, 780);
  assert.deepEqual(card.tags, ['Pokemon']);
});

test('marketplace home source includes lightweight cards fallback', () => {
  assert.match(apiSource, /async function fetchRowsForHomeFallback\(\)/);
  assert.match(apiSource, /from public\.marketplace_search_candidates/);
  assert.match(apiSource, /0 as listed_quantity/);
  assert.match(apiSource, /MARKETPLACE_HOME_SQL_SNAPSHOT/);
  assert.doesNotMatch(apiSource, /return Number\(1000n \+ \(BigInt\(row\.card_id \|\| 0\) % 120000n\)\)/);
  assert.match(apiSource, /marketplace-home snapshot fallback used/);
  assert.match(apiSource, /hydrateCanonicalCardTraderCache\(cards, cheapestCacheRelation\)/);
});

test('marketplace home card payload uses cache listing availability as stock', () => {
  const card = toCardJson({
    card_id: 497712,
    name: 'Magikarp',
    set_name: 'Paldea Evolved',
    card_number: '203/193',
    rarity: 'Illustration Rare',
    card_type: 'Trading card',
    listed_quantity: 0,
    lowest_price_pkn: null,
    has_cardtrader_listing: true,
    cardtrader_eligible_listing_count: 1,
    cardtrader_listed_quantity: 0,
    cardtrader_lowest_price_pkn: 1600,
  });

  assert.equal(card.stock, 1);
  assert.equal(card.price, 1600);
  assert.equal(card.hasCardTraderListing, true);
  assert.equal(card.cardtraderEligibleListingCount, 1);
  assert.equal(hasCardTraderAvailability(card), true);
  assert.equal(cardTileStock(card), 1);
});
