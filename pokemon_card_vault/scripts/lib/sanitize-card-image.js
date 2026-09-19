'use strict';

/**
 * Catalog ingest sanitizer for CardTrader / R2 card rasters.
 *
 * Physical TCG cards are poker trim 63.5 × 88.9 mm with a **circular** die-cut
 * of 0.125 in = 3.175 mm (3.175/63.5 = 5.0% of width, 3.175/88.9 ≈ 3.571% of
 * height). CSS `--tcg-corner: 5% / 3.571%` is that same circle. Catalog JPEGs
 * are axis-aligned rectangles, so the four cardboard crescents stay in the
 * file as near-white pixels. The clip may change **only those crescents**
 * (pixels in the four corner squares of side R that sit outside the quarter-
 * circle). Do not punch, weld, or matte-flood the printed face: silver SV
 * TRAINER chrome, the nameplate, yellow/silver rim inside the circle, or art.
 * Light interiors (Air Balloon name bar luma ~253) match “ear white”; a 1 px
 * JPEG collar that reseeds from freshly painted matte used to flood the whole
 * header. Snapshot the clear mask; never treat the nameplate as cardboard.
 * JPEG has no alpha, so a dark marketplace UI shows un-punched crescents as
 * ears. Default output is PNG with transparent corners. Catalog rewrites
 * (D00000E) stay JPEG: fill those crescents with the sampled outline colour,
 * then clip to the die-cut and flatten onto the dark matte. Square-cut scans
 * (yellow to 90°) get the same clip so the outer stroke follows the round.
 * Already-rounded sources (pokemontcg transparent corners, previously
 * sanitized leftovers) already are the die-cut — flatten remaining paper /
 * matte crescents; do not clip extra printed pixels at 5% and do not
 * fringe-punch silver. Studio photos of an already die-cut card (white corner
 * ears, or a thin white ring around a complete printed face) already have the
 * printed frame — punch that studio white, round, and do not pad or weld a
 * second rim. Stop the punch at washed JPEG yellow (the outer millimetre),
 * not at saturated chroma 55.
 *
 * Pipeline: (1) rotate so the inner printed rectangle is axis-aligned
 * (left/right join, Theil–Sen — not the name-bar step); (2) then measure
 * the outer rim and rebuild to era millimetres when the scan is a cropped
 * yellow/silver frame. Full-art, IR, SIR, rainbow, and shiny have no
 * yellow-frame rebuild. Gold-foil secrets deskew on the four straight outer
 * borders (left/right agree, top/bottom agree, then vertical matches
 * horizontal), crop tight to those intercepts, and die-cut only. Do not chase
 * the illustration or the jagged mask. AABB-clipped gold falls back to the
 * printed name/attack baselines. Do not redraw the whole face; the bottom
 * band is thicker on purpose (copyright / set number).
 *
 * Some files also pad the card with uniform black (or white) letterbox bands.
 *
 * Once the outer frame thickness is measured (mid-side walk, stop at the
 * interior), paint it as an axis-aligned rectangle — one T per side, straight
 * inner edges. Do not walk scanline-by-scanline into gold or holo noise.
 * Wizards/Neo printed yellow is ~2.33 mm on the sides (22 px / 600 on
 * pokemontcg.io neo3/65), not the ~3.2 mm leftover from a cropped Base Set photo.
 *
 * Gold hyper-rares (Mega Lucario ex 188/132, Mega Gardevoir ex 187/132) are
 * foil to the edge: ~88% of pixels are yellow hue. That is the art, not a
 * 2.3 mm frame. Leftover R2 keys often omit `hyper-rare` (`351691_mega-lucario-ex.jpg`).
 * If yellow covers ≥40% of sampled opaque pixels, die-cut only — never
 * `paintStraightFrame` / `weldToOutline` (those flatten the metallic highlight
 * `(252,220,76)` into saturated `(255,211,0)`). Gold HR catalog faces come
 * from CardTrader photos (foil grain). pokemontcg/Limitless gold renders are
 * flat silhouettes — do not replace a textured CT scan with those. Never
 * sanitize a previously welded live JPEG; use `originals/` or a fresh CT URL.
 * Flatten the die-cut onto the dark marketplace matte, not white.
 * Warm DP card stock (Lucario pop6/2) also matches `isYellowHue` (~50%)
 * because beige silver is r>b with chroma 40. That is a printed rim
 * (tMed ~12–15), not foil-to-edge. Skip gold-foil when a thin frame exists.
 * Pikachu pop6/9 is 67% yellow art with an 11 px rim — still rebuild-frame.
 *
 * Cropped DP promos (POP Series 6 Gible/Bidoof): pad, then weld the yellow
 * band only. Do not 8×-coverage-weld the silver name/HP bar — light
 * interior matches `isPunchableEar` and became yellow nicks in the header
 * corners. `inCornerFan` is the canvas die-cut, not orig+radius.
 *
 * Thickness walks must stop at the printed rim (`similarToOutline`), not
 * `isYellowHue` through Grass art (Turtwig pop6/17 walked 14 px of yellow
 * then 17 px of olive into T=31 and stamped 3.28 mm sides). pokemontcg
 * hires often have transparent corners; that is not “era-complete”.
 * After paint, left and right T must match and sit near 22/600 (2.33 mm).
 * Do not blit those alpha holes over the yellow pad — they sit inside the
 * padded die-cut and flatten to black nicks (Turtwig 17/17 at ~20,20).
 *
 * This module is the single recipe for the next import. Do not overwrite R2
 * originals in place. CardTrader remains the unsanitized source. See
 * docs/card-image-sanitize.md.
 */

const { punchPartialAlphaRgba } = require('./png-to-jpeg');
const POKER_WIDTH_MM = 63.5;
const POKER_HEIGHT_MM = 88.9;
const POKER_ASPECT = POKER_WIDTH_MM / POKER_HEIGHT_MM;
const POKER_CORNER_RADIUS_MM = 3.175;
const OFFICIAL_CORNER_RADIUS_RATIO = POKER_CORNER_RADIUS_MM / POKER_WIDTH_MM;

/** Circular die-cut: 5% of the short side (3.175 / 63.5). Matches CSS 5% / 3.571%. */
const DEFAULT_CORNER_RADIUS_RATIO = OFFICIAL_CORNER_RADIUS_RATIO;
const CSS_CORNER_RADIUS_Y = POKER_CORNER_RADIUS_MM / POKER_HEIGHT_MM;
/** Catalog is JPEG (D00000E). PNG is opt-in when you need transparent corners. */
const DEFAULT_OUTPUT_FORMAT = 'jpg';
const DEFAULT_MATTE = { r: 11, g: 11, b: 15 };
const DEFAULT_JPEG_QUALITY = 100;
const BLACK_MAX = 28;
const WHITE_MIN = 242;
const BAND_COVERAGE = 0.98;
const MAX_BAND_FRACTION = 0.25;

function parseMatte(value) {
  const raw = String(value || '#0b0b0f').trim();
  const hex = (raw.startsWith('#') ? raw.slice(1) : raw).toLowerCase();
  if (!/^[0-9a-f]{6}$/.test(hex)) {
    return { ...DEFAULT_MATTE };
  }
  return {
    r: parseInt(hex.slice(0, 2), 16),
    g: parseInt(hex.slice(2, 4), 16),
    b: parseInt(hex.slice(4, 6), 16),
  };
}

function catalogFormat(format) {
  const normalized = String(format || '').toLowerCase();
  if (normalized === 'jpeg' || normalized === 'jpg') {
    return 'jpg';
  }
  if (normalized === 'png' || normalized === 'webp' || normalized === 'gif') {
    return normalized;
  }
  return DEFAULT_OUTPUT_FORMAT;
}

function outputFormatFrom(value) {
  const format = catalogFormat(value || DEFAULT_OUTPUT_FORMAT);
  return format === 'gif' ? DEFAULT_OUTPUT_FORMAT : format;
}

function sanitizeOptionsFromEnv(env = process.env) {
  if (String(env.ORACLE_IMAGE_SANITIZE || '1') === '0') {
    return { enabled: false };
  }
  const radiusRatio = Number(env.ORACLE_IMAGE_CORNER_RADIUS_RATIO || DEFAULT_CORNER_RADIUS_RATIO);
  const jpegQuality = Number(env.ORACLE_IMAGE_SANITIZE_JPEG_QUALITY || DEFAULT_JPEG_QUALITY);
  return {
    enabled: true,
    radiusRatio:
      Number.isFinite(radiusRatio) && radiusRatio > 0 && radiusRatio < 0.25
        ? radiusRatio
        : DEFAULT_CORNER_RADIUS_RATIO,
    matte: parseMatte(env.ORACLE_IMAGE_SANITIZE_MATTE),
    jpegQuality:
      Number.isFinite(jpegQuality) && jpegQuality >= 40 && jpegQuality <= 100
        ? jpegQuality
        : DEFAULT_JPEG_QUALITY,
    outputFormat: outputFormatFrom(env.ORACLE_IMAGE_SANITIZE_FORMAT),
  };
}

function loadSharp(provided) {
  if (provided) {
    return provided;
  }
  try {
    return require('sharp');
  } catch {
    return null;
  }
}

function samplePixel(data, width, channels, x, y) {
  const index = (y * width + x) * channels;
  return [data[index], data[index + 1], data[index + 2]];
}

function isBlack(r, g, b, blackMax = BLACK_MAX) {
  return r <= blackMax && g <= blackMax && b <= blackMax;
}

function isWhite(r, g, b, whiteMin = WHITE_MIN) {
  return r >= whiteMin && g >= whiteMin && b >= whiteMin;
}

function lineKind(data, width, height, channels, { axis, offset }) {
  const length = axis === 'row' ? width : height;
  let black = 0;
  let white = 0;
  for (let i = 0; i < length; i += 1) {
    const x = axis === 'row' ? i : offset;
    const y = axis === 'row' ? offset : i;
    const [r, g, b] = samplePixel(data, width, channels, x, y);
    if (isBlack(r, g, b)) {
      black += 1;
    } else if (isWhite(r, g, b)) {
      white += 1;
    }
  }
  if (black / length >= BAND_COVERAGE) {
    return 'black';
  }
  if (white / length >= BAND_COVERAGE) {
    return 'white';
  }
  return null;
}

function countBand(data, width, height, channels, { axis, fromStart }) {
  const limit = axis === 'row' ? height : width;
  const max = Math.floor(limit * MAX_BAND_FRACTION);
  let count = 0;
  let kind = null;
  while (count < max) {
    const offset = fromStart ? count : limit - 1 - count;
    const found = lineKind(data, width, height, channels, { axis, offset });
    if (!found) {
      break;
    }
    if (!kind) {
      kind = found;
    } else if (found !== kind) {
      break;
    }
    count += 1;
  }
  return { count, kind };
}

function detectLetterbox(data, width, height, channels) {
  const top = countBand(data, width, height, channels, { axis: 'row', fromStart: true });
  const bottom = countBand(data, width, height, channels, { axis: 'row', fromStart: false });
  const left = countBand(data, width, height, channels, { axis: 'col', fromStart: true });
  const right = countBand(data, width, height, channels, { axis: 'col', fromStart: false });

  const cropY = top.count > 0 && bottom.count > 0 && top.kind === bottom.kind;
  const cropX = left.count > 0 && right.count > 0 && left.kind === right.kind;
  if (!cropY && !cropX) {
    return null;
  }
  // White on only one axis is a card in a square studio photo, often tilted.
  // Pillarboxing it clips the silhouette and the inner-rectangle deskew
  // then chases the art. Black cinematic bars may still be one axis.
  if ((cropX && !cropY && left.kind === 'white') || (cropY && !cropX && top.kind === 'white')) {
    return null;
  }

  const extract = {
    left: cropX ? left.count : 0,
    top: cropY ? top.count : 0,
    width: width - (cropX ? left.count + right.count : 0),
    height: height - (cropY ? top.count + bottom.count : 0),
  };
  if (extract.width < 32 || extract.height < 32) {
    return null;
  }
  if (extract.width === width && extract.height === height) {
    return null;
  }
  return extract;
}

