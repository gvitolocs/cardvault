const assert = require('node:assert/strict');
const test = require('node:test');

const {
  _test: deckLookupTest,
} = require('./deck-card-version-lookup');

const {
  candidateRowsForCardId,
  cardDetailSlugParts,
  cardIdFromDoubledId,
  collectorNumberTokenVariants,
  gradedListingSummaryJoin,
  projectedExpansionNumberIntSql,
  projectedExpansionNumberSql,
  resolveCardRoute,
  slugMatchClause,
  canonicalSlugForRow,
  canonicalSlugMatches,
  projectedRaritySql,
  rowsForVersions,
} = require('./marketplace-card-versions');

test('card versions fallback row uses canonical homepage cheapest cache', async () => {
  const captured = [];
  await candidateRowsForCardId('316600', async (sql, values) => {
    captured.push({ sql, values });
    if (sql.includes('to_regclass')) {
      return { rows: [{ relation: 'public.cheapest_homepage_cache_blueprint' }] };
    }
    return { rows: [] };
  });

  assert.equal(captured.length, 2);
  assert.match(captured[1].sql, /public\.cheapest_homepage_cache_blueprint/);
  assert.match(captured[1].sql, /cardtrader\.cheapest_price_pkn as lowest_price_pkn/);
  assert.match(captured[1].sql, /cardtrader_eligible_listing_count/);
  assert.doesNotMatch(captured[1].sql, /price_summary\.lowest_ask_pkn as lowest_price_pkn/);
  assert.doesNotMatch(captured[1].sql, /cardtrader_market_listing_snapshots/);
});

test('deck card lookup ranks Dreepy TWM 128 before Fusion Strike', () => {
  const rows = deckLookupTest.rankDeckVersionRows(
    [
      {
        card_id: 'fs',
        name: 'Dreepy',
        expansion_name: 'Fusion Strike',
        expansion_number: '128/264',
        expansion_code: 'FST',
        product_type: 'card',
      },
      {
        card_id: 'twm',
        name: 'Dreepy',
        expansion_name: 'Twilight Masquerade',
        expansion_number: '128/167',
        expansion_code: 'TWM',
        product_type: 'card',
      },
    ],
    { name: 'Dreepy', setCode: 'TWM', collectorNumber: '128' },
  );

  assert.equal(rows[0].card_id, 'twm');
  assert.equal(rows[0].match.setCode, 'exact');
  assert.equal(rows[0].match.collectorNumber, 'exact');
});

test('card detail slug parser ignores punctuation and numeric separators', () => {
  assert.deepEqual(
    cardDetailSlugParts('rare-leafeon-005-131-prismatic-evolutions'),
    ['rare', 'leafeon', '005', '131', 'prismatic', 'evolutions'],
  );
});

