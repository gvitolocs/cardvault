#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { GetObjectCommand, PutObjectCommand, S3Client } = require('@aws-sdk/client-s3');
const { Pool } = require('pg');
const sharp = require('sharp');

const {
  getArtistR2Config,
  normalizeArtist,
  publicUrlForKey,
} = require('./import-marketplace-artist-profiles');
const { projectedRaritySql } = require('../api/_marketplace_card_rarity');

const ROOT_DIR = path.resolve(__dirname, '..');
const POKOINPOS_ROOT = process.env.POKOINPOS_ROOT || '/Users/giuseppe/pokoinpos';
const DEFAULT_ORACLE_ENV = path.join(POKOINPOS_ROOT, 'deploy/env/peer4-postgres.env');
const DEFAULT_AUDIT_REPORT = path.join(
  ROOT_DIR,
  'workflows',
  'reports',
  'artist-profile-grey-placeholder-audit-20260525.json',
);
const DEFAULT_AVATAR_SIZE = 512;
const DEFAULT_CROP_Y_RATIO = 0.18;
const CROP_STRATEGY_NAME = 'upper_artwork_square_v2';

function cleanText(value, maxLength = 1000) {
  return String(value || '').trim().replace(/\s+/g, ' ').slice(0, maxLength);
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

function parseNumber(value, fallback, { min = 0, max = Number.MAX_SAFE_INTEGER } = {}) {
  const number = Number(value);
  if (!Number.isFinite(number)) return fallback;
  return Math.min(Math.max(number, min), max);
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
    concurrency: 2,
    artist: '',
    artistKeys: [],
    writeReport: '',
    auditReport: DEFAULT_AUDIT_REPORT,
    avatarSize: DEFAULT_AVATAR_SIZE,
    cropYRatio: DEFAULT_CROP_Y_RATIO,
    includeMissing: true,
    includePlaceholders: true,
    regenerateGeneratedFallbacks: false,
    sampleDir: '',
    sampleLimit: 0,
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
    } else if (rawKey === 'dry-run') {
      options.apply = false;
    } else if (rawKey === 'limit') {
      options.limit = String(value).toLowerCase() === 'all'
        ? Infinity
        : parsePositiveInt(value, 100, 10000);
    } else if (rawKey === 'concurrency') {
      options.concurrency = parsePositiveInt(value, 2, 6);
    } else if (rawKey === 'artist') {
      options.artist = cleanText(value, 1000);
      options.artistKeys = parseArtistList(value);
    } else if (rawKey === 'write-report') {
      options.writeReport = cleanText(value, 1000);
    } else if (rawKey === 'audit-report') {
      options.auditReport = path.resolve(ROOT_DIR, cleanText(value, 1000));
    } else if (rawKey === 'avatar-size') {
      options.avatarSize = parsePositiveInt(value, DEFAULT_AVATAR_SIZE, 2048);
    } else if (rawKey === 'crop-y-ratio') {
      options.cropYRatio = parseNumber(value, DEFAULT_CROP_Y_RATIO, { min: 0, max: 0.5 });
    } else if (rawKey === 'regenerate-generated-fallbacks') {
      options.regenerateGeneratedFallbacks = true;
    } else if (rawKey === 'sample-dir') {
      options.sampleDir = path.resolve(ROOT_DIR, cleanText(value, 1000));
      if (!options.sampleLimit) options.sampleLimit = 10;
    } else if (rawKey === 'sample-limit') {
      options.sampleLimit = parsePositiveInt(value, 10, 1000);
    } else if (rawKey === 'missing-only') {
      options.includeMissing = true;
      options.includePlaceholders = false;
    } else if (rawKey === 'placeholders-only') {
      options.includeMissing = false;
      options.includePlaceholders = true;
    } else if (rawKey === 'no-missing') {
      options.includeMissing = false;
    } else if (rawKey === 'no-placeholders') {
      options.includePlaceholders = false;
    }
  }

  if (!options.includeMissing && !options.includePlaceholders && !options.regenerateGeneratedFallbacks) {
    throw new Error('At least one target class is required: missing, placeholder, or generated fallback regeneration.');
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
    max: 3,
    idleTimeoutMillis: 10_000,
    connectionTimeoutMillis: 10_000,
    ssl: { rejectUnauthorized: false },
    application_name: 'marketplace-artist-fallback-avatar-generator',
  });
}

function slugForKey(value) {
  return normalizeArtist(value).replace(/\s+/g, '-');
}

