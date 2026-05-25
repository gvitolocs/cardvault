const assert = require('node:assert/strict');
const test = require('node:test');

const {
  defaultLogoUrl,
  defaultSymbolUrl,
  listExpansionSymbols,
  objectKeyFromCdnUrl,
} = require('./marketplace-expansion-symbols');

test('admin expansion endpoint exposes separate default symbol and logo URLs', () => {
  assert.equal(
    defaultSymbolUrl('Prismatic Evolutions'),
    'https://cdn.pokoin.com/expansions/symbols/prismatic-evolutions.png',
  );
  assert.equal(
    defaultLogoUrl('Prismatic Evolutions'),
    'https://cdn.pokoin.com/expansions/logos/prismatic-evolutions.png',
  );
});

test('admin expansion endpoint derives object keys for CDN assets', () => {
  assert.equal(
    objectKeyFromCdnUrl(
      'https://cdn.pokoin.com/expansions/symbols/prismatic-evolutions.png',
      'expansions/symbols',
    ),
    'expansions/symbols/prismatic-evolutions.png',
  );
  assert.equal(
    objectKeyFromCdnUrl(
      'https://cdn.pokoin.com/expansions/logos/prismatic-evolutions.png',
      'expansions/logos',
    ),
    'expansions/logos/prismatic-evolutions.png',
  );
});

test('admin expansion endpoint returns editable full logo fields', async () => {
  const rows = await listExpansionSymbols({
    limit: 5,
    dbQuery: async (sql) => {
      assert.match(sql, /logo_image_url/);
      assert.match(sql, /logo_object_key/);
      return {
        rows: [
          {
            name: 'Prismatic Evolutions',
            expansion_id: 2000,
            code: 'pre',
            source_asset_code: 'sv8pt5',
            symbol_image_url: 'https://cdn.pokoin.test/expansions/symbols/prismatic-evolutions.png',
            symbol_object_key: 'expansions/symbols/prismatic-evolutions.png',
            logo_image_url: 'https://cdn.pokoin.test/expansions/logos/prismatic-evolutions.png',
            logo_object_key: 'expansions/logos/prismatic-evolutions.png',
            card_count: 131,
          },
        ],
      };
    },
  });

  assert.equal(rows[0].logoImageUrl, 'https://cdn.pokoin.test/expansions/logos/prismatic-evolutions.png');
  assert.equal(rows[0].logoObjectKey, 'expansions/logos/prismatic-evolutions.png');
});
