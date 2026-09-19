#!/usr/bin/env node

/**
 * One sample card per marketplace expansion vs pokemontcg.io hires.
 * Pixel size decides obvious downloads. Qwen VL (local qwen3-vl:32b) judges
 * close calls. Writes JPEG catalog files only when --write. Never uploads R2.
 *
 *   node scripts/compare-expansion-samples.js
 *   node scripts/compare-expansion-samples.js --qwen --qwen-limit=20
 */

'use strict';

const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
const {
  resolvePokemontcgHires,
  absoluteCdnUrl,
  pngDimensionsFromPrefix,
  isBetterDefinition,
  catalogJpegFromPokemontcgPng,
} = require('./lib/pokemontcg-hires');
const { loadPokemontcgSets, indexPokemontcgSets, matchPokemontcgSet } = require('./lib/pokemontcg-sets');
const { shouldAskQwen, qwenCompareCardImages } = require('./lib/qwen-card-compare');
const { sanitizeCardImage } = require('./lib/sanitize-card-image');

const API = 'https://api.pokoin.com/api/marketplace-expansion-page';
const DEFAULT_OUT = '/tmp/pokemontcg-expansion-samples';
const UA = 'Pokoin expansion sample compare';

function parseArgs(argv) {
  const options = {
    qwen: false,
    qwenLimit: 24,
    write: false,
    limit: Infinity,
    out: DEFAULT_OUT,
    concurrency: 4,
  };
  for (const arg of argv) {
    if (arg === '--qwen') {
      options.qwen = true;
    } else if (arg === '--write') {
      options.write = true;
    } else if (arg.startsWith('--qwen-limit=')) {
      options.qwenLimit = Math.max(1, Number(arg.slice('--qwen-limit='.length)) || 24);
    } else if (arg.startsWith('--limit=')) {
      options.limit = Math.max(1, Number(arg.slice('--limit='.length)) || 1);
    } else if (arg.startsWith('--out=')) {
      options.out = arg.slice('--out='.length) || DEFAULT_OUT;
    } else if (arg.startsWith('--concurrency=')) {
      options.concurrency = Math.max(1, Math.min(8, Number(arg.slice('--concurrency='.length)) || 4));
    }
  }
  return options;
}

async function fetchJson(url) {
  const response = await fetch(url, { headers: { Accept: 'application/json', 'User-Agent': UA } });
  if (!response.ok) {
    throw new Error(`${response.status} ${url}`);
  }
  return response.json();
}

async function fetchBuffer(url, range) {
  const headers = { 'User-Agent': UA };
  if (range) {
    headers.Range = range;
  }
  const response = await fetch(url, { headers });
  if (!response.ok) {
    throw new Error(`${response.status} ${url}`);
  }
  return Buffer.from(await response.arrayBuffer());
}

async function pngSize(url, cache) {
  if (cache.has(url)) {
    return cache.get(url);
  }
  const prefix = await fetchBuffer(url, 'bytes=0-31');
  const size = pngDimensionsFromPrefix(prefix);
  cache.set(url, size);
  return size;
}

async function jpegSize(url, cache) {
  if (!url) {
    return null;
  }
  if (cache.has(url)) {
    return cache.get(url);
  }
  try {
    const body = await fetchBuffer(url);
    const meta = await sharp(body, { failOn: 'none' }).metadata();
    const size = meta.width && meta.height
      ? { width: meta.width, height: meta.height, bytes: body.length, body }
      : null;
    cache.set(url, size);
    return size;
  } catch {
    cache.set(url, null);
    return null;
  }
}

async function mapPool(items, concurrency, worker) {
  const results = new Array(items.length);
  let index = 0;
  async function run() {
    while (index < items.length) {
      const current = index;
      index += 1;
      results[current] = await worker(items[current], current);
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, Math.max(1, items.length)) }, () => run()));
  return results;
}

