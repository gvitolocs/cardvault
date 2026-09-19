#!/usr/bin/env node
/**
 * Charizard 713832 — three non-CardTrader deskew variants on the local leftover.
 * GPU rotates (ROCm torch, 7900) in parallel; Node worker_threads finish die-cut.
 *
 *   node scripts/run-charizard-deskew-variants.js
 */

'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { Worker, isMainThread, parentPort, workerData } = require('node:worker_threads');
const os = require('node:os');
const sharp = require('sharp');
const {
  sanitizeCardImage,
  estimateBrightOuterEdgeSkewDegrees,
  estimateOuterSilhouetteSkewDegrees,
} = require('./lib/sanitize-card-image');

const ROOT = path.resolve(__dirname, '..');
const REVIEW = path.resolve(ROOT, '../../pokoin-web/market/public/review');
const SRC =
  process.env.CHARIZARD_SRC ||
  '/home/nez/Projects/pokoin/PokoinTest/index/cdn_images/356916_mega-charizard-x-ex.jpg';
const GPU_PY =
  process.env.GPU_PYTHON || '/home/nez/Projects/ai-toolkit/venv/bin/python';
const GPU_SCRIPT = path.join(__dirname, 'lib/gpu-deskew-variants.py');
const WORK = '/tmp/charizard-deskew-variants';
const REVISION = '2026-09-02-deskew-variants-gpu';
const JPEG = { quality: 100, mozjpeg: true, chromaSubsampling: '4:4:4' };

const VARIANTS = [
  {
    id: 'supersample',
    png: 'variant-supersample.png',
    file: 'charizard-variant-supersample.jpg',
    title: 'A · 2× supersample + GPU rotate',
    blurb:
      'Upsample 2× on RX 7900, bilinear rotate, downsample — less text ringing than 1× JPEG rotate.',
  },
  {
    id: 'mask_nn',
    png: 'variant-mask-nn.png',
    file: 'charizard-variant-mask-nn.jpg',
    title: 'B · mask / nearest RGB',
    blurb:
      'Nearest-neighbor RGB rotate (keeps foil/text pixels) + bilinear alpha; fringe punch only on edges.',
  },
  {
    id: 'crop_rotate',
    png: 'variant-crop-rotate.png',
    file: 'charizard-variant-crop-rotate.jpg',
    title: 'C · crop → rotate → crop',
    blurb:
      'Tight matte crop first, GPU rotate the small canvas, recrop — less resample footprint.',
  },
];

async function countCornerLightSpecks(buffer) {
  const { data, info } = await sharp(buffer).raw().toBuffer({ resolveWithObject: true });
  const { width, height, channels } = info;
  const matte = [11, 11, 15];
  const isMatte = (r, g, b) =>
    Math.abs(r - matte[0]) + Math.abs(g - matte[1]) + Math.abs(b - matte[2]) < 30;
  const lum = (r, g, b) => 0.2126 * r + 0.7152 * g + 0.0722 * b;
  let specks = 0;
  const corner = 40;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const inCorner =
        (x < corner || x >= width - corner) && (y < corner || y >= height - corner);
      if (!inCorner) continue;
      const i = (y * width + x) * channels;
      const r = data[i];
      const g = data[i + 1];
      const b = data[i + 2];
      if (isMatte(r, g, b) || lum(r, g, b) < 200) continue;
      let nm = 0;
      for (let dy = -1; dy <= 1; dy += 1) {
        for (let dx = -1; dx <= 1; dx += 1) {
          if (!dx && !dy) continue;
          const nx = x + dx;
          const ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
          const j = (ny * width + nx) * channels;
          if (isMatte(data[j], data[j + 1], data[j + 2])) nm += 1;
        }
      }
      if (nm >= 3) specks += 1;
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

async function attackBandSharpness(buffer) {
  const { data, info } = await sharp(buffer).raw().toBuffer({ resolveWithObject: true });
  const { width: w, height: h, channels: ch } = info;
  let n = 0;
  let grad = 0;
  for (let y = Math.floor(h * 0.58); y < Math.floor(h * 0.68); y += 1) {
    for (let x = Math.floor(w * 0.2); x < Math.floor(w * 0.8); x += 1) {
      const i = (y * w + x) * ch;
      const j = (y * w + x + 1) * ch;
      grad +=
        Math.abs(data[i] - data[j]) +
        Math.abs(data[i + 1] - data[j + 1]) +
        Math.abs(data[i + 2] - data[j + 2]);
      n += 1;
    }
  }
  return Number((grad / n).toFixed(2));
}

function runGpu(input, deg, outdir) {
  fs.mkdirSync(outdir, { recursive: true });
  const result = spawnSync(
    GPU_PY,
    [GPU_SCRIPT, '--input', input, '--deg', String(deg), '--outdir', outdir, '--device', '0'],
    { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 },
  );
  if (result.status !== 0) {
    throw new Error(`GPU variants failed: ${result.stderr || result.stdout}`);
  }
  return JSON.parse(fs.readFileSync(path.join(outdir, 'gpu-variants.json'), 'utf8'));
}

function finishInWorker(job) {
  return new Promise((resolve, reject) => {
    const worker = new Worker(__filename, {
      workerData: job,
      resourceLimits: { maxOldGenerationSizeMb: 1024 },
    });
    worker.on('message', resolve);
    worker.on('error', reject);
    worker.on('exit', (code) => {
      if (code !== 0) reject(new Error(`worker exit ${code}`));
    });
  });
}

async function workerMain(job) {
  const input = fs.readFileSync(job.pngPath);
  const result = await sanitizeCardImage(input, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '356916_mega-charizard-x-ex.jpg',
    productType: 'card',
    skipDeskew: true,
  });
  const body = await sharp(result.body).jpeg(JPEG).toBuffer();
  fs.writeFileSync(job.outJpg, body);
  const skew = await skewMetrics(body);
  const specks = await countCornerLightSpecks(body);
  const sharpness = await attackBandSharpness(body);
  parentPort.postMessage({
    id: job.id,
    file: job.file,
    width: result.width,
    height: result.height,
    punched: result.punched,
    job: result.job,
    skew,
    cornerLightSpecks: specks,
    attackSharpness: sharpness,
    bytes: body.length,
  });
}

