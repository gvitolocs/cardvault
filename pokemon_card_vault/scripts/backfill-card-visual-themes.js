#!/usr/bin/env node

// Backfill marketplace_leftover_visual_themes (schema 084) from the sampled
// leftover shades (marketplace_leftover_art_shades). One row per leftover
// ct_id. artwork_identity — the sha256 of the canonical leftover JPEG
// (085) — is stored with the theme and is the validity key: the card-page
// endpoint serves the row only while it equals the current identity.
// Re-running is idempotent.

'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const {
  THEME_VERSION,
  buildVisualTheme,
} = require('../api/_card_visual_theme');

const CONTAINER = process.env.POKOIN_MARKETPLACE_POSTGRES_CONTAINER
  || 'pokoin-marketplace-postgres-15t';
const REMOTE_TMP = '/tmp/pokoin-visual-themes-backfill';

function dockerShell(script) {
  const result = spawnSync('docker', ['exec', CONTAINER, 'sh', '-c', script], {
    encoding: 'utf8',
    maxBuffer: 2 ** 30,
  });
  if (result.status !== 0) {
    throw new Error(`docker exec failed: ${result.stderr || result.stdout || result.status}`);
  }
  return result.stdout;
}

function readShades() {
  const remote = `${REMOTE_TMP}-shades.csv`;
  dockerShell(`
PGPASSWORD="$POSTGRES_PASSWORD" psql -U pokoin_marketplace -d pokoin_marketplace -v ON_ERROR_STOP=1 \\
  -c "\\copy (select ct_id, shade, coalesce(artwork_identity, '') from public.marketplace_leftover_art_shades) to '${remote}' with csv"
`);
  const local = path.join(os.tmpdir(), 'pokoin-art-shades-export.csv');
  spawnSync('docker', ['cp', `${CONTAINER}:${remote}`, local], { stdio: 'ignore' });
  const rows = fs.readFileSync(local, 'utf8')
    .split('\n')
    .filter(Boolean)
    .map((line) => line.split(','));
  fs.unlinkSync(local);
  return rows;
}

function themeCsv(theme, ctId) {
  return [
    ctId,
    theme.version,
    theme.artworkShade,
    theme.artworkIdentity,
    theme.hue,
    theme.chroma,
    theme.background,
    theme.surface,
    theme.surfaceRaised,
    theme.hero,
    theme.heroBorder,
    theme.border,
    theme.tint,
  ].join(',');
}

async function main() {
  const limit = Number(process.argv[2] || 0) || 0;
  const shades = readShades();
  const rows = [];
  for (const [ctId, shade, identity] of shades) {
    const theme = buildVisualTheme(shade, identity);
    if (theme) {
      rows.push(themeCsv(theme, ctId));
    }
    if (limit && rows.length >= limit) {
      break;
    }
  }
  if (!rows.length) {
    console.error('no shades to derive themes from');
    return 1;
  }
  const local = path.join(os.tmpdir(), 'pokoin-visual-themes.csv');
  fs.writeFileSync(local, `${rows.join('\n')}\n`);
  const remote = `${REMOTE_TMP}-load.csv`;
  spawnSync('docker', ['cp', local, `${CONTAINER}:${remote}`], { stdio: 'ignore' });
  fs.unlinkSync(local);
  dockerShell(`
PGPASSWORD="$POSTGRES_PASSWORD" psql -U pokoin_marketplace -d pokoin_marketplace -v ON_ERROR_STOP=1 <<SQL
create temp table visual_theme_load (
  ct_id bigint,
  version text,
  artwork_shade text,
  artwork_identity text,
  hue real,
  chroma real,
  background text,
  surface text,
  surface_raised text,
  hero text,
  hero_border text,
  border text,
  tint text
);
\\copy visual_theme_load from '${remote}' csv
insert into public.marketplace_leftover_visual_themes (
  ct_id, version, artwork_shade, artwork_identity, hue, chroma,
  background, surface, surface_raised, hero, hero_border, border, tint, derived_at
)
select ct_id, version, artwork_shade, nullif(artwork_identity, ''), hue, chroma,
       background, surface, surface_raised, hero, hero_border, border, tint, now()
from visual_theme_load
on conflict (ct_id) do update
  set version = excluded.version,
      artwork_shade = excluded.artwork_shade,
      artwork_identity = excluded.artwork_identity,
      hue = excluded.hue,
      chroma = excluded.chroma,
      background = excluded.background,
      surface = excluded.surface,
      surface_raised = excluded.surface_raised,
      hero = excluded.hero,
      hero_border = excluded.hero_border,
      border = excluded.border,
      tint = excluded.tint,
      derived_at = now();
SQL
`);
  console.log(`backfilled ${rows.length} visual themes (${THEME_VERSION})`);
  return 0;
}

main().then(
  (code) => process.exit(code),
  (err) => {
    console.error(err.message || err);
    process.exit(1);
  },
);
