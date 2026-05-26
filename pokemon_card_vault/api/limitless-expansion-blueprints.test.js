const assert = require('node:assert/strict');
const test = require('node:test');

const {
  _test: {
    expansionBlueprintRows,
    normalizeCode,
  },
} = require('./limitless-expansion-blueprints');

test('limitless expansion blueprint API filters by set code and includes blueprints', async () => {
  const calls = [];
  const rows = await expansionBlueprintRows({
    setCode: 'TWM',
    includeBlueprints: true,
    query: async (sql, values) => {
      calls.push({ sql, values });
      assert.match(sql, /limitless_marketplace_expansions/);
      assert.match(sql, /limitless_marketplace_expansion_blueprints/);
      assert.equal(values[0], true);
      assert.equal(values[1], 'twm');
      return {
        rows: [
          {
            expansion_key: 'twilightmasquerade:twm',
            pokoin_expansion_name: 'Twilight Masquerade',
            pokoin_expansion_code: 'TWM',
            limitless_expansion_name: 'Twilight Masquerade',
            limitless_expansion_code: 'TWM',
            aliases: ['Twilight Masquerade', 'TWM'],
            blueprint_count: 1,
            blueprints: [
              {
                blueprintId: '287830',
                name: 'Dreepy',
                collectorNumber: '128/167',
                setCode: 'TWM',
              },
            ],
          },
        ],
      };
    },
  });

  assert.equal(calls.length, 1);
  assert.equal(rows[0].pokoinExpansionName, 'Twilight Masquerade');
  assert.equal(rows[0].blueprints[0].name, 'Dreepy');
});

test('limitless expansion code normalization is compact and lowercase', () => {
  assert.equal(normalizeCode(' TWM '), 'twm');
  assert.equal(normalizeCode('SV-P'), 'svp');
});
