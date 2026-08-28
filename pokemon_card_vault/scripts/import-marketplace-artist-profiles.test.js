const assert = require('node:assert/strict');
const test = require('node:test');

const {
  auditArtistProfileImageCache,
  getArtistR2Config,
  normalizeArtist,
  parsePocketMonstersProfile,
  parsePocketMonstersStaffIndex,
  parseArgs,
  fetchBulbapediaSummaryForArtist,
  mergeProfileParts,
  recacheMissingArtistProfileImages,
  trustedPocketMonstersProfileFromStaff,
  trustedProfileForArtist,
  trustedPocketMonstersProfileForArtist,
} = require('./import-marketplace-artist-profiles');

test('artist profile importer is dry-run by default', () => {
  assert.equal(parseArgs([]).apply, false);
  assert.equal(parseArgs(['--apply']).apply, true);
  assert.equal(parseArgs(['--limit=all']).limit, Infinity);
  assert.equal(parseArgs(['--language=ja']).language, 'ja');
  assert.equal(parseArgs(['--source=pocketmonsters']).source, 'pocketmonsters');
  assert.equal(parseArgs(['--concurrency=4']).concurrency, 4);
  assert.deepEqual(parseArgs(['--artist=Raita Kazama']).artistKeys, ['raita kazama']);
  assert.equal(
    parseArgs(['--pocketmonsters-id=7159']).pocketmonstersUrl,
    'https://www.pocketmonsters.net/staff/view/7159',
  );
  assert.equal(parseArgs(['--audit-image-cache']).auditImageCache, true);
  assert.equal(parseArgs(['--recache-missing-images']).recacheMissingImages, true);
});

test('artist profile normalization matches artist table keys', () => {
  assert.equal(normalizeArtist('Narumi-Sato'), 'narumi sato');
  assert.equal(normalizeArtist('  Keiichiro   Ito  '), 'keiichiro ito');
});

test('artist profile R2 URLs default to same-origin image proxy', async () => {
  const { publicUrlForKey } = require('./import-marketplace-artist-profiles');
  const config = getArtistR2Config({
    CLOUDFLARE_ACCOUNT_ID: 'account',
    R2_ACCESS_KEY_ID: 'key',
    R2_SECRET_ACCESS_KEY: 'secret',
    POKOIN_ARTIST_PROFILE_IMAGES_PUBLIC_URL: 'https://cdn.pokoin.com',
  });

  assert.equal(
    publicUrlForKey(config, 'artist-profiles/shin-nagasawa.png'),
    'https://pokoin.com/card-images/artist-profiles/shin-nagasawa.png',
  );
});

test('trusted profile parser maps sourced Wikipedia data', async () => {
  const requests = [];
  const responses = [
    {
      search: [
        {
          id: 'Q123',
          label: 'Narumi Sato',
          description: 'Japanese illustrator',
          aliases: [],
        },
      ],
    },
    {
      entities: {
        Q123: {
          labels: { en: { value: 'Narumi Sato' } },
          descriptions: { en: { value: 'Japanese illustrator' } },
          claims: {},
          sitelinks: { enwiki: { title: 'Narumi Sato' } },
        },
      },
    },
    {
      title: 'Narumi Sato',
      extract: 'Narumi Sato is an illustrator.',
      originalimage: { source: 'https://img.test/narumi.jpg' },
      content_urls: {
        desktop: { page: 'https://en.wikipedia.org/wiki/Narumi_Sato' },
      },
    },
  ];
  const profile = await trustedProfileForArtist(
    {
      artist: 'Narumi Sato',
      normalized_artist: 'narumi sato',
    },
    {
      fetchImpl: async (url, options) => {
        requests.push({ url: String(url), options });
        return {
          ok: true,
          async json() {
            return responses.shift();
          },
        };
      },
    },
  );

  assert.equal(requests.length, 3);
  assert.match(requests[0].url, /wikidata\.org\/w\/api\.php/);
  assert.match(requests[2].url, /wikipedia\.org\/api\/rest_v1\/page\/summary/);
  assert.equal(requests[0].options.headers['User-Agent'].includes('Pokoin'), true);
  assert.deepEqual(profile, {
    normalizedArtist: 'narumi sato',
    displayName: 'Narumi Sato',
    summary: '',
    bio: 'Narumi Sato is an illustrator.',
    profileImageUrl: 'https://img.test/narumi.jpg',
    profileImageCdnUrl: '',
    profileImageObjectKey: '',
    pocketmonstersUrl: '',
    pocketmonstersId: '',
    bulbapediaUrl: '',
    bulbapediaTitle: '',
    sourceName: 'Wikipedia',
    sourceUrl: 'https://en.wikipedia.org/wiki/Narumi_Sato',
    sourceAttribution: {
      wikidata: {
        name: 'Wikipedia/Wikidata',
        url: 'https://en.wikipedia.org/wiki/Narumi_Sato',
        wikidataId: 'Q123',
      },
    },
    rawMetadata: {
      wikidataId: 'Q123',
      title: 'Narumi Sato',
      fetchedAt: profile.rawMetadata.fetchedAt,
    },
  });
});