async function main() {
  if (!fs.existsSync(SRC)) {
    throw new Error(`Missing local leftover ${SRC} (no CardTrader fetch)`);
  }
  fs.mkdirSync(WORK, { recursive: true });
  fs.mkdirSync(REVIEW, { recursive: true });

  const beforeBuf = fs.readFileSync(SRC);
  await sharp(beforeBuf).jpeg(JPEG).toFile(path.join(REVIEW, 'charizard-leftover.jpg'));
  const beforeSkew = await skewMetrics(beforeBuf);
  const beforeSharp = await attackBandSharpness(beforeBuf);
  const beforeMeta = await sharp(beforeBuf).metadata();

  // Measured tilt is negative (CCW). Apply opposite rotation (same as deskewStudioDiecut).
  const measured = beforeSkew.brightDeg;
  if (!Number.isFinite(measured)) {
    throw new Error('Could not measure bright-edge tilt on local leftover');
  }
  const appliedDeg = -measured;
  console.log(`Local leftover bright edge ${measured}° → GPU rotate ${appliedDeg}°`);
  console.log(`GPU python: ${GPU_PY}`);
  console.log(`Workers: ${Math.min(3, os.cpus().length)}`);

  const gpu = runGpu(SRC, appliedDeg, WORK);
  console.log('GPU done', gpu.device, gpu.variants.map((v) => `${v.variant}:${v.gpu_ms}ms`).join(' '));

  // Second GPU pass if undershot (torch affine ≠ sharp by ~0.4° on this card).
  const corrected = {};
  await Promise.all(
    VARIANTS.map(async (v) => {
      const pngPath = path.join(WORK, v.png);
      const raw = await sharp(pngPath).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
      const remain = estimateBrightOuterEdgeSkewDegrees(raw.data, raw.info.width, raw.info.height);
      if (!Number.isFinite(remain) || Math.abs(remain) < 0.12) {
        corrected[v.id] = { remain: remain || 0, extra: 0 };
        return;
      }
      const extra = -remain;
      const fixDir = path.join(WORK, `fix-${v.id}`);
      fs.mkdirSync(fixDir, { recursive: true });
      // Reuse supersample path for small corrections on all (single-file GPU call).
      const fix = spawnSync(
        GPU_PY,
        [
          GPU_SCRIPT,
          '--input',
          pngPath,
          '--deg',
          String(extra),
          '--outdir',
          fixDir,
          '--device',
          '0',
          '--only',
          v.id === 'mask_nn' ? 'mask_nn' : v.id === 'crop_rotate' ? 'crop_rotate' : 'supersample',
        ],
        { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 },
      );
      if (fix.status !== 0) {
        throw new Error(`GPU fix ${v.id}: ${fix.stderr || fix.stdout}`);
      }
      const fixedPng = path.join(
        fixDir,
        v.id === 'mask_nn'
          ? 'variant-mask-nn.png'
          : v.id === 'crop_rotate'
            ? 'variant-crop-rotate.png'
            : 'variant-supersample.png',
      );
      fs.copyFileSync(fixedPng, pngPath);
      corrected[v.id] = { remain, extra };
    }),
  );
  console.log('GPU correction', corrected);

  const jobs = VARIANTS.map((v) => ({
    id: v.id,
    file: v.file,
    pngPath: path.join(WORK, v.png),
    outJpg: path.join(REVIEW, v.file),
  }));

  const finished = await Promise.all(jobs.map((j) => finishInWorker(j)));
  const byId = Object.fromEntries(finished.map((f) => [f.id, f]));

  // Baseline: current CPU bright-edge sanitize (for comparison strip).
  console.log('Baseline CPU bright-edge sanitize…');
  const baseline = await sanitizeCardImage(beforeBuf, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '356916_mega-charizard-x-ex.jpg',
  });
  const baselineBody = await sharp(baseline.body).jpeg(JPEG).toBuffer();
  fs.writeFileSync(path.join(REVIEW, 'cdn-leftover-bright-edge.jpg'), baselineBody);
  const baselineSkew = await skewMetrics(baselineBody);
  const baselineSpecks = await countCornerLightSpecks(baselineBody);
  const baselineSharp = await attackBandSharpness(baselineBody);

  const sections = [
    {
      id: 'charizard-before',
      title: 'Mega Charizard X ex · source',
      kicker: 'Local leftover 356916_ · no CardTrader',
      live: 'https://pokoin.com/marketplace/en/cards/713832',
      note: `Bright outer edge ${measured}°. Three GPU deskew variants below — pick one before ?v=ct3.`,
      pairs: [
        {
          before: {
            file: 'charizard-leftover.jpg',
            label: 'Before · local leftover',
            caption: `${beforeMeta.width}×${beforeMeta.height} · bright ${beforeSkew.brightDeg}°`,
            width: beforeMeta.width,
            height: beforeMeta.height,
            brightSkewDeg: beforeSkew.brightDeg,
            outerSkewDeg: beforeSkew.outerDeg,
            attackSharpness: beforeSharp,
            details: [
              'Local CDN mirror only — not CardTrader download.',
              `Attack-band horiz gradient ${beforeSharp} (higher = sharper text).`,
            ],
          },
          after: {
            file: 'cdn-leftover-bright-edge.jpg',
            label: 'Baseline · CPU bright-edge',
            caption: `+${(baseline.job?.deskewDeg || 0).toFixed(2)}° · bright ${baselineSkew.brightDeg}°`,
            width: baseline.width,
            height: baseline.height,
            brightSkewDeg: baselineSkew.brightDeg,
            outerSkewDeg: baselineSkew.outerDeg,
            cornerLightSpecks: baselineSpecks,
            attackSharpness: baselineSharp,
            punched: baseline.punched,
            job: baseline.job,
            details: [
              'Existing Node deskew (full-raster rotate + fringe).',
              `Attack sharpness ${baselineSharp} (was ${beforeSharp}).`,
            ],
          },
        },
      ],
    },
  ];

  const variantPairs = VARIANTS.map((v) => {
    const f = byId[v.id];
    return {
      before: {
        file: 'charizard-leftover.jpg',
        label: 'Before',
        caption: `bright ${beforeSkew.brightDeg}°`,
        brightSkewDeg: beforeSkew.brightDeg,
        attackSharpness: beforeSharp,
      },
      after: {
        file: v.file,
        label: v.title,
        caption: `bright ${f.skew.brightDeg}° · sharp ${f.attackSharpness}`,
        width: f.width,
        height: f.height,
        brightSkewDeg: f.skew.brightDeg,
        outerSkewDeg: f.skew.outerDeg,
        cornerLightSpecks: f.cornerLightSpecks,
        attackSharpness: f.attackSharpness,
        punched: f.punched,
        job: f.job,
        details: [
          v.blurb,
          `Remaining bright edge ${f.skew.brightDeg}° · silhouette ${f.skew.outerDeg}°.`,
          `Attack sharpness ${f.attackSharpness} (source ${beforeSharp}, baseline ${baselineSharp}).`,
          `Corner light specks ${f.cornerLightSpecks} · punched ${f.punched}.`,
        ],
      },
    };
  });

  sections.push({
    id: 'charizard-variants',
    title: 'GPU deskew variants',
    kicker: `${gpu.device} · parallel workers`,
    note:
      'A = supersample, B = nearest RGB / mask, C = crop-rotate-crop. Hairlines on for red-line test. Interior text: higher attack sharpness is better.',
    pairs: variantPairs,
  });

  const manifest = {
    revision: REVISION,
    generatedAt: new Date().toISOString(),
    host: 'test.pokoin.com',
    path: '/sanitize',
    url: 'https://test.pokoin.com/sanitize',
    gpu: {
      device: gpu.device,
      appliedDeg,
      measuredBrightDeg: measured,
      variants: gpu.variants,
    },
    deferred: [
      { title: 'Milotic C League', reason: 'Border rebuild still wrong — held back.' },
      { title: 'Swampert theme deck', reason: 'Clipped yellow + deskew still wrong — held back.' },
    ],
    sections,
    strip: null,
  };

  fs.writeFileSync(path.join(REVIEW, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(JSON.stringify({
    revision: REVISION,
    measured,
    appliedDeg,
    baseline: { bright: baselineSkew.brightDeg, sharp: baselineSharp },
    variants: finished.map((f) => ({
      id: f.id,
      bright: f.skew.brightDeg,
      sharp: f.attackSharpness,
      specks: f.cornerLightSpecks,
    })),
  }, null, 2));
}

if (isMainThread) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
} else {
  workerMain(workerData).catch((error) => {
    console.error(error);
    process.exit(1);
  });
}
