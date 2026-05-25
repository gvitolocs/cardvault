const assert = require('node:assert/strict');
const test = require('node:test');

const {
  candidateRowsForCardId,
  cardDetailSlugParts,
  cardIdFromDoubledId,
  collectorNumberTokenVariants,
  projectedExpansionNumberIntSql,
  projectedExpansionNumberSql,
  resolveCardRoute,
  slugMatchClause,
  canonicalSlugForRow,
  canonicalSlugMatches,
  projectedRaritySql,
  rowsForVersions,
} = require('./marketplace-card-versions');

test('card versions payload SQL does not use CardTrader availability cache', async () => {
  const captured = [];
  await candidateRowsForCardId('316600', async (sql, values) => {
    captured.push({ sql, values });
    return { rows: [] };
  });

  assert.doesNotMatch(captured[0].sql, /cardtrader_blueprint_listing_cache/);
  assert.doesNotMatch(captured[0].sql, /cardtrader_listed_quantity/);
  assert.doesNotMatch(captured[0].sql, /cardtrader_lowest_price_pkn/);
  assert.doesNotMatch(captured[0].sql, /cardtrader_market_listing_snapshots/);
});

test('card detail slug parser ignores punctuation and numeric separators', () => {
  assert.deepEqual(
    cardDetailSlugParts('rare-leafeon-005-131-prismatic-evolutions'),
    ['rare', 'leafeon', '005', '131', 'prismatic', 'evolutions'],
  );
});

test('card detail slug parser keeps Fan Rotom collector tokens', () => {
  assert.deepEqual(
    cardDetailSlugParts('common-fan-rotom-085-131-prismatic-evolutions'),
    ['common', 'fan', 'rotom', '085', '131', 'prismatic', 'evolutions'],
  );
});

test('collector number token variants tolerate leading zero slugs', () => {
  assert.deepEqual(collectorNumberTokenVariants('085'), ['085', '85']);
  assert.deepEqual(collectorNumberTokenVariants('85'), ['85']);
  assert.deepEqual(collectorNumberTokenVariants('fan'), []);
});

test('public number route segment decodes to real card id', () => {
  assert.equal(cardIdFromDoubledId('633200'), '316600');
  assert.equal(cardIdFromDoubledId('633201'), '');
  assert.equal(cardIdFromDoubledId('316600'), '158300');
});

test('route resolver only decodes public number when a slug is present', () => {
  assert.deepEqual(
    resolveCardRoute({
      doubledCardId: '633200',
      cardSlug: 'rare-leafeon-005-131-prismatic-evolutions',
    }),
    {
      cardId: '316600',
      cardSlug: 'rare-leafeon-005-131-prismatic-evolutions',
    },
  );
  assert.deepEqual(
    resolveCardRoute({ cardId: '316600', cardSlug: '' }),
    { cardId: '316600', cardSlug: '' },
  );
});

test('canonical slug matches legacy marketplace Fennekin route', () => {
  assert.equal(
    canonicalSlugForRow({
      name: 'Fennekin',
      expansion_number: '011',
      expansion_name: 'Chaos Rising',
      rarity: 'Card',
    }),
    'card-fennekin-011-chaos-rising',
  );
  assert.equal(
    canonicalSlugMatches(
      'card-fennekin-011-chaos-rising',
      'card-fennekin-011-086-chaos-rising',
    ),
    false,
  );
  assert.equal(
    canonicalSlugMatches(
      'card-fennekin-011-086-chaos-rising',
      'card-fennekin-11-086-chaos-rising',
    ),
    true,
  );
  assert.equal(
    canonicalSlugForRow({
      name: 'Fennekin',
      expansion_number: '011/086',
      expansion_name: 'Chaos Rising',
      rarity: 'Card',
    }),
    'card-fennekin-011-086-chaos-rising',
  );
});

test('canonical slug matching ignores rarity classifier mismatches', () => {
  assert.equal(
    canonicalSlugMatches(
      'card-super-rod-gold-silver-to-a-new-world',
      'common-super-rod-gold-silver-to-a-new-world',
    ),
    true,
  );
});

