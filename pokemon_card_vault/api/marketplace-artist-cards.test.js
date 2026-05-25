const assert = require('node:assert/strict');
const test = require('node:test');

const {
  artistCardsForSlug,
  artistProfileFromRow,
  artistSummaries,
  lookupAliasesForArtistName,
  normalizeArtistLookupName,
  normalizeArtistSlug,
  slugAliasesForArtistSlug,
  projectedRaritySql,
} = require('./marketplace-artist-cards');

test('artist endpoint normalizes URL slug and raw artist lookup keys', () => {
  assert.equal(normalizeArtistSlug('Raita Kazama'), 'raita-kazama');
  assert.equal(normalizeArtistSlug(' raita_kazama!! '), 'raita-kazama');
  assert.equal(normalizeArtistLookupName('Raita-Kazama'), 'raita kazama');
  assert.equal(normalizeArtistLookupName('  Raita   Kazama  '), 'raita kazama');
});

test('artist endpoint keeps Pikachu Project slug aliases compatible', async () => {
  assert.deepEqual(lookupAliasesForArtistName('Pikachu Project'), [
    'pikachu project',
    '2017 pikachu project',
    'pikachu project 2017',
  ]);
  assert.deepEqual(slugAliasesForArtistSlug('2017-pikachu-project'), [
    '2017-pikachu-project',
    'pikachu-project-2017',
  ]);
  assert.deepEqual(slugAliasesForArtistSlug('pikachu-project'), [
    'pikachu-project',
    '2017-pikachu-project',
    'pikachu-project-2017',
  ]);
  assert.deepEqual(slugAliasesForArtistSlug('pikachu-project-2017'), [
    'pikachu-project-2017',
    '2017-pikachu-project',
  ]);

  const queries = [];
  const payload = await artistCardsForSlug({
    artistSlug: 'pikachu-project',
    limit: 5,
    query: async (sql, values) => {
      queries.push({ sql, values });
      return {
        rows: [
          {
            card_id: '123',
            name: 'Pikachu',
            expansion_name: 'Promo',
            expansion_number: 'SM-P',
            blueprint_id: '123',
            preview_image_url: 'https://cdn.pokoin.test/pikachu.webp',
            artist: '2017 Pikachu Project',
            illustrator: '2017 Pikachu Project',
            normalized_artist: '2017 pikachu project',
            artist_slug: '2017-pikachu-project',
            artist_card_count: 7,
            total_artist_card_count: 7,
          },
        ],
      };
    },
  });

  assert.match(queries[0].sql, /any\(\$1::text\[\]\)/);
  assert.deepEqual(queries[0].values, [
    ['pikachu-project', '2017-pikachu-project', 'pikachu-project-2017'],
    5,
  ]);
  assert.equal(payload.artist.name, 'Pikachu Project');
  assert.equal(payload.artist.normalizedArtist, '2017 pikachu project');
  assert.equal(payload.artist.slug, '2017-pikachu-project');
  assert.equal(payload.profile.displayName, 'Pikachu Project');
  assert.equal(payload.cards[0].artist, 'Pikachu Project');
  assert.equal(payload.cards[0].normalized_artist, '2017 pikachu project');
});

test('artist endpoint resolves Tomokazu Komiya slug without aliases', async () => {
  assert.deepEqual(lookupAliasesForArtistName('Tomokazu Komiya'), [
    'tomokazu komiya',
  ]);
  assert.deepEqual(slugAliasesForArtistSlug('tomokazu-komiya'), [
    'tomokazu-komiya',
  ]);

  const queries = [];
  const payload = await artistCardsForSlug({
    artistSlug: 'tomokazu-komiya',
    limit: 300,
    query: async (sql, values) => {
      queries.push({ sql, values });
      return {
        rows: [
          {
            card_id: '261118',
            name: 'Gastly',
            expansion_name: '151',
            expansion_number: '092/165',
            blueprint_id: '261118',
            preview_image_url: 'https://cdn.pokoin.test/gastly.webp',
            artist: 'Tomokazu Komiya',
            illustrator: 'Tomokazu Komiya',
            normalized_artist: 'tomokazu komiya',
            artist_slug: 'tomokazu-komiya',
            artist_card_count: 0,
            total_artist_card_count: 261,
          },
        ],
      };
    },
  });

  assert.deepEqual(queries[0].values, [['tomokazu-komiya'], 300]);
  assert.equal(payload.artist.name, 'Tomokazu Komiya');
  assert.equal(payload.artist.normalizedArtist, 'tomokazu komiya');
  assert.equal(payload.artist.slug, 'tomokazu-komiya');
  assert.equal(payload.artist.cardCount, 261);
  assert.equal(payload.cards[0].artist, 'Tomokazu Komiya');
});

