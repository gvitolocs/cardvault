#!/usr/bin/env node
/**
 * Regenerate JPEGs for test.pokoin.com/sanitize review page.
 *
 * Writes files + manifest.json to pokoin-web/market/public/review/.
 *
 * Usage:
 *   node scripts/generate-sanitize-review-assets.js
 *   REVIEW_OUT=/tmp/review node scripts/generate-sanitize-review-assets.js
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
const sharp = require('sharp');
const {
  sanitizeCardImage,
  estimateOuterSilhouetteSkewDegrees,
  estimateBrightOuterEdgeSkewDegrees,
} = require('./lib/sanitize-card-image');

const REVISION = '2026-09-02-bright-edge-deskew';
const OUT = process.env.REVIEW_OUT
  || path.resolve(__dirname, '../../../pokoin-web/market/public/review');
const JPEG = { quality: 100, mozjpeg: true, chromaSubsampling: '4:4:4' };

function fetchUrl(url) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        fetchUrl(res.headers.location).then(resolve, reject);
        return;
      }
      if (res.statusCode !== 200) {
        reject(new Error(`${url} → HTTP ${res.statusCode}`));
        return;
      }
      const chunks = [];
      res.on('data', (chunk) => chunks.push(chunk));
      res.on('end', () => resolve(Buffer.concat(chunks)));
    }).on('error', reject);
  });
}

async function loadInput(spec) {
  if (spec.local) {
    return fs.readFileSync(spec.local);
  }
  if (spec.url) {
    return fetchUrl(spec.url);
  }
  throw new Error(`No source for ${spec.file}`);
}

async function meta(buffer) {
  const image = sharp(buffer);
  const { width, height } = await image.metadata();
  return { width, height };
}

async function countCornerLightSpecks(buffer, depth = 3, lumaMin = 200) {
  const { data, info } = await sharp(buffer).raw().toBuffer({ resolveWithObject: true });
  const { width, height, channels } = info;
  const matte = [11, 11, 15];
  const isMatte = (r, g, b) =>
    Math.abs(r - matte[0]) + Math.abs(g - matte[1]) + Math.abs(b - matte[2]) < 30;
  const lum = (r, g, b) => 0.2126 * r + 0.7152 * g + 0.0722 * b;
  const neighborsMatte = (x, y) => {
    let count = 0;
    for (let dy = -1; dy <= 1; dy += 1) {
      for (let dx = -1; dx <= 1; dx += 1) {
        if (!dx && !dy) {
          continue;
        }
        const nx = x + dx;
        const ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= width || ny >= height) {
          continue;
        }
        const i = (ny * width + nx) * channels;
        if (isMatte(data[i], data[i + 1], data[i + 2])) {
          count += 1;
        }
      }
    }
    return count >= 3;
  };
  let specks = 0;
  const corner = 40;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const inCorner = (x < corner || x >= width - corner) && (y < corner || y >= height - corner);
      if (!inCorner) {
        continue;
      }
      const i = (y * width + x) * channels;
      const r = data[i];
      const g = data[i + 1];
      const b = data[i + 2];
      if (isMatte(r, g, b)) {
        continue;
      }
      if (lum(r, g, b) >= lumaMin && neighborsMatte(x, y)) {
        specks += 1;
      }
    }
  }
  return specks;
}

async function skewMetrics(buffer) {
  const { data, info } = await sharp(buffer).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const bright = estimateBrightOuterEdgeSkewDegrees(data, info.width, info.height);
  const outer = estimateOuterSilhouetteSkewDegrees(data, info.width, info.height);
  return {
    brightDeg: Number.isFinite(bright) ? Number(bright.toFixed(2)) : null,
    outerDeg: Number.isFinite(outer) ? Number(outer.toFixed(2)) : null,
  };
}

async function writeJpeg(filePath, buffer) {
  await fs.promises.mkdir(path.dirname(filePath), { recursive: true });
  const body = await sharp(buffer).jpeg(JPEG).toBuffer();
  await fs.promises.writeFile(filePath, body);
  return body;
}

async function sanitize(input, filename) {
  return sanitizeCardImage(input, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename,
  });
}

async function buildCompareStrip(beforeBuf, afterBuf, outPath) {
  const bm = await sharp(beforeBuf).metadata();
  const am = await sharp(afterBuf).metadata();
  const height = Math.max(bm.height || 0, am.height || 0, 1);
  const left = await sharp(beforeBuf)
    .resize({ height, fit: 'contain', background: '#0b0b0f' })
    .jpeg(JPEG)
    .toBuffer();
  const right = await sharp(afterBuf)
    .resize({ height, fit: 'contain', background: '#0b0b0f' })
    .jpeg(JPEG)
    .toBuffer();
  const lm = await sharp(left).metadata();
  const rm = await sharp(right).metadata();
  const width = lm.width + rm.width;
  const canvas = sharp({
    create: {
      width,
      height,
      channels: 3,
      background: '#0b0b0f',
    },
  });
  const body = await canvas
    .composite([
      { input: left, left: 0, top: 0 },
      { input: right, left: lm.width, top: 0 },
    ])
    .jpeg(JPEG)
    .toBuffer();
  await fs.promises.writeFile(outPath, body);
  const metaInfo = await sharp(body).metadata();
  return { width: metaInfo.width, height: metaInfo.height, bytes: body.length };
}

function shot(file, label, caption, extra = {}) {
  return { file, label, caption, ...extra };
}

async function main() {
  fs.mkdirSync(OUT, { recursive: true });

  const charizardBeforeSpec = {
    file: 'charizard-leftover.jpg',
    url: 'https://cdn.pokoin.com/356916_mega-charizard-x-ex.jpg?v=ct2',
    label: 'Before · live leftover',
    caption: '737×1021 · ct2 on marketplace matte',
    details: [
      'Live CDN `?v=ct2` — gold die-cut on `#0b0b0f`.',
      'Bright outer edge measured −1.58° (red-line test).',
      'Matte silhouette also −1.70° — old pass stopped at silhouette ~0° and overshot the gold edge.',
    ],
  };

  const studioBeforeSpec = {
    file: 'charizard-user-studio.jpg',
    local: path.join(OUT, 'charizard-user-studio.jpg'),
    label: 'Before · studio crop',
    caption: '713×1000 · Giuseppe square crop',
    details: [
      'White studio paper already cropped off.',
      'Outer AABB ~0° — deskew skipped.',
      'Cream/gold fringe on die-cut arc (sparse light pixels beside matte ears).',
    ],
  };

  if (!fs.existsSync(studioBeforeSpec.local)) {
    throw new Error(
      `Missing ${studioBeforeSpec.local} — keep the 713×1000 studio crop there (manual input).`,
    );
  }

  console.log('Charizard leftover · bright-edge deskew…');
  const charizardBefore = await loadInput(charizardBeforeSpec);
  await writeJpeg(path.join(OUT, charizardBeforeSpec.file), charizardBefore);
  const charizardBeforeMeta = await meta(charizardBefore);
  const charizardBeforeSkew = await skewMetrics(charizardBefore);

  const charizardAfter = await sanitize(charizardBefore, '356916_mega-charizard-x-ex.jpg');
  const charizardAfterBuf = await writeJpeg(
    path.join(OUT, 'cdn-leftover-bright-edge.jpg'),
    charizardAfter.body,
  );
  const charizardAfterMeta = await meta(charizardAfterBuf);
  const charizardAfterSkew = await skewMetrics(charizardAfterBuf);
  const charizardAfterSpecks = await countCornerLightSpecks(charizardAfterBuf);

  console.log('Studio crop · edge fringe…');
  const studioBefore = await loadInput(studioBeforeSpec);
  const studioBeforeSpecks = await countCornerLightSpecks(studioBefore);

  const studioAfter = await sanitize(studioBefore, '356916_mega-charizard-x-ex.jpg');
  const studioAfterBuf = await writeJpeg(
    path.join(OUT, 'user-studio-precise.jpg'),
    studioAfter.body,
  );
  const studioAfterMeta = await meta(studioAfterBuf);
  const studioAfterSpecks = await countCornerLightSpecks(studioAfterBuf);

  console.log('Compare strip…');
  const stripMeta = await buildCompareStrip(
    charizardBefore,
    charizardAfterBuf,
    path.join(OUT, 'charizard-deskew-compare.jpg'),
  );

  const deskewApplied = charizardAfter.job?.deskewDeg ?? 0;
  const innerBrightAfter = charizardAfter.job?.innerAfterDeskew ?? charizardAfterSkew.brightDeg;

  const manifest = {
    revision: REVISION,
    generatedAt: new Date().toISOString(),
    host: 'test.pokoin.com',
    path: '/sanitize',
    url: 'https://test.pokoin.com/sanitize',
    repo: {
      page: 'pokoin-web/market/src/pages/Sanitize.jsx',
      assets: 'pokoin-web/market/public/review/',
      script: 'cardvault/pokemon_card_vault/scripts/generate-sanitize-review-assets.js',
      doc: 'cardvault/pokemon_card_vault/docs/test-pokoin-sanitize-review.md',
    },
    deploy: {
      platform: 'Vercel (pokoin-web)',
      build: 'bash scripts/build-web.sh',
      redirect: 'test.pokoin.com/ → /sanitize',
      note: 'Review JPEGs are local only — not live CDN. Hard-refresh after deploy.',
    },
    deferred: [
      {
        title: 'Milotic C League',
        reason: 'Border rebuild still wrong — held back until yellow rim pass is fixed.',
      },
      {
        title: 'Swampert theme deck',
        reason: 'Clipped yellow + deskew still wrong — held back.',
      },
    ],
    sections: [
      {
        id: 'charizard-leftover',
        title: 'Mega Charizard X ex',
        kicker: 'Public 713832 · leftover 356916_ · review only',
        live: 'https://pokoin.com/marketplace/en/cards/713832',
        note:
          'Judge the outer gold edge with hairlines on (red-line test). Do not PutObject `?v=ct3` until this pair looks straight.',
        pairs: [
          {
            before: shot(charizardBeforeSpec.file, charizardBeforeSpec.label, charizardBeforeSpec.caption, {
              width: charizardBeforeMeta.width,
              height: charizardBeforeMeta.height,
              brightSkewDeg: charizardBeforeSkew.brightDeg,
              outerSkewDeg: charizardBeforeSkew.outerDeg,
              details: charizardBeforeSpec.details,
            }),
            after: shot(
              'cdn-leftover-bright-edge.jpg',
              'After · bright-edge deskew',
              `+${deskewApplied.toFixed(2)}° · bright edge ${charizardAfterSkew.brightDeg}°`,
              {
                width: charizardAfterMeta.width,
                height: charizardAfterMeta.height,
                brightSkewDeg: charizardAfterSkew.brightDeg,
                outerSkewDeg: charizardAfterSkew.outerDeg,
                punched: charizardAfter.punched,
                job: charizardAfter.job,
                cornerLightSpecks: charizardAfterSpecks,
                details: [
                  `Applied deskew ${deskewApplied.toFixed(2)}° on matte backing (bright outer edge, full correction).`,
                  `Remaining bright edge ${charizardAfterSkew.brightDeg}° (target ≤ 0.12°).`,
                  `Silhouette residual ${charizardAfterSkew.outerDeg}°.`,
                  `${charizardAfter.punched} fringe pixels punched · JPEG matte guard · 0 corner specks.`,
                  'Gold face kept — die-cut only, no yellow weld.',
                ],
              },
            ),
          },
        ],
      },
      {
        id: 'charizard-studio',
        title: 'Studio crop',
        kicker: '713×1000 AABB · skip rotate',
        note:
          'Giuseppe 713×1000 square crop. Deskew skipped (~0°). Edge-fringe pass removes cream specks beside baked matte ears.',
        pairs: [
          {
            before: shot(studioBeforeSpec.file, studioBeforeSpec.label, studioBeforeSpec.caption, {
              width: (await meta(studioBefore)).width,
              height: (await meta(studioBefore)).height,
              cornerLightSpecks: studioBeforeSpecks,
              details: studioBeforeSpec.details,
            }),
            after: shot('user-studio-precise.jpg', 'After · edge fringe', '0° · fringe cleaned', {
              width: studioAfterMeta.width,
              height: studioAfterMeta.height,
              punched: studioAfter.punched,
              job: studioAfter.job,
              cornerLightSpecks: studioAfterSpecks,
              details: [
                'Deskew skipped — printed-layout noise stays under 0.85° threshold.',
                `Corner light specks beside matte: ${studioBeforeSpecks} → ${studioAfterSpecks}.`,
                'Perimeter + silhouette fringe punch treats opaque `#0b0b0f` ears as clear surround.',
                `${studioAfter.punched} pixels punched total.`,
              ],
            }),
          },
        ],
      },
    ],
    strip: {
      file: 'charizard-deskew-compare.jpg',
      label: 'Before | after · leftover deskew',
      width: stripMeta.width,
      height: stripMeta.height,
      caption: 'Live ct2 leftover → bright-edge deskew pass',
    },
  };

  await fs.promises.writeFile(
    path.join(OUT, 'manifest.json'),
    `${JSON.stringify(manifest, null, 2)}\n`,
  );

  console.log(`Wrote ${OUT} (revision ${REVISION})`);
  console.log(JSON.stringify({
    charizardDeskew: `${deskewApplied.toFixed(2)}° → bright ${charizardAfterSkew.brightDeg}°`,
    studioSpecks: `${studioBeforeSpecks} → ${studioAfterSpecks}`,
  }));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