function luminance(r, g, b) {
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function chroma(r, g, b) {
  return Math.max(r, g, b) - Math.min(r, g, b);
}

function isEarWhite(r, g, b) {
  return luminance(r, g, b) >= 210 && chroma(r, g, b) <= 40;
}

/** Cream JPEG fringe on the outer millimetre (Charizard 713832 top edge). */
function isLightMatteFringe(r, g, b) {
  return luminance(r, g, b) >= 168 && chroma(r, g, b) <= 48 && !isYellowHue(r, g, b);
}

/** Leftover JPEG ears after the 5% die-cut. Stop before the silver outline. */
function isPunchableEar(r, g, b, outline) {
  if (outline && Math.abs(r - outline.r) + Math.abs(g - outline.g) + Math.abs(b - outline.b) < 36) {
    return false;
  }
  return luminance(r, g, b) >= 180 && chroma(r, g, b) <= 55;
}

function isYellowHue(r, g, b) {
  return r > b + 20 && g > b + 8 && g >= r * 0.72 && chroma(r, g, b) >= 35;
}

/** Washed JPEG yellow that is already the printed rim (Milotic x=10 C50). */
function isWarmWashedYellow(r, g, b) {
  return isYellowHue(r, g, b);
}

/**
 * Studio backdrop paper (Qwen: high luma, chroma ≤16). Cream AA (C20) and
 * printed yellow are not paper. Holofoil sparkle is not paper, so a
 * border-connected flood cannot leak into SP art.
 */
function isStudioPaper(r, g, b) {
  return luminance(r, g, b) >= 230 && chroma(r, g, b) <= 16 && !isYellowHue(r, g, b);
}

/** Obvious studio paper. Not the cream fringe that already belongs to the rim. */
function isPunchableStudioSurround(r, g, b) {
  return isStudioPaper(r, g, b) || (luminance(r, g, b) >= 220 && chroma(r, g, b) <= 22 && !isWarmWashedYellow(r, g, b));
}

/**
 * Card scanners (OpenCV contour / CamScanner quad / product knockout) do not
 * key "near-white" globally. Studio paper is whatever actually sits on the
 * image border; the card is the first colour step inward. Totodile MEP silver
 * is luma ~221 — the old luma≥220 rule treated that rim as paper and punched
 * it. Euclidean RGB from the border median: paper d≤4, corner AA ~33, silver
 * ≥47. Tolerance 40 keeps the rim. See punchConnectedStudioWhite.
 */
const BORDER_BG_RGB_TOL = 40;

function rgbDist2(r, g, b, seed) {
  const dr = r - seed.r;
  const dg = g - seed.g;
  const db = b - seed.b;
  return dr * dr + dg * dg + db * db;
}

function sampleBorderBackground(rgba, width, height) {
  const rs = [];
  const gs = [];
  const bs = [];
  const take = (x, y) => {
    if (x < 0 || y < 0 || x >= width || y >= height) {
      return;
    }
    const i = (y * width + x) * 4;
    if (rgba[i + 3] < 40) {
      return;
    }
    rs.push(rgba[i]);
    gs.push(rgba[i + 1]);
    bs.push(rgba[i + 2]);
  };
  // Corners only. Mid-edge of a tight catalog JPEG is already the printed
  // rim (yellow/silver); including it contaminates the paper seed.
  const patch = Math.min(6, Math.max(2, Math.round(Math.min(width, height) * 0.02)));
  const corners = [
    [0, 0, 1, 1],
    [width - 1, 0, -1, 1],
    [0, height - 1, 1, -1],
    [width - 1, height - 1, -1, -1],
  ];
  for (const [sx, sy, dx, dy] of corners) {
    for (let j = 0; j < patch; j += 1) {
      for (let i = 0; i < patch; i += 1) {
        take(sx + i * dx, sy + j * dy);
      }
    }
  }
  if (!rs.length) {
    return null;
  }
  const med = (values) => {
    const sorted = [...values].sort((a, b) => a - b);
    return sorted[sorted.length >> 1];
  };
  return { r: med(rs), g: med(gs), b: med(bs) };
}

function isStudioBackdropSample(seed) {
  if (!seed) {
    return false;
  }
  const l = luminance(seed.r, seed.g, seed.b);
  const c = chroma(seed.r, seed.g, seed.b);
  if (isYellowHue(seed.r, seed.g, seed.b)) {
    return false;
  }
  if (l >= 220 && c <= 40) {
    return true;
  }
  if (l <= 28 && c <= 22) {
    return true;
  }
  return false;
}

function matchesBorderBackground(r, g, b, seed, tol = BORDER_BG_RGB_TOL) {
  if (!seed) {
    return false;
  }
  return rgbDist2(r, g, b, seed) <= tol * tol;
}

/** DP name/HP bar: light silver, not a yellow JPEG halo. */
function isLightInteriorNotYellow(r, g, b, outline) {
  return (
    (isEarWhite(r, g, b) || isPunchableEar(r, g, b, outline)) &&
    !isYellowHue(r, g, b)
  );
}

/**
 * JPEG halo / scanner highlight on the outer millimetre of yellow.
 * Gyarados: (225,233,220) then washed gold before real (239,205,20).
 * EX Charizard: (252,241,99) bright ring on top of (238,213,93).
 */
function isWashedOrHighlightFringe(r, g, b, outline) {
  if (isEarWhite(r, g, b) || isPunchableEar(r, g, b, outline)) {
    return true;
  }
  if (!outline) {
    return false;
  }
  if (similarToOutline(r, g, b, outline, 28)) {
    return false;
  }
  const oc = chroma(outline.r, outline.g, outline.b);
  const ol = luminance(outline.r, outline.g, outline.b);
  const c = chroma(r, g, b);
  const l = luminance(r, g, b);
  if (oc >= 80 && c < oc * 0.55 && l >= ol - 12) {
    return true;
  }
  if (l > ol + 16 && colorDistance(r, g, b, outline) < 90) {
    return true;
  }
  return false;
}

function belongsToFrame(r, g, b, outline) {
  if (!outline || isEarWhite(r, g, b) || isBlack(r, g, b)) {
    return false;
  }
  if (similarToOutline(r, g, b, outline, 80)) {
    return true;
  }
  const family = outlineFamily(outline);
  if (family === 'yellow') {
    return isYellowHue(r, g, b);
  }
  if (family === 'gold-pale') {
    return luminance(r, g, b) >= 140 && chroma(r, g, b) <= 55 && r > b;
  }
  if (family === 'silver') {
    return chroma(r, g, b) <= 40 && luminance(r, g, b) >= 80 && luminance(r, g, b) <= 210;
  }
  return false;
}

/**
 * Mid-side thickness: the printed rim only. `belongsToFrame` for yellow is
 * any `isYellowHue`, which continues through olive Grass art (Turtwig
 * pop6/17: true yellow d≈20 for 14 px, then d>100 still yh=true to 31 px).
 */
function belongsToPrintedRim(r, g, b, outline) {
  if (!outline || isEarWhite(r, g, b) || isBlack(r, g, b)) {
    return false;
  }
  if (isLightInteriorNotYellow(r, g, b, outline)) {
    return false;
  }
  return similarToOutline(r, g, b, outline, 80);
}

function toRgba(data, width, height, channels) {
  if (channels === 4) {
    return Buffer.from(data);
  }
  const rgba = Buffer.alloc(width * height * 4);
  for (let i = 0, p = 0; i < data.length; i += channels, p += 4) {
    rgba[p] = data[i];
    rgba[p + 1] = data[i + 1];
    rgba[p + 2] = data[i + 2];
    rgba[p + 3] = 255;
  }
  return rgba;
}

function punchCornerEars(rgba, width, height, outline) {
  const reach = Math.max(12, Math.round(Math.min(width, height) * 0.2));
  const marked = new Uint8Array(width * height);
  const stack = [];
  const starts = [
    [0, 0],
    [width - 1, 0],
    [0, height - 1],
    [width - 1, height - 1],
  ];
  for (const [sx, sy] of starts) {
    const i = (sy * width + sx) * 4;
    if (isPunchableEar(rgba[i], rgba[i + 1], rgba[i + 2], outline)) {
      stack.push([sx, sy, sx, sy]);
    }
  }
  let punched = 0;
  while (stack.length) {
    const [x, y, ox, oy] = stack.pop();
    if (x < 0 || y < 0 || x >= width || y >= height) {
      continue;
    }
    if (Math.abs(x - ox) > reach || Math.abs(y - oy) > reach) {
      continue;
    }
    const cell = y * width + x;
    if (marked[cell]) {
      continue;
    }
    const i = cell * 4;
    if (rgba[i + 3] < 40 || !isPunchableEar(rgba[i], rgba[i + 1], rgba[i + 2], outline)) {
      continue;
    }
    marked[cell] = 1;
    punched += 1;
    stack.push([x + 1, y, ox, oy], [x - 1, y, ox, oy], [x, y + 1, ox, oy], [x, y - 1, ox, oy]);
  }
  for (let pass = 0; pass < 2; pass += 1) {
    const extra = [];
    for (let y = 0; y < height; y += 1) {
      for (let x = 0; x < width; x += 1) {
        const cell = y * width + x;
        if (marked[cell]) {
          continue;
        }
        const i = cell * 4;
        if (rgba[i + 3] < 40 || !isPunchableEar(rgba[i], rgba[i + 1], rgba[i + 2], outline)) {
          continue;
        }
        let neighbor = false;
        for (let dy = -1; dy <= 1 && !neighbor; dy += 1) {
          for (let dx = -1; dx <= 1; dx += 1) {
            const nx = x + dx;
            const ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= width || ny >= height) {
              continue;
            }
            if (marked[ny * width + nx]) {
              neighbor = true;
            }
          }
        }
        if (neighbor) {
          extra.push(cell);
        }
      }
    }
    for (const cell of extra) {
      if (!marked[cell]) {
        marked[cell] = 1;
        punched += 1;
      }
    }
  }
  for (let cell = 0; cell < marked.length; cell += 1) {
    if (!marked[cell]) {
      continue;
    }
    const i = cell * 4;
    rgba[i] = 0;
    rgba[i + 1] = 0;
    rgba[i + 2] = 0;
    rgba[i + 3] = 0;
  }
  return punched;
}

/**
 * Studio JPEG of a complete printed card: white on the straight sides as
 * well as the four AABB crescents (Milotic League 257448, ~8–10 px ring).
 *
 * Magic-wand from the frame — same idea as product knockouts and cardscan
 * outer-contour crop, not a global "luma ≥ 220" key. Sample the border,
 * flood 4-connected pixels within RGB d≤40 of that seed. Light silver
 * frames (Totodile MEP, d≈47) are the card; they are not paper. Do not
 * flood yellow (JPEG holes in a washed rim leak into SP holofoil). Stop at
 * chroma-50 yellow (Milotic x=10). Tight crops whose corners are already
 * the printed rim are left alone. Borderless / FA must not call this:
 * white sky can connect to the edge.
 */
function punchConnectedStudioWhite(rgba, width, height, outline) {
  const seed = sampleBorderBackground(rgba, width, height);
  if (!isStudioBackdropSample(seed)) {
    return 0;
  }
  const marked = new Uint8Array(width * height);
  const stack = [];
  const consider = (x, y) => {
    if (x < 0 || y < 0 || x >= width || y >= height) {
      return;
    }
    const cell = y * width + x;
    if (marked[cell]) {
      return;
    }
    const i = cell * 4;
    if (rgba[i + 3] < 40) {
      return;
    }
    const r = rgba[i];
    const g = rgba[i + 1];
    const b = rgba[i + 2];
    if (belongsToPrintedRim(r, g, b, outline) || isYellowHue(r, g, b)) {
      return;
    }
    if (!matchesBorderBackground(r, g, b, seed)) {
      return;
    }
    marked[cell] = 1;
    stack.push(cell);
  };
  for (let x = 0; x < width; x += 1) {
    consider(x, 0);
    consider(x, height - 1);
  }
  for (let y = 0; y < height; y += 1) {
    consider(0, y);
    consider(width - 1, y);
  }
  while (stack.length) {
    const cell = stack.pop();
    const x = cell % width;
    const y = (cell / width) | 0;
    consider(x + 1, y);
    consider(x - 1, y);
    consider(x, y + 1);
    consider(x, y - 1);
  }
  let punched = 0;
  for (let cell = 0; cell < marked.length; cell += 1) {
    if (!marked[cell]) {
      continue;
    }
    const i = cell * 4;
    rgba[i] = 0;
    rgba[i + 1] = 0;
    rgba[i + 2] = 0;
    rgba[i + 3] = 0;
    punched += 1;
  }
  return punched;
}

function rimLooksClipped(thickness, short, outline, options = {}) {
  if (!thickness || !short) {
    return false;
  }
  const missing = [thickness.left, thickness.right, thickness.top].filter((t) => (t || 0) <= 2).length;
  const tMed = measuredFramePx(thickness);
  // Unpunched white surround makes every walk return 0. That is paper, not a
  // cropped rim. After punch, the same zeros mean the yellow was rotated or
  // cropped off — rebuild it (Swampert theme-deck left edge).
  if (!options.afterPunch && tMed <= 2 && missing === 3) {
    return false;
  }
  const target = targetFramePx(short, outline, tMed);
  return missing >= 1 || (tMed > 0 && target > 0 && tMed < Math.round(target * 0.85));
}

function isCardRaster(options = {}, width, height) {
  const kind = String(options.productType || options.itemKind || '').toLowerCase();
  if (kind === 'product' || kind === 'sealed' || kind === 'box' || kind === 'bundle' || kind === 'etb') {
    return false;
  }
  if (kind === 'card' || kind === 'single') {
    return true;
  }
  if (!width || !height) {
    return true;
  }
  const aspect = width / height;
  return aspect >= 0.62 && aspect <= 0.82;
}

function cornerRadiusPx(width, height, ratio = DEFAULT_CORNER_RADIUS_RATIO) {
  const short = Math.min(width, height);
  return Math.max(1, Math.round(short * ratio));
}

/**
 * Quarter-circle die-cut in pixel space. Center of the top-left arc is (R, R)
 * so a poker-aspect raster has a circular 3.175 mm fillet (not an ellipse
 * with ry = 5% of height).
 */
function dieCutCornerCenter(x, y, width, height, radius) {
  const r = Math.max(1, radius);
  if (x < r && y < r) {
    return { cx: r, cy: r, r };
  }
  if (x >= width - r && y < r) {
    return { cx: width - 1 - r, cy: r, r };
  }
  if (x < r && y >= height - r) {
    return { cx: r, cy: height - 1 - r, r };
  }
  if (x >= width - r && y >= height - r) {
    return { cx: width - 1 - r, cy: height - 1 - r, r };
  }
  return null;
}

/** Cardboard triangle outside the 3.175 mm arc (the only pixels the round may punch). */
function inDieCutCrescent(x, y, width, height, radius) {
  const corner = dieCutCornerCenter(x, y, width, height, radius);
  if (!corner) {
    return false;
  }
  return Math.hypot(x - corner.cx, y - corner.cy) > corner.r;
}

/** Printed face of a corner square (inside or on the arc). */
function inDieCutCap(x, y, width, height, radius) {
  const corner = dieCutCornerCenter(x, y, width, height, radius);
  if (!corner) {
    return false;
  }
  return Math.hypot(x - corner.cx, y - corner.cy) <= corner.r;
}

function medianChannel(values) {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.floor(sorted.length / 2)];
}

function colorDistance(r, g, b, outline) {
  if (!outline) {
    return 999;
  }
  return Math.abs(r - outline.r) + Math.abs(g - outline.g) + Math.abs(b - outline.b);
}

function similarToOutline(r, g, b, outline, max = 48) {
  return Boolean(outline) && colorDistance(r, g, b, outline) < max;
}

function isMatteCorner(r, g, b, a = 255) {
  if (a < 40) {
    return true;
  }
  return isBlack(r, g, b, 40) && chroma(r, g, b) <= 30;
}

function sampleCornerRgb(rgba, width, height, x, y, size = 3) {
  const rs = [];
  const gs = [];
  const bs = [];
  for (let dy = 0; dy < size; dy += 1) {
    for (let dx = 0; dx < size; dx += 1) {
      const px = Math.min(width - 1, Math.max(0, x + dx));
      const py = Math.min(height - 1, Math.max(0, y + dy));
      const i = (py * width + px) * 4;
      if (rgba[i + 3] < 40) {
        continue;
      }
      rs.push(rgba[i]);
      gs.push(rgba[i + 1]);
      bs.push(rgba[i + 2]);
    }
  }
  if (!rs.length) {
    return null;
  }
  return {
    r: medianChannel(rs),
    g: medianChannel(gs),
    b: medianChannel(bs),
  };
}

/**
 * square-cut: AABB corners match the printed outline (yellow/gold/silver).
 * white-ears: AABB corners are near-white crescents (studio JPEG of a die-cut).
 * already-rounded: corners are already dark-matte or transparent.
 */
function detectCornerKind(rgba, width, height, outline) {
  const samples = [
    sampleCornerRgb(rgba, width, height, 0, 0),
    sampleCornerRgb(rgba, width, height, width - 3, 0),
    sampleCornerRgb(rgba, width, height, 0, height - 3),
    sampleCornerRgb(rgba, width, height, width - 3, height - 3),
  ];
  let white = 0;
  let border = 0;
  let matte = 0;
  for (const sample of samples) {
    if (!sample) {
      matte += 1;
      continue;
    }
    if (isMatteCorner(sample.r, sample.g, sample.b)) {
      matte += 1;
      continue;
    }
    if (similarToOutline(sample.r, sample.g, sample.b, outline, 56)) {
      border += 1;
      continue;
    }
    if (isPunchableEar(sample.r, sample.g, sample.b, outline) || isEarWhite(sample.r, sample.g, sample.b)) {
      white += 1;
    }
  }
  if (matte >= 3) {
    return 'already-rounded';
  }
  if (border >= 3) {
    return 'square-cut';
  }
  if (white >= 3) {
    return 'white-ears';
  }
  if (border >= 2 && white >= 1) {
    return 'square-cut';
  }
  if (white >= 2) {
    return 'white-ears';
  }
  return 'mixed';
}

function measureSideThickness(rgba, width, height, outline) {
  const short = Math.min(width, height);
  const max = Math.max(8, Math.round(short * 0.07));
  const maxSkip = Math.max(4, Math.round(short * 0.02));
  const maxWhiteSkip = Math.max(8, Math.round(short * 0.05));
  const walk = (x0, y0, dx, dy) => {
    let n = 0;
    let skipped = 0;
    let x = x0;
    let y = y0;
    while (n < max && x >= 0 && y >= 0 && x < width && y < height) {
      const i = (y * width + x) * 4;
      if (rgba[i + 3] < 40) {
        if (n === 0 && skipped < maxWhiteSkip) {
          skipped += 1;
          x += dx;
          y += dy;
          continue;
        }
        break;
      }
      const r = rgba[i];
      const g = rgba[i + 1];
      const b = rgba[i + 2];
      const whitePad = isEarWhite(r, g, b) || isPunchableEar(r, g, b, outline);
      const skipCap = whitePad ? maxWhiteSkip : maxSkip;
      if (n === 0 && skipped < skipCap && (whitePad || isWashedOrHighlightFringe(r, g, b, outline))) {
        skipped += 1;
        x += dx;
        y += dy;
        continue;
      }
      if (!belongsToPrintedRim(r, g, b, outline)) {
        break;
      }
      n += 1;
      x += dx;
      y += dy;
    }
    return n;
  };
  const mx = Math.floor(width / 2);
  const my = Math.floor(height / 2);
  return {
    top: walk(mx, 0, 0, 1),
    bottom: walk(mx, height - 1, 0, -1),
    left: walk(0, my, 1, 0),
    right: walk(width - 1, my, -1, 0),
  };
}

function paintOutline(rgba, i, outline) {
  rgba[i] = outline.r;
  rgba[i + 1] = outline.g;
  rgba[i + 2] = outline.b;
  rgba[i + 3] = 255;
}

