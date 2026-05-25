#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { PutObjectCommand, S3Client } = require('@aws-sdk/client-s3');
const { Pool } = require('pg');

const ROOT_DIR = path.resolve(__dirname, '..');
const POKOINPOS_ROOT = process.env.POKOINPOS_ROOT || '/Users/giuseppe/pokoinpos';
const DEFAULT_ORACLE_ENV = path.join(POKOINPOS_ROOT, 'deploy/env/peer4-postgres.env');

function cleanText(value, maxLength = 5000) {
  return String(value || '').trim().replace(/\s+/g, ' ').slice(0, maxLength);
}

function normalizeArtist(value) {
  return cleanText(value, 180)
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

function cleanEnvValue(value) {
  const trimmed = String(value || '').trim();
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1).replace(/\\n/g, '\n');
  }
  return trimmed;
}

function loadEnvFile(filePath) {
  if (!filePath || !fs.existsSync(filePath)) return;
  for (const line of fs.readFileSync(filePath, 'utf8').split(/\r?\n/)) {
    const stripped = line.trim();
    if (!stripped || stripped.startsWith('#') || !stripped.includes('=')) continue;
    const separator = stripped.indexOf('=');
    const key = stripped.slice(0, separator).replace(/^export\s+/, '').trim();
    if (!key || process.env[key]) continue;
    process.env[key] = cleanEnvValue(stripped.slice(separator + 1));
  }
}

function loadLocalEnv() {
  loadEnvFile(path.join(ROOT_DIR, '.env.local'));
  loadEnvFile(DEFAULT_ORACLE_ENV);
}

function parsePositiveInt(value, fallback, max = Number.MAX_SAFE_INTEGER) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(Math.max(Math.trunc(number), 1), max);
}

function parseArtistList(value) {
  return String(value || '')
    .split(',')
    .map(normalizeArtist)
    .filter(Boolean);
}

function parseArgs(argv) {
  const options = {
    apply: false,
    limit: 100,
    language: 'en',
    refreshExisting: false,
    source: 'all',
    concurrency: 2,
    artist: '',
    artistKeys: [],
    writeReport: '',
    cacheImages: true,
    auditImageCache: false,
    recacheMissingImages: false,
    pocketmonstersId: '',
    pocketmonstersUrl: '',
  };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith('--')) continue;
    const [rawKey, inlineValue] = token.slice(2).split('=', 2);
    const value = inlineValue !== undefined
      ? inlineValue
      : argv[index + 1] && !argv[index + 1].startsWith('--')
        ? argv[++index]
        : true;
    if (rawKey === 'apply') {
      options.apply = true;
    } else if (rawKey === 'limit') {
      options.limit = String(value).toLowerCase() === 'all'
        ? Infinity
        : parsePositiveInt(value, 100, 10_000);
    } else if (rawKey === 'language') {
      options.language = cleanText(value, 12).toLowerCase() || 'en';
    } else if (rawKey === 'refresh-existing') {
      options.refreshExisting = true;
    } else if (rawKey === 'source') {
      options.source = cleanText(value, 40).toLowerCase() || 'wikidata';
    } else if (rawKey === 'concurrency') {
      options.concurrency = parsePositiveInt(value, 2, 6);
    } else if (rawKey === 'artist') {
      options.artist = cleanText(value, 180);
      options.artistKeys = parseArtistList(value);
    } else if (rawKey === 'write-report') {
      options.writeReport = cleanText(value, 1000);
    } else if (rawKey === 'no-cache-images') {
      options.cacheImages = false;
    } else if (rawKey === 'audit-image-cache') {
      options.auditImageCache = true;
    } else if (rawKey === 'recache-missing-images') {
      options.recacheMissingImages = true;
    } else if (rawKey === 'pocketmonsters-id') {
      options.pocketmonstersId = cleanText(value, 40).replace(/\D+/g, '');
    } else if (rawKey === 'pocketmonsters-url') {
      options.pocketmonstersUrl = cleanText(value, 1000);
    }
  }
  if (!['all', 'wikidata', 'pocketmonsters', 'bulbapedia'].includes(options.source)) {
    throw new Error('--source must be all, wikidata, pocketmonsters, or bulbapedia.');
  }
  if (options.pocketmonstersId && !options.pocketmonstersUrl) {
    options.pocketmonstersUrl = `https://www.pocketmonsters.net/staff/view/${options.pocketmonstersId}`;
  }
  return options;
}

function createPool() {
  const connectionString = process.env.MARKETPLACE_DATABASE_URL || process.env.ORACLE_DATABASE_URL;
  if (!connectionString) {
    throw new Error('MARKETPLACE_DATABASE_URL is required.');
  }
  return new Pool({
    connectionString,
    max: 2,
    idleTimeoutMillis: 10_000,
    connectionTimeoutMillis: 10_000,
    ssl: { rejectUnauthorized: false },
    application_name: 'marketplace-artist-profiles-import',
  });
}

async function fetchArtistRows(pool, { limit, refreshExisting }) {
  const artistKeys = Array.isArray(arguments[1]?.artistKeys) ? arguments[1].artistKeys : [];
  const source = cleanText(arguments[1]?.source, 40).toLowerCase();
  const result = await pool.query(
    `
      select distinct on (artists.normalized_artist)
        artists.artist,
        artists.illustrator,
        artists.normalized_artist,
        profiles.normalized_artist as profile_normalized_artist,
        profiles.display_name as profile_display_name,
        profiles.summary as profile_summary,
        profiles.bio as profile_bio,
        profiles.profile_image_url as profile_image_url,
        profiles.profile_image_cdn_url as profile_image_cdn_url,
        profiles.profile_image_object_key as profile_image_object_key,
        profiles.pocketmonsters_url as profile_pocketmonsters_url,
        profiles.pocketmonsters_id as profile_pocketmonsters_id,
        profiles.bulbapedia_url as profile_bulbapedia_url,
        profiles.bulbapedia_title as profile_bulbapedia_title,
        profiles.source_name as profile_source_name,
        profiles.source_url as profile_source_url,
        profiles.source_attribution as profile_source_attribution,
        profiles.raw_metadata as profile_raw_metadata
      from public.marketplace_blueprint_artists artists
      left join public.marketplace_artist_profiles profiles
        on profiles.normalized_artist = artists.normalized_artist
      where coalesce(artists.normalized_artist, '') <> ''
        and (
          $1::boolean
          or profiles.normalized_artist is null
          or (
            $4::text in ('all', 'bulbapedia')
            and coalesce(profiles.bulbapedia_url, '') = ''
          )
        )
        and (
          cardinality($3::text[]) = 0
          or artists.normalized_artist = any($3::text[])
          or lower(artists.artist) = any($3::text[])
          or lower(artists.illustrator) = any($3::text[])
        )
      order by artists.normalized_artist asc, artists.matched_at desc
      limit $2
    `,
    [refreshExisting, Number.isFinite(limit) ? limit : 1000000, artistKeys, source],
  );
  return result.rows;
}

