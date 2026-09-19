'use strict';

/**
 * Max-quality JPEG from a PNG. JPEG is still DCT-lossy; this is the closest
 * web-safe encode (q100, 4:4:4). Alpha is flattened onto white.
 */

const DEFAULT_MATTE = { r: 255, g: 255, b: 255 };
const DARK_MATTE = { r: 11, g: 11, b: 15 };
/** Below this, treat PNG alpha as outside the die-cut (kills white AA fringe). */
const PARTIAL_ALPHA_MIN_OPAQUE = 250;

function punchPartialAlphaRgba(rgba, minOpaque = PARTIAL_ALPHA_MIN_OPAQUE) {
  let punched = 0;
  for (let i = 0; i < rgba.length; i += 4) {
    const a = rgba[i + 3];
    if (a >= minOpaque) {
      continue;
    }
    if (a > 0 || rgba[i] > 8 || rgba[i + 1] > 8 || rgba[i + 2] > 8) {
      punched += 1;
    }
    rgba[i] = 0;
    rgba[i + 1] = 0;
    rgba[i + 2] = 0;
    rgba[i + 3] = 0;
  }
  return punched;
}

async function pngToMaxJpeg(
  input,
  { sharp, matte = DEFAULT_MATTE, punchPartialAlpha = false } = {},
) {
  if (!sharp) {
    throw new Error('sharp is required');
  }
  const image = sharp(input, { failOn: 'none' }).rotate();
  const meta = await image.metadata();
  let pipeline = image;
  if (meta.hasAlpha) {
    if (punchPartialAlpha) {
      const raw = await pipeline.ensureAlpha().raw().toBuffer({ resolveWithObject: true });
      const rgba =
        raw.info.channels === 4
          ? raw.data
          : (() => {
              const out = Buffer.alloc(raw.info.width * raw.info.height * 4);
              for (let i = 0, p = 0; i < raw.data.length; i += raw.info.channels, p += 4) {
                out[p] = raw.data[i];
                out[p + 1] = raw.data[i + 1];
                out[p + 2] = raw.data[i + 2];
                out[p + 3] = 255;
              }
              return out;
            })();
      punchPartialAlphaRgba(rgba);
      pipeline = sharp(rgba, {
        raw: { width: raw.info.width, height: raw.info.height, channels: 4 },
      });
    }
    pipeline = pipeline.flatten({ background: matte });
  }
  const body = await pipeline
    .jpeg({
      quality: 100,
      chromaSubsampling: '4:4:4',
      mozjpeg: true,
    })
    .toBuffer();
  return {
    body,
    width: meta.width,
    height: meta.height,
    hadAlpha: Boolean(meta.hasAlpha),
  };
}

function siblingJpegKey(key) {
  const clean = String(key || '').replace(/^\/+/, '');
  if (!clean || clean.startsWith('originals/')) {
    return null;
  }
  return clean.replace(/\.[^.]+$/, '.jpg');
}

module.exports = {
  DEFAULT_MATTE,
  DARK_MATTE,
  PARTIAL_ALPHA_MIN_OPAQUE,
  punchPartialAlphaRgba,
  pngToMaxJpeg,
  siblingJpegKey,
};
