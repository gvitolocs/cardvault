#!/usr/bin/env node
'use strict';

/**
 * Point marketplace rows at sibling PNGs from a rewrite log.
 * Run inside pokoin-oracle-api (has MARKETPLACE_DATABASE_URL).
 * Matches leftover ct_id only — never card_id — because leftover prefixes
 * can overlap another card's public id.
 * Does not run refresh_marketplace_oracle_projections().
 */

const fs = require('node:fs');
const { Pool } = require('pg');

function ctIdFromKey(key) {
  const base = String(key || '').replace(/^previews\//, '');
  const match = base.match(/^(\d+)_/);
  return match ? match[1] : null;
}

async function updateCatalog(pool, { ctId, isPreview, pngKey, cdnUrl }) {
  const id = Number(ctId);
  if (!Number.isSafeInteger(id) || id <= 0) {
    return { updated: false, reason: 'bad-id' };
  }
  if (isPreview) {
    await pool.query(
      `update public.cardtrader_pokemon_blueprints
       set preview_image_url = $1, preview_object_key = $2
       where id = $3`,
      [cdnUrl, pngKey, id],
    );
    for (const table of [
      'marketplace_cards',
      'marketplace_card_versions',
      'marketplace_search_candidates',
    ]) {
      await pool.query(
        `update public.${table}
         set preview_image_url = $1, projected_at = now()
         where ct_id = $2`,
        [cdnUrl, id],
      );
    }
    return { updated: true };
  }
  await pool.query(
    `update public.cardtrader_pokemon_blueprints
     set image_url = $1, cdn_image_url = $1, cdn_object_key = $2
     where id = $3`,
    [cdnUrl, pngKey, id],
  );
  for (const table of [
    'marketplace_cards',
    'marketplace_card_versions',
    'marketplace_search_candidates',
  ]) {
    await pool.query(
      `update public.${table}
       set image_url = $1, cdn_image_url = $1, projected_at = now()
       where ct_id = $2`,
      [cdnUrl, id],
    );
  }
  return { updated: true };
}

async function updateArtist(pool, { pngKey, jpegKey, cdnUrl }) {
  await pool.query(
    `update public.marketplace_artist_profiles
     set profile_image_object_key = $1,
         profile_image_cdn_url = $2
     where profile_image_object_key = $3
        or profile_image_cdn_url like '%' || $3`,
    [jpegKey, cdnUrl, pngKey],
  );
}

async function updateExpansion(pool, { pngKey, jpegKey, cdnUrl }) {
  await pool.query(
    `update public.pokoin_pokemon_expansions
     set symbol_image_url = $1,
         symbol_object_key = $2
     where symbol_object_key = $3
        or symbol_image_url like '%' || $3`,
    [cdnUrl, jpegKey, pngKey],
  );
}

async function main() {
  const revert = process.argv.includes('--revert');
  const logPath = process.argv.find((arg) => arg.endsWith('.jsonl') || arg.endsWith('.json'));
  if (!logPath) {
    throw new Error('usage: apply-digest-png-catalog.js [--revert] <rewrite.log.jsonl>');
  }
  const cdnBase = (process.env.POKOIN_CARD_CDN_BASE_URL || 'https://cdn.pokoin.com').replace(
    /\/$/,
    '',
  );
  if (!process.env.MARKETPLACE_DATABASE_URL) {
    throw new Error('Missing MARKETPLACE_DATABASE_URL');
  }
  const pool = new Pool({
    connectionString: process.env.MARKETPLACE_DATABASE_URL,
    max: 2,
    idleTimeoutMillis: 10_000,
    connectionTimeoutMillis: 15_000,
    ssl: process.env.MARKETPLACE_DATABASE_SSL === '0'
      ? false
      : { rejectUnauthorized: false },
  });
  const summary = { total: 0, updated: 0, skipped: 0, failed: 0, revert };
  try {
    const lines = fs.readFileSync(logPath, 'utf8').split(/\r?\n/).filter(Boolean);
    for (const line of lines) {
      const row = JSON.parse(line);
      summary.total += 1;
      const objectKey = row.jpegKey || (revert ? row.key : row.pngKey);
      const pngKey = row.pngKey || objectKey;
      if ((row.status !== 'ok' && row.status !== 'deleted-duplicate') || !objectKey) {
        summary.skipped += 1;
        continue;
      }
      const cdnUrl = `${cdnBase}/${objectKey}`;
      try {
        if (String(objectKey).startsWith('artist-profiles/')) {
          await updateArtist(pool, { pngKey, jpegKey: objectKey, cdnUrl });
          summary.updated += 1;
          continue;
        }
        if (String(objectKey).startsWith('expansions/')) {
          await updateExpansion(pool, { pngKey, jpegKey: objectKey, cdnUrl });
          summary.updated += 1;
          continue;
        }
        const ctId = ctIdFromKey(row.key || row.pngKey || objectKey);
        const isPreview = String(objectKey).startsWith('previews/');
        await updateCatalog(pool, { ctId, isPreview, pngKey: objectKey, cdnUrl });
        summary.updated += 1;
      } catch (error) {
        summary.failed += 1;
        console.error(JSON.stringify({ key: row.key, status: 'failed', error: error.message }));
      }
    }
  } finally {
    await pool.end();
  }
  console.log(JSON.stringify({ catalog: summary, logPath }));
  if (summary.failed > 0) {
    process.exitCode = 1;
  }
}

module.exports = { ctIdFromKey, updateCatalog };

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}
