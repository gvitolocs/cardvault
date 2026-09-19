const assert = require('node:assert/strict');
const test = require('node:test');
const sharp = require('sharp');

const {
  DEFAULT_CORNER_RADIUS_RATIO,
  DEFAULT_MATTE,
  DEFAULT_OUTPUT_FORMAT,
  FRAME_RATIO,
  WIZARDS_YELLOW_RATIO,
  WIZARDS_YELLOW_SIDE_MM,
  LOSSLESS_PNG_OPTIONS,
  OFFICIAL_CORNER_RADIUS_RATIO,
  POKER_ASPECT,
  POKER_CORNER_RADIUS_MM,
  POKER_HEIGHT_MM,
  POKER_WIDTH_MM,
  CSS_CORNER_RADIUS_Y,
  ROUND_SUPER_SAMPLE,
  cornerRadiusPx,
  inDieCutCrescent,
  inDieCutCap,
  padToUnpinch,
  parseMatte,
  prepareCatalogImage,
  sanitizeOptionsFromEnv,
  sanitizeCardImage,
  estimateInnerJoinSkewDegrees,
  estimateVerticalInnerJoinSkewDegrees,
  estimateOuterSilhouetteSkewDegrees,
  estimateBrightOuterEdgeSkewDegrees,
  estimateStraightBorderSkewDegrees,
  fitStraightBorder,
  punchSilhouetteLightFringe,
  paintMatteJpegGuard,
  innerRectangleSkewDegrees,
  shouldDeskewInnerRectangle,
  measureSideThickness,
  sampleOutlineColor,
  targetFramePx,
} = require('./sanitize-card-image');

async function pixel(body, x, y) {
  const { data, info } = await sharp(body).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const index = (y * info.width + x) * info.channels;
  return [data[index], data[index + 1], data[index + 2], info.channels > 3 ? data[index + 3] : 255];
}

async function cardWithWhiteEars() {
  const width = 200;
  const height = 280;
  const ear = await sharp({
    create: { width: 24, height: 24, channels: 3, background: { r: 255, g: 255, b: 255 } },
  })
    .png()
    .toBuffer();
  return sharp({
    create: {
      width,
      height,
      channels: 3,
      background: { r: 40, g: 90, b: 170 },
    },
  })
    .composite([
      { input: ear, left: 0, top: 0 },
      { input: ear, left: width - 24, top: 0 },
      { input: ear, left: 0, top: height - 24 },
      { input: ear, left: width - 24, top: height - 24 },
    ])
    .jpeg({ quality: 95 })
    .toBuffer();
}

test('official radius is ~5% of poker width; catalog uses the same circular die-cut', () => {
  assert.ok(Math.abs(POKER_ASPECT - 63.5 / 88.9) < 1e-9);
  assert.equal(POKER_WIDTH_MM, 63.5);
  assert.equal(POKER_HEIGHT_MM, 88.9);
  assert.equal(POKER_CORNER_RADIUS_MM, 3.175);
  assert.ok(Math.abs(OFFICIAL_CORNER_RADIUS_RATIO - 3.175 / 63.5) < 1e-9);
  assert.ok(Math.abs(CSS_CORNER_RADIUS_Y - 3.175 / 88.9) < 1e-6);
  assert.equal(DEFAULT_CORNER_RADIUS_RATIO, OFFICIAL_CORNER_RADIUS_RATIO);
  assert.deepEqual(parseMatte('#0b0b0f'), DEFAULT_MATTE);
  assert.equal(WIZARDS_YELLOW_RATIO, 22 / 600);
  assert.ok(Math.abs(WIZARDS_YELLOW_SIDE_MM - 2.3283) < 0.01);
  assert.equal(FRAME_RATIO.yellow, WIZARDS_YELLOW_RATIO);
  assert.equal(FRAME_RATIO.silver, 0.024);
  const r = cornerRadiusPx(733, 1024);
  assert.equal(r, Math.round(733 * 0.05));
  assert.equal(inDieCutCrescent(0, 0, 733, 1024, r), true);
  assert.equal(inDieCutCap(0, 0, 733, 1024, r), false);
  assert.equal(inDieCutCrescent(r - 1, r - 1, 733, 1024, r), false);
  assert.equal(inDieCutCap(r - 1, r - 1, 733, 1024, r), true);
  assert.equal(inDieCutCrescent(r + 8, 4, 733, 1024, r), false);
});

test('matte JPEG collar does not flood a white TRAINER nameplate', () => {
  const width = 80;
  const height = 100;
  const radius = 8;
  const matte = DEFAULT_MATTE;
  const rgba = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 4;
      const crescent = inDieCutCrescent(x, y, width, height, radius);
      if (crescent) {
        rgba[i] = matte.r;
        rgba[i + 1] = matte.g;
        rgba[i + 2] = matte.b;
      } else {
        rgba[i] = 253;
        rgba[i + 1] = 253;
        rgba[i + 2] = 253;
      }
      rgba[i + 3] = 255;
    }
  }
  paintMatteJpegGuard(rgba, width, height, matte, radius);
  const name = (Math.round(height * 0.12) * width + Math.round(width * 0.5)) * 4;
  assert.ok(rgba[name] > 200 && rgba[name + 3] > 200, `nameplate stayed printed ${rgba[name]},${rgba[name + 1]},${rgba[name + 2]}`);
});

test('already-rounded silver trainer keeps the nameplate; die-cut is only the crescents', async () => {
  const width = 200;
  const height = 280;
  const radius = cornerRadiusPx(width, height);
  const t = 10;
  const matte = DEFAULT_MATTE;
  const silver = { r: 148, g: 150, b: 153 };
  const nameplate = { r: 253, g: 253, b: 253 };
  const rgba = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 4;
      rgba[i + 3] = 255;
      if (inDieCutCrescent(x, y, width, height, radius)) {
        rgba[i] = matte.r;
        rgba[i + 1] = matte.g;
        rgba[i + 2] = matte.b;
        continue;
      }
      const inset = Math.min(x, y, width - 1 - x, height - 1 - y);
      if (inset < t) {
        rgba[i] = silver.r;
        rgba[i + 1] = silver.g;
        rgba[i + 2] = silver.b;
        continue;
      }
      if (y < Math.round(height * 0.16)) {
        rgba[i] = nameplate.r;
        rgba[i + 1] = nameplate.g;
        rgba[i + 2] = nameplate.b;
        continue;
      }
      rgba[i] = 80;
      rgba[i + 1] = 170;
      rgba[i + 2] = 140;
    }
  }
  const jpeg = await sharp(rgba, { raw: { width, height, channels: 4 } }).jpeg({ quality: 100 }).toBuffer();
  const beforeName = await pixel(jpeg, Math.round(width * 0.5), Math.round(height * 0.11));
  assert.ok(beforeName[0] > 200, `source nameplate ${beforeName}`);
  const result = await sanitizeCardImage(jpeg, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '342345_air-balloon.jpg',
  });
  assert.equal(result.job.reason, 'already-rounded');
  assert.equal(result.radius, radius);
  const corner = await pixel(result.body, 1, 1);
  assert.ok(corner[0] < 40 && corner[1] < 40, `crescent stays matte ${corner}`);
  const name = await pixel(result.body, Math.round(width * 0.5), Math.round(height * 0.11));
  assert.ok(name[0] > 180 && name[1] > 180, `Air Balloon nameplate not flooded ${name}`);
  const tool = await pixel(result.body, Math.round(width * 0.18), Math.round(height * 0.06));
  assert.ok(tool[0] > 120, `TRAINER chrome not punched ${tool}`);
});

test('sanitize is on by default and writes JPEG', () => {
  assert.equal(sanitizeOptionsFromEnv({}).enabled, true);
  assert.equal(sanitizeOptionsFromEnv({}).outputFormat, 'jpg');
  assert.equal(sanitizeOptionsFromEnv({ ORACLE_IMAGE_SANITIZE: '0' }).enabled, false);
  assert.equal(sanitizeOptionsFromEnv({ ORACLE_IMAGE_SANITIZE_FORMAT: 'png' }).outputFormat, 'png');
  assert.deepEqual(
    sanitizeOptionsFromEnv({ ORACLE_IMAGE_SANITIZE_MATTE: '#16141a' }).matte,
    { r: 22, g: 20, b: 26 },
  );
  assert.equal(DEFAULT_OUTPUT_FORMAT, 'jpg');
});

test('opt-in PNG keeps transparent corner ears', async () => {
  const source = await cardWithWhiteEars();
  const before = await pixel(source, 1, 1);
  assert.ok(before[0] > 240 && before[1] > 240 && before[2] > 240);

  const result = await sanitizeCardImage(source, { sharp, format: 'png' });
  assert.equal(result.skipped, false);
  assert.equal(result.format, 'png');
  assert.equal(result.letterbox, null);
  assert.equal(result.width, 200);
  assert.equal(result.height, 280);

  const corner = await pixel(result.body, 1, 1);
  assert.ok(corner[3] < 20, `png corner alpha ${corner}`);
  const interior = await pixel(result.body, 100, 140);
  assert.ok(interior[2] > 140 && interior[3] > 200, `interior ${interior}`);
});

test('prepareCatalogImage keeps the catalog JPEG extension', async () => {
  const source = await cardWithWhiteEars();
  const prepared = await prepareCatalogImage(source, 'jpg', { sharp, env: {} });
  assert.equal(prepared.skipped, false);
  assert.equal(prepared.ext, 'jpg');
});

test('uniform black letterbox on opposite edges is cropped before rounding', async () => {
  const inner = await sharp({
    create: {
      width: 200,
      height: 280,
      channels: 3,
      background: { r: 40, g: 90, b: 170 },
    },
  })
    .png()
    .toBuffer();
  const boxed = await sharp(inner)
    .extend({
      top: 24,
      bottom: 24,
      left: 0,
      right: 0,
      background: { r: 0, g: 0, b: 0 },
    })
    .png()
    .toBuffer();

  const result = await sanitizeCardImage(boxed, { sharp, productType: 'card' });
  assert.equal(result.skipped, false);
  assert.ok(result.letterbox);
  assert.equal(result.letterbox.top, 24);
  assert.equal(result.letterbox.height, 280);
  assert.equal(result.height, 280);
  assert.equal(result.width, 200);
});

