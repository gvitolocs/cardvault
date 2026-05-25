const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');

const script = fs.readFileSync(
  path.join(__dirname, 'generate-oracle-homepage-card-images.js'),
  'utf8',
);

test('homepage generator uses a fixed 240px width reference', () => {
  assert.match(script, /const HOMEPAGE_REFERENCE_WIDTH = 240;/);
  assert.doesNotMatch(script, /DEFAULT_BASELINE_WIDTH/);
  assert.doesNotMatch(script, /DEFAULT_BASELINE_HEIGHT/);
});

test('homepage derivatives preserve natural aspect without rectangular product logic', () => {
  assert.match(script, /width: referenceWidth/);
  assert.match(script, /withoutEnlargement: true/);
  assert.doesNotMatch(script, /fit: 'contain'/);
  assert.doesNotMatch(script, /fit: 'cover'/);
  assert.doesNotMatch(script, /background:/);
  assert.doesNotMatch(script, /item_kind|itemKind|product_type|productType/);
});

test('homepage generator does not reuse preview keys as derivative keys', () => {
  assert.match(script, /existing\.endsWith\('_homepage\.webp'\)/);
  assert.match(script, /homepageKeyForFullKey\(fullKey\)/);
});

test('homepage generator does not link weak previews as fallbacks', () => {
  assert.match(script, /preview-below-reference-and-missing-full-source/);
  assert.match(script, /no-safe-homepage-source/);
  assert.doesNotMatch(script, /missing-full-source-preview-below-reference-width/);
});

test('homepage generator treats small sources as valid derivatives', () => {
  assert.match(script, /isExpectedHomepageForSource/);
  assert.match(script, /Math\.min\(sourceMetadata\.width, referenceWidth\)/);
});

test('homepage generator validates existing derivatives against the source', () => {
  assert.match(script, /isExpectedHomepageForSource\(homepageMetadata, fullMetadata, referenceWidth\)/);
  assert.doesNotMatch(script, /existing-homepage-safe-at-reference-width/);
});

test('homepage generator revisits existing mappings and supports concurrency', () => {
  assert.match(script, /--concurrency=/);
  assert.match(script, /--start-id=/);
  assert.match(script, /errorLimit/);
  const fetchRows = script.slice(
    script.indexOf('async function fetchRows'),
    script.indexOf('async function updateHomepage'),
  );
  assert.doesNotMatch(fetchRows, /coalesce\(homepage_image_url, ''\) = ''/);
  assert.match(script, /rows: \$\{rows\.length\}; concurrency:/);
  assert.match(script, /next start id:/);
});

test('homepage generator exposes coverage verification counts', () => {
  assert.match(script, /--verify-coverage/);
  assert.match(script, /eligible_blueprints/);
  assert.match(script, /missing_homepage_images/);
  assert.match(script, /preview_linked_fallbacks/);
  assert.match(script, /snapshot_homepage_mismatches/);
  assert.match(script, /snapshot_preview_fallbacks/);
});

test('homepage generator only links preview as fallback without source', () => {
  assert.match(script, /if \(previewMetadata && !fullKey\)/);
  assert.doesNotMatch(script, /preview-safe-at-reference-width/);
  assert.match(script, /fallback-only-no-full-source/);
});