test('trusted profile parser skips fuzzy non-artist results', async () => {
  const profile = await trustedProfileForArtist(
    { artist: 'Unknown Artist', normalized_artist: 'unknown artist' },
    {
      fetchImpl: async () => ({
        ok: true,
        async json() {
          return {
            search: [
              {
                id: 'Q999',
                label: 'Unknown',
                description: 'song',
                aliases: [],
              },
            ],
          };
        },
      }),
    },
  );
  assert.equal(profile, null);
});

test('PocketMonsters staff index parser reads TCG artist links', () => {
  const rows = parsePocketMonstersStaffIndex(`
    <td><a href="https://www.pocketmonsters.net/staff/view/7171">matazo</a></td>
    <td><a href="https://www.pocketmonsters.net/staff/view/7098">&quot;Big Mama&quot; Tagawa</a></td>
  `);
  assert.deepEqual(rows, [
    {
      name: 'matazo',
      normalizedArtist: 'matazo',
      sourceUrl: 'https://www.pocketmonsters.net/staff/view/7171',
    },
    {
      name: '"Big Mama" Tagawa',
      normalizedArtist: 'big mama tagawa',
      sourceUrl: 'https://www.pocketmonsters.net/staff/view/7098',
    },
  ]);
});

test('PocketMonsters profile parser maps biography and staff image', () => {
  const profile = parsePocketMonstersProfile(
    `
      <h2 class="border-b-0 font-bold m-0 pr-4">matazo</h2>
      <img src="//media.pocketmonsters.net/staff/7171/main.png/t/250.png">
      <div id="Biography">
        <div class="header-block">Biography</div>
        <div class="bg-white">
          matazo is an artist for the TCG.
          <br>
          <h2 id="2025_Highlight">Highlighting the Talented Artists</h2>
        </div>
      </div>
      <div id="TCG">
      </div>
    `,
    'https://www.pocketmonsters.net/staff/view/7171',
  );
  assert.equal(profile.displayName, 'matazo');
  assert.equal(profile.bio, 'matazo is an artist for the TCG. Highlighting the Talented Artists');
  assert.equal(
    profile.profileImageUrl,
    'https://media.pocketmonsters.net/staff/7171/main.png/t/250.png',
  );
  assert.equal(profile.sourceName, 'PocketMonsters.Net');
  assert.equal(profile.sourceUrl, 'https://www.pocketmonsters.net/staff/view/7171');
  assert.equal(profile.pocketmonstersId, '7171');
});

test('PocketMonsters trusted profile matches only existing artist names', async () => {
  const profile = await trustedPocketMonstersProfileForArtist(
    { artist: 'matazo', normalized_artist: 'matazo' },
    {
      staffByArtist: new Map([
        [
          'matazo',
          {
            name: 'matazo',
            normalizedArtist: 'matazo',
            sourceUrl: 'https://www.pocketmonsters.net/staff/view/7171',
          },
        ],
      ]),
      fetchImpl: async () => ({
        ok: true,
        async text() {
          return `
            <h1>matazo</h1>
            <img src="//media.pocketmonsters.net/staff/7171/main.png/t/250.png">
            <h3>Biography</h3>
            <p>matazo is an artist for the TCG.</p>
            <h2>Cards</h2>
          `;
        },
      }),
    },
  );
  assert.equal(profile.normalizedArtist, 'matazo');
  assert.equal(profile.displayName, 'matazo');
  assert.equal(profile.sourceName, 'PocketMonsters.Net');
});