function fillCornerEarsWithOutline(rgba, width, height, outline, radius = 0) {
  if (!outline) {
    return 0;
  }
  const reach = Math.max(
    (radius || 0) + 6,
    Math.round(Math.min(width, height) * 0.08),
  );
  const marked = new Uint8Array(width * height);
  const stack = [];
  const starts = [
    [0, 0],
    [width - 1, 0],
    [0, height - 1],
    [width - 1, height - 1],
  ];
  for (const [sx, sy] of starts) {
    const i = (sy * width + sx) * 4;
    if (isPunchableEar(rgba[i], rgba[i + 1], rgba[i + 2], outline) || isEarWhite(rgba[i], rgba[i + 1], rgba[i + 2])) {
      stack.push([sx, sy, sx, sy]);
    }
  }
  let filled = 0;
  while (stack.length) {
    const [x, y, ox, oy] = stack.pop();
    if (x < 0 || y < 0 || x >= width || y >= height) {
      continue;
    }
    if (Math.abs(x - ox) > reach || Math.abs(y - oy) > reach) {
      continue;
    }
    const cell = y * width + x;
    if (marked[cell]) {
      continue;
    }
    const i = cell * 4;
    if (rgba[i + 3] < 40) {
      continue;
    }
    if (
      !isPunchableEar(rgba[i], rgba[i + 1], rgba[i + 2], outline) &&
      !isEarWhite(rgba[i], rgba[i + 1], rgba[i + 2])
    ) {
      continue;
    }
    marked[cell] = 1;
    paintOutline(rgba, i, outline);
    filled += 1;
    stack.push([x + 1, y, ox, oy], [x - 1, y, ox, oy], [x, y + 1, ox, oy], [x, y - 1, ox, oy]);
  }
  return filled;
}

function fillPerimeterFringeWithOutline(rgba, width, height, outline, depth = 2) {
  if (!outline) {
    return 0;
  }
  const d = Math.max(1, Math.min(6, depth));
  let filled = 0;
  const fill = (x, y) => {
    const i = (y * width + x) * 4;
    if (rgba[i + 3] < 40) {
      return;
    }
    if (similarToOutline(rgba[i], rgba[i + 1], rgba[i + 2], outline, 36)) {
      return;
    }
    if (!isWashedOrHighlightFringe(rgba[i], rgba[i + 1], rgba[i + 2], outline)) {
      return;
    }
    paintOutline(rgba, i, outline);
    filled += 1;
  };
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < d && x < width; x += 1) {
      fill(x, y);
    }
    for (let x = Math.max(0, width - d); x < width; x += 1) {
      fill(x, y);
    }
  }
  for (let x = 0; x < width; x += 1) {
    for (let y = 0; y < d && y < height; y += 1) {
      fill(x, y);
    }
    for (let y = Math.max(0, height - d); y < height; y += 1) {
      fill(x, y);
    }
  }
  return filled;
}

/**
 * Paint white crescents that sit inside the die-cut (the gap CSS 5% would
 * otherwise pinch) with the outline colour. Leaves artwork and the existing
 * yellow band on the straight edges alone. Never paint the silver DP name
 * bar: that sits inside the quarter-circle (`x > T && y > T`) and matches
 * `isPunchableEar` — Gible/Bidoof yellow nicks.
 */
function fillInsideDieCutEars(rgba, width, height, radius, outline, thickness) {
  if (!outline) {
    return 0;
  }
  const r = Math.max(1, radius);
  const r2 = r * r;
  const fallback = Math.max(8, Math.round(Math.min(width, height) * 0.04));
  const side = (value) => (value > 2 ? value : fallback);
  const tL = side(thickness && thickness.left);
  const tR = side(thickness && thickness.right);
  const tT = side(thickness && thickness.top);
  const tB = side(thickness && thickness.bottom);
  let filled = 0;
  const paintFan = (x0, x1, y0, y1, cx, cy, pastInner) => {
    for (let y = y0; y < y1; y += 1) {
      for (let x = x0; x < x1; x += 1) {
        const dx = x - cx;
        const dy = y - cy;
        if (dx * dx + dy * dy > r2) {
          continue;
        }
        if (pastInner(x, y)) {
          continue;
        }
        const i = (y * width + x) * 4;
        if (rgba[i + 3] < 40) {
          paintOutline(rgba, i, outline);
          filled += 1;
          continue;
        }
        if (similarToOutline(rgba[i], rgba[i + 1], rgba[i + 2], outline, 48)) {
          continue;
        }
        if (
          !isPunchableEar(rgba[i], rgba[i + 1], rgba[i + 2], outline) &&
          !isEarWhite(rgba[i], rgba[i + 1], rgba[i + 2])
        ) {
          continue;
        }
        paintOutline(rgba, i, outline);
        filled += 1;
      }
    }
  };
  paintFan(0, r, 0, r, r, r, (x, y) => x >= tL && y >= tT);
  paintFan(Math.max(0, width - r), width, 0, r, width - 1 - r, r, (x, y) => x < width - tR && y >= tT);
  paintFan(0, r, Math.max(0, height - r), height, r, height - 1 - r, (x, y) => x >= tL && y < height - tB);
  paintFan(
    Math.max(0, width - r),
    width,
    Math.max(0, height - r),
    height,
    width - 1 - r,
    height - 1 - r,
    (x, y) => x < width - tR && y < height - tB,
  );
  return filled;
}

function rebuildOuterBorder(rgba, width, height, radius, outline, options = {}) {
  const filled =
    fillCornerEarsWithOutline(rgba, width, height, outline, radius) +
    fillInsideDieCutEars(rgba, width, height, radius, outline, options.thickness);
  if (options.paintPerimeter === false) {
    return filled;
  }
  return filled + fillPerimeterFringeWithOutline(rgba, width, height, outline, 4);
}

/**
 * Wizards/Neo printed yellow, from pokemontcg.io neo3/65 (600×825 square-cut):
 * sides 21–22 px → 2.22–2.33 mm on 63.5 mm. Inner join is an AABB.
 * (The old ~3.2 mm figure was leftover yellow on a 322 px Base Set studio crop.)
 */
const WIZARDS_YELLOW_RATIO = 22 / 600;
const WIZARDS_YELLOW_SIDE_MM = WIZARDS_YELLOW_RATIO * POKER_WIDTH_MM;

/**
 * Printed outer-frame width as a fraction of the short side (63.5 mm trim).
 * English kept a thick yellow frame until SV; Japan went silver/thinner in BW.
 * `yellow` matches Wizards/Neo (neo3/65). Cropped EX leftovers still pad via
 * `padToUnpinch` (0.78 R), not by inflating this ratio.
 */
const FRAME_RATIO = {
  yellow: WIZARDS_YELLOW_RATIO,
  'gold-pale': 0.028,
  silver: 0.024,
  other: 0.036,
};

/**
 * Coverage samples per output pixel along the four die-cut corners.
 * 1× binary clip is ~16 px stairs on a 5% radius. 8× is a 0.125 px
 * coverage grid (64 taps / pixel) without allocating an 8× full raster.
 */
const ROUND_SUPER_SAMPLE = 8;

function outlineFamily(outline) {
  if (!outline) {
    return 'other';
  }
  const c = chroma(outline.r, outline.g, outline.b);
  if (outline.r > outline.b + 40 && outline.g > outline.b + 20 && c >= 50) {
    return 'yellow';
  }
  if (c <= 28 && luminance(outline.r, outline.g, outline.b) >= 90) {
    return 'silver';
  }
  if (c <= 40 && outline.r > 170 && outline.g > 150) {
    return 'gold-pale';
  }
  return 'other';
}

function medianPositive(values) {
  const xs = values.filter((value) => value > 2).sort((a, b) => a - b);
  if (!xs.length) {
    return 0;
  }
  return xs[Math.floor(xs.length / 2)];
}

function measuredFramePx(thickness) {
  if (!thickness) {
    return 0;
  }
  return medianPositive([thickness.left, thickness.right, thickness.top]);
}

function targetFramePx(short, outline, measured) {
  const ratio = FRAME_RATIO[outlineFamily(outline)] || FRAME_RATIO.other;
  return Math.max(measured, Math.round(short * ratio));
}

/** CardTrader `full-v4` is resolution, not Full Art treatment. */
function isCardTraderFullFile(filename) {
  return /full-v4/i.test(String(filename || ''));
}

function parseCollectorOverNumber(filename) {
  const matches = String(filename || '').matchAll(/(?:^|[_-])(\d{1,3})-(\d{2,3})(?=[_.-]|$)/g);
  for (const match of matches) {
    const n = Number(match[1]);
    const set = Number(match[2]);
    if (set >= 10 && n > set) {
      return { n, set, extra: n - set };
    }
  }
  return null;
}

/**
 * Treatments whose "frame" is foil/art to the rim. Never invent yellow/silver pad.
 * Over-number alone is not enough: EX 100/97 secrets still have a yellow frame.
 * Leftover catalog keys are often short (`351691_mega-lucario-ex.jpg`) and omit
 * these slugs — gold foil also uses `isGoldFoilRaster`.
 */
function isBorderlessTreatment(filename) {
  const s = String(filename || '').toLowerCase();
  if (!s || isCardTraderFullFile(s)) {
    return false;
  }
  return (
    /full-art/.test(s) ||
    /special-illustration-rare/.test(s) ||
    /illustration-rare/.test(s) ||
    /hyper-rare/.test(s) ||
    /rainbow-rare/.test(s) ||
    /shiny-rare/.test(s) ||
    /gold-hyper/.test(s) ||
    /gold-secret/.test(s) ||
    /ultra-rare/.test(s)
  );
}

/**
 * Gold HR / UR foil: yellow is the whole face, not a printed rim.
 * Wizards yellow-frame rasters are ~15–20% yellow pixels; Mega Lucario ex
 * 188 and Mega Gardevoir ex 187 are ~88%. Threshold 0.4 leaves Gyarados
 * weld intact.
 */
const GOLD_FOIL_YELLOW_FRACTION = 0.4;

function isGoldFoilRaster(rgba, width, height, channels = 4, thickness = null) {
  if (!rgba || !width || !height) {
    return false;
  }
  const short = Math.min(width, height);
  const tMed = measuredFramePx(thickness);
  let yellow = 0;
  let n = 0;
  const step = Math.max(2, Math.floor(short / 80));
  for (let y = 0; y < height; y += step) {
    for (let x = 0; x < width; x += step) {
      const i = (y * width + x) * channels;
      if (channels === 4 && rgba[i + 3] < 40) {
        continue;
      }
      const r = rgba[i];
      const g = rgba[i + 1];
      const b = rgba[i + 2];
      if (isPunchableStudioSurround(r, g, b) || isBlack(r, g, b)) {
        continue;
      }
      n += 1;
      if (isYellowHue(r, g, b)) {
        yellow += 1;
      }
    }
  }
  const fraction = n > 0 ? yellow / n : 0;
  // Printed Wizards/DP yellow is 10–22 px. Gold HR walks to the 7% cap
  // because the face is the “rim”. Warm DP stock is ~50% isYellowHue
  // (Lucario pop6/2) with tMed 13 — that is not Mega Lucario ex 188.
  // After a tight gold crop, JPEG AA on the foil edge is tMed ~3 — that
  // is not a printed rim; do not veto foil-to-edge.
  if (tMed >= 8 && tMed < Math.round(short * 0.06)) {
    return false;
  }
  return fraction >= GOLD_FOIL_YELLOW_FRACTION;
}

function classifyRebuildJob({ filename, width, height, cornerKind, outline, thickness, goldFoil } = {}) {
  if (width && height && !isCardRaster({}, width, height)) {
    return { action: 'skip', reason: 'not-a-card' };
  }
  const short = Math.min(width || 0, height || 0);
  const tMed = measuredFramePx(thickness);
  const family = outlineFamily(outline);
  const overNumber = parseCollectorOverNumber(filename);
  if (isBorderlessTreatment(filename)) {
    return {
      action: 'diecut-only',
      reason: 'borderless-treatment',
      family,
      tMed,
      overNumber,
    };
  }
  if (goldFoil) {
    return {
      action: 'diecut-only',
      reason: 'gold-foil',
      family,
      tMed,
      overNumber,
    };
  }
  if (short && family !== 'yellow' && family !== 'gold-pale' && tMed > 0 && tMed < short * 0.012) {
    return { action: 'diecut-only', reason: 'thin-non-yellow-rim', family, tMed, overNumber };
  }
  if (cornerKind === 'already-rounded') {
    const target = targetFramePx(short, outline, tMed);
    if (
      (family === 'yellow' || family === 'gold-pale') &&
      tMed > 2 &&
      target > 0 &&
      tMed < Math.round(target * 0.85)
    ) {
      return {
        action: 'rebuild-frame',
        reason: 'cropped-alpha-corners',
        family,
        tMed,
        overNumber,
      };
    }
    return { action: 'diecut-only', reason: 'already-rounded', family, tMed, overNumber };
  }
  if (cornerKind === 'white-ears') {
    return {
      action: 'diecut-only',
      reason: 'studio-diecut',
      family,
      tMed,
      overNumber,
    };
  }
  return {
    action: 'rebuild-frame',
    reason: cornerKind || 'framed',
    family,
    tMed,
    overNumber,
  };
}

function paddedFrameThickness(thickness, pad) {
  const extra = Math.max(0, pad || 0);
  if (!thickness) {
    return { top: extra, bottom: extra, left: extra, right: extra };
  }
  return {
    top: extra + (thickness.top || 0),
    bottom: extra + (thickness.bottom || 0),
    left: extra + (thickness.left || 0),
    right: extra + (thickness.right || 0),
  };
}

/**
 * Extra pixels of outline pad so a 5% die-cut does not pinch the frame.
 * Want remaining frame at the corner ≈ 0.78 of the radius (physical yellow
 * is ~2.5 mm vs 3.175 mm radius).
 */
function padToUnpinch(width, radiusRatio, measured, target) {
  const want = Math.max(target, Math.round(0.78 * width * radiusRatio));
  if (measured >= want) {
    return 0;
  }
  // pokemontcg.io / WGG scans already have a printed frame (~4% of width).
  // Growing 21 px → 24 px on a 600 px Gyarados draws a second rim.
  if (target > 0 && measured >= Math.round(target * 0.85)) {
    return 0;
  }
  const k = 0.78 * radiusRatio;
  const denom = 1 - 2 * k;
  if (denom <= 0.2) {
    return 0;
  }
  const pad = Math.ceil((k * width - measured) / denom);
  return Math.max(0, Math.min(Math.round(width * 0.08), pad));
}

/**
 * Peel leftover printed yellow so a clipped studio crop can get a fresh
 * era-width AABB (Swampert theme-deck left T = 0 after deskew). Sides the
 * walk could not see (T ≤ 2, often bottom) stay; we only add yellow outside.
 */
function stripPrintedRim(rgba, width, height) {
  const cap = Math.max(16, Math.round(Math.min(width, height) * 0.12));
  const walk = (x0, y0, dx, dy) => {
    let n = 0;
    let x = x0;
    let y = y0;
    while (n < cap && x >= 0 && y >= 0 && x < width && y < height) {
      const i = (y * width + x) * 4;
      const r = rgba[i];
      const g = rgba[i + 1];
      const b = rgba[i + 2];
      const a = rgba[i + 3];
      if (a < 40 || isStudioPaper(r, g, b) || isEarWhite(r, g, b) || isYellowHue(r, g, b)) {
        n += 1;
        x += dx;
        y += dy;
        continue;
      }
      break;
    }
    return n;
  };
  const mx = Math.floor(width / 2);
  const my = Math.floor(height / 2);
  const left = walk(0, my, 1, 0);
  const right = walk(width - 1, my, -1, 0);
  const top = walk(mx, 0, 0, 1);
  const bottom = walk(mx, height - 1, 0, -1);
  if (!left && !right && !top && !bottom) {
    return { rgba, width, height };
  }
  const box = {
    left,
    top,
    width: width - left - right,
    height: height - top - bottom,
  };
  if (box.width < 40 || box.height < 40) {
    return { rgba, width, height };
  }
  return {
    rgba: extractRgbaBox(rgba, width, box),
    width: box.width,
    height: box.height,
  };
}

function roundedRectCoverage(px, py, width, height, radius) {
  const r = Math.max(1, radius);
  let cx;
  let cy;
  if (px < r && py < r) {
    cx = r;
    cy = r;
  } else if (px >= width - r && py < r) {
    cx = width - r;
    cy = r;
  } else if (px < r && py >= height - r) {
    cx = r;
    cy = height - r;
  } else if (px >= width - r && py >= height - r) {
    cx = width - r;
    cy = height - r;
  } else {
    return 1;
  }
  const d = Math.hypot(px - cx, py - cy);
  if (d <= r - 0.5) {
    return 1;
  }
  if (d >= r + 0.5) {
    return 0;
  }
  return r + 0.5 - d;
}

/**
 * Paint outline into holes inside the 5% circle (transparent PNG corners,
 * white studio ears, jagged JPEG stairs) so the coverage clip has a solid
 * cap to anti-alias. Do not paint high-chroma art (Mega Lopunny pink leak
 * is a dirty source JPEG — replace from pokemontcg, do not weld magenta).
 */
