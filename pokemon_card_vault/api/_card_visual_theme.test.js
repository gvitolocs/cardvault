'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {
  THEME_VERSION,
  THEME_HEX_FIELDS,
  buildVisualTheme,
  visualThemeForShade,
  packVisualTheme,
  contrastRatio,
  hexToOklch,
  oklchToHex,
} = require('./_card_visual_theme');

const SHADE = '#b52a2a';
const IDENTITY = 'a'.repeat(64);

test('oklch round-trips a sRGB hex within visual tolerance', () => {
  const source = hexToOklch('#b52a2a');
  assert.ok(Math.abs(source.l - 0.5095) < 0.01, `L ${source.l}`);
  assert.ok(Math.abs(source.h - 26.08) < 1.5, `h ${source.h}`);
  const back = oklchToHex(source);
  const channel = (hex, at) => Number.parseInt(hex.slice(1 + at * 2, 3 + at * 2), 16);
  for (let at = 0; at < 3; at += 1) {
    assert.ok(Math.abs(channel(back, at) - channel('#b52a2a', at)) <= 2, `${back} @${at}`);
  }
});

test('theme is deterministic and carries version + source shade', () => {
  const first = buildVisualTheme('#b52a2a');
  const second = buildVisualTheme('#B52A2A');
  assert.deepEqual(first, second);
  assert.equal(first.version, THEME_VERSION);
  assert.equal(first.artworkShade, '#b52a2a');
  for (const field of [
    'background',
    'surface',
    'surfaceRaised',
    'hero',
    'heroBorder',
    'border',
    'tint',
  ]) {
    assert.match(first[field], /^#[0-9a-f]{6}$/, field);
  }
});

test('surface hierarchy steps darker → lighter, page background darkest', () => {
  const theme = buildVisualTheme('#3b6ea5');
  const luma = (hex) => {
    const at = (i) => Number.parseInt(hex.slice(1 + i * 2, 3 + i * 2), 16);
    return 0.2126 * at(0) + 0.7152 * at(1) + 0.0722 * at(2);
  };
  assert.ok(luma(theme.background) < luma(theme.surface), 'bg < surface');
  assert.ok(luma(theme.surface) < luma(theme.surfaceRaised), 'surface < raised');
  assert.ok(luma(theme.hero) > luma(theme.surfaceRaised), 'hero strongest');
});

test('pathological artwork stays readable', () => {
  for (const shade of ['#ffffff', '#000000', '#00ff00', '#ff00ff', '#123456']) {
    const theme = buildVisualTheme(shade);
    assert.ok(theme, shade);
    const heroL = hexToOklch(theme.hero).l;
    // 0.01 slack: the served hex quantizes back to ±0.005 around the clamp.
    assert.ok(heroL <= 0.53, `${shade} hero too light: ${heroL}`);
    assert.ok(heroL >= 0.14, `${shade} hero too dark: ${heroL}`);
    assert.ok(hexToOklch(theme.background).l >= 0.14, `${shade} bg collapsed`);
    assert.ok(hexToOklch(theme.background).l <= 0.2);
    assert.ok(contrastRatio(theme.hero, '#ffffff') >= 4.5, `${shade} hero contrast`);
    assert.ok(contrastRatio(theme.background, '#ffffff') >= 7, `${shade} bg contrast`);
  }
});

test('achromatic artwork keeps a neutral Pokoin hue, not NaN', () => {
  const theme = buildVisualTheme('#3a3a3a');
  assert.ok(Number.isFinite(theme.hue));
  assert.equal(theme.hue, 265);
});

test('invalid shade yields no theme', () => {
  assert.equal(buildVisualTheme(''), null);
  assert.equal(buildVisualTheme('nope'), null);
  assert.equal(buildVisualTheme('#12345'), null);
});

test('persisted rows are trusted only when artwork identity matches', () => {
  const derived = buildVisualTheme(SHADE, IDENTITY);
  assert.equal(derived.artworkIdentity, IDENTITY);
  const row = {
    version: THEME_VERSION,
    artwork_shade: SHADE,
    artwork_identity: IDENTITY,
    hue: derived.hue,
    chroma: derived.chroma,
    background: derived.background,
    surface: derived.surface,
    surface_raised: derived.surfaceRaised,
    hero: derived.hero,
    hero_border: derived.heroBorder,
    border: derived.border,
    tint: derived.tint,
  };
  assert.deepEqual(visualThemeForShade(row, SHADE, IDENTITY), derived);

  // Artwork replaced but the new artwork samples to the SAME shade: the
  // identity no longer matches, so the persisted row is never served.
  const otherIdentity = 'b'.repeat(64);
  const rederived = visualThemeForShade(row, SHADE, otherIdentity);
  assert.equal(rederived.artworkIdentity, otherIdentity);
  assert.deepEqual(rederived, buildVisualTheme(SHADE, otherIdentity));

  // Row predates identity tracking (never resampled since 085): unverifiable.
  const noIdentity = { ...row, artwork_identity: '' };
  assert.deepEqual(visualThemeForShade(noIdentity, SHADE, IDENTITY), derived);

  // Older version → re-derive from the current shade.
  assert.deepEqual(visualThemeForShade({ ...row, version: 'v0' }, SHADE, IDENTITY), derived);
  // Corrupt hex in a level → re-derive.
  assert.deepEqual(visualThemeForShade({ ...row, hero: 'zzz' }, SHADE, IDENTITY), derived);
  // Missing row + valid shade → derive.
  assert.deepEqual(visualThemeForShade(null, SHADE, IDENTITY), derived);
  // No shade at all → neutral-safe null, regardless of identity.
  assert.equal(visualThemeForShade(row, '', IDENTITY), null);
});

test('packed themes round-trip the semantic palette in 44 chars', () => {
  const theme = buildVisualTheme(SHADE, IDENTITY);
  const packed = packVisualTheme(theme);
  assert.match(packed, /^v1[0-9a-f]{42}$/);
  assert.equal(packed.length, 44);
  assert.equal(packVisualTheme(visualThemeForShade(null, SHADE, IDENTITY)), packed);
  const roundTrip = packVisualTheme({
    version: theme.version,
    background: theme.background,
    surface: theme.surface,
    surfaceRaised: theme.surfaceRaised,
    hero: theme.hero,
    heroBorder: theme.heroBorder,
    border: theme.border,
    tint: theme.tint,
  });
  assert.equal(roundTrip, packed);
  // Rejects wrong version and bad hexes.
  assert.equal(packVisualTheme({ ...theme, version: 'v2' }), '');
  assert.equal(packVisualTheme({ ...theme, hero: 'zzz' }), '');
  assert.equal(packVisualTheme(null), '');
  assert.equal(THEME_HEX_FIELDS.length, 7);
});