test('artist card lookup filters by normalized artist slug and preserves card rows', async () => {
  const queries = [];
  const payload = await artistCardsForSlug({
    artistSlug: 'Raita Kazama',
    limit: 5,
    query: async (sql, values) => {
      queries.push({ sql, values });
      return {
        rows: [
          {
            card_id: '370923',
            name: "N's Zoroark ex",
            expansion_name: 'Ascended Heroes',
            expansion_number: '',
            blueprint_id: '370923',
            canonical_path:
              '/marketplace/en/cards/741846/card-n-s-zoroark-ex-ascended-heroes',
            preview_image_url: 'https://cdn.pokoin.test/zoroark.webp',
            artist: 'Raita Kazama',
            illustrator: 'Raita Kazama',
            normalized_artist: 'raita kazama',
            artist_slug: 'raita-kazama',
            artist_card_count: 0,
            total_artist_card_count: 2,
            profile_display_name: 'Raita Kazama',
            profile_summary: 'Japanese illustrator.',
            profile_bio: 'Illustrator known for dynamic Pokemon card art.',
            profile_image_url: 'https://example.test/raita.jpg',
            profile_image_cdn_url: 'https://cdn.pokoin.test/artists/raita.webp',
            profile_image_object_key: 'artist-profiles/raita-kazama.webp',
            profile_pocketmonsters_url: 'https://www.pocketmonsters.net/staff/view/7159',
            profile_pocketmonsters_id: '7159',
            profile_bulbapedia_url: 'https://bulbapedia.bulbagarden.net/wiki/Raita_Kazama',
            profile_bulbapedia_title: 'Raita Kazama',
            profile_source_name: 'PocketMonsters.Net + Bulbapedia',
            profile_source_url: 'https://www.pocketmonsters.net/staff/view/7159',
            profile_source_attribution: {
              pocketmonsters: {
                name: 'PocketMonsters.Net',
                url: 'https://www.pocketmonsters.net/staff/view/7159',
              },
              bulbapedia: {
                name: 'Bulbapedia',
                url: 'https://bulbapedia.bulbagarden.net/wiki/Raita_Kazama',
                license: 'CC BY-NC-SA',
              },
            },
          },
        ],
      };
    },
  });

  assert.equal(queries.length, 1);
  assert.match(queries[0].sql, /marketplace_blueprint_artists/);
  assert.match(queries[0].sql, /marketplace_card_versions/);
  assert.match(queries[0].sql, /marketplace_card_urls urls/);
  assert.match(queries[0].sql, /urls\.canonical_path/);
  assert.match(queries[0].sql, /total_artist_card_count/);
  assert.deepEqual(queries[0].values, [['raita-kazama'], 5]);
  assert.deepEqual(payload.artist, {
    name: 'Raita Kazama',
    illustrator: 'Raita Kazama',
    normalizedArtist: 'raita kazama',
    slug: 'raita-kazama',
    cardCount: 2,
  });
  assert.deepEqual(payload.profile, {
    displayName: 'Raita Kazama',
    summary: 'Japanese illustrator.',
    bio: 'Illustrator known for dynamic Pokemon card art.',
    imageUrl: 'https://cdn.pokoin.test/artists/raita.webp',
    sourceImageUrl: 'https://example.test/raita.jpg',
    imageObjectKey: 'artist-profiles/raita-kazama.webp',
    pocketmonstersUrl: 'https://www.pocketmonsters.net/staff/view/7159',
    pocketmonstersId: '7159',
    bulbapediaUrl: 'https://bulbapedia.bulbagarden.net/wiki/Raita_Kazama',
    bulbapediaTitle: 'Raita Kazama',
    sourceName: 'PocketMonsters.Net + Bulbapedia',
    sourceUrl: 'https://www.pocketmonsters.net/staff/view/7159',
    sourceAttribution: {
      pocketmonsters: {
        name: 'PocketMonsters.Net',
        url: 'https://www.pocketmonsters.net/staff/view/7159',
      },
      bulbapedia: {
        name: 'Bulbapedia',
        url: 'https://bulbapedia.bulbagarden.net/wiki/Raita_Kazama',
        license: 'CC BY-NC-SA',
      },
    },
    generatedProfileImage: {},
  });
  assert.equal(payload.cards.length, 1);
  assert.equal(payload.cards[0].card_id, '370923');
  assert.equal(
    payload.cards[0].canonical_path,
    '/marketplace/en/cards/741846/card-n-s-zoroark-ex-ascended-heroes',
  );
});