function loadPlaceholderArtists(auditReportPath = DEFAULT_AUDIT_REPORT) {
  if (!auditReportPath || !fs.existsSync(auditReportPath)) return new Map();
  const payload = JSON.parse(fs.readFileSync(auditReportPath, 'utf8'));
  const rows = [
    ...(Array.isArray(payload.affected) ? payload.affected : []),
    ...(Array.isArray(payload.affectedSamples) ? payload.affectedSamples : []),
  ];
  const byArtist = new Map();
  for (const row of rows) {
    const normalizedArtist = normalizeArtist(row.normalizedArtist || row.normalized_artist || row.artist);
    if (!normalizedArtist) continue;
    byArtist.set(normalizedArtist, {
      status: cleanText(row.status, 80) || 'placeholder_profile_image',
      sourceImageUrl: cleanText(row.sourceImageUrl || row.profileImageUrl, 1000),
      sha256: cleanText(row.sha256 || row.image?.sha256, 128),
      cdnUrl: cleanText(row.cdnUrl || row.profileImageCdnUrl, 1000),
      objectKey: cleanText(row.profileImageObjectKey, 1000),
    });
  }
  return byArtist;
}

function hasNoProfileImage(row) {
  return !cleanText(row.profile_image_url) &&
    !cleanText(row.profile_image_cdn_url) &&
    !cleanText(row.profile_image_object_key);
}

function generatedFallbackFromRow(row) {
  const sourceAttribution =
    row.source_attribution && typeof row.source_attribution === 'object'
      ? row.source_attribution
      : {};
  const rawMetadata =
    row.raw_metadata && typeof row.raw_metadata === 'object'
      ? row.raw_metadata
      : {};
  const generatedProfileImage =
    sourceAttribution.generatedProfileImage && typeof sourceAttribution.generatedProfileImage === 'object'
      ? sourceAttribution.generatedProfileImage
      : rawMetadata.generatedProfileImage && typeof rawMetadata.generatedProfileImage === 'object'
        ? rawMetadata.generatedProfileImage
        : null;
  if (!generatedProfileImage || generatedProfileImage.source !== 'card_art_fallback') {
    return null;
  }
  return generatedProfileImage;
}

function isGeneratedFallbackObjectKey(value) {
  return cleanText(value, 1000).startsWith('artist-profiles/generated/');
}

function isCurrentGeneratedFallbackImage(row) {
  if (isGeneratedFallbackObjectKey(row.profile_image_object_key)) return true;
  const candidates = [
    row.profile_image_cdn_url,
    row.profile_image_url,
  ].map((value) => cleanText(value, 1000));
  return candidates.some((value) => {
    try {
      const url = new URL(value);
      return url.pathname.includes('/artist-profiles/generated/');
    } catch {
      return value.includes('/artist-profiles/generated/');
    }
  });
}

function auditedPlaceholderStillCurrent(row, audit) {
  if (!audit) return false;
  const currentSourceUrl = cleanText(row.profile_image_url, 1000);
  const currentCdnUrl = cleanText(row.profile_image_cdn_url, 1000);
  const currentObjectKey = cleanText(row.profile_image_object_key, 1000);
  if (audit.objectKey && currentObjectKey === audit.objectKey) return true;
  if (audit.cdnUrl && currentCdnUrl === audit.cdnUrl) return true;
  if (audit.sourceImageUrl && currentSourceUrl === audit.sourceImageUrl) return true;
  return false;
}

function targetReasonForRow(row, placeholderArtists, options, generatedFallback = generatedFallbackFromRow(row)) {
  if (
    options.regenerateGeneratedFallbacks &&
    generatedFallback &&
    isCurrentGeneratedFallbackImage(row)
  ) {
    return cleanText(generatedFallback.reason, 120) || 'generated_card_art_fallback';
  }

  const normalizedArtist = normalizeArtist(row.normalized_artist);
  const placeholderAudit = placeholderArtists.get(normalizedArtist);
  if (
    options.includePlaceholders &&
    auditedPlaceholderStillCurrent(row, placeholderAudit)
  ) {
    return 'placeholder_profile_image';
  }
  if (options.includeMissing && hasNoProfileImage(row)) {
    return 'missing_profile_image';
  }
  return '';
}

