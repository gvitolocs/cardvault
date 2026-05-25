const assert = require('node:assert/strict');
const test = require('node:test');

const {
  normalizeArtistQuery,
  normalizeArtistSlug,
  searchArtistSuggestions,
} = require('./marketplace-artist-suggestions');

test('artist suggestions normalize query and slug keys', () => {
  assert.equal(normalizeArtistQuery('  Raita-Kazama!! '), 'raita kazama');
  assert.equal(normalizeArtistQuery('Mitsuhiro Arita'), 'mitsuhiro arita');
  assert.equal(normalizeArtistSlug('Mitsuhiro Arita'), 'mitsuhiro-arita');
});

test('artist suggestions query artist profiles and blueprint artists', async () => {
  const queries = [];
  const artists = await searchArtistSuggestions({
    query: 'ari',
    limit: 8,
    queryFn: async (sql, values) => {
      queries.push({ sql, values });
      return {
        rows: [
          {
            artist: 'Mitsuhiro Arita',
            normalized_artist: 'mitsuhiro arita',
            known_count: 312,
            profile_image_url: 'https://example.test/arita.jpg',
          },
        ],
      };
    },
  });

  assert.equal(queries.length, 1);
  assert.match(queries[0].sql, /marketplace_blueprint_artists/);
  assert.match(queries[0].sql, /marketplace_artist_profiles/);
  assert.deepEqual(queries[0].values, [
    'ari',
    'ari%',
    '% ari%',
    '%ari%',
    '%ari%',
    '%a%r%i%',
    8,
  ]);
  assert.deepEqual(artists, [
    {
      name: 'Mitsuhiro Arita',
      normalizedArtist: 'mitsuhiro arita',
      slug: 'mitsuhiro-arita',
      knownCount: 312,
      cardCount: 312,
      imageUrl: 'https://example.test/arita.jpg',
      profileImageUrl: 'https://example.test/arita.jpg',
    },
  ]);
});

test('artist suggestions display Pikachu Project without changing lookup key', async () => {
  const artists = await searchArtistSuggestions({
    query: 'pikachu project',
    limit: 8,
    queryFn: async () => ({
      rows: [
        {
          artist: '2017 Pikachu Project',
          normalized_artist: '2017 pikachu project',
          known_count: 7,
          profile_image_url: '',
        },
      ],
    }),
  });

  assert.deepEqual(artists, [
    {
      name: 'Pikachu Project',
      normalizedArtist: '2017 pikachu project',
      slug: '2017-pikachu-project',
      knownCount: 7,
      cardCount: 7,
      imageUrl: '',
      profileImageUrl: '',
    },
  ]);
});