function fillInsideRoundCaps(rgba, width, height, radius, outline) {
  if (!outline) {
    return 0;
  }
  const r = Math.max(1, radius);
  const r2 = r * r;
  let filled = 0;
  const paint = (x, y, cx, cy) => {
    const dx = x - cx;
    const dy = y - cy;
    if (dx * dx + dy * dy > r2) {
      return;
    }
    const i = (y * width + x) * 4;
    if (
      rgba[i + 3] >= 40 &&
      !isEarWhite(rgba[i], rgba[i + 1], rgba[i + 2]) &&
      !isPunchableEar(rgba[i], rgba[i + 1], rgba[i + 2], outline)
    ) {
      return;
    }
    paintOutline(rgba, i, outline);
    rgba[i + 3] = 255;
    filled += 1;
  };
  for (let y = 0; y < r && y < height; y += 1) {
    for (let x = 0; x < r && x < width; x += 1) {
      paint(x, y, r, r);
    }
    for (let x = Math.max(0, width - r); x < width; x += 1) {
      paint(x, y, width - 1 - r, r);
    }
  }
  for (let y = Math.max(0, height - r); y < height; y += 1) {
    for (let x = 0; x < r && x < width; x += 1) {
      paint(x, y, r, height - 1 - r);
    }
    for (let x = Math.max(0, width - r); x < width; x += 1) {
      paint(x, y, width - 1 - r, height - 1 - r);
    }
  }
  return filled;
}

function isCardboardCrescentPixel(r, g, b, a, outline) {
  if (a < 40 || isMatteCorner(r, g, b, a)) {
    return true;
  }
  if (belongsToPrintedRim(r, g, b, outline) || similarToOutline(r, g, b, outline, 36)) {
    return false;
  }
  if (isYellowHue(r, g, b)) {
    return false;
  }
  return isStudioPaper(r, g, b) || isEarWhite(r, g, b) || isPunchableStudioSurround(r, g, b);
}

/**
 * Clip the four corner squares to a rounded rect using an 8× coverage grid.
 * Partial alpha is flattened onto the catalog matte — that is the AA, not
 * a 1× binary punch (`applyHardRoundedRectAlpha`). Straight edges stay 1×.
 * `lockPrinted` (already-rounded leftovers): only punch cardboard / matte /
 * paper in the crescent. Do not shave the printed silver frame a second time.
 */
function applySupersampledRoundedRectAlpha(rgba, width, height, radius, scale = ROUND_SUPER_SAMPLE, options = {}) {
  if (scale && typeof scale === 'object') {
    options = scale;
    scale = ROUND_SUPER_SAMPLE;
  }
  const r = Math.max(1, radius);
  const s = Math.max(2, scale);
  const taps = s * s;
  const reach = Math.min(width, height, r + 1);
  const lockPrinted = options.lockPrinted === true;
  const outline = options.outline || null;
  const clipCorner = (x0, x1, y0, y1) => {
    const xa = Math.max(0, x0);
    const xb = Math.min(width, x1);
    const ya = Math.max(0, y0);
    const yb = Math.min(height, y1);
    for (let y = ya; y < yb; y += 1) {
      for (let x = xa; x < xb; x += 1) {
        let cover = 0;
        for (let sy = 0; sy < s; sy += 1) {
          for (let sx = 0; sx < s; sx += 1) {
            cover += roundedRectCoverage(
              x + (sx + 0.5) / s,
              y + (sy + 0.5) / s,
              width,
              height,
              r,
            );
          }
        }
        cover /= taps;
        const i = (y * width + x) * 4;
        if (
          lockPrinted &&
          cover < 1 &&
          !isCardboardCrescentPixel(rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3], outline)
        ) {
          continue;
        }
        if (cover <= 0) {
          rgba[i] = 0;
          rgba[i + 1] = 0;
          rgba[i + 2] = 0;
          rgba[i + 3] = 0;
        } else if (cover < 1) {
          rgba[i + 3] = Math.round(rgba[i + 3] * cover);
        }
      }
    }
  };
  clipCorner(0, reach, 0, reach);
  clipCorner(width - reach, width, 0, reach);
  clipCorner(0, reach, height - reach, height);
  clipCorner(width - reach, width, height - reach, height);
}

/**
 * Copy opaque source pixels onto dest. Skip fully transparent PNG corners
 * so they do not punch holes in the yellow pad (those holes sit inside the
 * padded die-cut and flatten to black nicks).
 */
function blitRgba(src, sw, sh, dest, dw, dx, dy) {
  for (let y = 0; y < sh; y += 1) {
    for (let x = 0; x < sw; x += 1) {
      const si = (y * sw + x) * 4;
      if (src[si + 3] < 40) {
        continue;
      }
      const di = ((dy + y) * dw + dx + x) * 4;
      dest[di] = src[si];
      dest[di + 1] = src[si + 1];
      dest[di + 2] = src[si + 2];
      dest[di + 3] = src[si + 3];
    }
  }
}

/**
 * Paint the outer frame as one rectangle per side (straight inner edges).
 * Thickness comes from the mid-side walk, plus outward pad on cropped
 * scans so the rebuilt T is era-width (POP Series 6 Gible is 13–15 px /
 * 1.48 mm on 600; target 22 px / 2.33 mm). Values past ~7% of the short
 * side are the gold art window, not the printed yellow — drop them.
 */
function paintStraightFrame(rgba, width, height, outline, thickness, options = {}) {
  if (!outline) {
    return 0;
  }
  const short = Math.min(width, height);
  const cap = Math.round(short * 0.07);
  const clamp = (t) => {
    const n = Math.max(0, t || 0);
    return n > 2 && n <= cap ? n : 0;
  };
  let tL = clamp(thickness && thickness.left);
  let tR = clamp(thickness && thickness.right);
  let tT = clamp(thickness && thickness.top);
  let tB = clamp(thickness && thickness.bottom);
  const measured = [tL, tR, tT, tB].filter((value) => value > 2);
  if (!measured.length) {
    return 0;
  }
  const fallback = medianPositive(measured);
  if (tL <= 2) {
    tL = fallback;
  }
  if (tR <= 2) {
    tR = fallback;
  }
  if (tT <= 2) {
    tT = fallback;
  }
  if (tB <= 2) {
    tB = fallback;
  }
  const side = medianPositive([tL, tR].filter((value) => value > 2)) || fallback;
  tL = side;
  tR = side;
  let painted = 0;
  const paintIf = (x, y) => {
    const i = (y * width + x) * 4;
    if (rgba[i + 3] < 40) {
      paintOutline(rgba, i, outline);
      painted += 1;
      return;
    }
    const r = rgba[i];
    const g = rgba[i + 1];
    const b = rgba[i + 2];
    if (similarToOutline(r, g, b, outline, 20)) {
      return;
    }
    // DP name/HP bar (Gible/Bidoof): skip light silver in the header/footer
    // AABB corners. On the straight sides, fill silver holes so the inner
    // join is one vertical line (D00000I). Turtwig grass is not light silver.
    const headerY = Math.max(tT + 32, Math.round(height * 0.13));
    const inHeaderOrFooter = y < headerY || y >= height - headerY;
    const inset = Math.min(x, y, width - 1 - x, height - 1 - y);
    if (isLightInteriorNotYellow(r, g, b, outline) && inHeaderOrFooter && inset >= 3) {
      return;
    }
    paintOutline(rgba, i, outline);
    painted += 1;
  };
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < tL && x < width; x += 1) {
      paintIf(x, y);
    }
    for (let x = Math.max(0, width - tR); x < width; x += 1) {
      paintIf(x, y);
    }
  }
  for (let x = 0; x < width; x += 1) {
    for (let y = 0; y < tT && y < height; y += 1) {
      paintIf(x, y);
    }
    for (let y = Math.max(0, height - tB); y < height; y += 1) {
      paintIf(x, y);
    }
  }
  return painted;
}

function weldOutlineSeam(rgba, canvasW, canvasH, pad, origW, origH, outline, depth = 4) {
  if (!outline) {
    return 0;
  }
  const d = Math.max(2, Math.min(8, depth));
  const left = pad;
  const top = pad;
  const right = pad + origW;
  const bottom = pad + origH;
  let filled = 0;
  for (let y = top; y < bottom; y += 1) {
    for (let x = left; x < right; x += 1) {
      const dist = Math.min(x - left, y - top, right - 1 - x, bottom - 1 - y);
      if (dist >= d) {
        continue;
      }
      const i = (y * canvasW + x) * 4;
      if (rgba[i + 3] < 40) {
        continue;
      }
      if (similarToOutline(rgba[i], rgba[i + 1], rgba[i + 2], outline, 36)) {
        continue;
      }
      const r = rgba[i];
      const g = rgba[i + 1];
      const b = rgba[i + 2];
      if (!isWashedOrHighlightFringe(r, g, b, outline)) {
        continue;
      }
      if (isLightInteriorNotYellow(r, g, b, outline)) {
        continue;
      }
      paintOutline(rgba, i, outline);
      filled += 1;
    }
  }
  return filled;
}

/**
 * JPEG path: restore a full-width printed frame, then clip with an 8×
 * coverage-sampled rounded rect so the die-cut has a defined arc (not 16px
 * stairs). Pad only when the caller asked (square-cut cropped frames). Never
 * grow a studio die-cut that already has the yellow.
 */
function rebuildEvenOuterBorder(rgba, width, height, radiusRatio, outline, thickness, options = {}) {
  const weldToOutline = options.weldToOutline !== false;
  const paintFrame = options.paintFrame !== false;
  const filledEars = rebuildOuterBorder(
    rgba,
    width,
    height,
    cornerRadiusPx(width, height, radiusRatio),
    outline,
    { paintPerimeter: false, thickness },
  );
  if (!outline) {
    const radius = cornerRadiusPx(width, height, radiusRatio);
    punchHaloAlongRound(rgba, width, height, radius, 3, outline);
    fillInsideRoundCaps(rgba, width, height, radius, outline);
    applySupersampledRoundedRectAlpha(rgba, width, height, radius);
    return {
      rgba,
      width,
      height,
      radius,
      pad: 0,
      filled: filledEars,
      superSample: 1,
    };
  }
  const short = Math.min(width, height);
  const rawMeasured = measuredFramePx(thickness);
  const measured = options.forceEraPad ? rawMeasured : rawMeasured || Math.round(short * 0.03);
  const target = targetFramePx(short, outline, measured);
  const allowPad = options.allowPad !== false;
  let pad = allowPad ? padToUnpinch(width, radiusRatio, measured, target) : 0;
  if (allowPad && options.forceEraPad) {
    // Clipped studio after deskew: restore Wizards/EX millimetres, not the
    // 0.78 R unpinch used on square-cut Gible crops (that overshoots 2.33 mm).
    pad = Math.max(1, target);
  }
  const perimeter = pad > 0
    ? fillPerimeterFringeWithOutline(rgba, width, height, outline, 4)
    : 0;
  let cohering = 0;
  if (paintFrame && pad === 0) {
    // Era-complete scan (Gyarados 21–22 px): AABB at measured T only.
    cohering = paintStraightFrame(rgba, width, height, outline, thickness);
  }
  const nw = width + pad * 2;
  const nh = height + pad * 2;
  const radius = cornerRadiusPx(nw, nh, radiusRatio);
  const tFrame = measured + pad;
  const padded = Buffer.alloc(nw * nh * 4);
  for (let i = 0; i < padded.length; i += 4) {
    paintOutline(padded, i, outline);
  }
  blitRgba(rgba, width, height, padded, nw, pad, pad);
  if (paintFrame && pad > 0) {
    // Cropped yellow (Gible 14 px / 1.48 mm): grow outside, then paint the
    // full pad+measured AABB so the inner join is one straight era-width rim.
    cohering = paintStraightFrame(
      padded,
      nw,
      nh,
      outline,
      paddedFrameThickness(thickness, pad),
    );
  }
  const welded = pad > 0 ? weldOutlineSeam(padded, nw, nh, pad, width, height, outline, 4) : 0;
  const painted = weldWashedCornerFringe(
    padded,
    nw,
    nh,
    radius,
    outline,
    thickness,
    pad,
    width,
    height,
    weldToOutline,
  );
  applySupersampledRoundedRectAlpha(padded, nw, nh, radius);

  return {
    rgba: padded,
    width: nw,
    height: nh,
    outWidth: nw,
    outHeight: nh,
    radius,
    pad,
    tFrame,
    filled: filledEars + cohering + perimeter + painted + welded,
    superSample: 1,
  };
}

/**
 * 1× leftover of the old 4× full-raster weld: washed halo in the die-cut
 * corner fans (and the pad seam) becomes outline, or punches when welding
 * is off. Coverage AA is applied after this.
 */
function weldWashedCornerFringe(rgba, width, height, radius, outline, thickness, pad, origW, origH, weldToOutline) {
  if (!outline) {
    return 0;
  }
  const r = Math.max(1, radius);
  const origL = pad;
  const origT = pad;
  const origR = pad + origW;
  const origB = pad + origH;
  let painted = 0;
  const consider = (x, y) => {
    const i = (y * width + x) * 4;
    if (rgba[i + 3] < 40) {
      return;
    }
    const inOriginal = x >= origL && x < origR && y >= origT && y < origB;
    const inCornerFan =
      (x < r && y < r) ||
      (x >= width - r && y < r) ||
      (x < r && y >= height - r) ||
      (x >= width - r && y >= height - r);
    const onOrigSeam =
      pad > 0 &&
      inOriginal &&
      Math.min(x - origL, y - origT, origR - 1 - x, origB - 1 - y) < 4;
    const cr = rgba[i];
    const cg = rgba[i + 1];
    const cb = rgba[i + 2];
    const pastMeasuredT =
      inOriginal &&
      x - origL >= ((thickness && thickness.left) || 0) &&
      origR - 1 - x >= ((thickness && thickness.right) || 0) &&
      y - origT >= ((thickness && thickness.top) || 0) &&
      origB - 1 - y >= ((thickness && thickness.bottom) || 0);
    const washed =
      (inCornerFan || onOrigSeam) &&
      isWashedOrHighlightFringe(cr, cg, cb, outline);
    if (!inOriginal) {
      if (weldToOutline && !similarToOutline(cr, cg, cb, outline, 36)) {
        paintOutline(rgba, i, outline);
        painted += 1;
      }
      return;
    }
    if (
      washed &&
      !pastMeasuredT &&
      !isLightInteriorNotYellow(cr, cg, cb, outline) &&
      !similarToOutline(cr, cg, cb, outline, 36)
    ) {
      if (weldToOutline) {
        paintOutline(rgba, i, outline);
      } else {
        rgba[i] = 0;
        rgba[i + 1] = 0;
        rgba[i + 2] = 0;
        rgba[i + 3] = 0;
      }
      painted += 1;
    }
  };
  for (let y = 0; y < r && y < height; y += 1) {
    for (let x = 0; x < r && x < width; x += 1) {
      consider(x, y);
    }
    for (let x = Math.max(0, width - r); x < width; x += 1) {
      consider(x, y);
    }
  }
  for (let y = Math.max(0, height - r); y < height; y += 1) {
    for (let x = 0; x < r && x < width; x += 1) {
      consider(x, y);
    }
    for (let x = Math.max(0, width - r); x < width; x += 1) {
      consider(x, y);
    }
  }
  if (pad > 0) {
    for (let y = origT; y < origB; y += 1) {
      for (let x = origL; x < origL + 4 && x < origR; x += 1) {
        consider(x, y);
      }
      for (let x = Math.max(origL, origR - 4); x < origR; x += 1) {
        consider(x, y);
      }
    }
    for (let x = origL; x < origR; x += 1) {
      for (let y = origT; y < origT + 4 && y < origB; y += 1) {
        consider(x, y);
      }
      for (let y = Math.max(origT, origB - 4); y < origB; y += 1) {
        consider(x, y);
      }
    }
  }
  return painted;
}