async function fetchArtistTargets(pool, options, placeholderArtists) {
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
        profiles.profile_image_url,
        profiles.profile_image_cdn_url,
        profiles.profile_image_object_key,
        profiles.pocketmonsters_url,
        profiles.pocketmonsters_id,
        profiles.bulbapedia_url,
        profiles.bulbapedia_title,
        profiles.source_name,
        profiles.source_url,
        profiles.source_attribution,
        profiles.raw_metadata
      from public.marketplace_blueprint_artists artists
      left join public.marketplace_artist_profiles profiles
        on profiles.normalized_artist = artists.normalized_artist
      where coalesce(artists.normalized_artist, '') <> ''
        and (
          cardinality($1::text[]) = 0
          or artists.normalized_artist = any($1::text[])
          or lower(artists.artist) = any($1::text[])
          or lower(artists.illustrator) = any($1::text[])
        )
      order by artists.normalized_artist asc, artists.matched_at desc
    `,
    [options.artistKeys],
  );

  const targets = [];
  const skippedRealProfileImages = [];
  for (const row of result.rows) {
    const generatedFallback = generatedFallbackFromRow(row);
    if (
      options.regenerateGeneratedFallbacks &&
      generatedFallback &&
      !isCurrentGeneratedFallbackImage(row)
    ) {
      skippedRealProfileImages.push({
        artist: displayNameForTarget(row),
        normalizedArtist: normalizeArtist(row.normalized_artist),
        status: 'skipped',
        reason: 'current_profile_image_is_not_generated_fallback',
        profileImageCdnUrl: cleanText(row.profile_image_cdn_url, 1000),
        profileImageObjectKey: cleanText(row.profile_image_object_key, 1000),
        previousGeneratedAt: cleanText(generatedFallback.generatedAt, 80),
      });
      continue;
    }

    const reason = targetReasonForRow(row, placeholderArtists, options, generatedFallback);
    if (!reason) continue;
    targets.push({
      ...row,
      normalized_artist: normalizeArtist(row.normalized_artist),
      generation_reason: reason,
      placeholder_audit: placeholderArtists.get(normalizeArtist(row.normalized_artist)) || null,
      generated_profile_image: generatedFallback,
      regenerate_generated_fallback: Boolean(options.regenerateGeneratedFallbacks && generatedFallback),
    });
    if (Number.isFinite(options.limit) && targets.length >= options.limit) break;
  }
  targets.skippedRealProfileImages = skippedRealProfileImages;
  return targets;
}

function sourceFullImageUrl(row) {
  const candidates = [
    row.cdn_image_url,
    row.image_url,
  ].map((value) => cleanText(value, 1000)).filter(Boolean);
  return candidates.find((value) => !isPreviewLikeUrl(value)) || '';
}

function isPreviewLikeUrl(value) {
  const url = String(value || '').toLowerCase();
  return url.includes('/previews/') || url.includes('/preview_') || url.includes('_homepage.');
}

function cardImageFetchUrl(value) {
  const clean = cleanText(value, 1000);
  if (!clean) return '';
  try {
    const url = new URL(clean);
    if (url.hostname === 'cdn.pokoin.com') {
      return `https://pokoin.com/card-images${url.pathname}`;
    }
  } catch {
    return clean;
  }
  return clean;
}

function objectKeyFromPublicImageUrl(value) {
  const clean = cleanText(value, 1000);
  if (!clean) return '';
  try {
    const url = new URL(clean);
    if (url.hostname === 'pokoin.com' && url.pathname.startsWith('/card-images/')) {
      return decodeURIComponent(url.pathname.slice('/card-images/'.length));
    }
    if (url.hostname === 'cdn.pokoin.com') {
      return decodeURIComponent(url.pathname.replace(/^\/+/, ''));
    }
  } catch {
    return '';
  }
  return '';
}