test('PocketMonsters trusted profile can import a staff row directly', async () => {
  const profile = await trustedPocketMonstersProfileFromStaff(
    {
      name: 'matazo',
      normalizedArtist: 'matazo',
      sourceUrl: 'https://www.pocketmonsters.net/staff/view/7171',
    },
    {
      fetchImpl: async () => ({
        ok: true,
        async text() {
          return `
            <h1>matazo</h1>
            <h3>Biography</h3>
            <p>matazo is an artist for the TCG.</p>
            <h2>Cards</h2>
          `;
        },
      }),
    },
  );
  assert.equal(profile.normalizedArtist, 'matazo');
  assert.equal(profile.displayName, 'matazo');
  assert.equal(profile.sourceUrl, 'https://www.pocketmonsters.net/staff/view/7171');
});

test('direct PocketMonsters import reports unknown artist instead of inserting', async () => {
  const result = await require('./import-marketplace-artist-profiles').importPocketMonstersArtistProfiles({
    pool: {
      async query() {
        return { rows: [] };
      },
    },
    options: {
      source: 'pocketmonsters',
      limit: 1,
      concurrency: 1,
      artistKeys: [],
      pocketmonstersUrl: 'https://www.pocketmonsters.net/staff/view/7159',
    },
    fetchImpl: async () => ({
      ok: true,
      async text() {
        return '<h1>Verified Artist</h1>';
      },
    }),
  });

  assert.equal(result.counts.scanned, 1);
  assert.equal(result.counts.skipped, 1);
  assert.equal(result.report[0].reason, 'unknown_artist_not_in_artist_table');
});

test('Bulbapedia summary parser requires exact artist page match', async () => {
  const requests = [];
  const profile = await fetchBulbapediaSummaryForArtist(
    { artist: 'Raita Kazama', normalized_artist: 'raita kazama' },
    {
      fetchImpl: async (url) => {
        requests.push(String(url));
        return {
          ok: true,
          async json() {
            return {
              query: {
                pages: [
                  {
                    title: 'Raita Kazama',
                    extract: 'Raita Kazama is an artist who has illustrated cards for the Pokémon TCG.',
                    fullurl: 'https://bulbapedia.bulbagarden.net/wiki/Raita_Kazama',
                  },
                ],
              },
            };
          },
        };
      },
    },
  );

  assert.equal(requests.length, 1);
  assert.match(requests[0], /bulbapedia\.bulbagarden\.net\/w\/api\.php/);
  assert.equal(profile.normalizedArtist, 'raita kazama');
  assert.equal(profile.title, 'Raita Kazama');
  assert.equal(profile.attribution.license, 'CC BY-NC-SA');
});

test('Bulbapedia summary parser normalizes slug-like artist names', async () => {
  const requests = [];
  const diagnostics = {};
  const profile = await fetchBulbapediaSummaryForArtist(
    { artist: 'you-iribi', normalized_artist: 'you iribi' },
    {
      diagnostics,
      fetchImpl: async (url) => {
        requests.push(String(url));
        return {
          ok: true,
          async json() {
            return {
              query: {
                pages: [
                  {
                    title: 'You Iribi',
                    extract:
                      'You Iribi is an illustrator for the Pokémon Trading Card Game.',
                    fullurl: 'https://bulbapedia.bulbagarden.net/wiki/You_Iribi',
                  },
                ],
              },
            };
          },
        };
      },
    },
  );

  assert.match(requests[0], /titles=you_Iribi|titles=you_iribi/i);
  assert.equal(profile.normalizedArtist, 'you iribi');
  assert.equal(profile.title, 'You Iribi');
  assert.equal(profile.sourceUrl, 'https://bulbapedia.bulbagarden.net/wiki/You_Iribi');
  assert.deepEqual(diagnostics, {});
});

