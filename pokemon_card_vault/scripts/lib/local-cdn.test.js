'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const {
  DEFAULT_LOCAL_CDN,
  indexLocalCdn,
  resolveLocalCdnFile,
  writeLocalCdnObject,
  findExactLocal,
} = require('./local-cdn');

test('local CDN default is the nezopt catalog mirror', () => {
  assert.equal(DEFAULT_LOCAL_CDN, '/home/nez/Projects/pokoin/PokoinTest/index/cdn_images');
});

test('exact leftover key wins over a different ct_id filename', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'local-cdn-exact-'));
  fs.writeFileSync(path.join(dir, '129834_gengar-mimikyu-gx-rare-ultra-165-181-team-up.jpg'), 'old');
  assert.equal(findExactLocal([dir], '129834_gengar-mimikyu-gx.jpg'), null);
  writeLocalCdnObject(dir, '129834_gengar-mimikyu-gx.jpg', Buffer.from('live'));
  assert.equal(findExactLocal([dir], '129834_gengar-mimikyu-gx.jpg').how, 'exact');
});