function normalizeCardText(value) {
  return cleanText(value, 500)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

function classifyCardArt(row) {
  const text = normalizeCardText([
    row.rarity,
    row.expansion_number,
    row.product_variant,
    row.name,
  ].join(' '));

  if (
    /\bspecial illustration rare\b/.test(text) ||
    /\billustration rare\b/.test(text) ||
    /\bspecial art rare\b/.test(text) ||
    /\bart rare\b/.test(text) ||
    /\bcharacter rare\b/.test(text) ||
    /\bcharacter super rare\b/.test(text)
  ) {
    return { category: 'illustration', priority: 0 };
  }
  if (
    /\bfull art\b/.test(text) ||
    /\bfullart\b/.test(text) ||
    /\balternate art\b/.test(text) ||
    /\balt art\b/.test(text) ||
    /\bultra rare\b/.test(text) ||
    /\bsecret rare\b/.test(text) ||
    /\bhyper rare\b/.test(text)
  ) {
    return { category: 'full_art', priority: 1 };
  }
  return { category: 'normal_art', priority: 2 };
}

function compareCardsForAvatar(a, b) {
  if (a.artPriority !== b.artPriority) return a.artPriority - b.artPriority;
  const aProjected = new Date(a.projected_at || 0).getTime() || 0;
  const bProjected = new Date(b.projected_at || 0).getTime() || 0;
  if (aProjected !== bProjected) return bProjected - aProjected;
  return Number(a.card_id || 0) - Number(b.card_id || 0);
}

async function fetchCandidateCards(pool, normalizedArtists) {
  if (normalizedArtists.length === 0) return new Map();
  const raritySql = projectedRaritySql({
    rarityColumn: 'candidates.rarity',
    collectorNumberSql: 'versions.expansion_number',
  });
  const result = await pool.query(
    `
      select
        artist.normalized_artist,
        artist.artist,
        artist.illustrator,
        versions.card_id,
        versions.blueprint_id,
        versions.name,
        versions.expansion_name,
        versions.expansion_number,
        versions.product_variant,
        versions.cdn_image_url,
        versions.image_url,
        versions.homepage_image_url,
        versions.preview_image_url,
        versions.projected_at,
        ${raritySql} as rarity,
        candidates.card_type,
        urls.canonical_path
      from public.marketplace_blueprint_artists artist
      join public.marketplace_card_versions versions
        on versions.blueprint_id = artist.blueprint_id
      left join public.marketplace_search_candidates candidates
        on candidates.card_id = versions.card_id
      left join public.cardtrader_pokemon_blueprints blueprints
        on blueprints.id = versions.card_id
      left join public.marketplace_blueprint_tcg_metadata tcg_metadata
        on tcg_metadata.blueprint_id = versions.card_id
      left join public.marketplace_card_urls urls
        on urls.card_id = versions.card_id
        and urls.language = 'en'
      where artist.normalized_artist = any($1::text[])
        and versions.product_type = 'card'
        and coalesce(versions.cdn_image_url, versions.image_url, '') <> ''
    `,
    [normalizedArtists],
  );

  const byArtist = new Map();
  for (const row of result.rows) {
    const sourceImageUrl = sourceFullImageUrl(row);
    if (!sourceImageUrl) continue;
    const art = classifyCardArt(row);
    const card = {
      ...row,
      sourceImageUrl,
      sourceImageFetchUrl: cardImageFetchUrl(sourceImageUrl),
      sourceImageObjectKey: objectKeyFromPublicImageUrl(sourceImageUrl),
      artCategory: art.category,
      artPriority: art.priority,
      canonicalUrl: row.canonical_path ? `https://pokoin.com${row.canonical_path}` : '',
    };
    const list = byArtist.get(row.normalized_artist) || [];
    list.push(card);
    byArtist.set(row.normalized_artist, list);
  }

  for (const [artist, cards] of byArtist.entries()) {
    cards.sort(compareCardsForAvatar);
    byArtist.set(artist, cards);
  }
  return byArtist;
}

function cropSettingsForArtCategory(artCategory) {
  if (artCategory === 'normal_art') {
    return {
      widthRatio: 0.52,
      maxBottomRatio: 0.48,
    };
  }
  return {
    widthRatio: 0.55,
    maxBottomRatio: 0.46,
  };
}

function calculateUpperArtworkSquareCrop({
  width,
  height,
  yRatio = DEFAULT_CROP_Y_RATIO,
  artCategory = 'normal_art',
}) {
  const imageWidth = Number(width || 0);
  const imageHeight = Number(height || 0);
  if (!Number.isFinite(imageWidth) || !Number.isFinite(imageHeight) || imageWidth < 1 || imageHeight < 1) {
    throw new Error('Valid image dimensions are required.');
  }

  if (imageWidth >= imageHeight) {
    const size = Math.floor(Math.min(imageWidth, imageHeight));
    return {
      left: Math.round(Math.max(0, imageWidth - size) / 2),
      top: Math.round(Math.max(0, imageHeight - size) / 2),
      width: size,
      height: size,
    };
  }

  const settings = cropSettingsForArtCategory(artCategory);
  const top = Math.max(0, Math.round(imageHeight * yRatio));
  const maxBottom = Math.max(top + 1, Math.round(imageHeight * settings.maxBottomRatio));
  const availableArtworkHeight = Math.max(1, maxBottom - top);
  const preferredWidth = Math.floor(imageWidth * settings.widthRatio);
  const size = Math.max(
    1,
    Math.floor(Math.min(preferredWidth, availableArtworkHeight, imageWidth, imageHeight)),
  );
  const maxLeft = Math.max(0, Math.floor(imageWidth - size));
  const maxTop = Math.max(0, Math.floor(imageHeight - size));
  return {
    left: Math.round(maxLeft / 2),
    top: Math.min(top, maxTop),
    width: size,
    height: size,
  };
}

async function downloadImage(sourceUrl, fetchImpl = fetch) {
  const response = await fetchImpl(sourceUrl, {
    headers: {
      'User-Agent': 'PokoinArtistFallbackAvatarGenerator/1.0 (https://pokoin.com)',
      Accept: 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    },
  });
  if (!response.ok) {
    throw new Error(`image_fetch_${response.status}`);
  }
  const contentType = cleanText(response.headers.get('content-type'), 120).toLowerCase();
  if (contentType && !contentType.startsWith('image/')) {
    throw new Error('image_content_type_invalid');
  }
  return Buffer.from(await response.arrayBuffer());
}

async function streamToBuffer(stream) {
  const chunks = [];
  for await (const chunk of stream) {
    chunks.push(Buffer.from(chunk));
  }
  return Buffer.concat(chunks);
}

async function getR2ObjectBody({ client, r2Config, objectKey }) {
  const response = await client.send(
    new GetObjectCommand({
      Bucket: r2Config.bucket,
      Key: objectKey,
    }),
  );
  return streamToBuffer(response.Body);
}

async function loadSourceImageBody({
  card,
  client,
  r2Config,
  fetchImpl = fetch,
}) {
  if (client && r2Config && card.sourceImageObjectKey) {
    try {
      return await getR2ObjectBody({
        client,
        r2Config,
        objectKey: card.sourceImageObjectKey,
      });
    } catch (error) {
      if (!String(error?.name || error?.message || '').includes('NoSuchKey')) {
        throw error;
      }
    }
  }
  return downloadImage(card.sourceImageFetchUrl, fetchImpl);
}

async function generateAvatarPng(sourceBody, { avatarSize, cropYRatio, artCategory }) {
  const image = sharp(sourceBody, { failOn: 'none' });
  const metadata = await image.metadata();
  const crop = calculateUpperArtworkSquareCrop({
    width: metadata.width,
    height: metadata.height,
    yRatio: cropYRatio,
    artCategory,
  });
  const output = await image
    .rotate()
    .extract(crop)
    .resize(avatarSize, avatarSize, {
      fit: 'cover',
      kernel: sharp.kernel.lanczos3,
      withoutEnlargement: false,
    })
    .png()
    .toBuffer();
  return {
    output,
    metadata: {
      width: metadata.width || 0,
      height: metadata.height || 0,
      format: metadata.format || '',
    },
    crop,
  };
}

function createS3Client(r2Config) {
  return new S3Client({
    region: 'auto',
    endpoint: `https://${r2Config.accountId}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: r2Config.accessKeyId,
      secretAccessKey: r2Config.secretAccessKey,
    },
  });
}

async function uploadAvatar({ client, r2Config, objectKey, body }) {
  await client.send(
    new PutObjectCommand({
      Bucket: r2Config.bucket,
      Key: objectKey,
      Body: body,
      ContentType: 'image/png',
      CacheControl: 'public, max-age=31536000, immutable',
    }),
  );
  return publicUrlForKey(r2Config, objectKey);
}

function displayNameForTarget(target) {
  return cleanText(
    target.profile_display_name ||
      target.artist ||
      target.illustrator ||
      target.normalized_artist,
    220,
  );
}

function sourceNameForInsert(target) {
  return cleanText(target.source_name, 220) || 'Generated card art';
}

function sourceUrlForInsert(target, card) {
  return cleanText(target.source_url, 1000) || cleanText(card.canonicalUrl, 1000) || cleanText(card.sourceImageUrl, 1000);
}

function generatedMetadata({ target, card, publicUrl, objectKey, crop, sourceMetadata, options, generatedAt }) {
  const previousGeneratedProfileImage =
    target.generated_profile_image && typeof target.generated_profile_image === 'object'
      ? target.generated_profile_image
      : null;
  const sourceCard = {
    normalizedArtist: target.normalized_artist,
    artist: displayNameForTarget(target),
    blueprintId: cleanText(card.blueprint_id, 80),
    cardId: cleanText(card.card_id, 80),
    name: cleanText(card.name, 240),
    expansionName: cleanText(card.expansion_name, 240),
    expansionNumber: cleanText(card.expansion_number, 120),
    rarity: cleanText(card.rarity, 120),
    artCategory: card.artCategory,
    sourceImageUrl: card.sourceImageUrl,
    sourceImageObjectKey: card.sourceImageObjectKey,
    canonicalPath: cleanText(card.canonical_path, 1000),
    canonicalUrl: cleanText(card.canonicalUrl, 1000),
  };
  return {
    source: 'card_art_fallback',
    reason: target.generation_reason,
    generatedAt,
    profileImageCdnUrl: publicUrl,
    profileImageObjectKey: objectKey,
    cropStrategy: {
      name: CROP_STRATEGY_NAME,
      yRatio: options.cropYRatio,
      outputSize: options.avatarSize,
      sourceWidth: sourceMetadata.width,
      sourceHeight: sourceMetadata.height,
      sourceFormat: sourceMetadata.format,
      artCategory: card.artCategory,
      crop,
    },
    regeneratedFrom: previousGeneratedProfileImage
      ? {
          generatedAt: cleanText(previousGeneratedProfileImage.generatedAt, 80),
          cropStrategy: previousGeneratedProfileImage.cropStrategy || null,
          sourceCard: previousGeneratedProfileImage.sourceCard || null,
        }
      : undefined,
    sourceCard,
  };
}

async function upsertGeneratedProfileImage(pool, target, card, generated) {
  const attribution = {
    generatedProfileImage: {
      source: generated.source,
      reason: generated.reason,
      generatedAt: generated.generatedAt,
      cropStrategy: generated.cropStrategy,
      sourceCard: generated.sourceCard,
      regeneratedFrom: generated.regeneratedFrom,
    },
  };
  const rawMetadata = {
    generatedProfileImage: generated,
  };
  const result = await pool.query(
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
        display_name = coalesce(nullif(public.marketplace_artist_profiles.display_name, ''), excluded.display_name),
        summary = public.marketplace_artist_profiles.summary,
        bio = public.marketplace_artist_profiles.bio,
        profile_image_url = excluded.profile_image_url,
        profile_image_cdn_url = excluded.profile_image_cdn_url,
        profile_image_object_key = excluded.profile_image_object_key,
        pocketmonsters_url = public.marketplace_artist_profiles.pocketmonsters_url,
        pocketmonsters_id = public.marketplace_artist_profiles.pocketmonsters_id,
        bulbapedia_url = public.marketplace_artist_profiles.bulbapedia_url,
        bulbapedia_title = public.marketplace_artist_profiles.bulbapedia_title,
        source_name = coalesce(nullif(public.marketplace_artist_profiles.source_name, ''), excluded.source_name),
        source_url = coalesce(nullif(public.marketplace_artist_profiles.source_url, ''), excluded.source_url),
        source_attribution = coalesce(public.marketplace_artist_profiles.source_attribution, '{}'::jsonb) || excluded.source_attribution,
        fetched_at = coalesce(public.marketplace_artist_profiles.fetched_at, excluded.fetched_at),
        raw_metadata = coalesce(public.marketplace_artist_profiles.raw_metadata, '{}'::jsonb) || excluded.raw_metadata,
        updated_at = now()
      where (
          coalesce(public.marketplace_artist_profiles.profile_image_url, '') = ''
          and coalesce(public.marketplace_artist_profiles.profile_image_cdn_url, '') = ''
          and coalesce(public.marketplace_artist_profiles.profile_image_object_key, '') = ''
        )
        or (
          $16::boolean
          and coalesce(public.marketplace_artist_profiles.profile_image_url, '') = $17
          and coalesce(public.marketplace_artist_profiles.profile_image_cdn_url, '') = $18
          and coalesce(public.marketplace_artist_profiles.profile_image_object_key, '') = $19
        )
        or (
          $20::boolean
          and coalesce(public.marketplace_artist_profiles.profile_image_object_key, '') = $21
          and coalesce(public.marketplace_artist_profiles.profile_image_object_key, '') like 'artist-profiles/generated/%'
        )
      returning normalized_artist
    `,
    [
      target.normalized_artist,
      displayNameForTarget(target),
      cleanText(target.profile_summary, 5000),
      cleanText(target.profile_bio, 5000),
      card.sourceImageUrl,
      generated.profileImageCdnUrl,
      generated.profileImageObjectKey,
      cleanText(target.pocketmonsters_url, 1000),
      cleanText(target.pocketmonsters_id, 80),
      cleanText(target.bulbapedia_url, 1000),
      cleanText(target.bulbapedia_title, 220),
      sourceNameForInsert(target),
      sourceUrlForInsert(target, card),
      JSON.stringify(attribution),
      JSON.stringify(rawMetadata),
      target.generation_reason === 'placeholder_profile_image',
      cleanText(target.profile_image_url, 1000),
      cleanText(target.profile_image_cdn_url, 1000),
      cleanText(target.profile_image_object_key, 1000),
      Boolean(target.regenerate_generated_fallback),
      cleanText(target.profile_image_object_key, 1000),
    ],
  );
  return result.rowCount > 0;
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

function incrementReason(counts, reason) {
  const key = cleanText(reason || 'unknown', 120) || 'unknown';
  counts.reasons[key] = (counts.reasons[key] || 0) + 1;
}

async function generateArtistFallbackAvatars({
  pool,
  options,
  fetchImpl = fetch,
  r2Config = getArtistR2Config(),
}) {
  const placeholderArtists = loadPlaceholderArtists(options.auditReport);
  const targets = await fetchArtistTargets(pool, options, placeholderArtists);
  const skippedRealProfileImages = Array.isArray(targets.skippedRealProfileImages)
    ? targets.skippedRealProfileImages
    : [];
  const cardsByArtist = await fetchCandidateCards(
    pool,
    targets.map((row) => row.normalized_artist),
  );
  const counts = {
    scanned: targets.length,
    placeholderProfileImage: targets.filter((row) => row.generation_reason === 'placeholder_profile_image').length,
    missingProfileImage: targets.filter((row) => row.generation_reason === 'missing_profile_image').length,
    candidatesWithCard: 0,
    generated: 0,
    uploaded: 0,
    upserted: 0,
    skipped: 0,
    skippedRealProfileImages: skippedRealProfileImages.length,
    failed: 0,
    reasons: {},
  };
  const report = [...skippedRealProfileImages];
  const samples = [];
  let writtenSampleCount = 0;

  if (options.apply && !r2Config) {
    throw new Error('R2 artist profile image configuration is required for --apply.');
  }
  const client = options.apply ? createS3Client(r2Config) : null;
  if (options.sampleDir) {
    fs.mkdirSync(options.sampleDir, { recursive: true });
  }

  await mapWithConcurrency(targets, options.concurrency, async (target) => {
    const cards = cardsByArtist.get(target.normalized_artist) || [];
    const card = cards[0];
    if (!card) {
      counts.skipped += 1;
      incrementReason(counts, 'no_full_size_card_image');
      report.push({
        artist: displayNameForTarget(target),
        normalizedArtist: target.normalized_artist,
        status: 'skipped',
        reason: 'no_full_size_card_image',
        generationReason: target.generation_reason,
      });
      return;
    }

    counts.candidatesWithCard += 1;
    const objectKey = `artist-profiles/generated/${slugForKey(target.normalized_artist)}.png`;
    const publicUrl = r2Config
      ? publicUrlForKey(r2Config, objectKey)
      : `https://pokoin.com/card-images/${objectKey}`;
    let generated = null;
    let status = options.apply ? 'generated' : 'matched_dry_run';
    let errorMessage = '';
    let localSamplePath = '';
    const shouldWriteSample = Boolean(
      options.sampleDir &&
        !options.apply &&
        writtenSampleCount < options.sampleLimit,
    );
    if (shouldWriteSample) {
      writtenSampleCount += 1;
    }

    try {
      if (options.apply) {
        const sourceBody = await loadSourceImageBody({
          card,
          client,
          r2Config,
          fetchImpl,
        });
        const avatar = await generateAvatarPng(sourceBody, {
          ...options,
          artCategory: card.artCategory,
        });
        const uploadedUrl = await uploadAvatar({
          client,
          r2Config,
          objectKey,
          body: avatar.output,
        });
        generated = generatedMetadata({
          target,
          card,
          publicUrl: uploadedUrl,
          objectKey,
          crop: avatar.crop,
          sourceMetadata: avatar.metadata,
          options,
          generatedAt: new Date().toISOString(),
        });
        const wroteProfile = await upsertGeneratedProfileImage(pool, target, card, generated);
        if (!wroteProfile) {
          throw new Error('profile_image_changed_before_update');
        }
        counts.generated += 1;
        counts.uploaded += 1;
        counts.upserted += 1;
      } else if (shouldWriteSample) {
        const sourceBody = await loadSourceImageBody({
          card,
          client: null,
          r2Config,
          fetchImpl,
        });
        const avatar = await generateAvatarPng(sourceBody, {
          ...options,
          artCategory: card.artCategory,
        });
        const fileName = `${slugForKey(target.normalized_artist)}-${cleanText(card.card_id, 80) || 'card'}.png`;
        localSamplePath = path.join(options.sampleDir, fileName);
        fs.writeFileSync(localSamplePath, avatar.output);
        status = 'sampled_dry_run';
        generated = {
          reason: target.generation_reason,
          profileImageCdnUrl: publicUrl,
          profileImageObjectKey: objectKey,
          cropStrategy: {
            name: CROP_STRATEGY_NAME,
            yRatio: options.cropYRatio,
            outputSize: options.avatarSize,
            sourceWidth: avatar.metadata.width,
            sourceHeight: avatar.metadata.height,
            sourceFormat: avatar.metadata.format,
            artCategory: card.artCategory,
            crop: avatar.crop,
          },
          sourceCard: {
            cardId: cleanText(card.card_id, 80),
            blueprintId: cleanText(card.blueprint_id, 80),
            name: cleanText(card.name, 240),
            expansionName: cleanText(card.expansion_name, 240),
            expansionNumber: cleanText(card.expansion_number, 120),
            rarity: cleanText(card.rarity, 120),
            artCategory: card.artCategory,
            sourceImageUrl: card.sourceImageUrl,
            canonicalUrl: cleanText(card.canonicalUrl, 1000),
          },
        };
      } else {
        generated = {
          reason: target.generation_reason,
          profileImageCdnUrl: publicUrl,
          profileImageObjectKey: objectKey,
          sourceCard: {
            cardId: cleanText(card.card_id, 80),
            blueprintId: cleanText(card.blueprint_id, 80),
            name: cleanText(card.name, 240),
            expansionName: cleanText(card.expansion_name, 240),
            expansionNumber: cleanText(card.expansion_number, 120),
            rarity: cleanText(card.rarity, 120),
            artCategory: card.artCategory,
            sourceImageUrl: card.sourceImageUrl,
            canonicalUrl: cleanText(card.canonicalUrl, 1000),
          },
        };
      }
      incrementReason(counts, card.artCategory);
    } catch (error) {
      counts.failed += 1;
      status = 'failed';
      errorMessage = error.message || String(error);
      incrementReason(counts, errorMessage);
    }

    const entry = {
      artist: displayNameForTarget(target),
      normalizedArtist: target.normalized_artist,
      status,
      error: errorMessage || undefined,
      generationReason: target.generation_reason,
      artCategory: card.artCategory,
      sourceCardName: card.name,
      sourceCardId: cleanText(card.card_id, 80),
      sourceBlueprintId: cleanText(card.blueprint_id, 80),
      sourceRarity: cleanText(card.rarity, 120),
      sourceImageUrl: card.sourceImageUrl,
      sourceImageFetchUrl: card.sourceImageFetchUrl,
      sourceImageObjectKey: card.sourceImageObjectKey,
      sourceCardUrl: card.canonicalUrl,
      profileImageCdnUrl: generated?.profileImageCdnUrl || publicUrl,
      profileImageObjectKey: objectKey,
      samplePath: localSamplePath ? path.relative(ROOT_DIR, localSamplePath) : undefined,
      cropStrategy: generated?.cropStrategy || {
        name: CROP_STRATEGY_NAME,
        yRatio: options.cropYRatio,
        outputSize: options.avatarSize,
        artCategory: card.artCategory,
      },
    };
    report.push(entry);
    if (samples.length < 20 && status !== 'failed') {
      samples.push(entry);
    }
  });

  return { counts, samples, report };
}

async function main() {
  loadLocalEnv();
  const options = parseArgs(process.argv.slice(2));
  const pool = createPool();
  try {
    const result = await generateArtistFallbackAvatars({ pool, options });
    const mode = options.apply
      ? 'artist-fallback-avatar-apply'
      : 'artist-fallback-avatar-dry-run';
    const payload = {
      generatedAt: new Date().toISOString(),
      mode,
      options: {
        limit: Number.isFinite(options.limit) ? options.limit : 'all',
        concurrency: options.concurrency,
        artist: options.artist,
        auditReport: path.relative(ROOT_DIR, options.auditReport),
        avatarSize: options.avatarSize,
        cropYRatio: options.cropYRatio,
        includeMissing: options.includeMissing,
        includePlaceholders: options.includePlaceholders,
        regenerateGeneratedFallbacks: options.regenerateGeneratedFallbacks,
        sampleDir: options.sampleDir ? path.relative(ROOT_DIR, options.sampleDir) : '',
        sampleLimit: options.sampleLimit,
      },
      counts: result.counts,
      samples: result.samples,
      report: result.report,
    };
    if (options.writeReport) {
      const reportPath = path.resolve(ROOT_DIR, options.writeReport);
      fs.mkdirSync(path.dirname(reportPath), { recursive: true });
      fs.writeFileSync(reportPath, JSON.stringify(payload, null, 2));
    }
    console.log(JSON.stringify(payload, null, 2));
    if (!options.apply) {
      console.log('Dry run only; pass --apply to upload avatars and update artist profile rows.');
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
  calculateUpperArtworkSquareCrop,
  cardImageFetchUrl,
  classifyCardArt,
  fetchArtistTargets,
  generateArtistFallbackAvatars,
  loadPlaceholderArtists,
  parseArgs,
  sourceFullImageUrl,
};
