const assert = require('node:assert/strict');
const test = require('node:test');
const sharp = require('sharp');
const { pngToMaxJpeg, siblingJpegKey, DARK_MATTE, punchPartialAlphaRgba } = require('./png-to-jpeg');

test('siblingJpegKey swaps extension and skips originals/', () => {
  assert.equal(
    siblingJpegKey('105054_65-poke-doll-mythical-mania-sleeves.png'),
    '105054_65-poke-doll-mythical-mania-sleeves.jpg',
  );
  assert.equal(siblingJpegKey('previews/109972_lugia-ex-full-v4.png'), 'previews/109972_lugia-ex-full-v4.jpg');
  assert.equal(siblingJpegKey('originals/foo.png'), null);
});

test('pngToMaxJpeg writes a JPEG at q100 and flattens alpha', async () => {
  const png = await sharp({
    create: {
      width: 8,
      height: 8,
      channels: 4,
      background: { r: 10, g: 20, b: 30, alpha: 0.5 },
    },
  })
    .png()
    .toBuffer();
  const result = await pngToMaxJpeg(png, { sharp });
  assert.equal(result.hadAlpha, true);
  const jpeg = sharp(result.body);
  const meta = await jpeg.metadata();
  assert.equal(meta.format, 'jpeg');
  assert.equal(meta.hasAlpha, false);
  assert.equal(result.width, 8);
});

test('punchPartialAlphaRgba zeros white stored in transparent pixels', () => {
  const rgba = Buffer.from([255, 255, 255, 0, 255, 255, 255, 120, 80, 80, 80, 255]);
  const punched = punchPartialAlphaRgba(rgba);
  assert.equal(punched, 2);
  assert.equal(rgba[3], 0);
  assert.equal(rgba[7], 0);
  assert.equal(rgba[11], 255);
});

test('punchPartialAlpha drops white AA before dark flatten', async () => {
  const width = 40;
  const height = 56;
  const rgba = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const i = (y * width + x) * 4;
      const inset = Math.min(x, y, width - 1 - x, height - 1 - y);
      if (inset >= 8) {
        rgba[i] = 80;
        rgba[i + 1] = 80;
        rgba[i + 2] = 80;
        rgba[i + 3] = 255;
      } else if (inset >= 6) {
        rgba[i] = 255;
        rgba[i + 1] = 255;
        rgba[i + 2] = 255;
        rgba[i + 3] = 120;
      } else {
        rgba[i] = 255;
        rgba[i + 1] = 255;
        rgba[i + 2] = 255;
        rgba[i + 3] = 0;
      }
    }
  }
  const png = await sharp(rgba, { raw: { width, height, channels: 4 } }).png().toBuffer();
  const result = await pngToMaxJpeg(png, {
    sharp,
    matte: DARK_MATTE,
    punchPartialAlpha: true,
  });
  const { data, info } = await sharp(result.body).raw().toBuffer({ resolveWithObject: true });
  const pix = (x, y) => {
    const i = (y * info.width + x) * info.channels;
    return [data[i], data[i + 1], data[i + 2]];
  };
  assert.ok(pix(0, 0)[0] < 30 && pix(0, 0)[1] < 30, `AABB is dark ${pix(0, 0)}`);
  assert.ok(pix(7, 7)[0] < 50, `partial white ring punched ${pix(7, 7)}`);
  assert.ok(pix(20, 28)[0] > 60, `card face kept ${pix(20, 28)}`);
});