test('Bulbapedia summary parser reports safe skip reasons', async () => {
  const diagnostics = {};
  const profile = await fetchBulbapediaSummaryForArtist(
    { artist: 'Wrong Artist', normalized_artist: 'wrong artist' },
    {
      diagnostics,
      fetchImpl: async () => ({
        ok: true,
        async json() {
          return {
            query: {
              pages: [
                {
                  title: 'Wrong Artist (Trainer)',
                  extract: 'Wrong Artist is a Trainer card.',
                  fullurl: 'https://bulbapedia.bulbagarden.net/wiki/Wrong_Artist_(Trainer)',
                },
              ],
            },
          };
        },
      }),
    },
  );

  assert.equal(profile, null);
  assert.equal(diagnostics.reason, 'title_mismatch');
  assert.equal(diagnostics.details.attempts[0].pageTitle, 'Wrong Artist (Trainer)');
});

test('artist profile merge keeps source attribution separate', () => {
  const profile = mergeProfileParts(
    { artist: 'Raita Kazama', normalized_artist: 'raita kazama' },
    {
      pocketmonsters: {
        normalizedArtist: 'raita kazama',
        displayName: 'Raita Kazama',
        bio: 'PocketMonsters biography.',
        profileImageUrl: 'https://media.pocketmonsters.net/staff/7159/main.png',
        pocketmonstersUrl: 'https://www.pocketmonsters.net/staff/view/7159',
        pocketmonstersId: '7159',
        sourceName: 'PocketMonsters.Net',
        sourceUrl: 'https://www.pocketmonsters.net/staff/view/7159',
        sourceAttribution: {
          pocketmonsters: {
            name: 'PocketMonsters.Net',
            url: 'https://www.pocketmonsters.net/staff/view/7159',
          },
        },
        rawMetadata: { pocketmonstersId: '7159' },
      },
      bulbapedia: {
        normalizedArtist: 'raita kazama',
        title: 'Raita Kazama',
        summary: 'Bulbapedia summary.',
        sourceUrl: 'https://bulbapedia.bulbagarden.net/wiki/Raita_Kazama',
        attribution: {
          name: 'Bulbapedia',
          url: 'https://bulbapedia.bulbagarden.net/wiki/Raita_Kazama',
          license: 'CC BY-NC-SA',
        },
      },
    },
  );

  assert.equal(profile.normalizedArtist, 'raita kazama');
  assert.equal(profile.profileImageUrl, 'https://media.pocketmonsters.net/staff/7159/main.png');
  assert.equal(profile.bulbapediaUrl, 'https://bulbapedia.bulbagarden.net/wiki/Raita_Kazama');
  assert.equal(profile.sourceAttribution.bulbapedia.license, 'CC BY-NC-SA');
});

test('Bulbapedia-only import preserves existing profile fields on upsert', async () => {
  const upserts = [];
  const result = await require('./import-marketplace-artist-profiles').importArtistProfiles({
    pool: {
      async query(sql, values) {
        if (/insert into public\.marketplace_artist_profiles/.test(sql)) {
          upserts.push(values);
          return { rows: [] };
        }
        return {
          rows: [
            {
              artist: 'You Iribi',
              illustrator: 'You Iribi',
              normalized_artist: 'you iribi',
              profile_normalized_artist: 'you iribi',
              profile_display_name: 'You Iribi',
              profile_summary: '',
              profile_bio: 'Existing PocketMonsters biography.',
              profile_image_url: 'https://media.pocketmonsters.test/you.png',
              profile_image_cdn_url: 'https://pokoin.com/card-images/artist-profiles/you-iribi.png',
              profile_image_object_key: 'artist-profiles/you-iribi.png',
              profile_pocketmonsters_url: 'https://www.pocketmonsters.net/staff/view/9999',
              profile_pocketmonsters_id: '9999',
              profile_bulbapedia_url: '',
              profile_bulbapedia_title: '',
              profile_source_name: 'PocketMonsters.Net',
              profile_source_url: 'https://www.pocketmonsters.net/staff/view/9999',
              profile_source_attribution: {
                pocketmonsters: {
                  name: 'PocketMonsters.Net',
                  url: 'https://www.pocketmonsters.net/staff/view/9999',
                },
              },
              profile_raw_metadata: { sources: { pocketmonsters: { pocketmonstersId: '9999' } } },
            },
          ],
        };
      },
    },
    options: {
      ...parseArgs(['--apply', '--source=bulbapedia', '--artist=You Iribi', '--limit=1']),
      cacheImages: false,
    },
    fetchImpl: async () => ({
      ok: true,
      async json() {
        return {
          query: {
            pages: [
              {
                title: 'You Iribi',
                extract:
                  'You Iribi is an illustrator for the Pokémon Trading Card Game.',
                fullurl: 'https://bulbapedia.bulbagarden.net/wiki/You_Iribi',
              },
            ],
          },
        };
      },
    }),
  });

  assert.equal(result.counts.upserted, 1);
  assert.equal(result.counts.reasons.matched_bulbapedia, 1);
  assert.equal(upserts.length, 1);
  assert.equal(upserts[0][3], 'Existing PocketMonsters biography.');
  assert.equal(upserts[0][4], 'https://media.pocketmonsters.test/you.png');
  assert.equal(upserts[0][7], 'https://www.pocketmonsters.net/staff/view/9999');
  assert.equal(upserts[0][9], 'https://bulbapedia.bulbagarden.net/wiki/You_Iribi');
  assert.equal(upserts[0][11], 'PocketMonsters.Net + Bulbapedia');
});

