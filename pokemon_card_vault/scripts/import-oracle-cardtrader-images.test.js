const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');

const script = fs.readFileSync(
  path.join(__dirname, 'import-oracle-cardtrader-images.js'),
  'utf8',
);

test('oracle full image importer never falls back to preview images', () => {
  const fullImageUrlsBody = script.slice(
    script.indexOf('function deriveFullFromPreviewUrl'),
    script.indexOf('function previewImageUrls'),
  );

  assert.match(fullImageUrlsBody, /allowPreview: false/);
  assert.match(fullImageUrlsBody, /return \[\];/);
  assert.match(fullImageUrlsBody, /replace\('\/preview_', '\/'\)/);
  assert.doesNotMatch(fullImageUrlsBody, /previewImageUrls\(row\)/);
  assert.doesNotMatch(fullImageUrlsBody, /Import it as the full image/);
});

test('oracle quality audit compares current R2 dimensions to preferred full source', () => {
  assert.match(script, /function shouldRepairFullImage/);
  assert.match(script, /const preferredFullUrl = candidates\[0\]/);
  assert.match(script, /current-full-lower-resolution/);
  assert.match(script, /ORACLE_IMAGE_QUALITY_MIN_RATIO/);
});

test('oracle importer skips full import cleanly when no full source exists', () => {
  const importRowBody = script.slice(
    script.indexOf('async function importRow'),
    script.indexOf('async function shouldRepairFullImage'),
  );

  assert.match(importRowBody, /const fullUrls = fullImageUrls\(row\);/);
  assert.match(importRowBody, /fullUrls\.length === 0/);
  assert.match(importRowBody, /skipped\.push\('full:no-full-image'\)/);
  assert.match(importRowBody, /firstDownload\(fullUrls, 1024\)/);
  assert.match(importRowBody, /sanitizeForCatalog/);
  assert.match(importRowBody, /prepared\.body/);
  assert.match(importRowBody, /return \{ imported, skipped \};/);
  assert.doesNotMatch(importRowBody, /imported\.push\('skipped-full/);
});

test('oracle importer backups live R2 keys under originals/ before upload', () => {
  assert.match(script, /require\('\.\/lib\/backup-r2-original'\)/);
  assert.match(script, /backupExistingObject/);
  assert.match(script, /existingKey: row\.cdn_object_key/);
  assert.match(script, /existingKey: row\.preview_object_key/);
});
