const assert = require('node:assert/strict');
const Module = require('node:module');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

function loadDebugArtistsWithStubs() {
  const target = require.resolve('./marketplace-debug-artists');
  const originalLoad = Module._load;
  delete require.cache[target];
  Module._load = function load(request, parent, isMain) {
    if (request === './_marketplace_db') {
      return {
        getMarketplacePool: () => {
          throw new Error('database should not be used by helper tests');
        },
        marketplaceQuery: async () => {
          throw new Error('database should not be used by helper tests');
        },
      };
    }
    if (request === './_search_debug_auth') {
      return {
        authorizeSearchDebugRequest: async () => ({
          uid: 'debug-user',
          email: 'debug@example.com',
          username: 'debugger',
        }),
      };
    }
    return originalLoad.apply(this, arguments);
  };
  try {
    return require('./marketplace-debug-artists');
  } finally {
    Module._load = originalLoad;
    delete require.cache[target];
  }
}

test('artist debug normalizes artist keys conservatively', () => {
  const { _test } = loadDebugArtistsWithStubs();

  assert.equal(_test.normalizeArtistKey('  Naïto   Komiya  '), 'naito komiya');
  assert.equal(_test.normalizeArtistKey('Ryo Ueda'), 'ryo ueda');
});

test('artist debug clamps unsafe blueprint ids and product types', () => {
  const { _test } = loadDebugArtistsWithStubs();

  assert.equal(_test.cleanBlueprintId('316600'), 316600);
  assert.equal(_test.cleanBlueprintId('-1'), 0);
  assert.equal(_test.cleanBlueprintId('1.2'), 0);
  assert.equal(_test.cleanProductType('Elite Trainer Box'), 'elite_trainer_box');
  assert.equal(_test.cleanProductType('card'), 'sealed_product');
});

test('artist debug serializes missing and low-confidence candidates', () => {
  const { _test } = loadDebugArtistsWithStubs();

  assert.equal(_test.missingReason({ current_artist: '' }), 'missing_artist');
  assert.equal(
    _test.missingReason({ current_artist: 'Ryo Ueda', current_confidence: 0.5 }),
    'low_confidence_artist',
  );

  const payload = _test.serializeCandidate(
    {
      card_id: 316600,
      name: 'Leafeon',
      canonical_name: 'Leafeon',
      set_name: 'Prismatic Evolutions',
      card_number: '005/131',
      image_url: 'https://cdn.example/card.png',
      current_artist: '',
    },
    [{ normalizedArtist: 'aky cg works', artist: 'aky CG Works', knownCount: 2 }],
  );

  assert.equal(payload.blueprintId, '316600');
  assert.equal(payload.missingReason, 'missing_artist');
  assert.equal(payload.artists.length, 1);
});

test('artist debug SQL casts ambiguous placeholders', () => {
  const source = fs.readFileSync(
    path.join(__dirname, 'marketplace-debug-artists.js'),
    'utf8',
  );

  assert.doesNotMatch(source, /nullif\(\$\d+,\s*''\)/);
  assert.doesNotMatch(source, /limit\s+\$\d+(?!::)/i);
  assert.doesNotMatch(source, /where\s+card_id\s*=\s*\$\d+(?!::)/i);
  assert.match(source, /\$1::bigint as blueprint_id,\s*\$2::text as product_type/);
  assert.match(source, /'product'::text,\s*product_type,/);
  assert.match(source, /'single'::text,\s*'card'::text,\s*source,/);
  assert.match(source, /update public\.marketplace_search_candidates as candidates/);
  assert.match(source, /where candidates\.card_id = input\.blueprint_id/);
});