function sampleOutlineColor(data, width, height, channels) {
  const short = Math.min(width, height);
  const skip = Math.round(short * 0.12);
  const depths = [
    Math.max(2, Math.round(short * 0.012)),
    Math.max(3, Math.round(short * 0.022)),
    Math.max(4, Math.round(short * 0.032)),
    Math.max(5, Math.round(short * 0.04)),
  ];
  let family = null;
  let yellowBest = null;
  let yellowChroma = -1;
  let silverBest = null;
  for (const inset of depths) {
    const samples = [];
    for (let x = skip; x < width - skip; x += 1) {
      samples.push(samplePixel(data, width, channels, x, inset));
      samples.push(samplePixel(data, width, channels, x, height - 1 - inset));
    }
    for (let y = skip; y < height - skip; y += 1) {
      samples.push(samplePixel(data, width, channels, inset, y));
      samples.push(samplePixel(data, width, channels, width - 1 - inset, y));
    }
    const notMatte = samples.filter(([r, g, b]) => !isStudioPaper(r, g, b) && !isBlack(r, g, b));
    const yellows = notMatte.filter(([r, g, b]) => chroma(r, g, b) >= 50 && isYellowHue(r, g, b));
    const silvers = notMatte.filter(([r, g, b]) => {
      const l = luminance(r, g, b);
      return chroma(r, g, b) <= 28 && l >= 80 && l < 230;
    });
    const hasYellow = yellows.length >= 8;
    const hasSilver = silvers.length >= 8;
    if (!family) {
      if (hasYellow && (!hasSilver || yellows.length >= silvers.length)) {
        family = 'yellow';
      } else if (hasSilver) {
        family = 'silver';
      }
    }
    if (family === 'yellow' && hasYellow) {
      const candidate = {
        r: medianChannel(yellows.map((p) => p[0])),
        g: medianChannel(yellows.map((p) => p[1])),
        b: medianChannel(yellows.map((p) => p[2])),
      };
      const c = chroma(candidate.r, candidate.g, candidate.b);
      if (c > yellowChroma) {
        yellowChroma = c;
        yellowBest = candidate;
      }
    }
    if (family === 'silver' && hasSilver && !silverBest) {
      silverBest = {
        r: medianChannel(silvers.map((p) => p[0])),
        g: medianChannel(silvers.map((p) => p[1])),
        b: medianChannel(silvers.map((p) => p[2])),
      };
    }
  }
  return yellowBest || silverBest;
}

function fillCornerEars(data, width, height, channels, radius, outline) {
  const reach = Math.max(radius + 4, Math.round(Math.min(width, height) * 0.12));
  let filled = 0;
  const paint = (x, y) => {
    const [r, g, b] = samplePixel(data, width, channels, x, y);
    if (!isEarWhite(r, g, b)) {
      return;
    }
    const index = (y * width + x) * channels;
    data[index] = outline.r;
    data[index + 1] = outline.g;
    data[index + 2] = outline.b;
    filled += 1;
  };
  for (let y = 0; y < reach; y += 1) {
    for (let x = 0; x < reach; x += 1) {
      paint(x, y);
    }
    for (let x = width - reach; x < width; x += 1) {
      paint(x, y);
    }
  }
  for (let y = height - reach; y < height; y += 1) {
    for (let x = 0; x < reach; x += 1) {
      paint(x, y);
    }
    for (let x = width - reach; x < width; x += 1) {
      paint(x, y);
    }
  }
  return filled;
}

/**
 * Sharp PNG `quality` / `effort` / `palette` enable libimagequant (lossy).
 * compressionLevel is zlib only. See https://sharp.pixelplumbing.com/api-output/#png
 */
const LOSSLESS_PNG_OPTIONS = {
  compressionLevel: 9,
  adaptiveFiltering: true,
  palette: false,
  force: true,
};

function shouldPunchMatteSpeck(r, g, b, alpha, outline) {
  if (alpha < 8) {
    return false;
  }
  if (belongsToPrintedRim(r, g, b, outline) || similarToOutline(r, g, b, outline, 36)) {
    return false;
  }
  if (
    isStudioPaper(r, g, b) ||
    isEarWhite(r, g, b) ||
    isPunchableEar(r, g, b, outline) ||
    isPunchableStudioSurround(r, g, b) ||
    isLightMatteFringe(r, g, b)
  ) {
    return true;
  }
  return luminance(r, g, b) >= 160 && chroma(r, g, b) <= 55;
}

function punchPerimeterFringe(rgba, width, height, outline, depth = 2) {
  const d = Math.max(1, Math.min(4, depth));
  let punched = 0;
  const punch = (x, y) => {
    const i = (y * width + x) * 4;
    if (
      !shouldPunchMatteSpeck(
        rgba[i],
        rgba[i + 1],
        rgba[i + 2],
        rgba[i + 3],
        outline,
      )
    ) {
      return;
    }
    rgba[i] = 0;
    rgba[i + 1] = 0;
    rgba[i + 2] = 0;
    rgba[i + 3] = 0;
    punched += 1;
  };
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < d && x < width; x += 1) {
      punch(x, y);
    }
    for (let x = Math.max(0, width - d); x < width; x += 1) {
      punch(x, y);
    }
  }
  for (let x = 0; x < width; x += 1) {
    for (let y = 0; y < d && y < height; y += 1) {
      punch(x, y);
    }
    for (let y = Math.max(0, height - d); y < height; y += 1) {
      punch(x, y);
    }
  }
  return punched;
}

/**
 * Opaque white / light AA sitting on the die-cut arc after PNG flatten.
 * Punch it to transparent so JPEG matte is dark, not a halo.
 */
function punchHaloAlongRound(rgba, width, height, radius, depth = 3, outline = null) {
  const r = Math.max(1, radius);
  const inner = Math.max(0, r - Math.max(1, depth));
  const inner2 = inner * inner;
  const outer2 = (r + 0.5) * (r + 0.5);
  let punched = 0;
  const consider = (x, y, cx, cy) => {
    const dx = x - cx;
    const dy = y - cy;
    const d2 = dx * dx + dy * dy;
    if (d2 < inner2 || d2 > outer2) {
      return;
    }
    const i = (y * width + x) * 4;
    if (
      !shouldPunchMatteSpeck(
        rgba[i],
        rgba[i + 1],
        rgba[i + 2],
        rgba[i + 3],
        outline,
      )
    ) {
      return;
    }
    rgba[i] = 0;
    rgba[i + 1] = 0;
    rgba[i + 2] = 0;
    rgba[i + 3] = 0;
    punched += 1;
  };
  for (let y = 0; y < r && y < height; y += 1) {
    for (let x = 0; x < r && x < width; x += 1) {
      consider(x, y, r, r);
    }
    for (let x = Math.max(0, width - r); x < width; x += 1) {
      consider(x, y, width - 1 - r, r);
    }
  }
  for (let y = Math.max(0, height - r); y < height; y += 1) {
    for (let x = 0; x < r && x < width; x += 1) {
      consider(x, y, r, height - 1 - r);
    }
    for (let x = Math.max(0, width - r); x < width; x += 1) {
      consider(x, y, width - 1 - r, height - 1 - r);
    }
  }
  return punched;
}

/**
 * Bright pixels just inside the die-cut silhouette (1–3 px from transparency).
 * Leftover JPEG ears are often opaque catalog matte, not alpha=0 — treat both
 * as clear so foil highlights beside baked matte ears are punched.
 */
function isMatteSurround(r, g, b, matte) {
  if (!matte) {
    return false;
  }
  if (luminance(r, g, b) > 50) {
    return false;
  }
  return colorDistance(r, g, b, matte) < 40;
}

function isClearSurround(r, g, b, alpha, matte) {
  return alpha < 40 || isMatteSurround(r, g, b, matte);
}

/** Leftover JPEG already flattened onto catalog matte (#0b0b0f), not white studio. */
function isMarketplaceMatteBacking(rgba, width, height, channels = 4, matte = DEFAULT_MATTE) {
  const corner = Math.max(12, Math.floor(Math.min(width, height) * 0.05));
  let mattePx = 0;
  let total = 0;
  const corners = [
    [0, 0],
    [Math.max(0, width - corner), 0],
    [0, Math.max(0, height - corner)],
    [Math.max(0, width - corner), Math.max(0, height - corner)],
  ];
  for (const [cx, cy] of corners) {
    for (let y = cy; y < Math.min(height, cy + corner); y += 1) {
      for (let x = cx; x < Math.min(width, cx + corner); x += 1) {
        const i = (y * width + x) * channels;
        const a = channels === 4 ? rgba[i + 3] : 255;
        if (a < 8) {
          continue;
        }
        total += 1;
        if (isMatteSurround(rgba[i], rgba[i + 1], rgba[i + 2], matte)) {
          mattePx += 1;
        }
      }
    }
  }
  return total >= 24 && mattePx / total >= 0.55;
}

function punchSilhouetteLightFringe(rgba, width, height, maxDepth = 2, lumaMin = 195, matte = null, outline = null) {
  const depth = Math.max(1, Math.min(3, maxDepth));
  const dist = new Int16Array(width * height);
  dist.fill(-1);
  const queue = [];
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const idx = y * width + x;
      const i = idx * 4;
      if (isClearSurround(rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3], matte)) {
        dist[idx] = 0;
        queue.push(x, y);
      }
    }
  }
  for (let qi = 0; qi < queue.length; qi += 2) {
    const x = queue[qi];
    const y = queue[qi + 1];
    const d = dist[y * width + x];
    if (d >= depth) {
      continue;
    }
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
        const idx = ny * width + nx;
        if (dist[idx] >= 0) {
          continue;
        }
        const i = idx * 4;
        if (isClearSurround(rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3], matte)) {
          continue;
        }
        dist[idx] = d + 1;
        queue.push(nx, ny);
      }
    }
  }
  let punched = 0;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const idx = y * width + x;
      const d = dist[idx];
      if (d <= 0 || d > depth) {
        continue;
      }
      const i = idx * 4;
      const rr = rgba[i];
      const gg = rgba[i + 1];
      const bb = rgba[i + 2];
      const l = luminance(rr, gg, bb);
      if (isYellowHue(rr, gg, bb) || belongsToPrintedRim(rr, gg, bb, outline) || similarToOutline(rr, gg, bb, outline, 36)) {
        continue;
      }
      if (
        l < lumaMin &&
        !isEarWhite(rr, gg, bb) &&
        !isLightMatteFringe(rr, gg, bb) &&
        !shouldPunchMatteSpeck(rr, gg, bb, rgba[i + 3], null)
      ) {
        continue;
      }
      rgba[i] = 0;
      rgba[i + 1] = 0;
      rgba[i + 2] = 0;
      rgba[i + 3] = 0;
      punched += 1;
    }
  }
  return punched;
}

/**
 * mozjpeg rings bright gold/ear-white into adjacent matte DCT blocks. PNG
 * output is clean; force a 1 px solid matte collar before JPEG flatten.
 * Snapshot the clear mask first — do not reseed from freshly painted
 * pixels or a white TRAINER nameplate (luma 253, chroma 0) floods to matte.
 * Only collar cardboard-like pixels that already touch the die-cut.
 */
function paintMatteJpegGuard(rgba, width, height, matte, radius = 0) {
  if (!matte) {
    return 0;
  }
  const r = Math.max(0, radius);
  const seed = new Uint8Array(width * height);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 4;
      if (isClearSurround(rgba[i], rgba[i + 1], rgba[i + 2], rgba[i + 3], matte)) {
        seed[y * width + x] = 1;
      }
    }
  }
  let painted = 0;
  const paint = (x, y) => {
    const i = (y * width + x) * 4;
    rgba[i] = matte.r;
    rgba[i + 1] = matte.g;
    rgba[i + 2] = matte.b;
    rgba[i + 3] = 255;
    painted += 1;
  };
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      if (!seed[y * width + x]) {
        continue;
      }
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
          if (seed[ny * width + nx]) {
            continue;
          }
          if (r > 0 && inDieCutCap(nx, ny, width, height, r)) {
            continue;
          }
          const j = (ny * width + nx) * 4;
          const rr = rgba[j];
          const gg = rgba[j + 1];
          const bb = rgba[j + 2];
          if (
            rgba[j + 3] < 40 ||
            isEarWhite(rr, gg, bb) ||
            isLightMatteFringe(rr, gg, bb)
          ) {
            paint(nx, ny);
          }
        }
      }
    }
  }
  return painted;
}

function applyHardRoundedRectAlpha(rgba, width, height, radius) {
  const r = Math.max(1, radius);
  const r2 = r * r;
  let cleared = 0;
  const clear = (x, y) => {
    const i = (y * width + x) * 4;
    if (rgba[i + 3] === 0) {
      return;
    }
    rgba[i] = 0;
    rgba[i + 1] = 0;
    rgba[i + 2] = 0;
    rgba[i + 3] = 0;
    cleared += 1;
  };
  const outsideCorner = (x, y, cx, cy) => {
    const dx = x - cx;
    const dy = y - cy;
    return dx * dx + dy * dy > r2;
  };
  for (let y = 0; y < r && y < height; y += 1) {
    for (let x = 0; x < r && x < width; x += 1) {
      if (outsideCorner(x, y, r, r)) {
        clear(x, y);
      }
    }
    for (let x = Math.max(0, width - r); x < width; x += 1) {
      if (outsideCorner(x, y, width - 1 - r, r)) {
        clear(x, y);
      }
    }
  }
  for (let y = Math.max(0, height - r); y < height; y += 1) {
    for (let x = 0; x < r && x < width; x += 1) {
      if (outsideCorner(x, y, r, height - 1 - r)) {
        clear(x, y);
      }
    }
    for (let x = Math.max(0, width - r); x < width; x += 1) {
      if (outsideCorner(x, y, width - 1 - r, height - 1 - r)) {
        clear(x, y);
      }
    }
  }
  return cleared;
}

async function encodeSanitized(pipeline, format, { matte, jpegQuality }) {
  if (format === 'png') {
    return { body: await pipeline.png(LOSSLESS_PNG_OPTIONS).toBuffer(), format: 'png' };
  }
  if (format === 'webp') {
    return {
      body: await pipeline.webp({ lossless: true }).toBuffer(),
      format: 'webp',
    };
  }
  const jpeg = { quality: jpegQuality, mozjpeg: true };
  if (jpegQuality >= 95) {
    jpeg.chromaSubsampling = '4:4:4';
  }
  return {
    body: await pipeline.flatten({ background: matte }).jpeg(jpeg).toBuffer(),
    format: 'jpg',
  };
}

const STUDIO_DESKEW_MIN_DEG = 0.4;
const STUDIO_DESKEW_MAX_DEG = 12;
const STUDIO_DESKEW_DONE_DEG = 0.12;
const STUDIO_DESKEW_DAMP = 0.92;
const STUDIO_DESKEW_ITERS = 10;
/** Skip die-cut rounds when fitting the straight outer border. */
const STRAIGHT_BORDER_INSET = 0.22;
/** Opposite sides of a rectangle agree within this (Charizard L/R were 0.45°). */
const STRAIGHT_SIDE_MATCH_DEG = 0.55;
/** Vertical residual must match horizontal residual (pure rotation). */
const AXIS_MATCH_DEG = 0.4;

function theilSenSlope(xs, ys, minSpan) {
  const n = xs.length;
  const slopes = [];
  const span = Math.max(4, minSpan || 12);
  for (let i = 0; i < n; i += 1) {
    for (let j = i + 1; j < n; j += 1) {
      const dx = xs[j] - xs[i];
      if (Math.abs(dx) < span) {
        continue;
      }
      slopes.push((ys[j] - ys[i]) / dx);
    }
  }
  if (slopes.length < 8) {
    return null;
  }
  slopes.sort((a, b) => a - b);
  return slopes[Math.floor(slopes.length / 2)];
}

function slopeToDegrees(slope) {
  if (!Number.isFinite(slope)) {
    return 0;
  }
  return (Math.atan(slope) * 180) / Math.PI;
}

/** Studio paper, white ears, or marketplace/die-cut matte — not the card. */
function isSilhouetteVoid(r, g, b, a) {
  if (a != null && a < 40) {
    return true;
  }
  return isBlack(r, g, b) || isPunchableStudioSurround(r, g, b) || isEarWhite(r, g, b);
}

/** Gray JPEG AA between matte and paper after rotate() is not the gold edge. */
function isOuterSilhouetteVoid(r, g, b, a) {
  if (isSilhouetteVoid(r, g, b, a)) {
    return true;
  }
  return chroma(r, g, b) < 20 && luminance(r, g, b) < 200;
}