test('artist profile image cache audit reports source-only rows', async () => {
  const queries = [];
  const result = await auditArtistProfileImageCache({
    pool: {
      async query(sql, values) {
        queries.push({ sql, values });
        if (/count\(\*\)::int as profile_rows/.test(sql)) {
          return {
            rows: [
              {
                profile_rows: 2,
                source_images: 2,
                cached_images: 1,
                cache_needed: 1,
              },
            ],
          };
        }
        return {
          rows: [
            {
              normalized_artist: 'mitsuhiro arita',
              display_name: 'Mitsuhiro Arita',
              profile_image_url: 'https://media.pocketmonsters.net/staff/6956/main.png/t/250.png',
              profile_image_cdn_url: '',
              profile_image_object_key: '',
              pocketmonsters_url: 'https://www.pocketmonsters.net/staff/view/6956',
              pocketmonsters_id: '6956',
              bulbapedia_url: 'https://bulbapedia.bulbagarden.net/wiki/Mitsuhiro_Arita',
              source_name: 'PocketMonsters.Net',
              source_url: 'https://www.pocketmonsters.net/staff/view/6956',
              updated_at: new Date('2026-05-24T10:00:00Z'),
            },
          ],
        };
      },
    },
    options: parseArgs(['--audit-image-cache', '--artist=Mitsuhiro Arita', '--limit=10']),
  });

  assert.equal(queries.length, 2);
  assert.deepEqual(queries[0].values[0], ['mitsuhiro arita']);
  assert.equal(result.counts.cache_needed, 1);
  assert.equal(result.report[0].normalizedArtist, 'mitsuhiro arita');
  assert.equal(result.report[0].status, 'cache_needed');
});

test('recache missing artist images supports a dry-run report', async () => {
  const result = await recacheMissingArtistProfileImages({
    pool: {
      async query() {
        return {
          rows: [
            {
              normalized_artist: 'mitsuhiro arita',
              display_name: 'Mitsuhiro Arita',
              summary: '',
              bio: '',
              profile_image_url: 'https://media.pocketmonsters.net/staff/6956/main.png/t/250.png',
              profile_image_cdn_url: '',
              profile_image_object_key: '',
              pocketmonsters_url: 'https://www.pocketmonsters.net/staff/view/6956',
              pocketmonsters_id: '6956',
              bulbapedia_url: 'https://bulbapedia.bulbagarden.net/wiki/Mitsuhiro_Arita',
              bulbapedia_title: 'Mitsuhiro Arita',
              source_name: 'PocketMonsters.Net',
              source_url: 'https://www.pocketmonsters.net/staff/view/6956',
              source_attribution: {},
              raw_metadata: {},
            },
          ],
        };
      },
    },
    options: parseArgs(['--recache-missing-images', '--artist=Mitsuhiro Arita', '--limit=1']),
  });

  assert.equal(result.counts.scanned, 1);
  assert.equal(result.counts.imageCacheNeeded, 1);
  assert.equal(result.counts.upserted, 0);
  assert.equal(result.report[0].status, 'matched_dry_run');
  assert.equal(result.report[0].imageCache, 'cache_needed');
});