test('a colored top border is not treated as letterbox', async () => {
  const source = await sharp({
    create: {
      width: 200,
      height: 280,
      channels: 3,
      background: { r: 40, g: 90, b: 170 },
    },
  })
    .jpeg({ quality: 95 })
    .toBuffer();
  const result = await sanitizeCardImage(source, { sharp });
  assert.equal(result.letterbox, null);
  assert.equal(result.height, 280);
});

test('FORMAT=jpg still flattens corners onto the marketplace matte', async () => {
  const source = await cardWithWhiteEars();
  const result = await sanitizeCardImage(source, { format: 'jpg', sharp });
  assert.equal(result.format, 'jpg');
  const corner = await pixel(result.body, 1, 1);
  assert.ok(corner[0] < 40 && corner[1] < 40 && corner[2] < 40, `corner ${corner}`);
});

test('PNG mask uses the official circular radius (5% of the short side)', async () => {
  const source = await cardWithWhiteEars();
  const result = await sanitizeCardImage(source, { sharp, format: 'png' });
  assert.equal(result.radius, 10);
});

test('PNG encode is zlib-lossless: no palette, no quality, no effort', () => {
  assert.equal(LOSSLESS_PNG_OPTIONS.palette, false);
  assert.equal(LOSSLESS_PNG_OPTIONS.quality, undefined);
  assert.equal(LOSSLESS_PNG_OPTIONS.effort, undefined);
  assert.equal(LOSSLESS_PNG_OPTIONS.compressionLevel, 9);
});

test('interior pixels are a lossless copy of the decoded JPEG', async () => {
  const source = await cardWithWhiteEars();
  const decoded = await sharp(source).raw().toBuffer({ resolveWithObject: true });
  const result = await sanitizeCardImage(source, { sharp, format: 'png' });
  const out = await sharp(result.body).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const x = 100;
  const y = 140;
  const di = (y * decoded.info.width + x) * decoded.info.channels;
  const oi = (y * out.info.width + x) * out.info.channels;
  assert.equal(out.data[oi], decoded.data[di]);
  assert.equal(out.data[oi + 1], decoded.data[di + 1]);
  assert.equal(out.data[oi + 2], decoded.data[di + 2]);
  assert.equal(out.data[oi + 3], 255);
});

test('irregular 1px white halo is punched without letterbox crop', async () => {
  const width = 200;
  const height = 280;
  const data = Buffer.alloc(width * height * 3, 18);
  const set = (x, y, r, g, b) => {
    const index = (y * width + x) * 3;
    data[index] = r;
    data[index + 1] = g;
    data[index + 2] = b;
  };
  for (let x = 0; x < width; x += 1) {
    if (x >= 90 && x <= 110) {
      continue;
    }
    set(x, 0, 255, 255, 255);
    set(x, height - 1, 255, 255, 255);
  }
  for (let y = 0; y < height; y += 1) {
    if (y >= 130 && y <= 150) {
      continue;
    }
    set(0, y, 255, 255, 255);
    set(width - 1, y, 255, 255, 255);
  }
  const source = await sharp(data, { raw: { width, height, channels: 3 } }).png().toBuffer();
  const result = await sanitizeCardImage(source, { sharp, productType: 'card', format: 'png' });
  assert.equal(result.letterbox, null);
  const edge = await pixel(result.body, 0, 10);
  assert.ok(edge[3] < 20, `edge alpha ${edge}`);
  const body = await pixel(result.body, 100, 140);
  assert.ok(body[3] > 200 && body[0] < 40, `body ${body}`);
  const topMid = await pixel(result.body, 40, 0);
  assert.ok(topMid[3] < 8 || topMid[3] > 250, `no AA white halo ${topMid}`);
});

test('padToUnpinch restores ~0.78 R of frame so a 5% die-cut does not pinch', () => {
  const pad = padToUnpinch(500, 0.05, 10, Math.round(500 * FRAME_RATIO.yellow));
  assert.ok(pad >= 8, `pad ${pad}`);
  assert.equal(ROUND_SUPER_SAMPLE, 8);
  const pokemontcg = padToUnpinch(600, 0.05, 21, Math.round(600 * FRAME_RATIO.yellow));
  assert.equal(pokemontcg, 0, 'neo3/65 hires already has an era frame');
});

test('JPEG square-cut yellow grows a thicker corner cap, not a pinched L', async () => {
  const width = 200;
  const height = 280;
  const t = 4;
  const data = Buffer.alloc(width * height * 3);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 3;
      const frame = x < t || y < t || x >= width - t || y >= height - t;
      data[i] = frame ? 250 : 40;
      data[i + 1] = frame ? 220 : 160;
      data[i + 2] = frame ? 50 : 70;
    }
  }
  const source = await sharp(data, { raw: { width, height, channels: 3 } }).png().toBuffer();
  const result = await sanitizeCardImage(source, { sharp, format: 'jpg', jpegQuality: 100 });
  assert.equal(result.skipped, false);
  assert.ok(result.pad > 0, `pad ${result.pad}`);
  assert.ok(result.width > width, `grew ${result.width}`);
  const corner = await pixel(result.body, 1, 1);
  assert.ok(corner[0] < 40 && corner[1] < 40, `matte corner ${corner}`);
  const midLeft = await pixel(result.body, 4, Math.floor(result.height / 2));
  assert.ok(midLeft[0] > 180 && midLeft[1] > 150, `side yellow ${midLeft}`);
});

test('sampleOutlineColor prefers saturated frame, not the JPEG halo', () => {
  const { sampleOutlineColor } = require('./sanitize-card-image');
  const width = 120;
  const height = 168;
  const data = Buffer.alloc(width * height * 3);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 3;
      const edge = Math.min(x, y, width - 1 - x, height - 1 - y);
      if (edge <= 2) {
        data[i] = 226;
        data[i + 1] = 206;
        data[i + 2] = 119;
      } else if (edge <= 10) {
        data[i] = 239;
        data[i + 1] = 205;
        data[i + 2] = 20;
      } else {
        data[i] = 40;
        data[i + 1] = 90;
        data[i + 2] = 170;
      }
    }
  }
  const outline = sampleOutlineColor(data, width, height, 3);
  assert.ok(outline, 'sampled');
  const c = Math.max(outline.r, outline.g, outline.b) - Math.min(outline.r, outline.g, outline.b);
  assert.ok(c >= 160, `chroma ${c} from ${JSON.stringify(outline)}`);
  assert.ok(outline.b < 80, `not washed gold ${JSON.stringify(outline)}`);
});

test('studio die-cut with a full yellow frame is rounded, not grown', async () => {
  const width = 200;
  const height = 280;
  const t = 12;
  const data = Buffer.alloc(width * height * 3);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 3;
      const inEar = (x < 20 && y < 20) || (x >= width - 20 && y < 20)
        || (x < 20 && y >= height - 20) || (x >= width - 20 && y >= height - 20);
      if (inEar) {
        data[i] = 255;
        data[i + 1] = 255;
        data[i + 2] = 255;
        continue;
      }
      const frame = x < t || y < t || x >= width - t || y >= height - t;
      data[i] = frame ? 239 : 40;
      data[i + 1] = frame ? 205 : 90;
      data[i + 2] = frame ? 20 : 170;
    }
  }
  const source = await sharp(data, { raw: { width, height, channels: 3 } }).jpeg({ quality: 95 }).toBuffer();
  const result = await sanitizeCardImage(source, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '123762_shining-gyarados-65-64-neo-revelation.jpg',
  });
  assert.equal(result.skipped, false);
  assert.equal(result.job.action, 'diecut-only');
  assert.equal(result.pad, 0);
  assert.equal(result.width, width);
  const topMid = await pixel(result.body, Math.floor(width / 2), 3);
  assert.ok(topMid[2] < 80, `no pale second rim ${topMid}`);
  assert.ok(topMid[0] > 180 && topMid[1] > 150, `existing yellow ${topMid}`);
});

test('die-cut-only punches a top JPEG halo to matte; the printed yellow stays', async () => {
  const width = 200;
  const height = 280;
  const t = 12;
  const data = Buffer.alloc(width * height * 3);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 3;
      const inEar = (x < 22 && y < 22) || (x >= width - 22 && y < 22)
        || (x < 22 && y >= height - 22) || (x >= width - 22 && y >= height - 22);
      if (inEar || y < 3) {
        data[i] = 230;
        data[i + 1] = 232;
        data[i + 2] = 220;
        continue;
      }
      const frame = x < t || y < t || x >= width - t || y >= height - t;
      data[i] = frame ? 239 : 40;
      data[i + 1] = frame ? 205 : 90;
      data[i + 2] = frame ? 20 : 170;
    }
  }
  const source = await sharp(data, { raw: { width, height, channels: 3 } }).png().toBuffer();
  const result = await sanitizeCardImage(source, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '123762_shining-gyarados-65-64-neo-revelation.jpg',
  });
  assert.equal(result.pad, 0);
  assert.equal(result.job.reason, 'studio-diecut');
  const mx = Math.floor(result.width / 2);
  const corner = await pixel(result.body, 1, 1);
  assert.ok(corner[0] < 40 && corner[1] < 40, `die-cut corner is matte ${corner}`);
  const edge = await pixel(result.body, mx, 1);
  const yellowPx = await pixel(result.body, mx, 8);
  assert.ok(edge[0] > 180 && edge[2] < 80, `top is printed yellow after paper punch ${edge}`);
  assert.ok(yellowPx[0] > 180 && yellowPx[2] < 80, `original yellow kept ${yellowPx}`);
});

