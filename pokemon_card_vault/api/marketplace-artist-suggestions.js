const { marketplaceQuery } = require('./_marketplace_db');
const {
  displayNameForArtist,
  normalizeArtistSlug,
} = require('./_artist_display');

function cleanText(value, maxLength = 160) {
  return String(value || '').trim().slice(0, maxLength);
}

function cleanLimit(value, fallback = 12) {
  const limit = Number(value);
  if (!Number.isFinite(limit)) {
    return fallback;
  }
  return Math.min(Math.max(Math.trunc(limit), 1), 50);
}

function normalizeArtistQuery(value) {
  return cleanText(value, 180)
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

function escapeLike(value) {
  return String(value || '').replace(/[\\%_]/g, (match) => `\\${match}`);
}

function fuzzyLikePattern(value) {
  const compact = String(value || '').replace(/[^a-z0-9]+/g, '');
  if (!compact) {
    return '%%';
  }
  return `%${compact.split('').map(escapeLike).join('%')}%`;
}

async function searchArtistSuggestions({
  query,
  limit,
  queryFn = marketplaceQuery,
} = {}) {
  const queryKey = normalizeArtistQuery(query);
  const escapedQuery = escapeLike(queryKey);
  const compactQuery = queryKey.replace(/\s+/g, '');
  const values = [
    queryKey,
    `${escapedQuery}%`,
    `% ${escapedQuery}%`,
    `%${escapedQuery}%`,
    `%${escapeLike(compactQuery)}%`,
    fuzzyLikePattern(queryKey),
    cleanLimit(limit),
  ];

  const result = await queryFn(
    `
      with artist_sources as (
        select
          normalized_artist,
          max(nullif(artist, '')) as artist,
          max(coalesce(artist_card_count, 0))::integer as artist_card_count,
          count(distinct blueprint_id)::integer as known_count,
          ''::text as profile_image_url
        from public.marketplace_blueprint_artists
        where normalized_artist <> ''
        group by normalized_artist
        union all
        select
          normalized_artist,
          max(nullif(display_name, '')) as artist,
          0::integer as artist_card_count,
          0::integer as known_count,
          max(coalesce(nullif(profile_image_cdn_url, ''), nullif(profile_image_url, ''))) as profile_image_url
        from public.marketplace_artist_profiles
        where normalized_artist <> ''
        group by normalized_artist
      ),
      merged as (
        select
          normalized_artist,
          (array_agg(
            artist
            order by
              case when known_count > 0 then 0 else 1 end,
              artist_card_count desc,
              artist asc
          ))[1] as artist,
          greatest(max(artist_card_count), sum(known_count))::integer as known_count,
          max(profile_image_url) as profile_image_url
        from artist_sources
        where coalesce(artist, '') <> ''
        group by normalized_artist
      ),
      searchable as (
        select
          *,
          lower(regexp_replace(coalesce(artist, ''), '[^a-z0-9]+', ' ', 'g')) as artist_key,
          lower(regexp_replace(coalesce(normalized_artist, ''), '[^a-z0-9]+', ' ', 'g')) as normalized_key,
          regexp_replace(lower(coalesce(artist, '')), '[^a-z0-9]+', '', 'g') as compact_artist_key,
          regexp_replace(lower(coalesce(normalized_artist, '')), '[^a-z0-9]+', '', 'g') as compact_normalized_key
        from merged
      )
      select normalized_artist, artist, known_count, profile_image_url
      from searchable
      where $1::text = ''
        or artist_key = $1::text
        or normalized_key = $1::text
        or artist_key like $2::text escape '\\'
        or normalized_key like $2::text escape '\\'
        or artist_key like $3::text escape '\\'
        or normalized_key like $3::text escape '\\'
        or artist_key like $4::text escape '\\'
        or normalized_key like $4::text escape '\\'
        or compact_artist_key like $5::text escape '\\'
        or compact_normalized_key like $5::text escape '\\'
        or compact_artist_key like $6::text escape '\\'
        or compact_normalized_key like $6::text escape '\\'
      order by
        case
          when artist_key = $1::text or normalized_key = $1::text then 0
          when artist_key like $2::text escape '\\'
            or normalized_key like $2::text escape '\\' then 1
          when artist_key like $3::text escape '\\'
            or normalized_key like $3::text escape '\\' then 2
          when artist_key like $4::text escape '\\'
            or normalized_key like $4::text escape '\\' then 3
          when compact_artist_key like $5::text escape '\\'
            or compact_normalized_key like $5::text escape '\\' then 4
          else 5
        end,
        known_count desc,
        artist asc
      limit $7::integer
    `,
    values,
  );

  return result.rows
    .map((row) => ({
      name: displayNameForArtist({
        normalizedArtist: row.normalized_artist,
        fallbackName: row.artist,
      }),
      normalizedArtist: row.normalized_artist || '',
      slug: normalizeArtistSlug(row.normalized_artist || row.artist || ''),
      knownCount: Number(row.known_count || 0),
      cardCount: Number(row.known_count || 0),
      imageUrl: row.profile_image_url || '',
      profileImageUrl: row.profile_image_url || '',
    }))
    .filter((artist) => artist.name && artist.normalizedArtist);
}

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
    const artists = await searchArtistSuggestions({
      query: url.searchParams.get('q') || url.searchParams.get('query') || '',
      limit: url.searchParams.get('limit'),
    });
    res.setHeader('Cache-Control', 'public, max-age=20, s-maxage=120');
    return res.status(200).json({ artists });
  } catch (error) {
    console.error('marketplace-artist-suggestions failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Marketplace artist suggestions failed.',
    });
  }
};

module.exports.cleanLimit = cleanLimit;
module.exports.normalizeArtistQuery = normalizeArtistQuery;
module.exports.normalizeArtistSlug = normalizeArtistSlug;
module.exports.searchArtistSuggestions = searchArtistSuggestions;
