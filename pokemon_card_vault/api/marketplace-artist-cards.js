const { marketplaceQuery } = require('./_marketplace_db');
const {
  applyArtistDisplayNameToRow,
  displayNameForArtist,
  lookupAliasesForArtistName,
  normalizeArtistLookupName,
  normalizeArtistSlug,
  slugAliasesForArtistSlug,
} = require('./_artist_display');
const { withCardEmojiFields } = require('./_marketplace_card_emoji');
const { projectedRaritySql } = require('./_marketplace_card_rarity');

function cleanLimit(value, fallback = 240) {
  const limit = Number(value);
  if (!Number.isFinite(limit)) {
    return fallback;
  }
  return Math.min(Math.max(Math.trunc(limit), 1), 1000);
}

function cleanText(value, maxLength = 120) {
  return String(value || '').trim().slice(0, maxLength);
}

function slugSql(column) {
  return `trim(both '-' from regexp_replace(lower(coalesce(${column}, '')), '[^a-z0-9]+', '-', 'g'))`;
}

function normalizedCollectorNumberSql(column) {
  return `coalesce(
    substring(${column} from '([A-Za-z]*[0-9]+[A-Za-z]?\\s*/\\s*[0-9]+)'),
    substring(${column} from '([A-Za-z]{1,4}\\s*[0-9]+)'),
    ${column}
  )`;
}

function sameOriginArtistProfileImageUrl(value) {
  const clean = cleanText(value, 1000);
  if (!clean) return '';
  try {
    const url = new URL(clean);
    if (
      url.hostname === 'cdn.pokoin.com' &&
      url.pathname.startsWith('/artist-profiles/')
    ) {
      return `https://pokoin.com/card-images${url.pathname}`;
    }
  } catch {
    return clean;
  }
  return clean;
}

function projectedExpansionNumberSql() {
  const imageSource = `coalesce(
    versions.cdn_image_url,
    versions.image_url,
    versions.homepage_image_url,
    versions.preview_image_url,
    ''
  )`;
  const imageCollectorNumber = `replace(
    substring(${imageSource} from '([0-9]{1,4}[A-Za-z]?[-/][0-9]{1,4})'),
    '-',
    '/'
  )`;
  return `coalesce(
    nullif(versions.expansion_number, ''),
    nullif(${imageCollectorNumber}, ''),
    versions.expansion_number
  )`;
}

function projectedExpansionNumberIntSql(expansionNumberSql = projectedExpansionNumberSql()) {
  return `coalesce(
    versions.expansion_number_int,
    nullif(substring(${expansionNumberSql} from '([0-9]+)'), '')::integer
  )`;
}

function normalCollectorSql(column) {
  const normalized = normalizedCollectorNumberSql(column);
  return `case
    when ${normalized} ~ '^\\s*[0-9]+[A-Za-z]?\\s*(/[0-9]+)?\\s*$'
    then 0
    else 1
  end`;
}

function artistProfileFromRow(row) {
  const sourceAttribution =
    row.profile_source_attribution && typeof row.profile_source_attribution === 'object'
      ? row.profile_source_attribution
      : {};
  const generatedProfileImage =
    sourceAttribution.generatedProfileImage && typeof sourceAttribution.generatedProfileImage === 'object'
      ? sourceAttribution.generatedProfileImage
      : {};
  const imageUrl = sameOriginArtistProfileImageUrl(
    row.profile_image_cdn_url || row.profile_image_url || '',
  );
  return {
    displayName: displayNameForArtist({
      normalizedArtist: row.normalized_artist,
      profileDisplayName: row.profile_display_name,
      fallbackName: row.artist || row.illustrator,
    }),
    summary: row.profile_summary || '',
    bio: row.profile_bio || '',
    imageUrl,
    sourceImageUrl: row.profile_image_url || '',
    imageObjectKey: row.profile_image_object_key || '',
    pocketmonstersUrl: row.profile_pocketmonsters_url || '',
    pocketmonstersId: row.profile_pocketmonsters_id || '',
    bulbapediaUrl: row.profile_bulbapedia_url || '',
    bulbapediaTitle: row.profile_bulbapedia_title || '',
    sourceName: row.profile_source_name || '',
    sourceUrl: row.profile_source_url || '',
    sourceAttribution,
    generatedProfileImage,
  };
}