test('white studio surround around a complete yellow card is punched, not welded', async () => {
  const width = 220;
  const height = 300;
  const pad = 10;
  const t = 12;
  const yellow = { r: 239, g: 205, b: 20 };
  const inner = { r: 40, g: 90, b: 170 };
  const data = Buffer.alloc(width * height * 3, 255);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 3;
      const inPad = x < pad || y < pad || x >= width - pad || y >= height - pad;
      if (inPad) {
        const dirty = (x + y) % 11 === 0;
        data[i] = dirty ? 236 : 252;
        data[i + 1] = dirty ? 238 : 253;
        data[i + 2] = dirty ? 230 : 248;
      }
    }
  }
  for (let y = pad; y < height - pad; y += 1) {
    for (let x = pad; x < width - pad; x += 1) {
      const i = (y * width + x) * 3;
      const lx = x - pad;
      const ly = y - pad;
      const cw = width - pad * 2;
      const ch = height - pad * 2;
      const frame = lx < t || ly < t || lx >= cw - t || ly >= ch - t;
      data[i] = frame ? yellow.r : inner.r;
      data[i + 1] = frame ? yellow.g : inner.g;
      data[i + 2] = frame ? yellow.b : inner.b;
    }
  }
  const cream = { r: 254, g: 251, b: 234 };
  const washed = { r: 249, g: 247, b: 199 };
  for (let y = 0; y < height; y += 1) {
    for (const x of [pad - 1, width - pad]) {
      const i = (y * width + x) * 3;
      data[i] = washed.r;
      data[i + 1] = washed.g;
      data[i + 2] = washed.b;
    }
  }
  for (let x = 0; x < width; x += 1) {
    for (const y of [pad - 1, height - pad]) {
      const i = (y * width + x) * 3;
      data[i] = washed.r;
      data[i + 1] = washed.g;
      data[i + 2] = washed.b;
    }
  }
  const source = await sharp(data, { raw: { width, height, channels: 3 } }).png().toBuffer();
  const result = await sanitizeCardImage(source, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '128724_milotic-c-pokemon-league-35-147-supreme-victors-promos.jpg',
  });
  assert.equal(result.skipped, false);
  assert.equal(result.job.action, 'diecut-only');
  assert.equal(result.job.reason, 'studio-diecut');
  assert.equal(result.pad, 0);
  const mid = Math.floor(result.height / 2);
  const outside = await pixel(result.body, 2, mid);
  assert.ok(outside[0] < 40 && outside[1] < 40, `mid-side white is matte ${outside}`);
  const rim = await pixel(result.body, pad + 4, mid);
  assert.ok(rim[0] > 180 && rim[2] < 80, `printed yellow kept ${rim}`);
  const d =
    Math.abs(rim[0] - yellow.r) + Math.abs(rim[1] - yellow.g) + Math.abs(rim[2] - yellow.b);
  assert.ok(d < 80, `rim not welded to a new yellow ${rim} d=${d}`);
  const core = await pixel(result.body, Math.floor(result.width / 2), mid);
  assert.ok(core[2] > 120, `inner square stays blue ${core}`);
  const fringe = await pixel(result.body, pad - 1, mid);
  assert.ok(fringe[0] > 180 && fringe[1] > 180, `washed yellow AA kept, not punched ${fringe}`);
  assert.ok(!result.job.deskewDeg, `untilted studio photo is not rotated ${result.job.deskewDeg}`);
});

test('upright silver studio card is not rotated by yellow collage', async () => {
  const width = 300;
  const height = 420;
  const padX = 28;
  const padY = 24;
  const t = 10;
  // Totodile MEP leftover: light McDonald's silver, luma ~221 — not paper.
  const silver = { r: 221, g: 222, b: 224 };
  const yellow = { r: 238, g: 196, b: 48 };
  const inner = { r: 40, g: 90, b: 160 };
  const data = Buffer.alloc(width * height * 3, 255);
  for (let y = padY; y < height - padY; y += 1) {
    for (let x = padX; x < width - padX; x += 1) {
      const i = (y * width + x) * 3;
      const lx = x - padX;
      const ly = y - padY;
      const cw = width - padX * 2;
      const ch = height - padY * 2;
      const frame = lx < t || ly < t || lx >= cw - t || ly >= ch - t;
      const collage = !frame && lx > cw * 0.62 && lx < cw * 0.88 && ly > ch * 0.22 && ly < ch * 0.48;
      data[i] = frame ? silver.r : collage ? yellow.r : inner.r;
      data[i + 1] = frame ? silver.g : collage ? yellow.g : inner.g;
      data[i + 2] = frame ? silver.b : collage ? yellow.b : inner.b;
    }
  }
  const source = await sharp(data, { raw: { width, height, channels: 3 } }).png().toBuffer();
  const result = await sanitizeCardImage(source, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '389931_totodile.jpg',
  });
  assert.equal(result.skipped, false);
  assert.equal(result.job.family, 'silver');
  assert.notEqual(result.job.reason, 'gold-foil');
  assert.ok(!result.job.deskewDeg, `upright silver card was rotated ${result.job.deskewDeg}`);
  assert.ok(result.width < width - 8, `studio paper still on the sides ${result.width} vs ${width}`);
  const ear = await pixel(result.body, 1, 1);
  assert.ok(ear[0] < 50 && ear[1] < 50, `corner is still paper ${ear}`);
  const mid = await pixel(result.body, 3, Math.floor(result.height / 2));
  assert.ok(mid[0] > 160 && mid[2] > 160 && Math.abs(mid[0] - mid[2]) < 30, `light silver rim kept ${mid}`);
});

test('studio-diecut deskew straightens inner-join tilt without flipping it', async () => {
  const width = 220;
  const height = 300;
  const pad = 16;
  const t = 12;
  const yellow = { r: 237, g: 214, b: 83 };
  const inner = { r: 40, g: 90, b: 170 };
  const data = Buffer.alloc(width * height * 3, 255);
  for (let y = pad; y < height - pad; y += 1) {
    for (let x = pad; x < width - pad; x += 1) {
      const i = (y * width + x) * 3;
      const lx = x - pad;
      const ly = y - pad;
      const cw = width - pad * 2;
      const ch = height - pad * 2;
      const frame = lx < t || ly < t || lx >= cw - t || ly >= ch - t;
      data[i] = frame ? yellow.r : inner.r;
      data[i + 1] = frame ? yellow.g : inner.g;
      data[i + 2] = frame ? yellow.b : inner.b;
    }
  }
  const upright = await sharp(data, { raw: { width, height, channels: 3 } }).png().toBuffer();
  const tilted = await sharp(upright)
    .rotate(-4.5, { background: { r: 255, g: 255, b: 255, alpha: 1 } })
    .png()
    .toBuffer();
  const beforeRaw = await sharp(tilted).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const beforeDeg = estimateInnerJoinSkewDegrees(
    beforeRaw.data,
    beforeRaw.info.width,
    beforeRaw.info.height,
  );
  assert.ok(Math.abs(beforeDeg) > 2, `synthetic tilt ${beforeDeg}`);
  const result = await sanitizeCardImage(tilted, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '128758_swampert-rare-holo-12-147-supreme-victors.jpg',
  });
  assert.equal(result.job.reason, 'studio-diecut');
  assert.ok(Math.abs(result.job.deskewDeg) > 1, `deskew applied ${result.job.deskewDeg}`);
  const afterRaw = await sharp(result.body).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const afterDeg = estimateInnerJoinSkewDegrees(
    afterRaw.data,
    afterRaw.info.width,
    afterRaw.info.height,
  );
  assert.ok(
    Math.abs(afterDeg) < 0.8,
    `inner join upright, not flipped the other way ${afterDeg} from ${beforeDeg}`,
  );
  assert.ok(
    Math.sign(afterDeg) !== Math.sign(beforeDeg) || Math.abs(afterDeg) < 0.4,
    `must not overshoot to the opposite tilt ${afterDeg}`,
  );
});

test('tilted studio crop is deskewed then missing yellow is rebuilt to era width', async () => {
  const width = 220;
  const height = 300;
  const pad = 4;
  const t = 12;
  const yellow = { r: 237, g: 214, b: 83 };
  const inner = { r: 40, g: 90, b: 170 };
  const data = Buffer.alloc(width * height * 3, 255);
  for (let y = pad; y < height - pad; y += 1) {
    for (let x = pad; x < width - pad; x += 1) {
      const i = (y * width + x) * 3;
      const lx = x - pad;
      const ly = y - pad;
      const cw = width - pad * 2;
      const ch = height - pad * 2;
      const frame = lx < t || ly < t || lx >= cw - t || ly >= ch - t;
      data[i] = frame ? yellow.r : inner.r;
      data[i + 1] = frame ? yellow.g : inner.g;
      data[i + 2] = frame ? yellow.b : inner.b;
    }
  }
  const upright = await sharp(data, { raw: { width, height, channels: 3 } }).png().toBuffer();
  const tilted = await sharp(upright)
    .rotate(-4.5, { background: { r: 255, g: 255, b: 255, alpha: 1 } })
    .png()
    .toBuffer();
  const meta = await sharp(tilted).metadata();
  const clipped = await sharp(tilted)
    .extract({
      left: 28,
      top: 16,
      width: meta.width - 48,
      height: meta.height - 32,
    })
    .png()
    .toBuffer();
  const result = await sanitizeCardImage(clipped, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '128716_swampert-non-holo-theme-deck-12-147-supreme-victors-promos.jpg',
  });
  const raw = await sharp(result.body).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const deg = estimateInnerJoinSkewDegrees(raw.data, raw.info.width, raw.info.height);
  assert.ok(Math.abs(deg) < 0.8, `deskewed inner join ${deg}`);
  const outline = sampleOutlineColor(raw.data, raw.info.width, raw.info.height, raw.info.channels);
  const thickness = measureSideThickness(raw.data, raw.info.width, raw.info.height, outline);
  const short = Math.min(raw.info.width, raw.info.height);
  const mm = (px) => (px / short) * 63.5;
  assert.ok(thickness.left > 2 && thickness.right > 2, `sides restored ${JSON.stringify(thickness)}`);
  assert.ok(
    Math.abs(thickness.left - thickness.right) <= 2,
    `left/right T match ${thickness.left} vs ${thickness.right}`,
  );
  const sideMm = mm((thickness.left + thickness.right) / 2);
  assert.ok(
    sideMm >= WIZARDS_YELLOW_SIDE_MM * 0.85 && sideMm <= 2.8,
    `side yellow ${sideMm.toFixed(2)} mm (era ${WIZARDS_YELLOW_SIDE_MM.toFixed(2)} mm)`,
  );
  const target = targetFramePx(short, outline, Math.round((thickness.left + thickness.right) / 2));
  assert.ok(thickness.left >= Math.round(target * 0.85), `T meets target ${thickness.left} vs ${target}`);
});