async function fetchJson(url, fetchImpl) {
  const response = await fetchImpl(url, {
    headers: {
      'User-Agent': 'PokoinMarketplaceArtistProfiles/1.0 (https://pokoin.com)',
    },
  });
  if (!response.ok) return null;
  return response.json();
}

async function mapWithConcurrency(items, concurrency, mapper) {
  const results = new Array(items.length);
  let nextIndex = 0;
  const workerCount = Math.min(Math.max(concurrency || 1, 1), Math.max(items.length, 1));
  await Promise.all(
    Array.from({ length: workerCount }, async () => {
      while (nextIndex < items.length) {
        const index = nextIndex;
        nextIndex += 1;
        results[index] = await mapper(items[index], index);
      }
    }),
  );
  return results;
}

function slugForKey(value) {
  return normalizeArtist(value).replace(/\s+/g, '-');
}

function getArtistR2Config(env = process.env) {
  const accountId = env.CLOUDFLARE_ACCOUNT_ID;
  const accessKeyId = env.R2_ACCESS_KEY_ID;
  const secretAccessKey = env.R2_SECRET_ACCESS_KEY;
  const bucket =
    env.R2_ARTIST_PROFILE_IMAGES_BUCKET ||
    env.POKOIN_ARTIST_PROFILE_IMAGES_BUCKET ||
    env.POKOIN_CARD_IMAGES_BUCKET ||
    'cardvault-images';
  const publicBaseUrl =
    env.R2_ARTIST_PROFILE_IMAGES_PUBLIC_URL ||
    env.POKOIN_ARTIST_PROFILE_IMAGES_PUBLIC_URL ||
    'https://pokoin.com/card-images';
  if (!accountId || !accessKeyId || !secretAccessKey || !bucket || !publicBaseUrl) {
    return null;
  }
  return {
    accountId,
    accessKeyId,
    secretAccessKey,
    bucket,
    publicBaseUrl: publicBaseUrl.replace(/\/+$/, ''),
  };
}

function normalizeArtistProfilePublicBaseUrl(value) {
  const clean = cleanText(value, 1000).replace(/\/+$/, '');
  if (!clean) return 'https://pokoin.com/card-images';
  try {
    const url = new URL(clean);
    if (url.hostname === 'cdn.pokoin.com') {
      return 'https://pokoin.com/card-images';
    }
  } catch {
    return clean;
  }
  return clean;
}

function publicUrlForKey(config, key) {
  const publicBaseUrl = normalizeArtistProfilePublicBaseUrl(config.publicBaseUrl);
  return `${publicBaseUrl}/${key.split('/').map(encodeURIComponent).join('/')}`;
}

function contentTypeForUrl(url, fallback = 'image/png') {
  const pathname = (() => {
    try {
      return new URL(url).pathname.toLowerCase();
    } catch {
      return '';
    }
  })();
  if (pathname.endsWith('.jpg') || pathname.endsWith('.jpeg')) return 'image/jpeg';
  if (pathname.endsWith('.webp')) return 'image/webp';
  if (pathname.endsWith('.gif')) return 'image/gif';
  return fallback;
}

function extensionForContentType(contentType, sourceUrl) {
  const type = String(contentType || '').split(';')[0].trim().toLowerCase();
  if (type === 'image/jpeg') return 'jpg';
  if (type === 'image/webp') return 'webp';
  if (type === 'image/gif') return 'gif';
  const pathname = (() => {
    try {
      return new URL(sourceUrl).pathname.toLowerCase();
    } catch {
      return '';
    }
  })();
  if (pathname.endsWith('.jpg') || pathname.endsWith('.jpeg')) return 'jpg';
  if (pathname.endsWith('.webp')) return 'webp';
  if (pathname.endsWith('.gif')) return 'gif';
  return 'png';
}