test('artist card lookup projects illustration rarity from collector labels', async () => {
  const payload = await artistCardsForSlug({
    artistSlug: 'Mitsuhiro Arita',
    limit: 5,
    query: async (sql, values) => {
      assert.match(sql, /split_part/);
      assert.match(sql, /as rarity/);
      assert.deepEqual(values, [['mitsuhiro-arita'], 5]);
      return {
        rows: [
          {
            card_id: '261310',
            name: 'Squirtle',
            expansion_name: '151',
            expansion_number: 'Illustration Rare | 170/165',
            blueprint_id: '261310',
            preview_image_url: 'https://cdn.pokoin.test/squirtle.webp',
            artist: 'Mitsuhiro Arita',
            illustrator: 'Mitsuhiro Arita',
            normalized_artist: 'mitsuhiro arita',
            artist_slug: 'mitsuhiro-arita',
            artist_card_count: 768,
            total_artist_card_count: 768,
            rarity: 'Illustration Rare',
          },
        ],
      };
    },
  });

  assert.equal(payload.cards[0].rarity, 'Illustration Rare');
});

test('projected rarity SQL derives rarity from collector labels when stored rarity is generic', () => {
  const sql = projectedRaritySql({
    rarityColumn: 'candidates.rarity',
    collectorNumberSql: 'versions.expansion_number',
  });

  assert.match(sql, /split_part\(versions\.expansion_number, '\|', 1\)/);
  assert.match(sql, /lower\(candidates\.rarity\) = 'card'/);
  assert.match(sql, /sourceCard,rarity/);
});

test('artist profile row mapping is stable with empty profile fields', () => {
  assert.deepEqual(artistProfileFromRow({}), {
    displayName: '',
    summary: '',
    bio: '',
    imageUrl: '',
    sourceImageUrl: '',
    imageObjectKey: '',
    pocketmonstersUrl: '',
    pocketmonstersId: '',
    bulbapediaUrl: '',
    bulbapediaTitle: '',
    sourceName: '',
    sourceUrl: '',
    sourceAttribution: {},
    generatedProfileImage: {},
  });
});

test('artist profile row mapping does not duplicate summary into bio', () => {
  const profile = artistProfileFromRow({
    profile_summary:
      'You Iribi is an illustrator for the Pokémon Trading Card Game.',
    profile_bio: '',
  });

  assert.equal(
    profile.summary,
    'You Iribi is an illustrator for the Pokémon Trading Card Game.',
  );
  assert.equal(profile.bio, '');
});

test('artist profile row mapping rewrites blocked CDN profile images', () => {
  const profile = artistProfileFromRow({
    profile_image_cdn_url: 'https://cdn.pokoin.com/artist-profiles/shin-nagasawa.png',
    profile_image_url: 'https://media.pocketmonsters.net/staff/6960/main.png/t/250.png',
  });

  assert.equal(
    profile.imageUrl,
    'https://pokoin.com/card-images/artist-profiles/shin-nagasawa.png',
  );
  assert.equal(
    profile.sourceImageUrl,
    'https://media.pocketmonsters.net/staff/6960/main.png/t/250.png',
  );
});

test('artist profile row mapping exposes generated card art attribution', () => {
  const profile = artistProfileFromRow({
    profile_image_cdn_url: 'https://pokoin.com/card-images/artist-profiles/aky-cg-works.png',
    profile_source_attribution: {
      generatedProfileImage: {
        source: 'card_art_fallback',
        reason: 'placeholder_profile_image',
        sourceCard: {
          cardId: '123',
          name: 'Pikachu ex',
          rarity: 'Illustration Rare',
        },
      },
    },
  });

  assert.equal(profile.generatedProfileImage.reason, 'placeholder_profile_image');
  assert.equal(profile.generatedProfileImage.sourceCard.name, 'Pikachu ex');
});

test('artist summaries expose persisted artist card counts', async () => {
  const queries = [];
  const payload = await artistSummaries({
    limit: 10,
    query: async (sql, values) => {
      queries.push({ sql, values });
      return {
        rows: [
          {
            artist: 'Raita Kazama',
            illustrator: 'Raita Kazama',
            normalized_artist: 'raita kazama',
            artist_slug: 'raita-kazama',
            artist_card_count: 213,
            image_url: 'https://cdn.pokoin.test/raita.webp',
          },
        ],
      };
    },
  });

  assert.equal(queries.length, 1);
  assert.match(queries[0].sql, /artist\.artist_card_count/);
  assert.match(queries[0].sql, /marketplace_card_versions/);
  assert.deepEqual(queries[0].values, [10]);
  assert.deepEqual(payload, [
    {
      name: 'Raita Kazama',
      illustrator: 'Raita Kazama',
      normalizedArtist: 'raita kazama',
      slug: 'raita-kazama',
      cardCount: 213,
      imageUrl: 'https://cdn.pokoin.test/raita.webp',
      profileImageUrl: '',
    },
  ]);
});
