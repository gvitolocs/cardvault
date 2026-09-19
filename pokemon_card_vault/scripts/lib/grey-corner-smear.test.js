'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');
const sharp = require('sharp');
const { detectGreyCornerSmear } = require('./grey-corner-smear');

async function paintDiagonalCard({ smearCorners, silverCorners, yellowCorners }) {
  const width = 80;
  const height = 112;
  const { data } = await sharp({
    create: {
      width,
      height,
      channels: 4,
      background: { r: 11, g: 10, b: 15, alpha: 255 },
    },
  })
    .raw()
    .toBuffer({ resolveWithObject: true });
  const origins = {
    TL: { x: 0, y: 0, dx: 1, dy: 1 },
    TR: { x: width - 1, y: 0, dx: -1, dy: 1 },
    BL: { x: 0, y: height - 1, dx: 1, dy: -1 },
    BR: { x: width - 1, y: height - 1, dx: -1, dy: -1 },
  };
  const paint = (name, rgb, from, to) => {
    const origin = origins[name];
    for (let i = from; i <= to; i += 1) {
      const x = origin.x + i * origin.dx;
      const y = origin.y + i * origin.dy;
      const o = (y * width + x) * 4;
      data[o] = rgb[0];
      data[o + 1] = rgb[1];
      data[o + 2] = rgb[2];
      data[o + 3] = 255;
    }
  };
  for (const name of smearCorners || []) {
    paint(name, [168, 163, 167], 11, 25);
  }
  for (const name of silverCorners || []) {
    paint(name, [228, 228, 230], 11, 22);
  }
  for (const name of yellowCorners || []) {
    paint(name, [168, 163, 167], 11, 13);
    paint(name, [255, 241, 0], 14, 26);
  }
  return sharp(data, { raw: { width, height, channels: 4 } }).jpeg({ quality: 95 }).toBuffer();
}

test('flattened silver rim on two corners is a smear', async () => {
  const jpeg = await paintDiagonalCard({ smearCorners: ['TR', 'BL'], yellowCorners: ['TL', 'BR'] });
  const result = await detectGreyCornerSmear(jpeg, { sharp });
  assert.equal(result.corners.TR.smear, true);
  assert.equal(result.corners.BL.smear, true);
  assert.equal(result.corners.TL.smear, false);
  assert.equal(result.corners.BR.smear, false);
  assert.equal(result.smeared, true);
  assert.ok(result.corners.TR.greyRun >= 8);
});

test('official silver rim after matte is clean', async () => {
  const jpeg = await paintDiagonalCard({ silverCorners: ['TL', 'TR', 'BL', 'BR'] });
  const result = await detectGreyCornerSmear(jpeg, { sharp });
  assert.equal(result.smeared, false);
  assert.equal(result.smearCount, 0);
});

test('short grey AA then TAG TEAM yellow is not a smear', async () => {
  const jpeg = await paintDiagonalCard({ yellowCorners: ['TL', 'TR', 'BL', 'BR'] });
  const result = await detectGreyCornerSmear(jpeg, { sharp });
  assert.equal(result.smeared, false);
});

test('Gengar old live JPEG smears TR and BL', async () => {
  const file = '/tmp/gengar-mimikyu-fa/live.jpg';
  if (!fs.existsSync(file)) {
    return;
  }
  const result = await detectGreyCornerSmear(fs.readFileSync(file), { sharp });
  assert.equal(result.corners.TR.smear, true);
  assert.equal(result.corners.BL.smear, true);
  assert.equal(result.corners.TL.smear, false);
  assert.equal(result.smeared, true);
});

test('Gengar fa1 JPEG is clean', async () => {
  const file = '/tmp/gengar-mimikyu-fa/verify/live-fa1.jpg';
  if (!fs.existsSync(file)) {
    return;
  }
  const result = await detectGreyCornerSmear(fs.readFileSync(file), { sharp });
  assert.equal(result.smeared, false);
});