function collectVerticalInnerJoin(rgba, width, height, channels, fromRight) {
  const xs = [];
  const ys = [];
  const y0 = Math.floor(height * 0.16);
  const y1 = Math.floor(height * 0.84);
  const xMax = Math.floor(width * 0.28);
  const xLimit = Math.max(8, xMax);
  for (let y = y0; y < y1; y += 1) {
    let sawYellow = false;
    const xStart = fromRight ? width - 1 : 0;
    const xEnd = fromRight ? width - 1 - xLimit : xLimit;
    const step = fromRight ? -1 : 1;
    for (let x = xStart; fromRight ? x > xEnd : x < xEnd; x += step) {
      const i = (y * width + x) * channels;
      const r = rgba[i];
      const g = rgba[i + 1];
      const b = rgba[i + 2];
      const a = channels === 4 ? rgba[i + 3] : 255;
      if (isSilhouetteVoid(r, g, b, a)) {
        continue;
      }
      if (isYellowHue(r, g, b)) {
        sawYellow = true;
        continue;
      }
      if (sawYellow) {
        xs.push(x);
        ys.push(y);
        break;
      }
    }
  }
  return { xs, ys };
}

/** First card pixel from the left/right — skip paper and dark matte. */
function collectOuterSilhouette(rgba, width, height, channels, fromRight) {
  const xs = [];
  const ys = [];
  const y0 = Math.floor(height * 0.18);
  const y1 = Math.floor(height * 0.82);
  const xLimit = Math.max(8, Math.floor(width * 0.28));
  for (let y = y0; y < y1; y += 1) {
    const xStart = fromRight ? width - 1 : 0;
    const xEnd = fromRight ? width - 1 - xLimit : xLimit;
    const step = fromRight ? -1 : 1;
    for (let x = xStart; fromRight ? x > xEnd : x < xEnd; x += step) {
      const i = (y * width + x) * channels;
      const r = rgba[i];
      const g = rgba[i + 1];
      const b = rgba[i + 2];
      const a = channels === 4 ? rgba[i + 3] : 255;
      if (isOuterSilhouetteVoid(r, g, b, a)) {
        continue;
      }
      xs.push(x);
      ys.push(y);
      break;
    }
  }
  return { xs, ys };
}

/** First card pixel from the top/bottom — skip paper and dark matte. */
function collectHorizontalSilhouette(rgba, width, height, channels, fromBottom) {
  const xs = [];
  const ys = [];
  const x0 = Math.floor(width * 0.18);
  const x1 = Math.floor(width * 0.82);
  const yLimit = Math.max(8, Math.floor(height * 0.28));
  for (let x = x0; x < x1; x += 1) {
    const yStart = fromBottom ? height - 1 : 0;
    const yEnd = fromBottom ? height - 1 - yLimit : yLimit;
    const step = fromBottom ? -1 : 1;
    for (let y = yStart; fromBottom ? y > yEnd : y < yEnd; y += step) {
      const i = (y * width + x) * channels;
      const r = rgba[i];
      const g = rgba[i + 1];
      const b = rgba[i + 2];
      const a = channels === 4 ? rgba[i + 3] : 255;
      if (isOuterSilhouetteVoid(r, g, b, a)) {
        continue;
      }
      xs.push(x);
      ys.push(y);
      break;
    }
  }
  return { xs, ys };
}

function angleFromPairedSamples(a, b, span, { swap } = {}) {
  const angleOf = (pts) => {
    const n = pts.xs.length;
    if (n < 16) {
      return { deg: Number.NaN, n };
    }
    const independent = swap ? pts.ys : pts.xs;
    const dependent = swap ? pts.xs : pts.ys;
    const robust = theilSenSlope(independent, dependent, span);
    return { deg: slopeToDegrees(robust), n };
  };
  const A = angleOf(a);
  const B = angleOf(b);
  const aOk = A.n >= 16 && Number.isFinite(A.deg);
  const bOk = B.n >= 16 && Number.isFinite(B.deg);
  if (aOk && bOk) {
    if (Math.abs(A.deg - B.deg) <= 1.2) {
      return (A.deg + B.deg) / 2;
    }
    return A.n >= B.n ? A.deg : B.deg;
  }
  if (aOk) {
    return A.deg;
  }
  if (bOk) {
    return B.deg;
  }
  return Number.NaN;
}

function angleFromVerticalSamples(left, right, height) {
  return angleFromPairedSamples(left, right, Math.max(10, Math.round(height * 0.06)), { swap: true });
}

function angleFromHorizontalSamples(top, bottom, width) {
  return angleFromPairedSamples(top, bottom, Math.max(10, Math.round(width * 0.06)));
}

function collectSilhouettePoints(rgba, width, height, channels = 4) {
  const pts = [];
  const step = Math.max(2, Math.round(Math.min(width, height) / 160));
  for (let y = 0; y < height; y += step) {
    for (let x = 0; x < width; x += step) {
      const i = (y * width + x) * channels;
      const a = channels === 4 ? rgba[i + 3] : 255;
      if (isOuterSilhouetteVoid(rgba[i], rgba[i + 1], rgba[i + 2], a)) {
        continue;
      }
      pts.push(x, y);
    }
  }
  return pts;
}

function aabbAreaAfterUndo(pts, tiltDeg) {
  const th = (-tiltDeg * Math.PI) / 180;
  const c = Math.cos(th);
  const s = Math.sin(th);
  let minX = Infinity;
  let minY = Infinity;
  let maxX = -Infinity;
  let maxY = -Infinity;
  for (let i = 0; i < pts.length; i += 2) {
    const x = pts[i];
    const y = pts[i + 1];
    const xr = x * c - y * s;
    const yr = x * s + y * c;
    if (xr < minX) minX = xr;
    if (xr > maxX) maxX = xr;
    if (yr < minY) minY = yr;
    if (yr > maxY) maxY = yr;
  }
  return (maxX - minX) * (maxY - minY);
}

/**
 * Tilt that minimises the AABB of card pixels once undone. Same sign as
 * Theil–Sen / Sharp (negative = counter-clockwise card). Refine around a
 * hint when the four-side fit already agrees.
 */
function minAreaSilhouetteDegrees(rgba, width, height, channels = 4, hint = Number.NaN) {
  const pts = collectSilhouettePoints(rgba, width, height, channels);
  if (pts.length < 80) {
    return Number.NaN;
  }
  const hasHint = Number.isFinite(hint);
  const lo = hasHint ? hint - 2.4 : -STUDIO_DESKEW_MAX_DEG;
  const hi = hasHint ? hint + 2.4 : STUDIO_DESKEW_MAX_DEG;
  const coarse = hasHint ? 0.1 : 0.25;
  let bestDeg = hasHint ? hint : 0;
  let bestArea = Infinity;
  for (let a = lo; a <= hi + 1e-9; a += coarse) {
    const area = aabbAreaAfterUndo(pts, a);
    if (area < bestArea) {
      bestArea = area;
      bestDeg = a;
    }
  }
  const fineLo = bestDeg - 0.35;
  const fineHi = bestDeg + 0.35;
  for (let a = fineLo; a <= fineHi + 1e-9; a += 0.05) {
    const area = aabbAreaAfterUndo(pts, a);
    if (area < bestArea) {
      bestArea = area;
      bestDeg = a;
    }
  }
  return bestDeg;
}

function consensusDegrees(values) {
  const finite = values.filter((v) => Number.isFinite(v) && Math.abs(v) <= STUDIO_DESKEW_MAX_DEG);
  if (!finite.length) {
    return Number.NaN;
  }
  finite.sort((a, b) => a - b);
  const med = finite[Math.floor(finite.length / 2)];
  const close = finite.filter((v) => Math.abs(v - med) <= 0.9);
  if (close.length >= 2) {
    return close.reduce((sum, v) => sum + v, 0) / close.length;
  }
  return med;
}

/**
 * Giuseppe's red-line test: first bright gold pixel on left/right mid-side.
 * Skips matte only — not gray fringe — so a leftover on #0b0b0f still reads
 * the printed edge that stair-steps when the AABB estimator thinks it is done.
 */
function collectBrightOuterEdge(rgba, width, height, channels, fromRight) {
  const xs = [];
  const ys = [];
  const y0 = Math.floor(height * 0.2);
  const y1 = Math.floor(height * 0.8);
  const xLimit = Math.max(8, Math.floor(width * 0.32));
  for (let y = y0; y < y1; y += 1) {
    const xStart = fromRight ? width - 1 : 0;
    const xEnd = fromRight ? width - 1 - xLimit : xLimit;
    const step = fromRight ? -1 : 1;
    for (let x = xStart; fromRight ? x > xEnd : x < xEnd; x += step) {
      const i = (y * width + x) * channels;
      const r = rgba[i];
      const g = rgba[i + 1];
      const b = rgba[i + 2];
      const a = channels === 4 ? rgba[i + 3] : 255;
      if (a < 40 || isBlack(r, g, b)) {
        continue;
      }
      if (isPunchableStudioSurround(r, g, b) || isEarWhite(r, g, b)) {
        continue;
      }
      const L = luminance(r, g, b);
      if (L < 80 && !isYellowHue(r, g, b)) {
        continue;
      }
      xs.push(x);
      ys.push(y);
      break;
    }
  }
  return { xs, ys };
}

function isBrightCardEdgePixel(r, g, b, a) {
  if (a < 40 || isBlack(r, g, b)) {
    return false;
  }
  if (isPunchableStudioSurround(r, g, b) || isEarWhite(r, g, b)) {
    return false;
  }
  const L = luminance(r, g, b);
  return L >= 80 || isYellowHue(r, g, b);
}

function fitTheilSenLine(indep, dep, minSpan) {
  if (!indep || indep.length < 16) {
    return null;
  }
  const m = theilSenSlope(indep, dep, minSpan);
  if (!Number.isFinite(m)) {
    return null;
  }
  const residuals = [];
  for (let i = 0; i < indep.length; i += 1) {
    residuals.push(dep[i] - m * indep[i]);
  }
  residuals.sort((a, b) => a - b);
  const c = residuals[Math.floor(residuals.length / 2)];
  let sse = 0;
  for (let i = 0; i < indep.length; i += 1) {
    const err = dep[i] - (m * indep[i] + c);
    sse += err * err;
  }
  return {
    m,
    c,
    deg: slopeToDegrees(m),
    n: indep.length,
    rms: Math.sqrt(sse / indep.length),
  };
}

function collectBrightHorizontalEdge(rgba, width, height, channels, fromBottom) {
  const xs = [];
  const ys = [];
  const x0 = Math.floor(width * STRAIGHT_BORDER_INSET);
  const x1 = Math.floor(width * (1 - STRAIGHT_BORDER_INSET));
  const yLimit = Math.max(8, Math.floor(height * 0.32));
  for (let x = x0; x < x1; x += 1) {
    const yStart = fromBottom ? height - 1 : 0;
    const yEnd = fromBottom ? height - 1 - yLimit : yLimit;
    const step = fromBottom ? -1 : 1;
    for (let y = yStart; fromBottom ? y > yEnd : y < yEnd; y += step) {
      const i = (y * width + x) * channels;
      const a = channels === 4 ? rgba[i + 3] : 255;
      if (!isBrightCardEdgePixel(rgba[i], rgba[i + 1], rgba[i + 2], a)) {
        continue;
      }
      xs.push(x);
      ys.push(y);
      break;
    }
  }
  return { xs, ys };
}

function collectBrightVerticalEdge(rgba, width, height, channels, fromRight) {
  const xs = [];
  const ys = [];
  const y0 = Math.floor(height * STRAIGHT_BORDER_INSET);
  const y1 = Math.floor(height * (1 - STRAIGHT_BORDER_INSET));
  const xLimit = Math.max(8, Math.floor(width * 0.32));
  for (let y = y0; y < y1; y += 1) {
    const xStart = fromRight ? width - 1 : 0;
    const xEnd = fromRight ? width - 1 - xLimit : xLimit;
    const step = fromRight ? -1 : 1;
    for (let x = xStart; fromRight ? x > xEnd : x < xEnd; x += step) {
      const i = (y * width + x) * channels;
      const a = channels === 4 ? rgba[i + 3] : 255;
      if (!isBrightCardEdgePixel(rgba[i], rgba[i + 1], rgba[i + 2], a)) {
        continue;
      }
      xs.push(x);
      ys.push(y);
      break;
    }
  }
  return { xs, ys };
}

/**
 * Four independent Theil–Sen lines on the straight outer gold (corners
 * inset). Vertical deg uses the Sharp convention (negative = CCW).
 */
function fitStraightBorder(rgba, width, height, channels = 4) {
  const leftPts = collectBrightVerticalEdge(rgba, width, height, channels, false);
  const rightPts = collectBrightVerticalEdge(rgba, width, height, channels, true);
  const topPts = collectBrightHorizontalEdge(rgba, width, height, channels, false);
  const bottomPts = collectBrightHorizontalEdge(rgba, width, height, channels, true);
  const vSpan = Math.max(10, Math.round(height * 0.06));
  const hSpan = Math.max(10, Math.round(width * 0.06));
  const leftFit = fitTheilSenLine(leftPts.ys, leftPts.xs, vSpan);
  const rightFit = fitTheilSenLine(rightPts.ys, rightPts.xs, vSpan);
  const top = fitTheilSenLine(topPts.xs, topPts.ys, hSpan);
  const bottom = fitTheilSenLine(bottomPts.xs, bottomPts.ys, hSpan);
  const withSharp = (fit) => (fit ? { ...fit, deg: -fit.deg } : null);
  return {
    left: withSharp(leftFit),
    right: withSharp(rightFit),
    top,
    bottom,
  };
}

function pairMeanDegrees(a, b, maxDelta) {
  const aOk = a && Number.isFinite(a.deg);
  const bOk = b && Number.isFinite(b.deg);
  if (aOk && bOk) {
    if (Math.abs(a.deg - b.deg) <= maxDelta) {
      return (a.deg + b.deg) / 2;
    }
    return (a.deg + b.deg) / 2;
  }
  if (aOk) {
    return a.deg;
  }
  if (bOk) {
    return b.deg;
  }
  return Number.NaN;
}

/**
 * Rotate so left/right are vertical and top/bottom are horizontal. Averaging
 * all four raw angles can cancel (Builder Cards); match the two axes first.
 */
function matchedAxisSkewDegrees(border) {
  if (!border) {
    return Number.NaN;
  }
  const vertical = pairMeanDegrees(border.left, border.right, STRAIGHT_SIDE_MATCH_DEG);
  const horizontal = pairMeanDegrees(border.top, border.bottom, STRAIGHT_SIDE_MATCH_DEG);
  const vOk = Number.isFinite(vertical);
  const hOk = Number.isFinite(horizontal);
  if (vOk && hOk && Math.abs(vertical - horizontal) <= AXIS_MATCH_DEG) {
    return (vertical + horizontal) / 2;
  }
  if (vOk) {
    return vertical;
  }
  return horizontal;
}

function estimateStraightBorderSkewDegrees(rgba, width, height, channels = 4) {
  return matchedAxisSkewDegrees(fitStraightBorder(rgba, width, height, channels));
}

/**
 * Inner AABB of the four fitted lines on the straight mid-band. Clips rotate
 * fringe and the jagged die-cut so the remaining sides are the gold edge.
 */
function tightStraightBorderBox(rgba, width, height, channels = 4) {
  const border = fitStraightBorder(rgba, width, height, channels);
  if (!border?.left || !border?.right || !border?.top || !border?.bottom) {
    return null;
  }
  const y0 = height * STRAIGHT_BORDER_INSET;
  const y1 = height * (1 - STRAIGHT_BORDER_INSET);
  const x0 = width * STRAIGHT_BORDER_INSET;
  const x1 = width * (1 - STRAIGHT_BORDER_INSET);
  const xAt = (fit, y) => fit.m * y + fit.c;
  const yAt = (fit, x) => fit.m * x + fit.c;
  let left = Math.ceil(Math.max(xAt(border.left, y0), xAt(border.left, y1)));
  let right = Math.floor(Math.min(xAt(border.right, y0), xAt(border.right, y1)));
  let top = Math.ceil(Math.max(yAt(border.top, x0), yAt(border.top, x1)));
  let bottom = Math.floor(Math.min(yAt(border.bottom, x0), yAt(border.bottom, x1)));
  left = Math.max(0, left);
  top = Math.max(0, top);
  right = Math.min(width - 1, right);
  bottom = Math.min(height - 1, bottom);
  const boxW = right - left + 1;
  const boxH = bottom - top + 1;
  if (boxW < 40 || boxH < 40) {
    return null;
  }
  if (boxW >= width - 1 && boxH >= height - 1) {
    return null;
  }
  return { left, top, width: boxW, height: boxH };
}