test('straight AABB frame does not walk into gold or step the inner edge', async () => {
  const width = 200;
  const height = 280;
  const t = 10;
  const data = Buffer.alloc(width * height * 3);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 3;
      const jag = y >= 80 && y < 140 && x >= 6 && x < t;
      const frame = !jag && (x < t || y < t || x >= width - t || y >= height - t);
      const gold = x >= 40 && x < 80 && y >= 40 && y < 100;
      if (frame) {
        data[i] = 246;
        data[i + 1] = 204;
        data[i + 2] = 0;
      } else if (gold) {
        data[i] = 212;
        data[i + 1] = 168;
        data[i + 2] = 36;
      } else {
        data[i] = 40;
        data[i + 1] = 110;
        data[i + 2] = 190;
      }
    }
  }
  const source = await sharp(data, { raw: { width, height, channels: 3 } }).png().toBuffer();
  const result = await sanitizeCardImage(source, { sharp, format: 'jpg', jpegQuality: 100 });
  assert.equal(result.skipped, false);
  assert.equal(result.pad, 0);
  const isYellow = (p) => p[0] > 180 && p[1] > 140 && p[2] < 80;
  const mid = Math.floor(result.height / 2);
  assert.ok(isYellow(await pixel(result.body, 4, mid)), 'left band is yellow');
  const pastFrame = await pixel(result.body, t + 6, mid);
  assert.ok(pastFrame[2] > 120, `interior past T stays blue ${pastFrame}`);
  const goldPx = await pixel(result.body, 50, 60);
  assert.ok(goldPx[0] > 160 && goldPx[2] < 90, `gold window kept ${goldPx}`);
  assert.ok(goldPx[2] < goldPx[1] - 40, `gold not flattened to outline ${goldPx}`);
  const insets = [];
  for (const y of [50, 90, 110, mid, 200]) {
    let x = 0;
    for (; x < 40; x += 1) {
      const p = await pixel(result.body, x, y);
      if (!isYellow(p)) {
        break;
      }
    }
    insets.push(x);
  }
  const spread = Math.max(...insets) - Math.min(...insets);
  assert.ok(spread <= 1, `left inner edge is a vertical line ${insets}`);
});

test('square-cut highlight ring is welded into the yellow, not left as a white line', async () => {
  const width = 200;
  const height = 280;
  const t = 8;
  const data = Buffer.alloc(width * height * 3);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 3;
      const frame = x < t || y < t || x >= width - t || y >= height - t;
      const highlight = y === 0 || x === 0;
      data[i] = highlight ? 252 : frame ? 238 : 40;
      data[i + 1] = highlight ? 241 : frame ? 213 : 90;
      data[i + 2] = highlight ? 99 : frame ? 93 : 70;
    }
  }
  const source = await sharp(data, { raw: { width, height, channels: 3 } }).png().toBuffer();
  const result = await sanitizeCardImage(source, { sharp, format: 'jpg', jpegQuality: 100 });
  assert.equal(result.skipped, false);
  const lum = (p) => 0.2126 * p[0] + 0.7152 * p[1] + 0.0722 * p[2];
  const seam = await pixel(result.body, Math.floor(result.width / 2), Math.max(0, result.pad));
  assert.ok(lum(seam) < 225, `no highlight ring at outer edge ${seam} lum=${lum(seam)}`);
});

test('cropped yellow (Gible-class) rebuilds the full AABB to era thickness', async () => {
  const { padToUnpinch, paddedFrameThickness, targetFramePx, FRAME_RATIO } = require('./sanitize-card-image');
  const width = 300;
  const height = 420;
  const t = 7;
  const target = targetFramePx(width, { r: 253, g: 229, b: 80 }, t);
  assert.ok(target >= Math.round(width * FRAME_RATIO.yellow));
  const pad = padToUnpinch(width, DEFAULT_CORNER_RADIUS_RATIO, t, target);
  assert.ok(pad > 0, `cropped 7 px on 300 must pad, got ${pad} target=${target}`);
  assert.deepEqual(paddedFrameThickness({ top: 13, bottom: 13, left: 15, right: 14 }, 11), {
    top: 24,
    bottom: 24,
    left: 26,
    right: 25,
  });
  const data = Buffer.alloc(width * height * 3);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 3;
      const frame = x < t || y < t || x >= width - t || y >= height - t;
      data[i] = frame ? 253 : 40;
      data[i + 1] = frame ? 229 : 90;
      data[i + 2] = frame ? 80 : 170;
    }
  }
  const source = await sharp(data, { raw: { width, height, channels: 3 } }).png().toBuffer();
  const result = await sanitizeCardImage(source, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '124385_gible-non-holo-promo-7-17-pop-series-6.jpg',
  });
  assert.equal(result.skipped, false);
  assert.equal(result.job.action, 'rebuild-frame');
  assert.ok(result.pad > 0, `pad ${result.pad}`);
  const isYellow = (p) => p[0] > 180 && p[1] > 140 && p[2] < 120;
  const mid = Math.floor(result.height / 2);
  let yellowW = 0;
  for (; yellowW < 40; yellowW += 1) {
    if (!isYellow(await pixel(result.body, yellowW, mid))) {
      break;
    }
  }
  assert.ok(yellowW >= t + result.pad - 1, `rebuilt left T ${yellowW} >= ${t}+${result.pad}`);
  const interior = await pixel(result.body, yellowW + 8, mid);
  assert.ok(interior[2] > 120, `interior past rebuilt T stays blue ${interior}`);
  const corner = await pixel(result.body, 1, 1);
  assert.ok(corner[0] < 40 && corner[2] < 40, `square-cut corners die-cut to matte ${corner}`);
});

test('cropped DP header (Bidoof-class) does not weld yellow into the silver name bar', async () => {
  const width = 300;
  const height = 420;
  const t = 7;
  const headerH = 72;
  const data = Buffer.alloc(width * height * 3);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 3;
      const frame = x < t || y < t || x >= width - t || y >= height - t;
      if (frame) {
        data[i] = 253;
        data[i + 1] = 229;
        data[i + 2] = 80;
      } else if (y < headerH) {
        data[i] = 208;
        data[i + 1] = 202;
        data[i + 2] = 192;
      } else {
        data[i] = 40;
        data[i + 1] = 90;
        data[i + 2] = 170;
      }
    }
  }
  const source = await sharp(data, { raw: { width, height, channels: 3 } }).png().toBuffer();
  const result = await sanitizeCardImage(source, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '124393_bidoof-non-holo-promo-11-17-pop-series-6.jpg',
  });
  assert.equal(result.skipped, false);
  assert.equal(result.job.action, 'rebuild-frame');
  assert.ok(result.pad > 0, `pad ${result.pad}`);
  const isYellow = (p) => p[0] > 180 && p[1] > 140 && p[2] < 120;
  const chromaOf = (p) => Math.max(p[0], p[1], p[2]) - Math.min(p[0], p[1], p[2]);
  const hx = result.pad + t + 6;
  const hy = result.pad + t + 6;
  const header = await pixel(result.body, hx, hy);
  assert.equal(isYellow(header), false, `inner header corner stays silver ${header} at ${hx},${hy}`);
  assert.ok(header[0] > 160 && chromaOf(header) < 50, `header is silver, not outline yellow ${header}`);
  const tr = await pixel(result.body, result.width - result.pad - t - 6, result.pad + t + 6);
  assert.equal(isYellow(tr), false, `top-right header stays silver ${tr}`);
  const mid = Math.floor(result.height / 2);
  let yellowW = 0;
  for (; yellowW < 40; yellowW += 1) {
    if (!isYellow(await pixel(result.body, yellowW, mid))) {
      break;
    }
  }
  assert.ok(yellowW >= t + result.pad - 1, `rebuilt left T ${yellowW} >= ${t}+${result.pad}`);
});

