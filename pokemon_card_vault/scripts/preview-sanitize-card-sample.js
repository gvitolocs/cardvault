'use strict';

/**
 * Download N catalog card rasters, run the ingest sanitizer, write a report.
 * Does not upload to R2.
 *
 *   node scripts/preview-sanitize-card-sample.js --limit=100
 */

const fs = require('node:fs');
const path = require('node:path');
const { sanitizeCardImage, isCardRaster } = require('./lib/sanitize-card-image');

const DEFAULT_OUT = '/tmp/card-sanitize-100';
const API = 'https://api.pokoin.com/api/marketplace-expansion-page';

function parseArgs(argv) {
  const options = {
    limit: 100,
    slug: 'mega-evolution',
    out: DEFAULT_OUT,
  };
  for (const arg of argv) {
    if (arg.startsWith('--limit=')) {
      options.limit = Number(arg.slice('--limit='.length)) || 100;
    } else if (arg.startsWith('--slug=')) {
      options.slug = arg.slice('--slug='.length);
    } else if (arg.startsWith('--out=')) {
      options.out = arg.slice('--out='.length);
    }
  }
  return options;
}

function cdnUrl(gridImageUrl) {
  const raw = String(gridImageUrl || '');
  if (raw.startsWith('http')) {
    return raw;
  }
  if (raw.startsWith('/card-images/')) {
    return `https://cdn.pokoin.com/${raw.slice('/card-images/'.length)}`;
  }
  return `https://pokoin.com${raw}`;
}

async function fetchCards(slug, limit) {
  const url = `${API}?slug=${encodeURIComponent(slug)}&productType=card&limit=${limit}`;
  const response = await fetch(url, { headers: { Accept: 'application/json' } });
  if (!response.ok) {
    throw new Error(`expansion-page ${response.status}`);
  }
  const payload = await response.json();
  return (payload.cards || []).filter((card) => String(card.productType || 'card') === 'card');
}

async function download(url) {
  const response = await fetch(url, {
    headers: { 'User-Agent': 'Pokoin card sanitize preview' },
  });
  if (!response.ok) {
    throw new Error(`download ${response.status} ${url}`);
  }
  return Buffer.from(await response.arrayBuffer());
}

function countEarWhite(data, width, height, channels) {
  let n = 0;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * channels;
      const r = data[i];
      const g = data[i + 1];
      const b = data[i + 2];
      const a = channels > 3 ? data[i + 3] : 255;
      if (a < 32) {
        continue;
      }
      const luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      const chroma = Math.max(r, g, b) - Math.min(r, g, b);
      if (luma >= 210 && chroma <= 40) {
        n += 1;
      }
    }
  }
  return n;
}

async function main() {
  const sharp = require('sharp');
  const options = parseArgs(process.argv.slice(2));
  fs.mkdirSync(options.out, { recursive: true });
  const cards = (await fetchCards(options.slug, options.limit)).slice(0, options.limit);
  const report = {
    slug: options.slug,
    requested: options.limit,
    processed: 0,
    skipped: 0,
    failed: 0,
    remainingWhite: 0,
    samples: [],
  };

  for (const card of cards) {
    const sourceUrl = cdnUrl(card.gridImageUrl || card.heroImageUrl);
    const id = String(card.id || card.cardId || '');
    try {
      const source = await download(sourceUrl);
      const before = await sharp(source).raw().toBuffer({ resolveWithObject: true });
      const whiteBefore = countEarWhite(
        before.data,
        before.info.width,
        before.info.height,
        before.info.channels,
      );
      if (!isCardRaster({ productType: card.productType }, before.info.width, before.info.height)) {
        report.skipped += 1;
        continue;
      }
      const result = await sanitizeCardImage(source, { productType: 'card', sharp });
      if (result.skipped) {
        report.skipped += 1;
        continue;
      }
      const dest = path.join(options.out, `${id}.png`);
      fs.writeFileSync(dest, result.body);
      const after = await sharp(result.body).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
      const whiteAfter = countEarWhite(
        after.data,
        after.info.width,
        after.info.height,
        after.info.channels,
      );
      report.processed += 1;
      report.remainingWhite += whiteAfter;
      report.samples.push({
        id,
        name: card.name,
        sourceUrl,
        dest,
        radius: result.radius,
        outline: result.outline,
        filled: result.filled,
        whiteBefore,
        whiteAfter,
      });
      console.log(
        `${id} ${card.name}: filled=${result.filled} white ${whiteBefore}→${whiteAfter} r=${result.radius} outline=${JSON.stringify(result.outline)}`,
      );
    } catch (error) {
      report.failed += 1;
      console.error(`${id} failed: ${error.message}`);
    }
  }

  fs.writeFileSync(path.join(options.out, 'report.json'), JSON.stringify(report, null, 2));
  console.log(
    JSON.stringify({
      out: options.out,
      processed: report.processed,
      skipped: report.skipped,
      failed: report.failed,
      remainingWhite: report.remainingWhite,
    }),
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