async function artistSummaries({ limit, query = marketplaceQuery }) {
  const result = await query(
    `
      select distinct on (artist.normalized_artist)
        artist.artist,
        artist.illustrator,
        artist.normalized_artist,
        ${slugSql('artist.normalized_artist')} as artist_slug,
        artist.artist_card_count,
        profiles.display_name as profile_display_name,
        coalesce(nullif(profiles.profile_image_cdn_url, ''), profiles.profile_image_url) as profile_image_url,
        coalesce(
          versions.preview_image_url,
          versions.homepage_image_url,
          versions.cdn_image_url,
          versions.image_url,
          ''
        ) as image_url
      from public.marketplace_blueprint_artists artist
      join public.marketplace_card_versions versions
        on versions.blueprint_id = artist.blueprint_id
      left join public.marketplace_artist_profiles profiles
        on profiles.normalized_artist = artist.normalized_artist
      where versions.product_type = 'card'
        and coalesce(
          versions.preview_image_url,
          versions.homepage_image_url,
          versions.cdn_image_url,
          versions.image_url
        ) is not null
      order by
        artist.normalized_artist asc,
        versions.projected_at desc nulls last,
        versions.blueprint_id asc
      limit $1
    `,
    [cleanLimit(limit, 1000)],
  );

  return result.rows
    .map((row) => {
      const displayName = displayNameForArtist({
        normalizedArtist: row.normalized_artist,
        profileDisplayName: row.profile_display_name,
        fallbackName: row.artist || row.illustrator,
      });
      return {
      name: displayName || row.artist || row.illustrator || '',
      illustrator: displayName || row.illustrator || row.artist || '',
      normalizedArtist: row.normalized_artist || '',
      slug: row.artist_slug || '',
      cardCount: Number(row.artist_card_count || 0),
      imageUrl: row.image_url || '',
      profileImageUrl: sameOriginArtistProfileImageUrl(row.profile_image_url || ''),
      };
    })
    .filter((row) => row.name && row.slug)
    .sort((a, b) => b.cardCount - a.cardCount || a.name.localeCompare(b.name));
}