test('Grass interior is not a yellow frame; alpha corners still pad a cropped rim', async () => {
  const {
    belongsToPrintedRim,
    classifyRebuildJob,
    measureSideThickness,
  } = require('./sanitize-card-image');
  const outline = { r: 253, g: 229, b: 80 };
  assert.equal(belongsToPrintedRim(254, 226, 65, outline), true);
  assert.equal(belongsToPrintedRim(146, 150, 76, outline), false, 'olive grass is not the rim');
  assert.equal(belongsToPrintedRim(192, 185, 81, outline), false, 'muddy grass transition is not the rim');
  const cropped = classifyRebuildJob({
    filename: '124401_turtwig-non-holo-promo-17-17-pop-series-6.jpg',
    width: 600,
    height: 825,
    cornerKind: 'already-rounded',
    outline,
    thickness: { top: 15, bottom: 13, left: 14, right: 14 },
  });
  assert.equal(cropped.action, 'rebuild-frame');
  assert.equal(cropped.reason, 'cropped-alpha-corners');
  const era = classifyRebuildJob({
    filename: '123762_shining-gyarados-65-64-neo-revelation.jpg',
    width: 600,
    height: 825,
    cornerKind: 'already-rounded',
    outline,
    thickness: { top: 22, bottom: 23, left: 21, right: 21 },
  });
  assert.equal(era.action, 'diecut-only');
  assert.equal(era.reason, 'already-rounded');

  const width = 300;
  const height = 420;
  const t = 7;
  const data = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 4;
      const corner = Math.min(x, y, width - 1 - x, height - 1 - y) < 8
        && (x < 16 || x >= width - 16)
        && (y < 16 || y >= height - 16);
      const frame = !corner && (x < t || y < t || x >= width - t || y >= height - t);
      if (corner) {
        data[i + 3] = 0;
      } else if (frame) {
        data[i] = 253;
        data[i + 1] = 229;
        data[i + 2] = 80;
        data[i + 3] = 255;
      } else {
        data[i] = 70;
        data[i + 1] = 125;
        data[i + 2] = 88;
        data[i + 3] = 255;
      }
    }
  }
  const thickness = measureSideThickness(data, width, height, outline);
  assert.ok(thickness.left <= t + 2, `walk stops at rim, not grass ${JSON.stringify(thickness)}`);
  assert.ok(thickness.right <= t + 2, `right walk ${thickness.right}`);
  const source = await sharp(data, { raw: { width, height, channels: 4 } }).png().toBuffer();
  const result = await sanitizeCardImage(source, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '124401_turtwig-non-holo-promo-17-17-pop-series-6.jpg',
  });
  assert.equal(result.skipped, false);
  assert.equal(result.job.action, 'rebuild-frame');
  const isYellow = (p) => p[0] > 180 && p[1] > 140 && p[2] < 120;
  const mid = Math.floor(result.height / 2);
  let yellowW = 0;
  for (; yellowW < 50; yellowW += 1) {
    if (!isYellow(await pixel(result.body, yellowW, mid))) {
      break;
    }
  }
  const target = Math.round(result.width * (22 / 600));
  assert.ok(yellowW <= target + 6, `left T ${yellowW} is not a 31px grass stamp (target~${target})`);
  assert.ok(yellowW >= t + result.pad - 2, `left T ${yellowW} pad=${result.pad}`);
  const interior = await pixel(result.body, yellowW + 10, mid);
  assert.ok(interior[1] > interior[2], `grass past T stays green ${interior}`);
  assert.equal(isYellow(interior), false);
  const r = Math.round(result.width * 0.05);
  const insideRound = (x, y) => {
    const cx = r;
    const cy = r;
    return Math.hypot(x - cx, y - cy) <= r - 1;
  };
  let hole = null;
  for (let y = 4; y < r && !hole; y += 1) {
    for (let x = 4; x < r; x += 1) {
      if (insideRound(x, y) && Math.min(x, y) <= 12) {
        hole = { x, y, p: await pixel(result.body, x, y) };
        break;
      }
    }
  }
  assert.ok(hole, 'found a pixel inside the die-cut near the corner');
  assert.equal(isYellow(hole.p), true, `pokemontcg alpha hole is yellow not matte ${JSON.stringify(hole)}`);
});

test('jagged inner yellow join is filled to a straight AABB on the sides', async () => {
  const width = 300;
  const height = 420;
  const t = 8;
  const data = Buffer.alloc(width * height * 3);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 3;
      const hole = y >= 160 && y < 220 && x >= t - 4 && x < t;
      const frame = !hole && (x < t || y < t || x >= width - t || y >= height - t);
      data[i] = frame ? 253 : 40;
      data[i + 1] = frame ? 229 : 90;
      data[i + 2] = frame ? 80 : 170;
    }
  }
  const source = await sharp(data, { raw: { width, height, channels: 3 } }).png().toBuffer();
  const result = await sanitizeCardImage(source, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '124385_gible-non-holo-promo-7-17-pop-series-6.jpg',
  });
  const isYellow = (p) => p[0] > 180 && p[1] > 140 && p[2] < 120;
  const widths = [];
  for (const y of [80, 180, Math.floor(result.height / 2), 300]) {
    let x = 0;
    for (; x < 40; x += 1) {
      if (!isYellow(await pixel(result.body, x, y))) {
        break;
      }
    }
    widths.push(x);
  }
  const spread = Math.max(...widths) - Math.min(...widths);
  assert.ok(spread <= 2, `left inner edge is a line ${widths}`);
});

test('borderless treatments are die-cut only; EX secrets still rebuild the yellow frame', () => {
  const {
    isBorderlessTreatment,
    parseCollectorOverNumber,
    classifyRebuildJob,
  } = require('./sanitize-card-image');
  assert.equal(isBorderlessTreatment('299026_dachsbun-ex-full-art-160-142-stellar-crown.jpg'), true);
  assert.equal(isBorderlessTreatment('261290_charmander-illustration-rare-168-165-151.jpg'), true);
  assert.equal(isBorderlessTreatment('241630_basic-fighting-energy-hyper-rare-258-198-scarlet-violet.jpg'), true);
  assert.equal(isBorderlessTreatment('343049_hilda-ultra-rare-164-086-white-flare.jpg'), true);
  assert.equal(isBorderlessTreatment('351691_mega-lucario-ex.jpg'), false);
  assert.equal(isBorderlessTreatment('351691_mega-lucario-ex-gold-secret-rare.jpg'), true);
  assert.equal(isBorderlessTreatment('109849_oddish-full-v4.jpg'), false);
  assert.equal(isBorderlessTreatment('115534_charizard-secret-rare-100-97-ex-dragon.jpg'), false);
  assert.deepEqual(parseCollectorOverNumber('299026_dachsbun-ex-full-art-160-142-stellar-crown.jpg'), {
    n: 160,
    set: 142,
    extra: 18,
  });
  assert.equal(parseCollectorOverNumber('110984_victory-cup-bw30-2nd-place.jpg'), null);
  const fa = classifyRebuildJob({
    filename: '299026_dachsbun-ex-full-art-160-142-stellar-crown.jpg',
    width: 500,
    height: 700,
    cornerKind: 'white-ears',
    outline: { r: 122, g: 122, b: 126 },
    thickness: { top: 2, bottom: 2, left: 2, right: 3 },
  });
  assert.equal(fa.action, 'diecut-only');
  const gyarados = classifyRebuildJob({
    filename: '123762_shining-gyarados-65-64-neo-revelation.jpg',
    width: 285,
    height: 395,
    cornerKind: 'white-ears',
    outline: { r: 239, g: 205, b: 20 },
    thickness: { top: 11, bottom: 14, left: 16, right: 15 },
  });
  assert.equal(gyarados.action, 'diecut-only');
  assert.equal(gyarados.reason, 'studio-diecut');
  const exSecret = classifyRebuildJob({
    filename: '115534_charizard-secret-rare-100-97-ex-dragon.jpg',
    width: 400,
    height: 550,
    cornerKind: 'square-cut',
    outline: { r: 238, g: 213, b: 93 },
    thickness: { top: 10, bottom: 10, left: 9, right: 10 },
  });
  assert.equal(exSecret.action, 'rebuild-frame');
});

test('already-rounded pokemontcg scans still die-cut; they are not skipped', () => {
  const { classifyRebuildJob } = require('./sanitize-card-image');
  const job = classifyRebuildJob({
    filename: '356895_mega-charizard-x-ex-full-art.jpg',
    width: 733,
    height: 1024,
    cornerKind: 'already-rounded',
    outline: { r: 74, g: 75, b: 77 },
    thickness: { top: 4, bottom: 4, left: 4, right: 4 },
  });
  assert.equal(job.action, 'diecut-only');
  assert.equal(job.reason, 'borderless-treatment');
});

test('gold foil (Mega Lucario / Gardevoir HR) is not a yellow frame', async () => {
  const {
    isGoldFoilRaster,
    GOLD_FOIL_YELLOW_FRACTION,
    classifyRebuildJob,
    isBorderlessTreatment,
  } = require('./sanitize-card-image');
  assert.equal(GOLD_FOIL_YELLOW_FRACTION, 0.4);
  assert.equal(isBorderlessTreatment('351691_mega-lucario-ex.jpg'), false);

  const width = 200;
  const height = 280;
  const foil = Buffer.alloc(width * height * 4);
  const earR = 12;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 4;
      const highlight = x < 2 || y < 2 || x >= width - 2 || y >= height - 2;
      foil[i] = 255;
      foil[i + 1] = highlight ? 220 : 213;
      foil[i + 2] = highlight ? 76 : 2;
      let cx = x;
      let cy = y;
      if (x < earR && y < earR) {
        cx = earR;
        cy = earR;
      } else if (x >= width - earR && y < earR) {
        cx = width - 1 - earR;
        cy = earR;
      } else if (x < earR && y >= height - earR) {
        cx = earR;
        cy = height - 1 - earR;
      } else if (x >= width - earR && y >= height - earR) {
        cx = width - 1 - earR;
        cy = height - 1 - earR;
      }
      const outside = Math.hypot(x - cx, y - cy) > earR && (x < earR || y < earR || x >= width - earR || y >= height - earR);
      foil[i + 3] = outside ? 0 : 255;
    }
  }
  assert.equal(isGoldFoilRaster(foil, width, height, 4), true);
  const goldJob = classifyRebuildJob({
    filename: '351691_mega-lucario-ex.jpg',
    width,
    height,
    cornerKind: 'already-rounded',
    outline: { r: 255, g: 211, b: 0 },
    thickness: { top: 80, bottom: 80, left: 80, right: 80 },
    goldFoil: true,
  });
  assert.equal(goldJob.action, 'diecut-only');
  assert.equal(goldJob.reason, 'gold-foil');

  const framed = Buffer.alloc(width * height * 4);
  const t = 12;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 4;
      const frame = x < t || y < t || x >= width - t || y >= height - t;
      framed[i] = frame ? 239 : 40;
      framed[i + 1] = frame ? 205 : 90;
      framed[i + 2] = frame ? 20 : 170;
      framed[i + 3] = 255;
    }
  }
  assert.equal(isGoldFoilRaster(framed, width, height, 4), false);

  const png = await sharp(foil, { raw: { width, height, channels: 4 } }).png().toBuffer();
  const result = await sanitizeCardImage(png, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '351691_mega-lucario-ex.jpg',
  });
  assert.equal(result.skipped, false);
  assert.equal(result.job.reason, 'gold-foil');
  const ear = await pixel(result.body, 1, 1);
  assert.ok(ear[0] < 40 && ear[1] < 40, `die-cut ears flatten to dark matte, not white/yellow ${ear}`);
  const edge = await pixel(result.body, Math.floor(result.width / 2), 1);
  assert.ok(edge[2] > 40, `gold highlight kept, not welded to (255,211,0): ${edge}`);
  assert.ok(edge[1] > 200, `gold highlight green kept ${edge}`);
});

