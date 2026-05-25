const assert = require('node:assert/strict');
const test = require('node:test');

const {
  rowsForExpansions,
  snapshotForExpansion,
} = require('./marketplace-expansions');

test('marketplace expansions exposes full logo URL beside symbol URL', async () => {
  const queries = [];
  const rows = await rowsForExpansions({
    slug: null,
    limit: 10,
    query: async (sql, values) => {
      queries.push({ sql, values });
      return {
        rows: [
          {
            name: 'Prismatic Evolutions',
            symbol_image_url: 'https://cdn.pokoin.test/expansions/symbols/prismatic-evolutions.png',
            logo_image_url: 'https://cdn.pokoin.test/expansions/logos/prismatic-evolutions.png',
            card_count: 131,
          },
        ],
      };
    },
  });

  assert.match(queries[0].sql, /logo_image_url/);
  assert.deepEqual(rows[0], {
    name: 'Prismatic Evolutions',
    slug: 'prismatic-evolutions',
    symbolImageUrl: 'https://cdn.pokoin.test/expansions/symbols/prismatic-evolutions.png',
    logoImageUrl: 'https://cdn.pokoin.test/expansions/logos/prismatic-evolutions.png',
    defaultSymbolUrl: 'https://cdn.pokoin.com/expansions/symbols/prismatic-evolutions.png',
    cardCount: 131,
  });
});

test('marketplace expansion snapshot carries logo URL on card rows', async () => {
  const payload = await snapshotForExpansion({
    slug: 'prismatic-evolutions',
    limit: 10,
    query: async (sql) => {
      if (/count\(\*\)::integer as card_count/.test(sql)) {
        return {
          rows: [
            {
              name: 'Prismatic Evolutions',
              symbol_image_url: 'https://cdn.pokoin.test/expansions/symbols/prismatic-evolutions.png',
              logo_image_url: 'https://cdn.pokoin.test/expansions/logos/prismatic-evolutions.png',
              card_count: 131,
            },
          ],
        };
      }
      assert.match(sql, /expansion_logo_url/);
      assert.match(sql, /marketplace_card_urls urls/);
      assert.match(sql, /urls\.canonical_path/);
      return {
        rows: [
          {
            card_id: '316698',
            name: 'Fan Rotom',
            canonical_path:
              '/marketplace/en/cards/633396/card-fan-rotom-085-131-prismatic-evolutions',
            expansion_symbol_url: 'https://cdn.pokoin.test/expansions/symbols/prismatic-evolutions.png',
            expansion_logo_url: 'https://cdn.pokoin.test/expansions/logos/prismatic-evolutions.png',
          },
        ],
      };
    },
  });

  assert.equal(payload.cards[0].expansion_logo_url, 'https://cdn.pokoin.test/expansions/logos/prismatic-evolutions.png');
  assert.equal(
    payload.cards[0].canonical_path,
    '/marketplace/en/cards/633396/card-fan-rotom-085-131-prismatic-evolutions',
  );
});
