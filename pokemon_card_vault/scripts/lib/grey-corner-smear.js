'use strict';

/**
 * Detect Gengar-class grey die-cut ears: an old JPEG flatten that turned a
 * thin silver/white FA rim into a mid-grey blob against the dark matte.
 *
 * Walk 45° from each corner, skip matte / transparent, then look for a long
 * low-chroma mid-grey run (the flattened rim). TAG TEAM yellow banners are
 * high-chroma and are not this bug. Official pokemontcg PNGs go transparent
 * then silver/white, not grey.
 */

const WALK = 48;
const GREY_MIN = 8;
const MATTE_LUM = 40;
const GREY_LUM_LO = 125;
const GREY_LUM_HI = 200;
const GREY_CHROMA = 28;
const SILVER_LUM = 205;
const SILVER_CHROMA = 45;
const HIGH_CHROMA = 80;

function luminance(r, g, b) {
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function chroma(r, g, b) {
  return Math.max(r, g, b) - Math.min(r, g, b);
}

function sampleAt(data, width, height, x, y) {
  if (x < 0 || y < 0 || x >= width || y >= height) {
    return null;
  }
  const offset = (y * width + x) * 4;
  const r = data[offset];
  const g = data[offset + 1];
  const b = data[offset + 2];
  const a = data[offset + 3];
  return { r, g, b, a, lum: luminance(r, g, b), ch: chroma(r, g, b) };
}

function isOutside(pixel) {
  return !pixel || pixel.a < 40 || pixel.lum < MATTE_LUM;
}

function isMidGrey(pixel) {
  return (
    pixel &&
    pixel.a >= 40 &&
    pixel.lum >= GREY_LUM_LO &&
    pixel.lum <= GREY_LUM_HI &&
    pixel.ch < GREY_CHROMA
  );
}

function isSilverWhite(pixel) {
  return pixel && pixel.a >= 40 && pixel.lum >= SILVER_LUM && pixel.ch <= SILVER_CHROMA;
}

function isHighChroma(pixel) {
  return pixel && pixel.a >= 40 && pixel.ch >= HIGH_CHROMA;
}

function walkCorner(data, width, height, origin) {
  const samples = [];
  for (let i = 0; i < WALK; i += 1) {
    const pixel = sampleAt(
      data,
      width,
      height,
      origin.x + i * origin.dx,
      origin.y + i * origin.dy,
    );
    if (!pixel) {
      break;
    }
    samples.push({ i, ...pixel });
  }
  return samples;
}

function analyzeWalk(samples) {
  let i = 0;
  while (i < samples.length && isOutside(samples[i])) {
    i += 1;
  }
  const firstOpaque = i < samples.length ? samples[i].i : null;
  let greyRun = 0;
  const greyStart = i < samples.length ? samples[i].i : null;
  while (i < samples.length && isMidGrey(samples[i])) {
    greyRun += 1;
    i += 1;
  }
  const after = i < samples.length ? samples[i] : null;
  const flattenedRim = greyRun >= GREY_MIN && !isHighChroma(after);
  const greyThenSilver = greyRun >= 6 && isSilverWhite(after);
  return {
    firstOpaque,
    greyRun,
    greyStart: greyRun ? greyStart : null,
    afterLum: after ? Math.round(after.lum) : null,
    afterChroma: after ? after.ch : null,
    smear: flattenedRim || greyThenSilver,
  };
}

function analyzeRgba(data, width, height) {
  const origins = {
    TL: { x: 0, y: 0, dx: 1, dy: 1 },
    TR: { x: width - 1, y: 0, dx: -1, dy: 1 },
    BL: { x: 0, y: height - 1, dx: 1, dy: -1 },
    BR: { x: width - 1, y: height - 1, dx: -1, dy: -1 },
  };
  const corners = {};
  let smearCount = 0;
  for (const [name, origin] of Object.entries(origins)) {
    const result = analyzeWalk(walkCorner(data, width, height, origin));
    corners[name] = result;
    if (result.smear) {
      smearCount += 1;
    }
  }
  return {
    width,
    height,
    corners,
    smearCount,
    smeared: smearCount >= 1,
  };
}

async function detectGreyCornerSmear(input, { sharp } = {}) {
  if (!sharp) {
    throw new Error('sharp is required');
  }
  const { data, info } = await sharp(input, { failOn: 'none' })
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  return analyzeRgba(data, info.width, info.height);
}

module.exports = {
  GREY_MIN,
  analyzeRgba,
  detectGreyCornerSmear,
  isMidGrey,
  isSilverWhite,
};