test('inner rectangle tilt prefers the side join over a name-bar step', async () => {
  const width = 220;
  const height = 300;
  const t = 12;
  const yellow = { r: 237, g: 214, b: 83 };
  const inner = { r: 40, g: 90, b: 170 };
  const data = Buffer.alloc(width * height * 3, 255);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 3;
      const evoStep = x < 80 && y < t + 28;
      const frame = x < t || y < t || x >= width - t || y >= height - t || evoStep;
      data[i] = frame ? yellow.r : inner.r;
      data[i + 1] = frame ? yellow.g : inner.g;
      data[i + 2] = frame ? yellow.b : inner.b;
    }
  }
  const upright = await sharp(data, { raw: { width, height, channels: 3 } }).png().toBuffer();
  const tilted = await sharp(upright)
    .rotate(-3.2, { background: { r: 255, g: 255, b: 255, alpha: 1 } })
    .png()
    .toBuffer();
  const raw = await sharp(tilted).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const top = estimateInnerJoinSkewDegrees(raw.data, raw.info.width, raw.info.height);
  const vertical = estimateVerticalInnerJoinSkewDegrees(raw.data, raw.info.width, raw.info.height);
  const chosen = innerRectangleSkewDegrees(raw.data, raw.info.width, raw.info.height);
  assert.ok(Number.isFinite(vertical), `vertical join ${vertical}`);
  assert.ok(
    Math.abs(chosen - vertical) < 0.2,
    `inner rectangle uses the side join ${chosen}, not top ${top}`,
  );
  assert.ok(
    Math.abs(vertical) < Math.abs(top) || Math.abs(top - vertical) < 0.4,
    `side join is not the evo-box overshoot ${vertical} vs top ${top}`,
  );
});

test('FA / IR / SIR skip inner-rectangle deskew; gold leftover keys still deskew', () => {
  assert.equal(shouldDeskewInnerRectangle('299053_dachsbun-ex-special-illustration-rare-169-142.jpg'), false);
  assert.equal(shouldDeskewInnerRectangle('261290_charmander-illustration-rare-168-165-151.jpg'), false);
  assert.equal(shouldDeskewInnerRectangle('298335_dachsbun-ex-full-art-160-142.jpg'), false);
  assert.equal(shouldDeskewInnerRectangle('356916_mega-charizard-x-ex.jpg'), true);
  assert.equal(shouldDeskewInnerRectangle('128716_swampert-non-holo-theme-deck-12-147.jpg'), true);
});

test('gold foil on white studio paper is punched and cropped, not deskewed by the inner join', async () => {
  const width = 280;
  const height = 400;
  const padX = 40;
  const padY = 50;
  const cw = 200;
  const ch = 280;
  const data = Buffer.alloc(width * height * 3, 255);
  for (let y = 0; y < ch; y += 1) {
    for (let x = 0; x < cw; x += 1) {
      const i = ((padY + y) * width + (padX + x)) * 3;
      data[i] = 252;
      data[i + 1] = 214;
      data[i + 2] = 48;
    }
  }
  const jpeg = await sharp(data, { raw: { width, height, channels: 3 } }).jpeg({ quality: 100 }).toBuffer();
  const result = await sanitizeCardImage(jpeg, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '356916_mega-charizard-x-ex.jpg',
  });
  assert.equal(result.job.reason, 'gold-foil');
  assert.ok(!result.job.deskewDeg, `gold studio paper is not inner-join rotated ${result.job.deskewDeg}`);
  assert.ok(result.width < 260 && result.height < 320, `cropped off the paper ${result.width}x${result.height}`);
  assert.ok(result.punched > 0, `studio paper punched ${result.punched}`);
  const ear = await pixel(result.body, 1, 1);
  assert.ok(ear[0] < 40 && ear[1] < 40, `ears are dark matte ${ear}`);
  const mid = await pixel(result.body, 2, Math.floor(result.height / 2));
  assert.ok(mid[0] < 40 || mid[2] < 80, `left edge is matte or gold, not paper ${mid}`);
  const core = await pixel(result.body, Math.floor(result.width / 2), Math.floor(result.height / 2));
  assert.ok(core[0] > 180 && core[2] < 90, `gold face kept ${core}`);
});

async function countLightEdgePixels(body, depth = 3, lumaMin = 160, chromaMax = 55) {
  const { data, info } = await sharp(body).raw().toBuffer({ resolveWithObject: true });
  const { width, height, channels } = info;
  let light = 0;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const onEdge = x < depth || y < depth || x >= width - depth || y >= height - depth;
      if (!onEdge) {
        continue;
      }
      const i = (y * width + x) * channels;
      const r = data[i];
      const g = data[i + 1];
      const b = data[i + 2];
      const l = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      const c = Math.max(r, g, b) - Math.min(r, g, b);
      if (l >= lumaMin && c <= chromaMax) {
        light += 1;
      }
    }
  }
  return light;
}

test('gold foil studio crop has no light matte specks on the outer band', async () => {
  const width = 280;
  const height = 400;
  const padX = 40;
  const padY = 50;
  const cw = 200;
  const ch = 280;
  const data = Buffer.alloc(width * height * 3, 255);
  for (let y = 0; y < ch; y += 1) {
    for (let x = 0; x < cw; x += 1) {
      const i = ((padY + y) * width + (padX + x)) * 3;
      data[i] = 252;
      data[i + 1] = 214;
      data[i + 2] = 48;
    }
  }
  for (let x = padX; x < padX + cw; x += 1) {
    for (let y = padY; y < padY + 2; y += 1) {
      const i = (y * width + x) * 3;
      data[i] = 178;
      data[i + 1] = 179;
      data[i + 2] = 165;
    }
  }
  const jpeg = await sharp(data, { raw: { width, height, channels: 3 } }).jpeg({ quality: 100 }).toBuffer();
  const result = await sanitizeCardImage(jpeg, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '356916_mega-charizard-x-ex.jpg',
  });
  const light = await countLightEdgePixels(result.body);
  assert.ok(light < 40, `outer band light specks ${light}`);
});

test('silhouette fringe punch treats baked matte ears as clear surround', async () => {
  const width = 80;
  const height = 100;
  const matte = { r: 11, g: 11, b: 15 };
  const rgba = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 4;
      const card = x >= 20 && x < 60 && y >= 20 && y < 80;
      if (card) {
        rgba[i] = x < 22 ? 230 : 120;
        rgba[i + 1] = x < 22 ? 220 : 90;
        rgba[i + 2] = x < 22 ? 200 : 40;
      } else {
        rgba[i] = matte.r;
        rgba[i + 1] = matte.g;
        rgba[i + 2] = matte.b;
      }
      rgba[i + 3] = 255;
    }
  }
  const { punchSilhouetteLightFringe } = require('./sanitize-card-image');
  const punched = punchSilhouetteLightFringe(rgba, width, height, 2, 195, matte);
  assert.ok(punched >= 1, `punched highlight beside matte ear ${punched}`);
  const i = (25 * width + 21) * 4;
  assert.equal(rgba[i + 3], 0, `light edge beside matte is transparent ${rgba[i]},${rgba[i + 1]},${rgba[i + 2]}`);
  const core = (50 * width + 40) * 4;
  assert.ok(rgba[core + 3] > 200, `card interior kept ${rgba[core]},${rgba[core + 1]},${rgba[core + 2]}`);
});

test('tilted gold secret deskews the card rectangle then die-cuts, no yellow rebuild', async () => {
  const width = 280;
  const height = 400;
  const padX = 40;
  const padY = 50;
  const cw = 200;
  const ch = 280;
  const data = Buffer.alloc(width * height * 3, 255);
  for (let y = 0; y < ch; y += 1) {
    for (let x = 0; x < cw; x += 1) {
      const i = ((padY + y) * width + (padX + x)) * 3;
      data[i] = 252;
      data[i + 1] = 214;
      data[i + 2] = 48;
    }
  }
  const upright = await sharp(data, { raw: { width, height, channels: 3 } }).png().toBuffer();
  const tilted = await sharp(upright)
    .rotate(-3.5, { background: { r: 255, g: 255, b: 255, alpha: 1 } })
    .png()
    .toBuffer();
  const result = await sanitizeCardImage(tilted, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '356916_mega-charizard-x-ex.jpg',
    productType: 'card',
  });
  assert.equal(result.job.reason, 'gold-foil');
  assert.ok(Math.abs(result.job.deskewDeg) > 1, `gold secret still deskews ${result.job.deskewDeg}`);
  assert.ok(!result.pad, `gold secret does not grow a yellow frame ${result.pad}`);
  const ear = await pixel(result.body, 1, 1);
  assert.ok(ear[0] < 40 && ear[1] < 40, `ears are dark matte ${ear}`);
  const core = await pixel(result.body, Math.floor(result.width / 2), Math.floor(result.height / 2));
  assert.ok(core[0] > 180 && core[2] < 90, `gold face kept ${core}`);
});

test('square white studio photo of a tilted gold secret deskews the silhouette, not the art', async () => {
  const width = 400;
  const height = 400;
  const padX = 90;
  const padY = 50;
  const cw = 200;
  const ch = 280;
  const data = Buffer.alloc(width * height * 3, 255);
  for (let y = 0; y < ch; y += 1) {
    for (let x = 0; x < cw; x += 1) {
      const i = ((padY + y) * width + (padX + x)) * 3;
      data[i] = 252;
      data[i + 1] = 214;
      data[i + 2] = 48;
    }
  }
  const upright = await sharp(data, { raw: { width, height, channels: 3 } }).png().toBuffer();
  const tilted = await sharp(upright)
    .rotate(-1.8, { background: { r: 255, g: 255, b: 255, alpha: 1 } })
    .png()
    .toBuffer();
  const result = await sanitizeCardImage(tilted, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '356916_mega-charizard-x-ex.jpg',
  });
  assert.equal(result.skipped, false);
  assert.equal(result.job.reason, 'gold-foil');
  assert.ok(Math.abs(result.job.deskewDeg) > 0.8, `deskewed ${result.job.deskewDeg}`);
  assert.ok(Math.abs(result.job.deskewDeg) < 3.2, `did not chase gold art ${result.job.deskewDeg}`);
  assert.ok(!result.pad, `no yellow rebuild ${result.pad}`);
  const after = await sharp(result.body).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const remain = estimateOuterSilhouetteSkewDegrees(after.data, after.info.width, after.info.height);
  assert.ok(Math.abs(remain) < 0.95, `silhouette upright after refine ${remain}`);
});