async function artistCardsForSlug({ artistSlug, artist, limit, query = marketplaceQuery }) {
  const normalizedSlugs = slugAliasesForArtistSlug(artistSlug);
  const normalizedArtists = lookupAliasesForArtistName(artist);
  const values = [];
  let where =
    'where coalesce(versions.homepage_image_url, versions.preview_image_url, versions.cdn_image_url, versions.image_url) is not null';

  if (normalizedSlugs.length > 0) {
    values.push(normalizedSlugs);
    where += ` and ${slugSql('artist.normalized_artist')} = any($${values.length}::text[])`;
  } else if (normalizedArtists.length > 0) {
    values.push(normalizedArtists);
    where += ` and lower(artist.normalized_artist) = any($${values.length}::text[])`;
  } else {
    return { artist: null, cards: [] };
  }

  values.push(cleanLimit(limit));
  const limitPlaceholder = `$${values.length}`;
  const expansionNumberSql = projectedExpansionNumberSql();
  const expansionNumberIntSql = projectedExpansionNumberIntSql(expansionNumberSql);
  const raritySql = projectedRaritySql({
    rarityColumn: 'candidates.rarity',
    collectorNumberSql: expansionNumberSql,
  });
  const result = await query(
    `
      select
        versions.card_id,
        versions.name,
        versions.expansion_name,
        ${expansionNumberSql} as expansion_number,
        ${expansionNumberIntSql} as expansion_number_int,
        versions.product_variant,
        versions.blueprint_id,
        coalesce(versions.homepage_image_url, versions.preview_image_url, versions.cdn_image_url, versions.image_url, '') as image_url,
        coalesce(versions.homepage_image_url, versions.preview_image_url, versions.cdn_image_url, versions.image_url, '') as cdn_image_url,
        versions.preview_image_url,
        versions.homepage_image_url,
        versions.product_type,
        versions.trainer_name,
        versions.card_palette,
        versions.emoji,
        urls.canonical_path,
        artist.artist,
        artist.illustrator,
        artist.normalized_artist,
        artist.artist_card_count,
        count(*) over ()::integer as total_artist_card_count,
        ${slugSql('artist.normalized_artist')} as artist_slug,
        profiles.display_name as profile_display_name,
        profiles.summary as profile_summary,
        profiles.bio as profile_bio,
        profiles.profile_image_url,
        profiles.profile_image_cdn_url,
        profiles.profile_image_object_key,
        profiles.pocketmonsters_url as profile_pocketmonsters_url,
        profiles.pocketmonsters_id as profile_pocketmonsters_id,
        profiles.bulbapedia_url as profile_bulbapedia_url,
        profiles.bulbapedia_title as profile_bulbapedia_title,
        profiles.source_name as profile_source_name,
        profiles.source_url as profile_source_url,
        profiles.source_attribution as profile_source_attribution,
        ${raritySql} as rarity,
        candidates.card_type,
        versions.projected_at,
        expansions.symbol_image_url as expansion_symbol_url
      from public.marketplace_card_versions versions
      join public.marketplace_blueprint_artists artist
        on artist.blueprint_id = versions.blueprint_id
      left join public.marketplace_artist_profiles profiles
        on profiles.normalized_artist = artist.normalized_artist
      left join public.marketplace_search_candidates candidates
        on candidates.card_id = versions.card_id
      left join public.cardtrader_pokemon_blueprints blueprints
        on blueprints.id = versions.card_id
      left join public.marketplace_blueprint_tcg_metadata tcg_metadata
        on tcg_metadata.blueprint_id = versions.card_id
      left join public.marketplace_card_urls urls
        on urls.card_id = versions.card_id
        and urls.language = 'en'
      left join (
        select name, min(symbol_image_url) as symbol_image_url
        from public.cardtrader_pokemon_expansions
        group by name
      ) expansions
        on expansions.name = versions.expansion_name
      ${where}
      order by
        versions.expansion_name asc,
        ${normalCollectorSql(expansionNumberSql)} asc,
        ${expansionNumberIntSql} asc nulls last,
        ${normalizedCollectorNumberSql(expansionNumberSql)} asc,
        versions.blueprint_id asc nulls last,
        versions.card_id asc
      limit ${limitPlaceholder}
    `,
    values,
  );

  const first = result.rows[0];
  return {
    artist: first
      ? {
          name: displayNameForArtist({
            normalizedArtist: first.normalized_artist,
            profileDisplayName: first.profile_display_name,
            fallbackName: first.artist || first.illustrator,
          }),
          illustrator: displayNameForArtist({
            normalizedArtist: first.normalized_artist,
            profileDisplayName: first.profile_display_name,
            fallbackName: first.illustrator || first.artist,
          }),
          normalizedArtist: first.normalized_artist || '',
          slug: first.artist_slug || normalizedSlugs[0] || '',
          cardCount: Number(first.artist_card_count || first.total_artist_card_count || result.rows.length),
        }
      : null,
    profile: first ? artistProfileFromRow(first) : null,
    cards: result.rows.map(applyArtistDisplayNameToRow).map(withCardEmojiFields),
  };
}

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
    if (url.searchParams.get('summaries') === '1') {
      const artists = await artistSummaries({
        limit: url.searchParams.get('limit'),
      });
      res.setHeader('Cache-Control', 'public, max-age=60, s-maxage=300');
      return res.status(200).json({ artists });
    }
    const payload = await artistCardsForSlug({
      artistSlug: url.searchParams.get('artistSlug') || url.searchParams.get('slug'),
      artist: url.searchParams.get('artist'),
      limit: url.searchParams.get('limit'),
    });
    res.setHeader('Cache-Control', 'public, max-age=20, s-maxage=300');
    return res.status(200).json(payload);
  } catch (error) {
    console.error('marketplace-artist-cards failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Marketplace artist cards failed.',
    });
  }
};

module.exports.artistCardsForSlug = artistCardsForSlug;
module.exports.artistSummaries = artistSummaries;
module.exports.artistProfileFromRow = artistProfileFromRow;
module.exports.normalizeArtistSlug = normalizeArtistSlug;
module.exports.normalizeArtistLookupName = normalizeArtistLookupName;
module.exports.lookupAliasesForArtistName = lookupAliasesForArtistName;
module.exports.slugAliasesForArtistSlug = slugAliasesForArtistSlug;
module.exports.projectedRaritySql = projectedRaritySql;