async function cacheProfileImage(profile, { fetchImpl = fetch, r2Config = getArtistR2Config() } = {}) {
  if (!r2Config || !profile?.profileImageUrl) {
    return {
      profile,
      cached: false,
      reason: r2Config ? 'missing_image_url' : 'missing_r2_config',
    };
  }
  const response = await fetchImpl(profile.profileImageUrl, {
    headers: {
      'User-Agent': 'PokoinMarketplaceArtistProfiles/1.0 (https://pokoin.com)',
    },
  });
  if (!response.ok) {
    return {
      profile,
      cached: false,
      reason: `image_fetch_${response.status}`,
    };
  }
  const contentType = contentTypeForUrl(
    profile.profileImageUrl,
    response.headers.get('content-type') || 'image/png',
  );
  if (!contentType.startsWith('image/')) {
    return { profile, cached: false, reason: 'image_content_type_invalid' };
  }
  const body = Buffer.from(await response.arrayBuffer());
  const extension = extensionForContentType(contentType, profile.profileImageUrl);
  const objectKey = `artist-profiles/${slugForKey(profile.normalizedArtist)}.${extension}`;
  const client = new S3Client({
    region: 'auto',
    endpoint: `https://${r2Config.accountId}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: r2Config.accessKeyId,
      secretAccessKey: r2Config.secretAccessKey,
    },
  });
  await client.send(
    new PutObjectCommand({
      Bucket: r2Config.bucket,
      Key: objectKey,
      Body: body,
      ContentType: contentType,
      CacheControl: 'public, max-age=31536000, immutable',
    }),
  );
  return {
    profile: {
      ...profile,
      profileImageCdnUrl: publicUrlForKey(r2Config, objectKey),
      profileImageObjectKey: objectKey,
    },
    cached: true,
    reason: 'cached',
  };
}

function profileFromExistingRow(row) {
  return {
    normalizedArtist: normalizeArtist(row.normalized_artist),
    displayName: row.display_name || row.normalized_artist || '',
    summary: row.summary || '',
    bio: row.bio || '',
    profileImageUrl: row.profile_image_url || '',
    profileImageCdnUrl: row.profile_image_cdn_url || '',
    profileImageObjectKey: row.profile_image_object_key || '',
    pocketmonstersUrl: row.pocketmonsters_url || '',
    pocketmonstersId: row.pocketmonsters_id || '',
    bulbapediaUrl: row.bulbapedia_url || '',
    bulbapediaTitle: row.bulbapedia_title || '',
    sourceName: row.source_name || '',
    sourceUrl: row.source_url || '',
    sourceAttribution: row.source_attribution || {},
    rawMetadata: row.raw_metadata || {},
  };
}

async function auditArtistProfileImageCache({ pool, options }) {
  const artistKeys = Array.isArray(options.artistKeys) ? options.artistKeys : [];
  const limit = Number.isFinite(options.limit) ? options.limit : 1000000;
  const aggregate = await pool.query(
    `
      select
        count(*)::int as profile_rows,
        count(*) filter (where coalesce(profile_image_url, '') <> '')::int as source_images,
        count(*) filter (
          where coalesce(profile_image_cdn_url, '') <> ''
            and coalesce(profile_image_object_key, '') <> ''
        )::int as cached_images,
        count(*) filter (
          where coalesce(profile_image_url, '') <> ''
            and (
              coalesce(profile_image_cdn_url, '') = ''
              or coalesce(profile_image_object_key, '') = ''
            )
        )::int as cache_needed
      from public.marketplace_artist_profiles
      where cardinality($1::text[]) = 0
        or normalized_artist = any($1::text[])
    `,
    [artistKeys],
  );
  const missing = await pool.query(
    `
      select
        normalized_artist,
        display_name,
        profile_image_url,
        profile_image_cdn_url,
        profile_image_object_key,
        pocketmonsters_url,
        pocketmonsters_id,
        bulbapedia_url,
        source_name,
        source_url,
        updated_at
      from public.marketplace_artist_profiles
      where coalesce(profile_image_url, '') <> ''
        and (
          coalesce(profile_image_cdn_url, '') = ''
          or coalesce(profile_image_object_key, '') = ''
        )
        and (
          cardinality($1::text[]) = 0
          or normalized_artist = any($1::text[])
        )
      order by normalized_artist asc
      limit $2
    `,
    [artistKeys, limit],
  );
  const counts = {
    ...(aggregate.rows[0] || {
      profile_rows: 0,
      source_images: 0,
      cached_images: 0,
      cache_needed: 0,
    }),
    reported_missing_rows: missing.rows.length,
  };
  const report = missing.rows.map((row) => ({
    artist: row.display_name || row.normalized_artist,
    normalizedArtist: row.normalized_artist,
    status: 'cache_needed',
    sourceUrl: row.source_url || row.pocketmonsters_url || row.bulbapedia_url || '',
    pocketmonstersUrl: row.pocketmonsters_url || '',
    bulbapediaUrl: row.bulbapedia_url || '',
    profileImageUrl: row.profile_image_url || '',
    profileImageCdnUrl: row.profile_image_cdn_url || '',
    profileImageObjectKey: row.profile_image_object_key || '',
    updatedAt: row.updated_at || null,
  }));
  return {
    counts,
    samples: report.slice(0, 20),
    report,
  };
}

async function updateProfileImageCache(pool, profile) {
  await pool.query(
    `
      update public.marketplace_artist_profiles
      set
        profile_image_cdn_url = $2,
        profile_image_object_key = $3,
        updated_at = now()
      where normalized_artist = $1
    `,
    [
      profile.normalizedArtist,
      profile.profileImageCdnUrl || '',
      profile.profileImageObjectKey || '',
    ],
  );
}

async function recacheMissingArtistProfileImages({
  pool,
  options,
  fetchImpl = fetch,
  r2Config = getArtistR2Config(),
}) {
  const artistKeys = Array.isArray(options.artistKeys) ? options.artistKeys : [];
  const limit = Number.isFinite(options.limit) ? options.limit : 1000000;
  const result = await pool.query(
    `
      select
        normalized_artist,
        display_name,
        summary,
        bio,
        profile_image_url,
        profile_image_cdn_url,
        profile_image_object_key,
        pocketmonsters_url,
        pocketmonsters_id,
        bulbapedia_url,
        bulbapedia_title,
        source_name,
        source_url,
        source_attribution,
        raw_metadata
      from public.marketplace_artist_profiles
      where coalesce(profile_image_url, '') <> ''
        and (
          coalesce(profile_image_cdn_url, '') = ''
          or coalesce(profile_image_object_key, '') = ''
        )
        and (
          cardinality($1::text[]) = 0
          or normalized_artist = any($1::text[])
        )
      order by normalized_artist asc
      limit $2
    `,
    [artistKeys, limit],
  );
  const counts = {
    scanned: result.rows.length,
    matched: 0,
    upserted: 0,
    skipped: 0,
    ambiguous: 0,
    imageCached: 0,
    imageCacheNeeded: 0,
    reasons: {},
  };
  const samples = [];
  const report = [];
  for (const row of result.rows) {
    const original = profileFromExistingRow(row);
    if (!original.normalizedArtist || !original.profileImageUrl) {
      counts.skipped += 1;
      incrementReason(counts, 'missing_image_url');
      continue;
    }
    counts.matched += 1;
    let profile = original;
    let imageCache = null;
    if (options.apply && options.cacheImages) {
      imageCache = await cacheProfileImage(profile, { fetchImpl, r2Config });
      profile = imageCache.profile;
      if (imageCache.cached) {
        await updateProfileImageCache(pool, profile);
        counts.imageCached += 1;
        counts.upserted += 1;
      } else {
        counts.imageCacheNeeded += 1;
      }
      incrementReason(counts, imageCache.reason || 'cache_attempted');
    } else {
      counts.imageCacheNeeded += 1;
      incrementReason(counts, options.cacheImages ? 'cache_needed' : 'cache_disabled');
    }
    const entry = {
      artist: original.displayName,
      normalizedArtist: original.normalizedArtist,
      status: options.apply && imageCache?.cached ? 'recached' : options.apply ? 'cache_failed' : 'matched_dry_run',
      sourceUrl: original.sourceUrl,
      pocketmonstersUrl: original.pocketmonstersUrl,
      bulbapediaUrl: original.bulbapediaUrl,
      profileImageUrl: original.profileImageUrl,
      profileImageCdnUrl: profile.profileImageCdnUrl || '',
      profileImageObjectKey: profile.profileImageObjectKey || '',
      imageCache: imageCache?.reason || (options.cacheImages ? 'cache_needed' : 'cache_disabled'),
    };
    report.push(entry);
    samples.push({
      artist: entry.artist,
      displayName: original.displayName,
      sourceUrl: entry.sourceUrl,
      imageUrl: entry.profileImageCdnUrl || entry.profileImageUrl,
    });
  }
  return { counts, samples, report };
}

function isTrustedArtistDescription(value) {
  const description = cleanText(value, 400).toLowerCase();
  return /\b(artist|illustrator|designer|manga|comic|painter|animator)\b/.test(description);
}

function exactEntityNameMatch(entity, normalizedArtist) {
  const candidates = [
    entity.label,
    ...(Array.isArray(entity.aliases) ? entity.aliases : []),
  ].map(normalizeArtist);
  return candidates.includes(normalizedArtist);
}

function commonsFileUrl(fileName) {
  const cleanFile = cleanText(fileName, 400);
  if (!cleanFile) return '';
  return `https://commons.wikimedia.org/wiki/Special:FilePath/${encodeURIComponent(cleanFile)}`;
}

function absoluteUrl(value, baseUrl = 'https://www.pocketmonsters.net') {
  const clean = cleanText(value, 1000);
  if (!clean) return '';
  if (clean.startsWith('//')) return `https:${clean}`;
  try {
    return new URL(clean, baseUrl).toString();
  } catch {
    return '';
  }
}

function htmlDecode(value) {
  return String(value || '')
    .replace(/&quot;/g, '"')
    .replace(/&#039;/g, "'")
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
}

function stripHtml(value) {
  return htmlDecode(String(value || '')
    .replace(/<\s*br\s*\/?>/gi, ' ')
    .replace(/<[^>]+>/g, ' '));
}

function parsePocketMonstersStaffIndex(html) {
  const rows = [];
  const pattern = /<a\s+href="(https?:\/\/www\.pocketmonsters\.net\/staff\/view\/\d+)">([\s\S]*?)<\/a>/gi;
  for (const match of html.matchAll(pattern)) {
    const name = cleanText(stripHtml(match[2]), 180);
    const sourceUrl = cleanText(match[1], 1000);
    if (name && sourceUrl) {
      rows.push({ name, normalizedArtist: normalizeArtist(name), sourceUrl });
    }
  }
  const byArtist = new Map();
  for (const row of rows) {
    byArtist.set(row.normalizedArtist, row);
  }
  return [...byArtist.values()];
}

function pageNumbersFromPocketMonstersIndex(html) {
  const pages = new Set([1]);
  for (const match of html.matchAll(/staff\?[^"']*page=(\d+)/g)) {
    const page = Number(match[1]);
    if (Number.isInteger(page) && page > 0) pages.add(page);
  }
  return [...pages].sort((a, b) => a - b);
}

function parsePocketMonstersProfile(html, sourceUrl) {
  const pocketmonstersId = cleanText(sourceUrl.match(/\/staff\/view\/(\d+)/)?.[1] || '', 40);
  const title = cleanText(
    stripHtml(
      html.match(/<h2[^>]*class="[^"]*\bfont-bold\b[^"]*"[^>]*>([\s\S]*?)<\/h2>/i)?.[1] ||
        html.match(/<meta\s+property="og:title"\s+content="Biography Details:\s*([^"]+)"/i)?.[1] ||
        html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i)?.[1] ||
        '',
    ),
    220,
  );
  const imageSrc = html.match(/<img[^>]+src="([^"]*\/staff\/\d+\/main\.png[^"]*)"[^>]*>/i)?.[1] || '';
  const biographyMatch =
    html.match(/<div[^>]+id="Biography"[\s\S]*?header-block">\s*Biography\s*<\/div>\s*<div[^>]*>([\s\S]*?)(?:<\/div>\s*<\/div>(?:\s*<div|\s*$)|<div[^>]+id="TCG"|<div[^>]+id="Pokemon"|Pokémon Portrayed)/i) ||
    html.match(/<h3[^>]*>\s*Biography\s*<\/h3>([\s\S]*?)(?:<h[23][^>]*>|<div[^>]+id="tcgCards"|TCG Cards|Pokémon Portrayed)/i);
  const bio = cleanText(stripHtml(biographyMatch?.[1] || ''), 1400);
  return {
    displayName: title,
    summary: '',
    bio,
    profileImageUrl: absoluteUrl(imageSrc),
    profileImageCdnUrl: '',
    profileImageObjectKey: '',
    pocketmonstersUrl: sourceUrl,
    pocketmonstersId,
    bulbapediaUrl: '',
    bulbapediaTitle: '',
    sourceName: 'PocketMonsters.Net',
    sourceUrl,
    sourceAttribution: {
      pocketmonsters: {
        name: 'PocketMonsters.Net',
        url: sourceUrl,
      },
    },
    rawMetadata: {
      fetchedAt: new Date().toISOString(),
      source: 'pocketmonsters_staff',
      pocketmonstersId,
    },
  };
}

async function wikipediaSummaryForTitle(title, { language, fetchImpl }) {
  const cleanTitle = cleanText(title, 220);
  if (!cleanTitle) return null;
  const url = new URL(`https://${language}.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(cleanTitle)}`);
  const payload = await fetchJson(url, fetchImpl);
  if (!payload?.content_urls?.desktop?.page) return null;
  return {
    title: cleanText(payload.title, 220),
    extract: cleanText(payload.extract, 1400),
    imageUrl: cleanText(payload.originalimage?.source || payload.thumbnail?.source, 1000),
    sourceUrl: cleanText(payload.content_urls.desktop.page, 1000),
  };
}

async function pocketMonstersStaffIndex({ fetchImpl = fetch } = {}) {
  const firstUrl = new URL('https://www.pocketmonsters.net/staff');
  firstUrl.searchParams.append('stype[]', '63');
  const firstHtml = await fetchText(firstUrl, fetchImpl);
  if (!firstHtml) return [];
  const pages = pageNumbersFromPocketMonstersIndex(firstHtml);
  const rows = parsePocketMonstersStaffIndex(firstHtml);
  for (const page of pages.filter((value) => value !== 1)) {
    const pageUrl = new URL('https://www.pocketmonsters.net/staff');
    pageUrl.searchParams.append('stype[]', '63');
    pageUrl.searchParams.set('page', String(page));
    const html = await fetchText(pageUrl, fetchImpl);
    rows.push(...parsePocketMonstersStaffIndex(html || ''));
  }
  const byArtist = new Map();
  for (const row of rows) {
    byArtist.set(row.normalizedArtist, row);
  }
  return [...byArtist.values()];
}

async function fetchText(url, fetchImpl) {
  const response = await fetchImpl(url, {
    headers: {
      'User-Agent': 'PokoinMarketplaceArtistProfiles/1.0 (https://pokoin.com)',
    },
  });
  if (!response.ok) return '';
  return response.text();
}

async function trustedPocketMonstersProfileForArtist(row, { staffByArtist, fetchImpl = fetch } = {}) {
  const name = cleanText(row.artist || row.illustrator, 180);
  const normalizedArtist = normalizeArtist(row.normalized_artist || name);
  const staff = staffByArtist.get(normalizedArtist);
  if (!staff) return null;
  const html = await fetchText(staff.sourceUrl, fetchImpl);
  if (!html) return null;
  const profile = parsePocketMonstersProfile(html, staff.sourceUrl);
  if (!profile.displayName || (!profile.bio && !profile.profileImageUrl)) return null;
  return {
    normalizedArtist,
    ...profile,
  };
}

async function trustedPocketMonstersProfileFromStaff(staff, { fetchImpl = fetch } = {}) {
  if (!staff?.normalizedArtist || !staff.sourceUrl) return null;
  const html = await fetchText(staff.sourceUrl, fetchImpl);
  if (!html) return null;
  const profile = parsePocketMonstersProfile(html, staff.sourceUrl);
  if (!profile.displayName) return null;
  return {
    normalizedArtist: staff.normalizedArtist,
    ...profile,
  };
}

function bulbapediaTitleCandidates(name) {
  const cleanName = cleanText(name, 220);
  if (!cleanName) return [];
  const underscored = cleanName
    .replace(/[-_]+/g, ' ')
    .trim()
    .replace(/\s+/g, '_');
  return [...new Set([underscored, `${underscored}_(TCG_Illustrator)`, `${underscored}_(illustrator)`])];
}

function bulbapediaPageUrl(title) {
  return `https://bulbapedia.bulbagarden.net/wiki/${encodeURIComponent(cleanText(title, 220).replace(/\s+/g, '_'))}`;
}

function normalizeBulbapediaArtistTitle(title) {
  return normalizeArtist(
    cleanText(title, 220).replace(/\s*\((?:TCG\s+)?Illustrator\)\s*/gi, ' '),
  );
}

function recordBulbapediaDiagnostic(diagnostics, reason, detail = {}) {
  if (!diagnostics) return;
  diagnostics.reason = reason;
  diagnostics.details = detail;
}

async function fetchBulbapediaSummaryForArtist(row, { fetchImpl = fetch, diagnostics } = {}) {
  const name = cleanText(row.artist || row.illustrator || row.displayName, 180);
  const normalizedArtist = normalizeArtist(row.normalized_artist || name);
  if (!name || !normalizedArtist) {
    recordBulbapediaDiagnostic(diagnostics, 'missing_artist_name');
    return null;
  }
  const attempts = [];
  for (const title of bulbapediaTitleCandidates(name)) {
    const attempt = { title };
    attempts.push(attempt);
    const url = new URL(`https://bulbapedia.bulbagarden.net/w/api.php`);
    url.searchParams.set('action', 'query');
    url.searchParams.set('format', 'json');
    url.searchParams.set('formatversion', '2');
    url.searchParams.set('prop', 'extracts|info');
    url.searchParams.set('exintro', '1');
    url.searchParams.set('explaintext', '1');
    url.searchParams.set('redirects', '1');
    url.searchParams.set('inprop', 'url');
    url.searchParams.set('titles', title);
    const payload = await fetchJson(url, fetchImpl);
    const page = payload?.query?.pages?.[0];
    if (!page || page.missing || !page.title) {
      attempt.reason = 'missing_page';
      continue;
    }
    const pageTitle = cleanText(page.title, 220);
    const titleKey = normalizeBulbapediaArtistTitle(pageTitle);
    if (titleKey !== normalizedArtist) {
      attempt.reason = 'title_mismatch';
      attempt.pageTitle = pageTitle;
      continue;
    }
    const extract = cleanText(page.extract, 1000);
    if (!extract || !/\b(illustrator|artist|tcg|trading card game|pokemon card)\b/i.test(extract)) {
      attempt.reason = extract ? 'non_artist_extract' : 'empty_extract';
      continue;
    }
    const sourceUrl = cleanText(page.fullurl, 1000) || bulbapediaPageUrl(pageTitle);
    return {
      normalizedArtist,
      title: pageTitle,
      summary: extract,
      sourceUrl,
      attribution: {
        name: 'Bulbapedia',
        url: sourceUrl,
        license: 'CC BY-NC-SA',
      },
    };
  }
  const reasons = attempts.map((attempt) => attempt.reason).filter(Boolean);
  recordBulbapediaDiagnostic(
    diagnostics,
    reasons.includes('title_mismatch')
      ? 'title_mismatch'
      : reasons.includes('non_artist_extract')
        ? 'non_artist_extract'
        : reasons.includes('empty_extract')
          ? 'empty_extract'
          : 'missing_page',
    { attempts },
  );
  return null;
}

function splitSourceNames(value) {
  return String(value || '')
    .split(/\s+\+\s+/)
    .map((name) => cleanText(name, 120))
    .filter(Boolean);
}

function mergeSourceNames(...values) {
  return [...new Set(values.flatMap(splitSourceNames))].join(' + ');
}

function mergeWithExistingProfile(profile, row) {
  if (!profile || !row?.profile_normalized_artist) return profile;
  const existingAttribution =
    row.profile_source_attribution && typeof row.profile_source_attribution === 'object'
      ? row.profile_source_attribution
      : {};
  const incomingAttribution =
    profile.sourceAttribution && typeof profile.sourceAttribution === 'object'
      ? profile.sourceAttribution
      : {};
  const existingMetadata =
    row.profile_raw_metadata && typeof row.profile_raw_metadata === 'object'
      ? row.profile_raw_metadata
      : {};
  const incomingMetadata =
    profile.rawMetadata && typeof profile.rawMetadata === 'object'
      ? profile.rawMetadata
      : {};
  return {
    ...profile,
    displayName: profile.displayName || row.profile_display_name || '',
    summary: profile.summary || row.profile_summary || '',
    bio: profile.bio || row.profile_bio || '',
    profileImageUrl: profile.profileImageUrl || row.profile_image_url || '',
    profileImageCdnUrl: profile.profileImageCdnUrl || row.profile_image_cdn_url || '',
    profileImageObjectKey: profile.profileImageObjectKey || row.profile_image_object_key || '',
    pocketmonstersUrl: profile.pocketmonstersUrl || row.profile_pocketmonsters_url || '',
    pocketmonstersId: profile.pocketmonstersId || row.profile_pocketmonsters_id || '',
    bulbapediaUrl: profile.bulbapediaUrl || row.profile_bulbapedia_url || '',
    bulbapediaTitle: profile.bulbapediaTitle || row.profile_bulbapedia_title || '',
    sourceName: mergeSourceNames(row.profile_source_name, profile.sourceName),
    sourceUrl: profile.sourceUrl || row.profile_source_url || '',
    sourceAttribution: {
      ...existingAttribution,
      ...incomingAttribution,
    },
    rawMetadata: {
      ...existingMetadata,
      ...incomingMetadata,
    },
  };
}

function incrementReason(counts, reason) {
  const key = cleanText(reason || 'unknown', 80) || 'unknown';
  counts.reasons[key] = (counts.reasons[key] || 0) + 1;
}

function mergeProfileParts(row, parts) {
  const normalizedArtist = normalizeArtist(row.normalized_artist || row.artist || row.illustrator);
  const pocketmonsters = parts.pocketmonsters || null;
  const bulbapedia = parts.bulbapedia || null;
  const wikidata = parts.wikidata || null;
  const displayName =
    cleanText(pocketmonsters?.displayName || bulbapedia?.title || wikidata?.displayName || row.artist || row.illustrator, 220);
  const sourceAttribution = {
    ...(wikidata?.sourceAttribution || {}),
    ...(pocketmonsters?.sourceAttribution || {}),
    ...(bulbapedia ? { bulbapedia: bulbapedia.attribution } : {}),
  };
  const sourceNames = [
    pocketmonsters && 'PocketMonsters.Net',
    bulbapedia && 'Bulbapedia',
    wikidata && wikidata.sourceName,
  ].filter(Boolean);
  const sourceUrl = pocketmonsters?.sourceUrl || bulbapedia?.sourceUrl || wikidata?.sourceUrl || '';
  if (!normalizedArtist || (!pocketmonsters && !bulbapedia && !wikidata)) return null;
  return {
    normalizedArtist,
    displayName,
    summary: bulbapedia?.summary || wikidata?.summary || '',
    bio: pocketmonsters?.bio || wikidata?.bio || '',
    profileImageUrl: pocketmonsters?.profileImageUrl || wikidata?.profileImageUrl || '',
    profileImageCdnUrl: pocketmonsters?.profileImageCdnUrl || wikidata?.profileImageCdnUrl || '',
    profileImageObjectKey: pocketmonsters?.profileImageObjectKey || wikidata?.profileImageObjectKey || '',
    pocketmonstersUrl: pocketmonsters?.pocketmonstersUrl || '',
    pocketmonstersId: pocketmonsters?.pocketmonstersId || '',
    bulbapediaUrl: bulbapedia?.sourceUrl || '',
    bulbapediaTitle: bulbapedia?.title || '',
    sourceName: [...new Set(sourceNames)].join(' + '),
    sourceUrl,
    sourceAttribution,
    rawMetadata: {
      fetchedAt: new Date().toISOString(),
      sources: {
        pocketmonsters: pocketmonsters?.rawMetadata || null,
        bulbapedia: bulbapedia
          ? {
              title: bulbapedia.title,
              sourceUrl: bulbapedia.sourceUrl,
            }
          : null,
        wikidata: wikidata?.rawMetadata || null,
      },
    },
  };
}

async function trustedProfileForArtist(row, { language = 'en', fetchImpl = fetch } = {}) {
  const name = cleanText(row.artist || row.illustrator, 180);
  const normalizedArtist = normalizeArtist(row.normalized_artist || name);
  if (!name || !normalizedArtist) return null;

  const searchUrl = new URL('https://www.wikidata.org/w/api.php');
  searchUrl.searchParams.set('action', 'wbsearchentities');
  searchUrl.searchParams.set('format', 'json');
  searchUrl.searchParams.set('language', language);
  searchUrl.searchParams.set('uselang', language);
  searchUrl.searchParams.set('type', 'item');
  searchUrl.searchParams.set('limit', '5');
  searchUrl.searchParams.set('search', name);

  const searchPayload = await fetchJson(searchUrl, fetchImpl);
  const match = (searchPayload?.search || []).find(
    (entity) =>
      exactEntityNameMatch(entity, normalizedArtist) &&
      isTrustedArtistDescription(entity.description),
  );
  if (!match?.id) return null;

  const entityUrl = new URL('https://www.wikidata.org/wiki/Special:EntityData/' + encodeURIComponent(match.id) + '.json');
  const entityPayload = await fetchJson(entityUrl, fetchImpl);
  const entity = entityPayload?.entities?.[match.id];
  if (!entity) return null;
  const labels = entity.labels || {};
  const descriptions = entity.descriptions || {};
  const sitelinks = entity.sitelinks || {};
  const displayName = cleanText(labels[language]?.value || labels.en?.value || match.label || name, 220);
  const description = cleanText(descriptions[language]?.value || descriptions.en?.value || match.description, 1000);
  if (!displayName || !isTrustedArtistDescription(description)) return null;

  const imageClaim = entity.claims?.P18?.[0]?.mainsnak?.datavalue?.value;
  const wikiTitle = sitelinks[`${language}wiki`]?.title || sitelinks.enwiki?.title || '';
  const summary = await wikipediaSummaryForTitle(wikiTitle, { language, fetchImpl });
  const sourceUrl = summary?.sourceUrl || `https://www.wikidata.org/wiki/${encodeURIComponent(match.id)}`;
  const imageUrl = summary?.imageUrl || commonsFileUrl(imageClaim);
  const bio = cleanText(summary?.extract || description, 1400);
  if (!sourceUrl || (!bio && !imageUrl)) return null;
  return {
    normalizedArtist,
    displayName,
    summary: '',
    bio,
    profileImageUrl: imageUrl,
    profileImageCdnUrl: '',
    profileImageObjectKey: '',
    pocketmonstersUrl: '',
    pocketmonstersId: '',
    bulbapediaUrl: '',
    bulbapediaTitle: '',
    sourceName: summary?.sourceUrl ? 'Wikipedia' : 'Wikidata',
    sourceUrl,
    sourceAttribution: {
      wikidata: {
        name: summary?.sourceUrl ? 'Wikipedia/Wikidata' : 'Wikidata',
        url: sourceUrl,
        wikidataId: match.id,
      },
    },
    rawMetadata: {
      wikidataId: match.id,
      title: displayName,
      fetchedAt: new Date().toISOString(),
    },
  };
}

async function upsertProfile(pool, profile) {
  await pool.query(
    `
      insert into public.marketplace_artist_profiles (
        normalized_artist,
        display_name,
        summary,
        bio,
        profile_image_url,
        profile_image_cdn_url,
        profile_image_object_key,
        pocketmonsters_url,
        pocketmonsters_id,
        bulbapedia_url,
        bulbapedia_title,
        source_name,
        source_url,
        source_attribution,
        fetched_at,
        raw_metadata,
        updated_at
      )
      values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14::jsonb, now(), $15::jsonb, now())
      on conflict (normalized_artist) do update set
        display_name = excluded.display_name,
        summary = excluded.summary,
        bio = excluded.bio,
        profile_image_url = excluded.profile_image_url,
        profile_image_cdn_url = excluded.profile_image_cdn_url,
        profile_image_object_key = excluded.profile_image_object_key,
        pocketmonsters_url = excluded.pocketmonsters_url,
        pocketmonsters_id = excluded.pocketmonsters_id,
        bulbapedia_url = excluded.bulbapedia_url,
        bulbapedia_title = excluded.bulbapedia_title,
        source_name = excluded.source_name,
        source_url = excluded.source_url,
        source_attribution = excluded.source_attribution,
        fetched_at = excluded.fetched_at,
        raw_metadata = excluded.raw_metadata,
        updated_at = now()
    `,
    [
      profile.normalizedArtist,
      profile.displayName,
      profile.summary || '',
      profile.bio,
      profile.profileImageUrl,
      profile.profileImageCdnUrl || '',
      profile.profileImageObjectKey || '',
      profile.pocketmonstersUrl || '',
      profile.pocketmonstersId || '',
      profile.bulbapediaUrl || '',
      profile.bulbapediaTitle || '',
      profile.sourceName,
      profile.sourceUrl,
      JSON.stringify(profile.sourceAttribution || {}),
      JSON.stringify(profile.rawMetadata || {}),
    ],
  );
}

async function importArtistProfiles({ pool, options, fetchImpl = fetch }) {
  if (options.source === 'pocketmonsters') {
    return importPocketMonstersArtistProfiles({ pool, options, fetchImpl });
  }
  const rows = await fetchArtistRows(pool, options);
  const counts = {
    scanned: rows.length,
    matched: 0,
    upserted: 0,
    skipped: 0,
    ambiguous: 0,
    imageCached: 0,
    imageCacheNeeded: 0,
    reasons: {},
  };
  const samples = [];
  const report = [];
  let staffByArtist = new Map();
  if (['all', 'pocketmonsters'].includes(options.source) || options.pocketmonstersUrl) {
    const staffRows = options.pocketmonstersUrl
      ? [
          {
            name: options.artist || options.pocketmonstersUrl,
            normalizedArtist: options.artistKeys[0] || '',
            sourceUrl: options.pocketmonstersUrl,
          },
        ]
      : await pocketMonstersStaffIndex({ fetchImpl });
    staffByArtist = new Map(staffRows.map((staff) => [staff.normalizedArtist, staff]));
  }

  await mapWithConcurrency(rows, options.concurrency, async (row) => {
    const parts = {};
    if (['all', 'pocketmonsters'].includes(options.source)) {
      parts.pocketmonsters = await trustedPocketMonstersProfileForArtist(row, {
        staffByArtist,
        fetchImpl,
      });
    }
    let bulbapediaDiagnostics = null;
    if (['all', 'bulbapedia'].includes(options.source)) {
      bulbapediaDiagnostics = {};
      parts.bulbapedia = await fetchBulbapediaSummaryForArtist(row, {
        fetchImpl,
        diagnostics: bulbapediaDiagnostics,
      });
    }
    if (options.source === 'wikidata') {
      parts.wikidata = await trustedProfileForArtist(row, {
        language: options.language,
        fetchImpl,
      });
    }
    let profile = mergeWithExistingProfile(mergeProfileParts(row, parts), row);
    if (!profile) {
      const reason = bulbapediaDiagnostics?.reason || 'no_verified_profile_match';
      counts.skipped += 1;
      incrementReason(counts, reason);
      report.push({
        artist: row.artist || row.illustrator,
        normalizedArtist: row.normalized_artist,
        status: 'skipped',
        reason,
        diagnostics: bulbapediaDiagnostics?.details || undefined,
      });
      return;
    }
    let imageCache = null;
    if (options.apply && options.cacheImages && profile.profileImageUrl) {
      imageCache = await cacheProfileImage(profile, { fetchImpl });
      profile = imageCache.profile;
      if (imageCache.cached) counts.imageCached += 1;
      else counts.imageCacheNeeded += 1;
    } else if (profile.profileImageUrl && !profile.profileImageCdnUrl) {
      counts.imageCacheNeeded += 1;
    }
    counts.matched += 1;
    incrementReason(counts, parts.bulbapedia ? 'matched_bulbapedia' : 'matched_other_source');
    samples.push({
      artist: row.artist || row.illustrator,
      displayName: profile.displayName,
      sourceUrl: profile.sourceUrl,
      imageUrl: profile.profileImageCdnUrl || profile.profileImageUrl,
      bulbapediaUrl: profile.bulbapediaUrl,
    });
    if (options.apply) {
      await upsertProfile(pool, profile);
      counts.upserted += 1;
    }
    report.push({
      artist: row.artist || row.illustrator,
      normalizedArtist: profile.normalizedArtist,
      status: options.apply ? 'upserted' : 'matched_dry_run',
      sourceUrl: profile.sourceUrl,
      pocketmonstersUrl: profile.pocketmonstersUrl,
      bulbapediaUrl: profile.bulbapediaUrl,
      profileImageUrl: profile.profileImageUrl,
      profileImageCdnUrl: profile.profileImageCdnUrl,
      imageCache: imageCache?.reason || (profile.profileImageUrl ? 'cache_needed' : 'no_image'),
    });
  });
  return { counts, samples, report };
}

async function importPocketMonstersArtistProfiles({ pool, options, fetchImpl = fetch }) {
  const staffRows = await pocketMonstersStaffIndex({ fetchImpl });
  const artistRows = await fetchArtistRows(pool, {
    limit: Infinity,
    refreshExisting: true,
    artistKeys: [],
  });
  const existingByArtist = new Map(artistRows.map((row) => [row.normalized_artist, row]));
  let sourceRows = staffRows;
  if (options.pocketmonstersUrl) {
    const html = await fetchText(options.pocketmonstersUrl, fetchImpl);
    const parsed = parsePocketMonstersProfile(html || '', options.pocketmonstersUrl);
    const name = options.artist || parsed.displayName || options.pocketmonstersUrl;
    sourceRows = [
      {
        name,
        normalizedArtist: options.artistKeys[0] || normalizeArtist(parsed.displayName || name),
        sourceUrl: options.pocketmonstersUrl,
        parsedProfile: parsed.displayName ? parsed : null,
      },
    ];
  }
  const filteredRows = sourceRows
    .filter((row) => options.artistKeys.length === 0 || options.artistKeys.includes(row.normalizedArtist))
    .slice(0, Number.isFinite(options.limit) ? options.limit : sourceRows.length);
  const counts = {
    scanned: filteredRows.length,
    matched: 0,
    upserted: 0,
    skipped: 0,
    ambiguous: 0,
    imageCached: 0,
    imageCacheNeeded: 0,
    reasons: {},
  };
  const samples = [];
  const report = [];
  await mapWithConcurrency(filteredRows, options.concurrency, async (row) => {
    if (!existingByArtist.has(row.normalizedArtist)) {
      counts.skipped += 1;
      report.push({
        artist: row.name,
        normalizedArtist: row.normalizedArtist,
        status: 'skipped',
        reason: 'unknown_artist_not_in_artist_table',
        sourceUrl: row.sourceUrl,
      });
      return;
    }
    const baseRow = existingByArtist.get(row.normalizedArtist) || {
      artist: row.name,
      illustrator: row.name,
      normalized_artist: row.normalizedArtist,
    };
    const pocketmonsters = row.parsedProfile
      ? { normalizedArtist: row.normalizedArtist, ...row.parsedProfile }
      : await trustedPocketMonstersProfileFromStaff(row, { fetchImpl });
    const bulbapediaDiagnostics = {};
    const bulbapedia = ['all', 'bulbapedia', 'pocketmonsters'].includes(options.source)
      ? await fetchBulbapediaSummaryForArtist(baseRow, { fetchImpl, diagnostics: bulbapediaDiagnostics })
      : null;
    let profile = mergeWithExistingProfile(mergeProfileParts(baseRow, { pocketmonsters, bulbapedia }), baseRow);
    if (!profile) {
      const reason = bulbapediaDiagnostics.reason || 'no_verified_profile_match';
      counts.skipped += 1;
      incrementReason(counts, reason);
      report.push({
        artist: row.name,
        normalizedArtist: row.normalizedArtist,
        status: 'skipped',
        reason,
        diagnostics: bulbapediaDiagnostics.details || undefined,
      });
      return;
    }
    let imageCache = null;
    if (options.apply && options.cacheImages && profile.profileImageUrl) {
      imageCache = await cacheProfileImage(profile, { fetchImpl });
      profile = imageCache.profile;
      if (imageCache.cached) counts.imageCached += 1;
      else counts.imageCacheNeeded += 1;
    } else if (profile.profileImageUrl && !profile.profileImageCdnUrl) {
      counts.imageCacheNeeded += 1;
    }
    counts.matched += 1;
    incrementReason(counts, bulbapedia ? 'matched_bulbapedia' : 'matched_other_source');
    samples.push({
      artist: row.name,
      displayName: profile.displayName,
      sourceUrl: profile.sourceUrl,
      imageUrl: profile.profileImageCdnUrl || profile.profileImageUrl,
      bulbapediaUrl: profile.bulbapediaUrl,
    });
    if (options.apply) {
      await upsertProfile(pool, profile);
      counts.upserted += 1;
    }
    report.push({
      artist: row.name,
      normalizedArtist: profile.normalizedArtist,
      status: options.apply ? 'upserted' : 'matched_dry_run',
      sourceUrl: profile.sourceUrl,
      pocketmonstersUrl: profile.pocketmonstersUrl,
      bulbapediaUrl: profile.bulbapediaUrl,
      profileImageUrl: profile.profileImageUrl,
      profileImageCdnUrl: profile.profileImageCdnUrl,
      imageCache: imageCache?.reason || (profile.profileImageUrl ? 'cache_needed' : 'no_image'),
    });
  });
  return { counts, samples, report };
}

async function main() {
  loadLocalEnv();
  const options = parseArgs(process.argv.slice(2));
  const pool = createPool();
  try {
    const mode = options.auditImageCache
      ? 'image-cache-audit'
      : options.recacheMissingImages
        ? options.apply
          ? 'recache-missing-images'
          : 'recache-missing-images-dry-run'
        : options.apply
          ? 'apply'
          : 'dry-run';
    const result = options.auditImageCache
      ? await auditArtistProfileImageCache({ pool, options })
      : options.recacheMissingImages
        ? await recacheMissingArtistProfileImages({ pool, options })
        : await importArtistProfiles({ pool, options });
    if (options.writeReport) {
      const reportPath = path.resolve(ROOT_DIR, options.writeReport);
      fs.mkdirSync(path.dirname(reportPath), { recursive: true });
      fs.writeFileSync(
        reportPath,
        JSON.stringify(
          {
            generatedAt: new Date().toISOString(),
            mode,
            options: {
              limit: Number.isFinite(options.limit) ? options.limit : 'all',
              source: options.source,
              concurrency: options.concurrency,
              artist: options.artist,
              refreshExisting: options.refreshExisting,
              cacheImages: options.cacheImages,
              auditImageCache: options.auditImageCache,
              recacheMissingImages: options.recacheMissingImages,
            },
            counts: result.counts,
            samples: result.samples,
            report: result.report,
          },
          null,
          2,
        ),
      );
    }
    console.log(JSON.stringify({ mode, ...result }, null, 2));
    if (!options.apply && !options.auditImageCache) {
      console.log('Dry run only; pass --apply to save trusted profiles.');
    }
  } finally {
    await pool.end().catch(() => {});
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}

module.exports = {
  cleanText,
  auditArtistProfileImageCache,
  importPocketMonstersArtistProfiles,
  importArtistProfiles,
  cacheProfileImage,
  fetchBulbapediaSummaryForArtist,
  getArtistR2Config,
  mergeProfileParts,
  normalizeArtist,
  publicUrlForKey,
  pageNumbersFromPocketMonstersIndex,
  parsePocketMonstersProfile,
  parsePocketMonstersStaffIndex,
  parseArgs,
  pocketMonstersStaffIndex,
  recacheMissingArtistProfileImages,
  trustedProfileForArtist,
  trustedPocketMonstersProfileFromStaff,
  trustedPocketMonstersProfileForArtist,
};
