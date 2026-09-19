'use strict';

/**
 * Map a public-id CDN request to the leftover R2 object key.
 *
 * Storage keys stay `{ct_id}_{slug}`. Public URLs use `{card_id}_{slug}`
 * where card_id = ct_id * 2 (D00000B). The Worker must try the requested
 * key first: leftover ct_id keys that happen to be even numbers must not
 * be halved while they still exist (Nacli ct_id 248768 vs Drifloon public
 * 248768 — slug disambiguates; as-is lookup wins).
 *
 * Returns null when the key is not a card object prefix, or the prefix is
 * not an even public id. Keep in sync with pokoin-cdn-card-images-worker.js.
 */
function leftoverCdnObjectKey(requestedKey) {
  const key = String(requestedKey || '').replace(/^\/+/, '');
  const match = key.match(/^(previews\/)?(\d+)(_.*)$/);
  if (!match) {
    return null;
  }
  const prefix = match[2];
  if (!/^\d+$/.test(prefix) || prefix.length > 16) {
    return null;
  }
  let value;
  try {
    value = BigInt(prefix);
  } catch {
    return null;
  }
  if (value <= 0n || value % 2n !== 0n) {
    return null;
  }
  const leftover = value / 2n;
  if (leftover <= 0n) {
    return null;
  }
  return `${match[1] || ''}${leftover}${match[3]}`;
}

const RASTER_EXTENSIONS = ['.jpg', '.jpeg', '.png', '.webp'];

function keepRawObjectKey(requestedKey) {
  const key = String(requestedKey || '').replace(/^\/+/, '');
  return (
    key.startsWith('originals/') ||
    key.startsWith('manifests/') ||
    key.startsWith('previews/') ||
    key.startsWith('competitive/') ||
    /_homepage\.webp$/i.test(key)
  );
}

/** After PNG-only catalog objects are rewritten to JPEG, old .png URLs map here. */
function jpegFallbackKey(requestedKey) {
  const key = String(requestedKey || '').replace(/^\/+/, '');
  if (!/\.png$/i.test(key)) {
    return null;
  }
  return key.replace(/\.png$/i, '.jpg');
}

/**
 * Live catalog objects are JPEG. Map leftover .png/.webp URLs to .jpg.
 * Homepage `_homepage.webp` tiles and `/previews/` stay as requested.
 */
function jpegCatalogKey(requestedKey) {
  const key = String(requestedKey || '').replace(/^\/+/, '');
  if (!key) {
    return null;
  }
  if (keepRawObjectKey(key)) {
    return key;
  }
  if (/\.jpe?g$/i.test(key)) {
    return key;
  }
  return key.replace(/\.(png|webp)$/i, '.jpg');
}

/**
 * @deprecated Worker serves JPEG only. Kept for tests that list sibling names.
 */
function rasterFallbackKeys(requestedKey) {
  const key = String(requestedKey || '').replace(/^\/+/, '');
  const match = key.match(/^(.*)(\.[^.]+)$/);
  if (!match) {
    return [];
  }
  const stem = match[1];
  const ext = match[2].toLowerCase();
  if (!RASTER_EXTENSIONS.includes(ext)) {
    return [];
  }
  return RASTER_EXTENSIONS.filter((candidate) => candidate !== ext).map(
    (candidate) => `${stem}${candidate}`,
  );
}

module.exports = {
  leftoverCdnObjectKey,
  jpegFallbackKey,
  jpegCatalogKey,
  keepRawObjectKey,
  rasterFallbackKeys,
};