async function sampleCard(expansion) {
  const tryFetch = async (params) => {
    const payload = await fetchJson(`${API}?${params}`);
    return (payload.cards || []).find((card) => String(card.productType || 'card') === 'card') || null;
  };
  const base = { productType: 'card', limit: '20', offset: '0' };
  if (expansion.slug) {
    try {
      const bySlug = new URLSearchParams({ ...base, slug: expansion.slug });
      const card = await tryFetch(bySlug);
      if (card) {
        return card;
      }
    } catch (_) {
      /* slug with & often 404s; fall back to the expansion name. */
    }
  }
  const byName = new URLSearchParams({ ...base, expansionName: expansion.name });
  return tryFetch(byName);
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const sets = await loadPokemontcgSets();
  const index = indexPokemontcgSets(sets);
  const listed = ((await fetchJson(`${API}?limit=2000`)).expansions || []).slice(0, options.limit);
  const pngCache = new Map();
  const jpegCache = new Map();
  const rows = [];
  let qwenUsed = 0;

  if (options.write) {
    fs.mkdirSync(options.out, { recursive: true });
  }

  await mapPool(listed, options.concurrency, async (expansion) => {
    const match = matchPokemontcgSet(expansion.name, index);
    const row = {
      expansion: expansion.name,
      slug: expansion.slug || '',
      cardCount: expansion.cardCount || 0,
      setId: match.setId,
      map: match.reason,
    };
    if (!match.setId) {
      row.action = 'unmapped';
      rows.push(row);
      return;
    }
    let card = null;
    try {
      card = await sampleCard(expansion);
    } catch (error) {
      row.error = String(error.message || error);
      row.action = 'error';
      rows.push(row);
      return;
    }
    if (!card) {
      row.action = 'no-card';
      rows.push(row);
      return;
    }
    const hires = resolvePokemontcgHires({
      ...card,
      set: expansion.name,
      setId: match.setId,
    });
    row.sample = card.name;
    row.id = card.id;
    row.number = hires.number;
    if (!hires.url) {
      row.action = 'no-number';
      rows.push(row);
      return;
    }
    try {
      const api = await pngSize(hires.url, pngCache);
      const oursUrl = absoluteCdnUrl(card.gridImageUrl || card.heroImageUrl || card.imageUrl);
      const ours = await jpegSize(oursUrl, jpegCache);
      const apiArea = api ? api.width * api.height : 0;
      const ourArea = ours ? ours.width * ours.height : 0;
      row.api = api ? `${api.width}x${api.height}` : 'missing';
      row.ours = ours ? `${ours.width}x${ours.height}` : 'missing';
      row.ratio = ourArea ? Math.round((apiArea / ourArea) * 100) / 100 : null;
      row.better = isBetterDefinition(api, ours);
      row.apiUrl = hires.url;
      row.action = row.better ? 'download' : 'keep';
      if (
        options.qwen &&
        qwenUsed < options.qwenLimit &&
        ours &&
        ours.body &&
        shouldAskQwen({ better: row.better, ratio: row.ratio, mapped: true })
      ) {
        qwenUsed += 1;
        const apiPng = await fetchBuffer(hires.url);
        const judged = await qwenCompareCardImages({
          oursJpeg: ours.body,
          apiBytes: apiPng,
          name: card.name,
          set: expansion.name,
          sharp,
        });
        row.qwen = judged;
        if (judged.same_card === false) {
          row.action = 'mismatch';
        } else if (judged.winner === 'api') {
          row.action = 'download';
        } else if (judged.winner === 'ours') {
          row.action = 'keep';
        }
      }
      if (options.write && row.action === 'download' && hires.url) {
        const png = await fetchBuffer(hires.url);
        const encoded = await catalogJpegFromPokemontcgPng(png, {
          sharp,
          sanitizeCardImage,
          filename: `${card.id}.jpg`,
        });
        const file = `${card.id}_${String(card.name || 'card').toLowerCase().replace(/[^a-z0-9]+/g, '-').slice(0, 60)}.jpg`;
        fs.writeFileSync(path.join(options.out, file), encoded.body);
        row.jpeg = file;
      }
    } catch (error) {
      row.error = String(error.message || error);
      row.action = row.action || 'error';
    }
    rows.push(row);
  });

  const summary = {
    expansions: listed.length,
    download: rows.filter((row) => row.action === 'download').length,
    keep: rows.filter((row) => row.action === 'keep').length,
    unmapped: rows.filter((row) => row.action === 'unmapped').length,
    qwen: rows.filter((row) => row.qwen).length,
    mismatch: rows.filter((row) => row.action === 'mismatch').length,
    errors: rows.filter((row) => row.action === 'error').length,
  };
  rows.sort((a, b) => (b.ratio || 0) - (a.ratio || 0));
  fs.mkdirSync(options.out, { recursive: true });
  const report = path.join(options.out, 'expansion-sample-compare.json');
  fs.writeFileSync(report, `${JSON.stringify({ summary, rows }, null, 2)}\n`);
  console.log(JSON.stringify({ ...summary, report, top: rows.filter((row) => row.action === 'download').slice(0, 15) }, null, 2));
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}

module.exports = { parseArgs };