function estimateBrightOuterEdgeSkewDegrees(rgba, width, height, channels = 4) {
  const deg = angleFromVerticalSamples(
    collectBrightOuterEdge(rgba, width, height, channels, false),
    collectBrightOuterEdge(rgba, width, height, channels, true),
    height,
  );
  return Number.isFinite(deg) ? -deg : deg;
}

/**
 * Gold HR deskew target: four straight outer borders (Giuseppe's red-line
 * test). Left/right must agree, top/bottom must agree, then vertical matches
 * horizontal. Averaging all four raw angles can cancel. The matte silhouette
 * can read ~0° while the bright edge still leans ~−1.6° (Charizard 713832).
 */
function estimateGoldFoilDeskewDegrees(rgba, width, height, channels = 4) {
  const matteBacking = isMarketplaceMatteBacking(rgba, width, height, channels);
  const axis = estimateStraightBorderSkewDegrees(rgba, width, height, channels);
  const axisOk =
    Number.isFinite(axis) &&
    Math.abs(axis) >= STUDIO_DESKEW_MIN_DEG &&
    Math.abs(axis) <= STUDIO_DESKEW_MAX_DEG;
  if (axisOk) {
    return axis;
  }
  const bright = estimateBrightOuterEdgeSkewDegrees(rgba, width, height, channels);
  const brightOk =
    Number.isFinite(bright) &&
    Math.abs(bright) >= STUDIO_DESKEW_MIN_DEG &&
    Math.abs(bright) <= STUDIO_DESKEW_MAX_DEG;
  const outer = estimateOuterSilhouetteSkewDegrees(rgba, width, height, channels);
  const outerOk =
    Number.isFinite(outer) &&
    Math.abs(outer) >= STUDIO_DESKEW_MIN_DEG &&
    Math.abs(outer) <= STUDIO_DESKEW_MAX_DEG;
  if (matteBacking && brightOk) {
    return bright;
  }
  if (outerOk) {
    return outer;
  }
  const layout = estimatePrintedLayoutSkewDegrees(rgba, width, height, channels);
  if (
    Number.isFinite(layout) &&
    Math.abs(layout) >= Math.max(STUDIO_DESKEW_MIN_DEG, 0.85) &&
    Math.abs(layout) <= STUDIO_DESKEW_MAX_DEG
  ) {
    return layout;
  }
  if (brightOk) {
    return bright;
  }
  if (Number.isFinite(axis)) {
    return axis;
  }
  if (Number.isFinite(bright)) {
    return bright;
  }
  return Number.isFinite(outer) ? outer : layout;
}

/**
 * Tilt of the left/right silver inner line (yellow rim → face). Image y
 * grows down; negative is a counter-clockwise card, same as the top join.
 * Giuseppe judges deskew on this line, not the name-bar. Prefer the side
 * with more samples so a clipped left yellow (Swampert theme-deck) still
 * reads the intact right join.
 */
function estimateVerticalInnerJoinSkewDegrees(rgba, width, height, channels = 4) {
  const deg = angleFromVerticalSamples(
    collectVerticalInnerJoin(rgba, width, height, channels, false),
    collectVerticalInnerJoin(rgba, width, height, channels, true),
    height,
  );
  // Image y grows down: atan(dx/dy) on the left edge is the opposite sign of
  // the top-join atan(dy/dx) for the same rotation. Sharp rotate() uses the
  // top-join convention (negative = counter-clockwise).
  return Number.isFinite(deg) ? -deg : deg;
}

/**
 * Tilt of the card silhouette against studio paper or marketplace matte.
 * Gold secrets have no yellow→face join — chasing the illustration would
 * rotate with the art. Align the printed rectangle: four-side Theil–Sen,
 * then min-area refine. Skip dark matte so a leftover JPEG after die-cut
 * still reads the gold edge (Charizard 713832 was 0° while the card sat ~1.7°).
 */
function estimateOuterSilhouetteSkewDegrees(rgba, width, height, channels = 4) {
  const side = angleFromVerticalSamples(
    collectOuterSilhouette(rgba, width, height, channels, false),
    collectOuterSilhouette(rgba, width, height, channels, true),
    height,
  );
  const top = angleFromHorizontalSamples(
    collectHorizontalSilhouette(rgba, width, height, channels, false),
    collectHorizontalSilhouette(rgba, width, height, channels, true),
    width,
  );
  const sideSharp = Number.isFinite(side) ? -side : Number.NaN;
  const hint = consensusDegrees([sideSharp, top]);
  const fitted = minAreaSilhouetteDegrees(rgba, width, height, channels, hint);
  if (Number.isFinite(fitted) && Number.isFinite(hint) && Math.abs(fitted - hint) <= 1.1) {
    return fitted;
  }
  if (Number.isFinite(hint)) {
    return hint;
  }
  return Number.isFinite(fitted) ? fitted : Number.NaN;
}

/**
 * Dark name / attack baselines on gold HR. Used only when the silhouette
 * has already been AABB-cropped (outer ~0°) but the printed layout still
 * leans. Name and attack must agree so a slanted Mega banner cannot win.
 */
function estimatePrintedLayoutSkewDegrees(rgba, width, height, channels = 4) {
  const band = (y0f, y1f) => {
    const xs = [];
    const ys = [];
    const y0 = Math.floor(height * y0f);
    const y1 = Math.floor(height * y1f);
    const x0 = Math.floor(width * 0.18);
    const x1 = Math.floor(width * 0.82);
    for (let x = x0; x < x1; x += 1) {
      let bestY = null;
      let bestL = 68;
      for (let y = y0; y < y1; y += 1) {
        const i = (y * width + x) * channels;
        const r = rgba[i];
        const g = rgba[i + 1];
        const b = rgba[i + 2];
        if (channels === 4 && rgba[i + 3] < 40) {
          continue;
        }
        if (isPunchableStudioSurround(r, g, b) || isEarWhite(r, g, b)) {
          continue;
        }
        const L = luminance(r, g, b);
        if (L < bestL) {
          bestL = L;
          bestY = y;
        }
      }
      if (bestY != null && bestL <= 52) {
        xs.push(x);
        ys.push(bestY);
      }
    }
    if (xs.length < 24) {
      return Number.NaN;
    }
    const robust = theilSenSlope(xs, ys, Math.max(12, Math.round(width * 0.12)));
    return slopeToDegrees(robust);
  };
  const name = band(0.06, 0.15);
  const attack = band(0.62, 0.72);
  if (!Number.isFinite(name) || !Number.isFinite(attack)) {
    return Number.NaN;
  }
  if (Math.abs(name - attack) > 0.7) {
    return Number.NaN;
  }
  return (name + attack) / 2;
}

/**
 * Angle of the top inner join (yellow rim → name/HP/art). Image y grows
 * down, so a negative value is a counter-clockwise card. Theil–Sen (median
 * pairwise slope) ignores the evolution-box step that makes OLS read −4.5°
 * on Swampert while the silver inner line is only ~1.8°.
 */
function estimateInnerJoinSkewDegrees(rgba, width, height, channels = 4) {
  const xs = [];
  const ys = [];
  const x0 = Math.floor(width * 0.22);
  const x1 = Math.floor(width * 0.78);
  const yMax = Math.floor(height * 0.25);
  for (let x = x0; x < x1; x += 2) {
    let sawYellow = false;
    for (let y = 0; y < yMax; y += 1) {
      const i = (y * width + x) * channels;
      const r = rgba[i];
      const g = rgba[i + 1];
      const b = rgba[i + 2];
      if (channels === 4 && rgba[i + 3] < 40) {
        continue;
      }
      if (isEarWhite(r, g, b)) {
        continue;
      }
      if (isYellowHue(r, g, b)) {
        sawYellow = true;
        continue;
      }
      if (sawYellow) {
        xs.push(x);
        ys.push(y);
        break;
      }
    }
  }
  if (xs.length < 12) {
    return 0;
  }
  const robust = theilSenSlope(xs, ys, Math.max(12, Math.round((x1 - x0) * 0.12)));
  if (Number.isFinite(robust)) {
    return (Math.atan(robust) * 180) / Math.PI;
  }
  const n = xs.length;
  let sx = 0;
  let sy = 0;
  let sxx = 0;
  let sxy = 0;
  for (let i = 0; i < n; i += 1) {
    sx += xs[i];
    sy += ys[i];
    sxx += xs[i] * xs[i];
    sxy += xs[i] * ys[i];
  }
  const den = n * sxx - sx * sx;
  if (Math.abs(den) < 1) {
    return 0;
  }
  const slope = (n * sxy - sx * sy) / den;
  return (Math.atan(slope) * 180) / Math.PI;
}

/**
 * Left outer edge of the printed card (first non-studio pixel). Image y
 * grows down. On a tight AABB crop the top inner join can disagree with
 * this (Swampert screenshot: inner −4.5°, side +0.85°) — rotating by the
 * inner join then leans the yellow silhouette the other way.
 */
function estimateSideSkewDegrees(rgba, width, height, channels = 4) {
  const xs = [];
  const ys = [];
  const y0 = Math.floor(height * 0.3);
  const y1 = Math.floor(height * 0.7);
  const xMax = Math.floor(width * 0.35);
  for (let y = y0; y < y1; y += 2) {
    for (let x = 0; x < xMax; x += 1) {
      const i = (y * width + x) * channels;
      const r = rgba[i];
      const g = rgba[i + 1];
      const b = rgba[i + 2];
      if (rgba[i + 3] < 40) {
        continue;
      }
      if (isPunchableStudioSurround(r, g, b) || isEarWhite(r, g, b)) {
        continue;
      }
      if (!isYellowHue(r, g, b)) {
        continue;
      }
      xs.push(x);
      ys.push(y);
      break;
    }
  }
  if (xs.length < 12) {
    return 0;
  }
  const n = xs.length;
  let sx = 0;
  let sy = 0;
  let syy = 0;
  let sxy = 0;
  for (let i = 0; i < n; i += 1) {
    sx += xs[i];
    sy += ys[i];
    syy += ys[i] * ys[i];
    sxy += xs[i] * ys[i];
  }
  const den = n * syy - sy * sy;
  if (Math.abs(den) < 1) {
    return 0;
  }
  const slope = (n * sxy - sy * sx) / den;
  return (Math.atan(slope) * 180) / Math.PI;
}

/**
 * Inner printed rectangle tilt. Prefer the left/right join (the line Giuseppe
 * looks at). Fall back to the top Theil–Sen join. Gold foil-to-edge has no
 * inner join — use the silhouette against paper/matte, then the printed
 * name/attack baselines if the AABB already ate the outer tilt. Do not
 * use the AABB outer edge after a tight crop, and do not chase the art.
 */
function innerRectangleSkewDegrees(rgba, width, height, channels = 4, options = {}) {
  if (options.family === 'silver' || options.family === 'other') {
    const outer = estimateOuterSilhouetteSkewDegrees(rgba, width, height, channels);
    if (
      Number.isFinite(outer) &&
      Math.abs(outer) >= STUDIO_DESKEW_MIN_DEG &&
      Math.abs(outer) <= STUDIO_DESKEW_MAX_DEG
    ) {
      return outer;
    }
    // Upright silver/other frame. Yellow join is collage (Totodile MEP), not tilt.
    return 0;
  }
  if (options.goldFoil) {
    return estimateGoldFoilDeskewDegrees(rgba, width, height, channels);
  }
  const vertical = estimateVerticalInnerJoinSkewDegrees(rgba, width, height, channels);
  if (
    Number.isFinite(vertical) &&
    Math.abs(vertical) >= STUDIO_DESKEW_MIN_DEG &&
    Math.abs(vertical) <= STUDIO_DESKEW_MAX_DEG
  ) {
    return vertical;
  }
  const top = estimateInnerJoinSkewDegrees(rgba, width, height, channels);
  if (Number.isFinite(top) && Math.abs(top) >= STUDIO_DESKEW_MIN_DEG && Math.abs(top) <= STUDIO_DESKEW_MAX_DEG) {
    return top;
  }
  return 0;
}

function studioTiltDegrees(rgba, width, height, channels = 4) {
  return innerRectangleSkewDegrees(rgba, width, height, channels);
}

function shouldDeskewInnerRectangle(filename) {
  return !isBorderlessTreatment(filename);
}

function contentBoxExcludingStudioWhite(rgba, width, height) {
  const seed = sampleBorderBackground(rgba, width, height);
  const dropBackdrop = isStudioBackdropSample(seed);
  let minX = width;
  let minY = height;
  let maxX = 0;
  let maxY = 0;
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 4;
      if (rgba[i + 3] < 40) {
        continue;
      }
      if (dropBackdrop && matchesBorderBackground(rgba[i], rgba[i + 1], rgba[i + 2], seed)) {
        continue;
      }
      if (x < minX) {
        minX = x;
      }
      if (y < minY) {
        minY = y;
      }
      if (x > maxX) {
        maxX = x;
      }
      if (y > maxY) {
        maxY = y;
      }
    }
  }
  if (maxX < minX || maxY < minY) {
    return null;
  }
  return { left: minX, top: minY, width: maxX - minX + 1, height: maxY - minY + 1 };
}

function extractRgbaBox(rgba, width, box) {
  const out = Buffer.alloc(box.width * box.height * 4);
  for (let y = 0; y < box.height; y += 1) {
    const src = ((box.top + y) * width + box.left) * 4;
    rgba.copy(out, y * box.width * 4, src, src + box.width * 4);
  }
  return out;
}

/**
 * Rotate until the inner printed rectangle is upright. Vertical join wins
 * over the top name-bar (Swampert evo-box step). Gold HR deskews on the
 * card silhouette against paper — not the illustration — then die-cut only.
 */
async function deskewStudioDiecut(rgba, width, height, sharp, options = {}) {
  const goldFoil = Boolean(options.goldFoil);
  const matte = options.matte || DEFAULT_MATTE;
  const initial = innerRectangleSkewDegrees(rgba, width, height, 4, {
    goldFoil,
    family: options.family,
  });
  if (
    !Number.isFinite(initial) ||
    Math.abs(initial) < STUDIO_DESKEW_MIN_DEG ||
    Math.abs(initial) > STUDIO_DESKEW_MAX_DEG
  ) {
    return { rgba, width, height, applied: 0 };
  }
  let buf = await sharp(rgba, { raw: { width, height, channels: 4 } }).png().toBuffer();
  let last = initial;
  let applied = 0;
  for (let i = 0; i < STUDIO_DESKEW_ITERS; i += 1) {
    const raw = await sharp(buf).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    const matteBacking =
      goldFoil && isMarketplaceMatteBacking(raw.data, raw.info.width, raw.info.height);
    const rotateBackground = matteBacking
      ? { r: matte.r, g: matte.g, b: matte.b, alpha: 1 }
      : { r: 255, g: 255, b: 255, alpha: 1 };
    const bright = goldFoil
      ? estimateStraightBorderSkewDegrees(raw.data, raw.info.width, raw.info.height)
      : Number.NaN;
    const deg = goldFoil
      ? estimateGoldFoilDeskewDegrees(raw.data, raw.info.width, raw.info.height)
      : (() => {
          const vertical = estimateVerticalInnerJoinSkewDegrees(raw.data, raw.info.width, raw.info.height);
          const top = estimateInnerJoinSkewDegrees(raw.data, raw.info.width, raw.info.height);
          const verticalUsable = Number.isFinite(vertical) && Math.abs(vertical) <= STUDIO_DESKEW_MAX_DEG;
          if (verticalUsable && Math.abs(vertical) < STUDIO_DESKEW_DONE_DEG) {
            return 0;
          }
          return verticalUsable && Math.abs(vertical) >= STUDIO_DESKEW_DONE_DEG ? vertical : top;
        })();
    if (
      matteBacking &&
      Number.isFinite(bright) &&
      Math.abs(bright) < STUDIO_DESKEW_DONE_DEG
    ) {
      break;
    }
    if (!Number.isFinite(deg) || Math.abs(deg) < STUDIO_DESKEW_DONE_DEG || Math.abs(deg) > STUDIO_DESKEW_MAX_DEG) {
      break;
    }
    if (i > 0 && Math.abs(deg) > Math.abs(last) * 1.15 && Math.sign(deg) !== Math.sign(last) && last !== 0) {
      break;
    }
    const brightLed =
      matteBacking &&
      Number.isFinite(bright) &&
      Math.abs(bright) >= STUDIO_DESKEW_MIN_DEG &&
      Math.abs(bright) <= STUDIO_DESKEW_MAX_DEG;
    const step = -deg * (brightLed ? 1 : goldFoil ? 0.8 : STUDIO_DESKEW_DAMP);
    buf = await sharp(buf)
      .rotate(step, { background: rotateBackground })
      .png()
      .toBuffer();
    applied += step;
    last = deg;
  }
  const raw = await sharp(buf).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  let out = Buffer.from(raw.data);
  let w = raw.info.width;
  let h = raw.info.height;
  const box = contentBoxExcludingStudioWhite(out, w, h);
  if (box && box.width >= 40 && box.height >= 40 && (box.width < w - 2 || box.height < h - 2)) {
    out = extractRgbaBox(out, w, box);
    w = box.width;
    h = box.height;
  }
  if (goldFoil) {
    const tight = tightStraightBorderBox(out, w, h);
    if (tight) {
      out = extractRgbaBox(out, w, tight);
      w = tight.width;
      h = tight.height;
    }
  }
  return { rgba: out, width: w, height: h, applied };
}

