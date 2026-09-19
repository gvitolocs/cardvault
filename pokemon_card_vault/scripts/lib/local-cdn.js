'use strict';

/**
 * Local exact copy of R2 `cardvault-images`. Keys match leftover
 * `{ct_id}_{slug}`. Catalog work reads this tree instead of downloading
 * from cdn.pokoin.com; every R2 PutObject must write the same key here.
 */

const fs = require('node:fs');
const path = require('node:path');

const DEFAULT_LOCAL_CDN = '/home/nez/Projects/pokoin/PokoinTest/index/cdn_images';

function indexLocalCdn(dir) {
  const byCt = new Map();
  if (!dir || !fs.existsSync(dir)) {
    return byCt;
  }
  for (const name of fs.readdirSync(dir)) {
    const match = name.match(/^(\d+)_.+\.(jpe?g|webp|png)$/i);
    if (!match || /_homepage\./i.test(name)) {
      continue;
    }
    const list = byCt.get(match[1]) || [];
    list.push(name);
    byCt.set(match[1], list);
  }
  return byCt;
}

function catalogNamesFor(index, ctId) {
  return (index.get(String(ctId)) || []).filter((name) => !name.startsWith('previews/'));
}

function resolveLocalCdnFile(localDir, key, ctId, index) {
  const clean = String(key || '').replace(/^\/+/, '');
  if (clean && !clean.includes('..')) {
    const exact = path.join(localDir, clean);
    if (fs.existsSync(exact) && fs.statSync(exact).isFile()) {
      return { path: exact, matched: clean, how: 'exact' };
    }
  }
  const names = catalogNamesFor(index, ctId);
  const jpegs = names.filter((name) => /\.jpe?g$/i.test(name));
  const pool = jpegs.length ? jpegs : names;
  if (!pool.length) {
    return null;
  }
  if (clean) {
    const stem = clean.replace(/\.[^.]+$/, '');
    const stemHit = pool.find((name) => name.replace(/\.[^.]+$/, '') === stem);
    if (stemHit) {
      return { path: path.join(localDir, stemHit), matched: stemHit, how: 'stem' };
    }
  }
  if (pool.length === 1) {
    return { path: path.join(localDir, pool[0]), matched: pool[0], how: 'ct-id' };
  }
  pool.sort((a, b) => b.length - a.length);
  return { path: path.join(localDir, pool[0]), matched: pool[0], how: 'ct-id-longest' };
}

function writeLocalCdnObject(localDir, key, body) {
  if (!localDir || !key || !body) {
    return null;
  }
  const clean = String(key).replace(/^\/+/, '');
  if (!clean || clean.includes('..')) {
    return null;
  }
  const dest = path.join(localDir, clean);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, body);
  return dest;
}

function findExactLocal(roots, key) {
  const clean = String(key || '').replace(/^\/+/, '');
  if (!clean || clean.includes('..')) {
    return null;
  }
  for (const root of roots || []) {
    if (!root) {
      continue;
    }
    const dest = path.join(root, clean);
    if (fs.existsSync(dest) && fs.statSync(dest).isFile()) {
      return { path: dest, matched: clean, how: 'exact', root };
    }
  }
  return null;
}

module.exports = {
  DEFAULT_LOCAL_CDN,
  indexLocalCdn,
  resolveLocalCdnFile,
  writeLocalCdnObject,
  findExactLocal,
};