test('projected expansion number falls back to candidate and image collector number', () => {
  const sql = projectedExpansionNumberSql();
  assert.match(sql, /nullif\(.*versions\.expansion_number[\s\S]*versions\.card_id::text/);
  assert.match(sql, /nullif\(.*candidates\.card_number[\s\S]*versions\.card_id::text/);
  assert.match(sql, /verified_links\.collector_number/);
  assert.match(sql, /product_parsing\.collector_number/);
  assert.match(sql, /blueprints\.blueprint#>>'\{fixed_properties,collector_number\}'/);
  assert.match(sql, /blueprints\.blueprint->>'collector_number'/);
  assert.match(sql, /blueprints\.version/);
  assert.match(sql, /versions\.preview_image_url/);
  assert.match(sql, /versions\.cdn_image_url/);
  assert.match(sql, /substring\(/);
  assert.match(sql, /\[0-9\]\{1,4\}\[A-Za-z\]\?\[-\/\]\[0-9\]\{1,4\}/);
  assert.match(sql, /replace\(/);
});

test('projected expansion number int derives only from cleaned collector number', () => {
  const sql = projectedExpansionNumberIntSql('projected_expansion_number');

  assert.equal(
    sql,
    "nullif(substring(projected_expansion_number from '([0-9]+)'), '')::integer",
  );
});

test('card versions projected rarity SQL uses TCG metadata before generic Card', () => {
  const sql = projectedRaritySql({
    rarityColumn: 'candidates.rarity',
    collectorNumberSql: 'versions.expansion_number',
  });

  assert.match(sql, /sourceCard,rarity/);
  assert.match(sql, /blueprints\.blueprint->>'rarity'/);
  assert.match(sql, /lower\(coalesce\(candidates\.rarity, ''\)\) <> 'card'/);
});

test('card versions payload repairs Servine-style two-token emoji', async () => {
  const rows = await rowsForVersions({
    cardId: '111409',
    limit: 10,
    dbQuery: async (sql, values) => {
      assert.match(sql, /marketplace_blueprint_tcg_metadata tcg_metadata/);
      assert.match(sql, /sourceCard,rarity/);
      assert.deepEqual(values, [111409, 10]);
      return {
        rows: [
          {
            card_id: '111409',
            name: 'Servine',
            expansion_name: 'Black & White',
            expansion_number: '4/114',
            product_variant: '',
            blueprint_id: '111409',
            image_url: 'https://cdn.pokoin.test/servine.webp',
            product_type: 'card',
            emoji: '🐍 🌿',
            rarity: 'Uncommon',
            card_type: 'Trading card',
          },
        ],
      };
    },
  });

  assert.equal(rows[0].rarity, 'Uncommon');
  assert.equal(rows[0].rarityVariantEmoji, '🔷');
  assert.equal(rows[0].emoji, '🐍 🌿 🔷');
});

test('slug match clause can use projected collector number', () => {
  const values = [];
  const clause = slugMatchClause(
    'common-fan-rotom-085-131-prismatic-evolutions',
    values,
    { collectorNumberSql: 'projected_expansion_number' },
  );

  assert.equal(values.length, 10);
  assert.deepEqual(values.slice(0, 7), [
    '%common%',
    '%fan%',
    '%rotom%',
    '%085%',
    '(^|-)085(-|$)',
    '(^|-)85(-|$)',
    '%131%',
  ]);
  assert.match(clause, /projected_expansion_number/);
  assert.match(clause, /\$5/);
  assert.match(clause, /\$6/);
  assert.match(clause, /regexp_replace\(regexp_replace/);
});

test('slug match clause keeps unpadded collector number slugs exact', () => {
  const values = [];
  const clause = slugMatchClause(
    'common-fan-rotom-85-131-prismatic-evolutions',
    values,
    { collectorNumberSql: 'projected_expansion_number' },
  );

  assert.equal(values.length, 9);
  assert.deepEqual(values.slice(0, 7), [
    '%common%',
    '%fan%',
    '%rotom%',
    '%85%',
    '(^|-)85(-|$)',
    '%131%',
    '(^|-)131(-|$)',
  ]);
  assert.match(clause, /projected_expansion_number/);
});

test('slug match clause can ignore leading rarity classifier', () => {
  const values = [];
  const clause = slugMatchClause(
    'common-super-rod-gold-silver-to-a-new-world',
    values,
    {
      collectorNumberSql: 'projected_expansion_number',
      ignoreLeadingClassifier: true,
    },
  );

  assert.deepEqual(values.slice(0, 3), ['%super%', '%rod%', '%gold%']);
  assert.doesNotMatch(clause, /%common%/);
  assert.match(clause, /versions\.name/);
});

test('slug match clause preserves existing Leafeon slug terms', () => {
  const values = [];
  slugMatchClause('rare-leafeon-005-131-prismatic-evolutions', values, {
    collectorNumberSql: 'projected_expansion_number',
  });

  assert.deepEqual(values.slice(0, 6), [
    '%rare%',
    '%leafeon%',
    '%005%',
    '(^|-)005(-|$)',
    '(^|-)5(-|$)',
    '%131%',
  ]);
});