async function sanitizeCardImage(input, options = {}) {
  const enabled = options.enabled !== false;
  if (!enabled) {
    return { body: input, skipped: true, reason: 'disabled' };
  }

  const sharp = loadSharp(options.sharp);
  if (!sharp) {
    return { body: input, skipped: true, reason: 'sharp-missing' };
  }
  if (!Buffer.isBuffer(input) || input.length < 256) {
    return { body: input, skipped: true, reason: 'too-small' };
  }

  const radiusRatio = options.radiusRatio || DEFAULT_CORNER_RADIUS_RATIO;
  const matte = options.matte || DEFAULT_MATTE;
  const jpegQuality = options.jpegQuality || DEFAULT_JPEG_QUALITY;
  const format = outputFormatFrom(options.outputFormat || options.format);

  const base = sharp(input, { failOn: 'none' }).rotate();
  const metadata = await base.clone().metadata();
  if (metadata.format === 'gif' || !metadata.width || !metadata.height) {
    return { body: input, skipped: true, reason: 'unsupported-format', format: metadata.format };
  }

  const raw = await base.clone().raw().toBuffer({ resolveWithObject: true });
  const letterbox = detectLetterbox(raw.data, raw.info.width, raw.info.height, raw.info.channels);
  const workingRaw = letterbox
    ? await base.clone().extract(letterbox).raw().toBuffer({ resolveWithObject: true })
    : raw;
  let width = workingRaw.info.width;
  let height = workingRaw.info.height;
  let rgba = toRgba(workingRaw.data, width, height, workingRaw.info.channels);
  punchPartialAlphaRgba(rgba);
  if (!isCardRaster(options, width, height)) {
    const box = contentBoxExcludingStudioWhite(rgba, width, height);
    const studioCard =
      box &&
      box.width >= 40 &&
      box.height >= 40 &&
      (box.width < width - 8 || box.height < height - 8) &&
      isCardRaster({}, box.width, box.height);
    if (!studioCard) {
      return { body: input, skipped: true, reason: 'not-a-card', format: catalogFormat(metadata.format) };
    }
  }
  let radius = cornerRadiusPx(width, height, radiusRatio);
  let outline = sampleOutlineColor(rgba, width, height, 4);
  let thickness = outline ? measureSideThickness(rgba, width, height, outline) : null;
  let cornerKind = detectCornerKind(rgba, width, height, outline);
  let goldFoil =
    isGoldFoilRaster(rgba, width, height, 4, thickness) && outlineFamily(outline) !== 'silver';
  const filename = options.filename || options.key;
  let deskewDeg = 0;
  let innerAfterDeskew = 0;
  if (options.skipDeskew !== true && shouldDeskewInnerRectangle(filename)) {
    const deskewed = await deskewStudioDiecut(rgba, width, height, sharp, {
      goldFoil,
      matte,
      family: outlineFamily(outline),
    });
    if (deskewed.applied) {
      rgba = deskewed.rgba;
      width = deskewed.width;
      height = deskewed.height;
      radius = cornerRadiusPx(width, height, radiusRatio);
      deskewDeg = deskewed.applied;
      innerAfterDeskew = goldFoil
        ? estimateStraightBorderSkewDegrees(rgba, width, height)
        : estimateVerticalInnerJoinSkewDegrees(rgba, width, height);
      if (!Number.isFinite(innerAfterDeskew)) {
        innerAfterDeskew = estimateInnerJoinSkewDegrees(rgba, width, height);
      }
      outline = sampleOutlineColor(rgba, width, height, 4);
      thickness = outline ? measureSideThickness(rgba, width, height, outline) : thickness;
      cornerKind = detectCornerKind(rgba, width, height, outline);
      goldFoil = goldFoil || isGoldFoilRaster(rgba, width, height, 4, thickness);
    }
  }
  if (!isCardRaster({}, width, height)) {
    outline = sampleOutlineColor(rgba, width, height, 4) || outline;
    punchConnectedStudioWhite(rgba, width, height, outline);
    const cardBox = contentBoxExcludingStudioWhite(rgba, width, height);
    if (
      cardBox &&
      cardBox.width >= 40 &&
      cardBox.height >= 40 &&
      (cardBox.width < width - 2 || cardBox.height < height - 2)
    ) {
      rgba = extractRgbaBox(rgba, width, cardBox);
      width = cardBox.width;
      height = cardBox.height;
      radius = cornerRadiusPx(width, height, radiusRatio);
    }
    outline = sampleOutlineColor(rgba, width, height, 4) || outline;
    thickness = outline ? measureSideThickness(rgba, width, height, outline) : thickness;
    cornerKind = detectCornerKind(rgba, width, height, outline);
    goldFoil = goldFoil || isGoldFoilRaster(rgba, width, height, 4, thickness);
  }
  const job = classifyRebuildJob({
    filename,
    width,
    height,
    cornerKind,
    outline,
    thickness,
    goldFoil,
  });
  job.deskewDeg = deskewDeg;
  if (deskewDeg) {
    job.innerAfterDeskew = innerAfterDeskew;
  }
  const usesAlpha = format === 'png' || format === 'webp';
  let punched = 0;
  let filled = 0;
  let pad = 0;
  let outWidth = width;
  let outHeight = height;
  let pipeline;
  if (usesAlpha) {
    punched =
      punchCornerEars(rgba, width, height, outline) +
      punchPerimeterFringe(rgba, width, height, outline, 2);
    punched += punchHaloAlongRound(rgba, width, height, radius, 3, outline);
    fillInsideRoundCaps(rgba, width, height, radius, outline);
    applySupersampledRoundedRectAlpha(rgba, width, height, radius);
    pipeline = sharp(rgba, {
      raw: {
        width,
        height,
        channels: 4,
      },
    });
  } else {
    const borderless = isBorderlessTreatment(options.filename || options.key);
    const family = outlineFamily(outline);
    // Gold HR family is "yellow"; leftover keys omit hyper-rare. Keep CT
    // foil pixels (punch + round only). Do not weld the metallic highlight
    // into saturated outline yellow.
    const keepOriginalRaster =
      job.reason === 'gold-foil' ||
      job.reason === 'borderless-treatment' ||
      job.reason === 'studio-diecut' ||
      (job.action === 'diecut-only' && family !== 'yellow' && family !== 'gold-pale');
    if (keepOriginalRaster) {
      // Yellow studio-diecut used to paintStraightFrame + weld the washed
      // JPEG outline (Milotic League 257448). The rim is already there;
      // punch the white surround and round. Do not fillInsideRoundCaps —
      // that paints outline back into the punched ring.
      if (job.reason === 'studio-diecut') {
        punched = punchConnectedStudioWhite(rgba, width, height, outline);
        const cardBox = contentBoxExcludingStudioWhite(rgba, width, height);
        if (
          cardBox &&
          cardBox.width >= 40 &&
          cardBox.height >= 40 &&
          (cardBox.width < width - 2 || cardBox.height < height - 2)
        ) {
          rgba = extractRgbaBox(rgba, width, cardBox);
          width = cardBox.width;
          height = cardBox.height;
          radius = cornerRadiusPx(width, height, radiusRatio);
        }
        outline = sampleOutlineColor(rgba, width, height, 4) || outline;
        thickness = outline ? measureSideThickness(rgba, width, height, outline) : thickness;
        const clipped = rimLooksClipped(thickness, Math.min(width, height), outline, {
          afterPunch: Boolean(deskewDeg),
        });
        if (clipped && outlineFamily(outline) === 'yellow') {
          job.clippedAfterDeskew = true;
          const stripped = stripPrintedRim(rgba, width, height);
          const rebuilt = rebuildEvenOuterBorder(
            stripped.rgba,
            stripped.width,
            stripped.height,
            radiusRatio,
            outline,
            { top: 0, bottom: 0, left: 0, right: 0 },
            {
              allowPad: true,
              paintFrame: true,
              weldToOutline: true,
              forceEraPad: true,
            },
          );
          filled = rebuilt.filled;
          pad = rebuilt.pad;
          punched = 0;
          outWidth = rebuilt.outWidth || rebuilt.width;
          outHeight = rebuilt.outHeight || rebuilt.height;
          radius = rebuilt.radius;
          pipeline = sharp(rebuilt.rgba, {
            raw: {
              width: rebuilt.width,
              height: rebuilt.height,
              channels: 4,
            },
          });
          if (rebuilt.superSample > 1) {
            pipeline = pipeline.resize(outWidth, outHeight, { kernel: 'lanczos3' });
          }
          width = outWidth;
          height = outHeight;
        } else {
          applySupersampledRoundedRectAlpha(rgba, width, height, radius);
          pipeline = sharp(rgba, {
            raw: {
              width,
              height,
              channels: 4,
            },
          });
        }
      } else {
        // Gold HR on white studio paper (Charizard 713832 1000×1000 scan):
        // punch the surround and crop. Do not fillInsideRoundCaps — that
        // paints outline gold into the ears. Do not rebuild a yellow frame.
        if (job.reason === 'gold-foil') {
          punched += punchConnectedStudioWhite(rgba, width, height, outline);
          const tight = tightStraightBorderBox(rgba, width, height);
          const cardBox = tight || contentBoxExcludingStudioWhite(rgba, width, height);
          if (
            cardBox &&
            cardBox.width >= 40 &&
            cardBox.height >= 40 &&
            (cardBox.width < width - 2 || cardBox.height < height - 2)
          ) {
            rgba = extractRgbaBox(rgba, width, cardBox);
            width = cardBox.width;
            height = cardBox.height;
            radius = cornerRadiusPx(width, height, radiusRatio);
          }
        }
        if (job.reason === 'already-rounded') {
          applySupersampledRoundedRectAlpha(rgba, width, height, radius, ROUND_SUPER_SAMPLE, {
            lockPrinted: true,
            outline,
          });
          paintMatteJpegGuard(rgba, width, height, matte, radius);
        } else {
          const fringeOutline = job.reason === 'gold-foil' ? null : outline;
          punched += punchPerimeterFringe(rgba, width, height, fringeOutline, 2);
          punched += punchHaloAlongRound(rgba, width, height, radius, 3, fringeOutline);
          applySupersampledRoundedRectAlpha(rgba, width, height, radius);
          punched += punchPerimeterFringe(rgba, width, height, fringeOutline, 2);
          punched += punchHaloAlongRound(rgba, width, height, radius, 3, fringeOutline);
          punched += punchSilhouetteLightFringe(rgba, width, height, 3, 195, matte, fringeOutline);
          paintMatteJpegGuard(rgba, width, height, matte, radius);
        }
        pipeline = sharp(rgba, {
          raw: {
            width,
            height,
            channels: 4,
          },
        });
      }
    } else {
      const rebuilt = rebuildEvenOuterBorder(rgba, width, height, radiusRatio, outline, thickness, {
        allowPad: job.action === 'rebuild-frame',
        paintFrame: !borderless && (job.action === 'rebuild-frame' || family === 'yellow'),
        weldToOutline: !borderless && (family === 'yellow' || family === 'gold-pale'),
      });
      filled = rebuilt.filled;
      pad = rebuilt.pad;
      outWidth = rebuilt.outWidth || rebuilt.width;
      outHeight = rebuilt.outHeight || rebuilt.height;
      radius = rebuilt.radius;
      pipeline = sharp(rebuilt.rgba, {
        raw: {
          width: rebuilt.width,
          height: rebuilt.height,
          channels: 4,
        },
      });
      if (rebuilt.superSample > 1) {
        pipeline = pipeline.resize(outWidth, outHeight, { kernel: 'lanczos3' });
      }
      width = outWidth;
      height = outHeight;
    }
  }

  const encoded = await encodeSanitized(pipeline, format, {
    matte,
    jpegQuality,
  });

  return {
    body: encoded.body,
    format: encoded.format,
    width,
    height,
    radius,
    letterbox,
    outline,
    thickness,
    cornerKind,
    filled,
    punched,
    pad,
    job,
    skipped: false,
  };
}

async function prepareCatalogImage(input, ext, options = {}) {
  const envOptions = options.env ? sanitizeOptionsFromEnv(options.env) : sanitizeOptionsFromEnv();
  if (!envOptions.enabled && options.enabled !== true) {
    return { body: input, ext: catalogFormat(ext), skipped: true, reason: 'disabled' };
  }
  const result = await sanitizeCardImage(input, {
    ...envOptions,
    ...options,
    outputFormat: options.outputFormat || envOptions.outputFormat || DEFAULT_OUTPUT_FORMAT,
  });
  if (result.skipped) {
    return { body: input, ext: catalogFormat(ext), skipped: true, reason: result.reason };
  }
  return {
    body: result.body,
    ext: result.format || catalogFormat(ext),
    skipped: false,
    width: result.width,
    height: result.height,
    radius: result.radius,
    letterbox: result.letterbox,
    outline: result.outline,
    thickness: result.thickness,
    cornerKind: result.cornerKind,
    filled: result.filled,
    punched: result.punched,
    pad: result.pad,
  };
}

module.exports = {
  POKER_ASPECT,
  POKER_WIDTH_MM,
  POKER_HEIGHT_MM,
  POKER_CORNER_RADIUS_MM,
  OFFICIAL_CORNER_RADIUS_RATIO,
  DEFAULT_CORNER_RADIUS_RATIO,
  CSS_CORNER_RADIUS_Y,
  dieCutCornerCenter,
  inDieCutCrescent,
  inDieCutCap,
  DEFAULT_OUTPUT_FORMAT,
  DEFAULT_MATTE,
  LOSSLESS_PNG_OPTIONS,
  parseMatte,
  catalogFormat,
  outputFormatFrom,
  sanitizeOptionsFromEnv,
  detectLetterbox,
  isCardRaster,
  cornerRadiusPx,
  sampleOutlineColor,
  detectCornerKind,
  measureSideThickness,
  rebuildOuterBorder,
  rebuildEvenOuterBorder,
  padToUnpinch,
  paddedFrameThickness,
  targetFramePx,
  outlineFamily,
  parseCollectorOverNumber,
  isBorderlessTreatment,
  isGoldFoilRaster,
  GOLD_FOIL_YELLOW_FRACTION,
  classifyRebuildJob,
  belongsToPrintedRim,
  FRAME_RATIO,
  WIZARDS_YELLOW_RATIO,
  WIZARDS_YELLOW_SIDE_MM,
  ROUND_SUPER_SAMPLE,
  paintStraightFrame,
  punchPerimeterFringe,
  punchConnectedStudioWhite,
  sampleBorderBackground,
  punchHaloAlongRound,
  paintMatteJpegGuard,
  punchSilhouetteLightFringe,
  estimateInnerJoinSkewDegrees,
  estimateVerticalInnerJoinSkewDegrees,
  estimateOuterSilhouetteSkewDegrees,
  estimateBrightOuterEdgeSkewDegrees,
  estimateStraightBorderSkewDegrees,
  fitStraightBorder,
  tightStraightBorderBox,
  estimateGoldFoilDeskewDegrees,
  estimatePrintedLayoutSkewDegrees,
  innerRectangleSkewDegrees,
  shouldDeskewInnerRectangle,
  isWarmWashedYellow,
  applyHardRoundedRectAlpha,
  applySupersampledRoundedRectAlpha,
  fillInsideRoundCaps,
  sanitizeCardImage,
  prepareCatalogImage,
};