test('card detail slug parser folds Pokémon accent and legacy slug', () => {
  assert.deepEqual(
    cardDetailSlugParts('Card Poliwhirl 176/165 Pokémon Card 151'),
    ['card', 'poliwhirl', '176', '165', 'pokemon', 'card', '151'],
  );
  assert.deepEqual(
    cardDetailSlugParts('card-poliwhirl-176-165-pok-mon-card-151'),
    ['card', 'poliwhirl', '176', '165', 'pokemon', 'card', '151'],
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

test('card versions search clause uses selected Italian language', async () => {
  const captured = [];
  await rowsForVersions({
    dbQuery: async (sql, values) => {
      captured.push({ sql, values });
      return { rows: [] };
    },
    query: 'camilla',
    searchLanguage: 'it',
    limit: 20,
  });

  const searchCall = captured.find(({ sql }) =>
    sql.includes('marketplace_card_name_translations'),
  );
  assert.ok(searchCall);
  assert.equal(searchCall.values[1], 'it');
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

test('card versions payload preserves database emoji', async () => {
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
  assert.equal(rows[0].rarityVariantEmoji, '');
  assert.equal(rows[0].emoji, '🐍 🌿');
});

test('card versions rows use canonical homepage cheapest availability', async () => {
  const captured = [];
  await rowsForVersions({
    expansionName: 'Play! Pokémon Prize Pack Series',
    productType: 'card',
    limit: 10,
    dbQuery: async (sql, values) => {
      captured.push({ sql, values });
      if (sql.includes('to_regclass')) {
        return { rows: [{ relation: 'public.cheapest_homepage_cache_blueprint' }] };
      }
      return {
        rows: [
          {
            card_id: '391030',
            name: 'Mega Venusaur ex',
            expansion_name: 'Play! Pokémon Prize Pack Series',
            expansion_number: '003/132',
            product_variant: '',
            blueprint_id: '391030',
            image_url: 'https://cdn.pokoin.test/mega-venusaur-ex.webp',
            product_type: 'card',
            rarity: 'Promo',
            card_type: 'Trading card',
            listed_quantity: 4,
            lowest_price_pkn: '615',
            has_cardtrader_listing: true,
            cardtrader_eligible_listing_count: 3,
          },
        ],
      };
    },
  });

  const versionQuery = captured.at(-1);
  assert.match(versionQuery.sql, /public\.cheapest_homepage_cache_blueprint/);
  assert.match(versionQuery.sql, /cardtrader\.cheapest_price_pkn as lowest_price_pkn/);
  assert.match(versionQuery.sql, /cardtrader_eligible_listing_count/);
  assert.doesNotMatch(versionQuery.sql, /price_summary\.lowest_ask_pkn as lowest_price_pkn/);
  assert.deepEqual(versionQuery.values, [
    'Play! Pokémon Prize Pack Series',
    'card',
    10,
  ]);
});

test('card versions graded product category filters active graded listings', async () => {
  const captured = [];
  await rowsForVersions({
    productType: 'card',
    productCategory: 'graded',
    limit: 10,
    dbQuery: async (sql, values) => {
      captured.push({ sql, values });
      return {
        rows: [
          {
            card_id: '391030',
            name: 'Mega Venusaur ex',
            expansion_name: 'Play! Pokémon Prize Pack Series',
            expansion_number: '003/132',
            product_variant: '',
            blueprint_id: '391030',
            image_url: 'https://cdn.pokoin.test/mega-venusaur-ex.webp',
            product_type: 'card',
            rarity: 'Promo',
            card_type: 'Trading card',
            listed_quantity: 1,
            lowest_price_pkn: '2500',
            is_graded: true,
            graded_listing_count: 1,
            grading_company: 'PSA',
            grade: '10',
          },
        ],
      };
    },
  });

  const versionQuery = captured.at(-1);
  assert.equal(captured.length, 1);
  assert.match(versionQuery.sql, /marketplace_user_listings native_listing/);
  assert.match(versionQuery.sql, /listing\.graded = true/);
  assert.match(versionQuery.sql, /listing\.status = 'active'/);
  assert.match(versionQuery.sql, /coalesce\(listing\.quantity_available, 0\) > 0/);
  assert.match(versionQuery.sql, /listing\.price_pkn > 0/);
  assert.match(versionQuery.sql, /coalesce\(graded_listings\.active_listing_count, 0\) > 0/);
  assert.match(versionQuery.sql, /graded_listings\.lowest_price_pkn as lowest_price_pkn/);
  assert.match(versionQuery.sql, /true as is_graded/);
  assert.doesNotMatch(versionQuery.sql, /to_regclass/);
  assert.doesNotMatch(versionQuery.sql, /cardtrader_cache/);
  assert.deepEqual(versionQuery.values, ['card', 10]);
});

test('graded listing summary exposes cheapest active native graded listing', () => {
  const joinSql = gradedListingSummaryJoin('versions');

  assert.match(joinSql, /left join lateral/);
  assert.match(joinSql, /marketplace_user_listings native_listing/);
  assert.match(joinSql, /listing\.card_id_bigint = versions\.card_id/);
  assert.match(joinSql, /listing\.graded = true/);
  assert.match(joinSql, /listing\.status = 'active'/);
  assert.match(joinSql, /coalesce\(listing\.quantity_available, 0\) > 0/);
  assert.match(joinSql, /listing\.price_pkn > 0/);
  assert.match(joinSql, /min\(listing\.price_pkn\) as lowest_price_pkn/);
  assert.match(joinSql, /array_agg\(nullif\(listing\.grading_company, ''\)/);
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

test('slug match clause folds accents in database fields', () => {
  const values = [];
  const clause = slugMatchClause(
    'card-poliwhirl-176-165-pokemon-card-151',
    values,
    { collectorNumberSql: 'projected_expansion_number' },
  );

  assert.match(clause, /replace\(lower\(coalesce\(versions\.expansion_name/);
  assert.ok(values.includes('%pokemon%'));
  assert.ok(values.includes('%151%'));
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