test('gold leftover on dark matte deskews a small silhouette tilt', async () => {
  const width = 240;
  const height = 340;
  const padX = 20;
  const padY = 30;
  const cw = 200;
  const ch = 280;
  const matte = { r: 11, g: 11, b: 15 };
  const data = Buffer.alloc(width * height * 3);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 3;
      data[i] = matte.r;
      data[i + 1] = matte.g;
      data[i + 2] = matte.b;
    }
  }
  for (let y = 0; y < ch; y += 1) {
    for (let x = 0; x < cw; x += 1) {
      const i = ((padY + y) * width + (padX + x)) * 3;
      data[i] = 252;
      data[i + 1] = 214;
      data[i + 2] = 48;
    }
  }
  const upright = await sharp(data, { raw: { width, height, channels: 3 } }).png().toBuffer();
  const tilted = await sharp(upright)
    .rotate(-1.7, { background: matte })
    .jpeg({ quality: 100, chromaSubsampling: '4:4:4' })
    .toBuffer();
  const beforeRaw = await sharp(tilted).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const before = estimateOuterSilhouetteSkewDegrees(
    beforeRaw.data,
    beforeRaw.info.width,
    beforeRaw.info.height,
  );
  assert.ok(Math.abs(before) > 0.8, `matte-backed gold still reads a silhouette ${before}`);
  const result = await sanitizeCardImage(tilted, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '356916_mega-charizard-x-ex.jpg',
    productType: 'card',
  });
  assert.equal(result.job.reason, 'gold-foil');
  assert.ok(Math.abs(result.job.deskewDeg) > 0.8, `deskewed leftover-class gold ${result.job.deskewDeg}`);
  const afterRaw = await sharp(result.body).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const after = estimateOuterSilhouetteSkewDegrees(
    afterRaw.data,
    afterRaw.info.width,
    afterRaw.info.height,
  );
  const afterBright = estimateBrightOuterEdgeSkewDegrees(
    afterRaw.data,
    afterRaw.info.width,
    afterRaw.info.height,
  );
  assert.ok(Math.abs(after) < 0.45, `remaining silhouette ${after} from ${before}`);
  assert.ok(Math.abs(afterBright) < 0.45, `remaining bright outer edge ${afterBright} from ${before}`);
});

test('charizard leftover ct2 bright outer edge is upright after sanitize', async () => {
  const fs = require('node:fs');
  const path = [
    '/home/nez/Projects/pokoin-web/market/public/review/charizard-leftover.jpg',
    '/home/nez/Projects/pokoin/PokoinTest/index/cdn_images/356916_mega-charizard-x-ex.jpg',
  ].find((candidate) => fs.existsSync(candidate));
  if (!path) {
    return;
  }
  const input = fs.readFileSync(path);
  const beforeRaw = await sharp(input).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const beforeBright = estimateBrightOuterEdgeSkewDegrees(
    beforeRaw.data,
    beforeRaw.info.width,
    beforeRaw.info.height,
  );
  assert.ok(Math.abs(beforeBright) > 0.8, `ct2 leftover still leans ${beforeBright}`);
  const result = await sanitizeCardImage(input, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '356916_mega-charizard-x-ex.jpg',
    productType: 'card',
  });
  assert.equal(result.job.reason, 'gold-foil');
  assert.equal(result.job.action, 'diecut-only');
  const afterRaw = await sharp(result.body).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const afterBright = estimateBrightOuterEdgeSkewDegrees(
    afterRaw.data,
    afterRaw.info.width,
    afterRaw.info.height,
  );
  assert.ok(
    Math.abs(afterBright) < 0.2,
    `bright outer edge after sanitize ${afterBright} from ${beforeBright}`,
  );
  const afterBorder = fitStraightBorder(afterRaw.data, afterRaw.info.width, afterRaw.info.height);
  const v = (afterBorder.left.deg + afterBorder.right.deg) / 2;
  const h = (afterBorder.top.deg + afterBorder.bottom.deg) / 2;
  assert.ok(Math.abs(afterBorder.left.deg - afterBorder.right.deg) <= 0.55, `L/R ${afterBorder.left.deg} ${afterBorder.right.deg}`);
  assert.ok(Math.abs(afterBorder.top.deg - afterBorder.bottom.deg) <= 0.55, `T/B ${afterBorder.top.deg} ${afterBorder.bottom.deg}`);
  assert.ok(Math.abs(v - h) <= 0.25, `vertical ${v} vs horizontal ${h}`);
  assert.ok(afterBorder.left.rms < 2.2, `left rms ${afterBorder.left.rms}`);
  assert.ok(afterBorder.right.rms < 2.2, `right rms ${afterBorder.right.rms}`);
});

test('silhouette fringe punch keeps the yellow gold edge', async () => {
  const width = 80;
  const height = 100;
  const matte = { r: 11, g: 11, b: 15 };
  const rgba = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 4;
      const card = x >= 20 && x < 60 && y >= 20 && y < 80;
      if (card) {
        rgba[i] = 252;
        rgba[i + 1] = 214;
        rgba[i + 2] = 48;
      } else {
        rgba[i] = matte.r;
        rgba[i + 1] = matte.g;
        rgba[i + 2] = matte.b;
      }
      rgba[i + 3] = 255;
    }
  }
  punchSilhouetteLightFringe(rgba, width, height, 3, 195, matte);
  const edge = (20 * width + 20) * 4;
  assert.equal(rgba[edge + 3], 255, `gold edge kept ${rgba[edge]},${rgba[edge + 1]},${rgba[edge + 2]}`);
  assert.ok(rgba[edge] > 200 && rgba[edge + 2] < 80, `still gold ${rgba[edge]},${rgba[edge + 1]},${rgba[edge + 2]}`);
});

test('AABB-clipped gold deskews printed layout when the outer edge is already cropped', async () => {
  const width = 280;
  const height = 400;
  const padX = 40;
  const padY = 50;
  const cw = 200;
  const ch = 280;
  const data = Buffer.alloc(width * height * 3, 255);
  for (let y = 0; y < ch; y += 1) {
    for (let x = 0; x < cw; x += 1) {
      const i = ((padY + y) * width + (padX + x)) * 3;
      data[i] = 252;
      data[i + 1] = 214;
      data[i + 2] = 48;
    }
  }
  const dark = (x0, x1, y0, y1) => {
    for (let y = y0; y < y1; y += 1) {
      for (let x = x0; x < x1; x += 1) {
        const i = ((padY + y) * width + (padX + x)) * 3;
        data[i] = 42;
        data[i + 1] = 32;
        data[i + 2] = 24;
      }
    }
  };
  dark(Math.round(cw * 0.2), Math.round(cw * 0.8), Math.round(ch * 0.09), Math.round(ch * 0.12));
  dark(Math.round(cw * 0.2), Math.round(cw * 0.8), Math.round(ch * 0.65), Math.round(ch * 0.68));
  const upright = await sharp(data, { raw: { width, height, channels: 3 } }).png().toBuffer();
  const tilted = await sharp(upright)
    .rotate(-2.2, { background: { r: 11, g: 11, b: 15, alpha: 1 } })
    .png()
    .toBuffer();
  const meta = await sharp(tilted).metadata();
  const clipped = await sharp(tilted)
    .extract({
      left: Math.round((meta.width - cw) / 2),
      top: Math.round((meta.height - ch) / 2),
      width: cw,
      height: ch,
    })
    .jpeg({ quality: 100, chromaSubsampling: '4:4:4' })
    .toBuffer();
  const result = await sanitizeCardImage(clipped, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '356916_mega-charizard-x-ex.jpg',
    productType: 'card',
  });
  assert.equal(result.job.reason, 'gold-foil');
  assert.ok(Math.abs(result.job.deskewDeg) > 0.8, `AABB-clipped gold still deskews ${result.job.deskewDeg}`);
  assert.ok(Math.abs(result.job.deskewDeg) < 3.5, `did not chase gold art ${result.job.deskewDeg}`);
});

test('warm DP stock is not gold foil; a thin yellow rim still rebuilds', async () => {
  const {
    isGoldFoilRaster,
    measureSideThickness,
    sampleOutlineColor,
  } = require('./sanitize-card-image');
  const width = 200;
  const height = 280;
  const t = 8;
  const data = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 4;
      const frame = x < t || y < t || x >= width - t || y >= height - t;
      data[i] = frame ? 254 : 189;
      data[i + 1] = frame ? 232 : 168;
      data[i + 2] = frame ? 72 : 147;
      data[i + 3] = 255;
    }
  }
  const outline = sampleOutlineColor(data, width, height, 4);
  const thickness = measureSideThickness(data, width, height, outline);
  assert.equal(
    isGoldFoilRaster(data, width, height, 4, thickness),
    false,
    `tMed ${JSON.stringify(thickness)} is a printed rim`,
  );
  const png = await sharp(data, { raw: { width, height, channels: 4 } }).png().toBuffer();
  const result = await sanitizeCardImage(png, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '124379_lucario-non-holo-promo-2-17-pop-series-6.jpg',
  });
  assert.notEqual(result.job.reason, 'gold-foil');
  assert.equal(result.job.action, 'rebuild-frame');
});

test('full-art pokemontcg PNG does not paint a yellow sliver in the die-cut', async () => {
  const width = 200;
  const height = 280;
  const rgba = Buffer.alloc(width * height * 4);
  const r = 20;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 4;
      let cx = x;
      let cy = y;
      if (x < r && y < r) {
        cx = r;
        cy = r;
      } else if (x >= width - r && y < r) {
        cx = width - 1 - r;
        cy = r;
      } else if (x < r && y >= height - r) {
        cx = r;
        cy = height - 1 - r;
      } else if (x >= width - r && y >= height - r) {
        cx = width - 1 - r;
        cy = height - 1 - r;
      }
      const d = Math.hypot(x - cx, y - cy);
      if ((x < r || y < r || x >= width - r || y >= height - r) && d > r) {
        rgba[i] = 255;
        rgba[i + 1] = 255;
        rgba[i + 2] = 255;
        rgba[i + 3] = d < r + 2 ? 140 : 0;
        continue;
      }
      rgba[i] = 74;
      rgba[i + 1] = 75;
      rgba[i + 2] = 77;
      rgba[i + 3] = 255;
    }
  }
  const png = await sharp(rgba, { raw: { width, height, channels: 4 } }).png().toBuffer();
  const result = await sanitizeCardImage(png, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '356895_mega-charizard-x-ex-full-art.jpg',
  });
  assert.equal(result.skipped, false);
  assert.equal(result.job.action, 'diecut-only');
  assert.equal(result.pad, 0);
  const { data, info } = await sharp(result.body).raw().toBuffer({ resolveWithObject: true });
  const pix = (x, y) => {
    const i = (y * info.width + x) * info.channels;
    return [data[i], data[i + 1], data[i + 2]];
  };
  assert.ok(pix(0, 0)[0] < 40, `AABB dark ${pix(0, 0)}`);
  const edge = pix(18, 18);
  const isYellow = edge[0] > 180 && edge[1] > 150 && edge[2] < 80;
  assert.equal(isYellow, false, `no invented yellow on FA ${edge}`);
  assert.ok(edge[0] < 90, `die-cut fringe is not white ${edge}`);
});

test('silver-rim trainer UR does not paint sunset orange into the die-cut', async () => {
  const width = 200;
  const height = 280;
  const r = 16;
  const t = 12;
  const rgba = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 4;
      let cx = x;
      let cy = y;
      if (x < r && y < r) {
        cx = r;
        cy = r;
      } else if (x >= width - r && y < r) {
        cx = width - 1 - r;
        cy = r;
      } else if (x < r && y >= height - r) {
        cx = r;
        cy = height - 1 - r;
      } else if (x >= width - r && y >= height - r) {
        cx = width - 1 - r;
        cy = height - 1 - r;
      }
      const d = Math.hypot(x - cx, y - cy);
      if ((x < r || y < r || x >= width - r || y >= height - r) && d > r) {
        rgba[i] = 255;
        rgba[i + 1] = 255;
        rgba[i + 2] = 255;
        rgba[i + 3] = 0;
        continue;
      }
      const inset = Math.min(x, y, width - 1 - x, height - 1 - y);
      if (inset < t) {
        rgba[i] = 148;
        rgba[i + 1] = 150;
        rgba[i + 2] = 153;
      } else {
        rgba[i] = 214;
        rgba[i + 1] = 124;
        rgba[i + 2] = 108;
      }
      rgba[i + 3] = 255;
    }
  }
  const png = await sharp(rgba, { raw: { width, height, channels: 4 } }).png().toBuffer();
  const result = await sanitizeCardImage(png, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '343049_hilda.jpg',
  });
  const { data, info } = await sharp(result.body).raw().toBuffer({ resolveWithObject: true });
  const pix = (x, y) => {
    const i = (y * info.width + x) * info.channels;
    return [data[i], data[i + 1], data[i + 2]];
  };
  const corner = pix(10, 10);
  const orange = corner[0] > 180 && corner[1] < 160 && corner[2] < 140;
  assert.equal(orange, false, `silver rim is not sunset orange ${corner}`);
  assert.ok(pix(0, 0)[0] < 40, `AABB dark ${pix(0, 0)}`);
  const silver = pix(Math.floor(width / 2), 4);
  const silverChroma = Math.max(silver[0], silver[1], silver[2]) - Math.min(silver[0], silver[1], silver[2]);
  assert.ok(silverChroma < 40 && silver[0] > 80, `mid-top stays silver ${silver}`);
  const fan = pix(6, 6);
  const fanOrange = fan[0] > 180 && fan[1] < 160 && fan[2] < 140;
  assert.equal(fanOrange, false, `die-cut fan is not orange ${fan}`);
});

test('silver-rim SIR with yellow art does not paint yellow into the header corners', async () => {
  const width = 200;
  const height = 280;
  const r = 16;
  const t = 14;
  const rgba = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 4;
      let cx = x;
      let cy = y;
      if (x < r && y < r) {
        cx = r;
        cy = r;
      } else if (x >= width - r && y < r) {
        cx = width - 1 - r;
        cy = r;
      } else if (x < r && y >= height - r) {
        cx = r;
        cy = height - 1 - r;
      } else if (x >= width - r && y >= height - r) {
        cx = width - 1 - r;
        cy = height - 1 - r;
      }
      const d = Math.hypot(x - cx, y - cy);
      if ((x < r || y < r || x >= width - r || y >= height - r) && d > r) {
        rgba[i] = 255;
        rgba[i + 1] = 255;
        rgba[i + 2] = 255;
        rgba[i + 3] = 0;
        continue;
      }
      const inset = Math.min(x, y, width - 1 - x, height - 1 - y);
      if (inset < t) {
        rgba[i] = 148;
        rgba[i + 1] = 150;
        rgba[i + 2] = 153;
      } else {
        rgba[i] = 239;
        rgba[i + 1] = 205;
        rgba[i + 2] = 20;
      }
      rgba[i + 3] = 255;
    }
  }
  const png = await sharp(rgba, { raw: { width, height, channels: 4 } }).png().toBuffer();
  const result = await sanitizeCardImage(png, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '351687_lillie-s-determination.jpg',
  });
  const { sampleOutlineColor, outlineFamily } = require('./sanitize-card-image');
  const raw = await sharp(png).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const outline = sampleOutlineColor(raw.data, raw.info.width, raw.info.height, raw.info.channels);
  assert.equal(outlineFamily(outline), 'silver', JSON.stringify(outline));
  const { data, info } = await sharp(result.body).raw().toBuffer({ resolveWithObject: true });
  const pix = (x, y) => {
    const i = (y * info.width + x) * info.channels;
    return [data[i], data[i + 1], data[i + 2]];
  };
  const tr = pix(width - 10, 10);
  const isYellow = tr[0] > 180 && tr[1] > 150 && tr[2] < 80;
  assert.equal(isYellow, false, `top-right rim is not yellow ${tr}`);
  const silverChroma = Math.max(tr[0], tr[1], tr[2]) - Math.min(tr[0], tr[1], tr[2]);
  assert.ok(silverChroma < 40 && tr[0] > 80, `top-right stays silver ${tr}`);
  const mid = pix(Math.floor(width / 2), 6);
  assert.ok(Math.abs(mid[0] - 148) < 12 && Math.abs(mid[1] - 150) < 12, `header copied from original ${mid}`);
});

test('product rasters are left unsanitized', async () => {
  const source = await sharp({
    create: {
      width: 400,
      height: 260,
      channels: 3,
      background: { r: 255, g: 255, b: 255 },
    },
  })
    .jpeg({ quality: 90 })
    .toBuffer();
  const result = await sanitizeCardImage(source, { sharp, productType: 'product' });
  assert.equal(result.skipped, true);
  assert.equal(result.reason, 'not-a-card');
});

test('JPEG corners are 8× coverage-AA, not 1× stairs', async () => {
  const width = 200;
  const height = 280;
  const t = 12;
  const data = Buffer.alloc(width * height * 3, 40);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 3;
      const frame = x < t || y < t || x >= width - t || y >= height - t;
      data[i] = frame ? 74 : 40;
      data[i + 1] = frame ? 75 : 90;
      data[i + 2] = frame ? 77 : 170;
    }
  }
  const source = await sharp(data, { raw: { width, height, channels: 3 } }).png().toBuffer();
  const result = await sanitizeCardImage(source, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '356870_mega-lopunny-ex.jpg',
  });
  const aabb = await pixel(result.body, 0, 0);
  assert.ok(aabb[0] < 40 && aabb[1] < 40, `outside the round is matte ${aabb}`);
  const { data: out, info } = await sharp(result.body).raw().toBuffer({ resolveWithObject: true });
  let blended = 0;
  for (let y = 0; y < 14; y += 1) {
    for (let x = 0; x < 14; x += 1) {
      const v = out[(y * info.width + x) * info.channels];
      if (v >= 28 && v <= 65) {
        blended += 1;
      }
    }
  }
  assert.ok(blended >= 4, `8× AA fringe expected, blended=${blended}`);
  const inner = await pixel(result.body, 8, 8);
  assert.ok(inner[0] > 55 && Math.abs(inner[0] - inner[1]) < 12, `inside the round stays silver ${inner}`);
});

test('magenta interior does not paint onto a silver rim', async () => {
  const width = 200;
  const height = 280;
  const t = 14;
  const data = Buffer.alloc(width * height * 3);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 3;
      const frame = x < t || y < t || x >= width - t || y >= height - t;
      data[i] = frame ? 74 : 235;
      data[i + 1] = frame ? 75 : 95;
      data[i + 2] = frame ? 77 : 121;
    }
  }
  const source = await sharp(data, { raw: { width, height, channels: 3 } }).jpeg({ quality: 100 }).toBuffer();
  const result = await sanitizeCardImage(source, {
    sharp,
    format: 'jpg',
    jpegQuality: 100,
    filename: '356870_mega-lopunny-ex.jpg',
  });
  const rim = await pixel(result.body, 6, 40);
  const chroma = Math.max(rim[0], rim[1], rim[2]) - Math.min(rim[0], rim[1], rim[2]);
  assert.ok(chroma < 40 && rim[0] < 140, `left rim stays silver, not magenta ${rim}`);
  const art = await pixel(result.body, 40, 40);
  assert.ok(art[0] > 180 && art[1] < 140, `interior magenta kept ${art}`);
});
