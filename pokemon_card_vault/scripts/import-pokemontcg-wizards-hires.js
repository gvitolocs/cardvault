#!/usr/bin/env node

/**
 * Pull Wizards-era English scans from images.pokemontcg.io when that PNG is
 * sharper than our catalog JPEG. Encode catalog JPEG only (q100, 4:4:4).
 * Default is local files. Does not write R2.
 *
 *   node scripts/import-pokemontcg-wizards-hires.js --dry-run
 *   node scripts/import-pokemontcg-wizards-hires.js --limit=40
 */

'use strict';

const fs = require('node:fs');
const path = require('node:path');
const sharp = require('sharp');
const {
  WIZARDS_EXPANSION_TO_SET,
  pokemontcgSetIdForExpansion,
  resolvePokemontcgHires,
  absoluteCdnUrl,
  pngDimensionsFromPrefix,
  isBetterDefinition,
  catalogJpegFromPokemontcgPng,
} = require('./lib/pokemontcg-hires');
const { sanitizeCardImage } = require('./lib/sanitize-card-image');

const API = 'https://api.pokoin.com/api/marketplace-expansion-page';
const DEFAULT_OUT = '/tmp/pokemontcg-wizards-jpg';
const UA = 'Pokoin pokemontcg-hires jpeg import';

function parseArgs(argv) {
  const options = {
    dryRun: false,
    limit: Infinity,
    out: DEFAULT_OUT,
    concurrency: 4,
    expansion: '',
  };
  for (const arg of argv) {
    if (arg === '--dry-run') {
      options.dryRun = true;
    } else if (arg.startsWith('--limit=')) {
      options.limit = Math.max(1, Number(arg.slice('--limit='.length)) || 1);
    } else if (arg.startsWith('--out=')) {
      options.out = arg.slice('--out='.length) || DEFAULT_OUT;
    } else if (arg.startsWith('--concurrency=')) {
      options.concurrency = Math.max(1, Math.min(8, Number(arg.slice('--concurrency='.length)) || 4));
    } else if (arg.startsWith('--expansion=')) {
      options.expansion = arg.slice('--expansion='.length);
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

async function fetchBuffer(url, { range } = {}) {
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
  if (cache.pngSize.has(url)) {
    return cache.pngSize.get(url);
  }
  const prefix = await fetchBuffer(url, { range: 'bytes=0-31' });
  const fromIhdr = pngDimensionsFromPrefix(prefix);
  const size = fromIhdr || null;
  cache.pngSize.set(url, size);
  return size;
}

async function jpegSize(url, cache) {
  if (!url) {
    return null;
  }
  if (cache.jpegSize.has(url)) {
    return cache.jpegSize.get(url);
  }
  try {
    const body = await fetchBuffer(url);
    const meta = await sharp(body, { failOn: 'none' }).metadata();
    const size = meta.width && meta.height
      ? { width: meta.width, height: meta.height, bytes: body.length }
      : null;
    cache.jpegSize.set(url, size);
    return size;
  } catch {
    cache.jpegSize.set(url, null);
    return null;
  }
}

async function listWizardsExpansions(onlyName) {
  const payload = await fetchJson(`${API}?limit=2000`);
  const listed = payload.expansions || [];
  const wanted = [];
  const seen = new Set();
  for (const row of listed) {
    const name = row.name || row.expansionName || '';
    const setId = pokemontcgSetIdForExpansion(name);
    if (!setId) {
      continue;
    }
    if (onlyName && pokemontcgSetIdForExpansion(onlyName) !== setId && name.toLowerCase() !== onlyName.toLowerCase()) {
      continue;
    }
    const key = `${setId}\0${name}`;
    if (seen.has(key)) {
      continue;
    }
    seen.add(key);
    wanted.push({ name, slug: row.slug || '', setId });
  }
  if (onlyName && !wanted.length) {
    const setId = pokemontcgSetIdForExpansion(onlyName);
    if (setId) {
      wanted.push({ name: onlyName, slug: '', setId });
    }
  }
  if (!wanted.length && !listed.length) {
    for (const [name, setId] of Object.entries(WIZARDS_EXPANSION_TO_SET)) {
      if (name.includes(' ')) {
        wanted.push({ name, slug: '', setId });
      }
    }
  }
  return wanted;
}

async function listExpansionCards(expansion) {
  const cards = [];
  let offset = 0;
  const pageSize = 400;
  for (;;) {
    const params = new URLSearchParams({
      productType: 'card',
      limit: String(pageSize),
      offset: String(offset),
    });
    if (expansion.slug) {
      params.set('slug', expansion.slug);
    } else {
      params.set('expansionName', expansion.name);
    }
    const payload = await fetchJson(`${API}?${params}`);
    const page = (payload.cards || []).filter((card) => String(card.productType || 'card') === 'card');
    cards.push(...page);
    if (page.length < pageSize || payload.hasMore === false) {
      break;
    }
    offset += pageSize;
    if (offset > 8000) {
      break;
    }
  }
  return cards;
}

function jpegFilename(card, setId, number) {
  const id = String(card.id || card.card_id || 'card');
  const slug = String(card.name || 'card')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80);
  return `${id}_${slug || 'card'}-${setId}-${number}.jpg`;
}

async function mapPool(items, concurrency, worker) {
  const results = [];
  let index = 0;
  async function run() {
    while (index < items.length) {
      const current = index;
      index += 1;
      results[current] = await worker(items[current], current);
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, () => run()));
  return results;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const expansions = await listWizardsExpansions(options.expansion);
  const stats = {
    expansions: expansions.length,
    cards: 0,
    mapped: 0,
    better: 0,
    skipped: 0,
    wrote: 0,
    missing: 0,
    errors: 0,
  };
  const log = [];
  const cache = { pngSize: new Map(), jpegSize: new Map(), encode: new Map() };
  if (!options.dryRun) {
    fs.mkdirSync(options.out, { recursive: true });
  }

  for (const expansion of expansions) {
    if (stats.better >= options.limit && !options.dryRun) {
      break;
    }
    if (stats.mapped >= options.limit && options.dryRun && Number.isFinite(options.limit)) {
      break;
    }
    let cards = [];
    try {
      cards = await listExpansionCards(expansion);
    } catch (error) {
      stats.errors += 1;
      log.push({ expansion: expansion.name, error: String(error.message || error) });
      continue;
    }
    stats.cards += cards.length;
    const jobs = [];
    for (const card of cards) {
      const hires = resolvePokemontcgHires({ ...card, expansion_name: expansion.name, set: card.set || expansion.name });
      if (!hires.url) {
        stats.skipped += 1;
        continue;
      }
      stats.mapped += 1;
      jobs.push({ card, expansion, hires });
    }
    await mapPool(jobs, options.concurrency, async (job) => {
      if (!options.dryRun && stats.wrote >= options.limit) {
        return;
      }
      try {
        const apiSize = await pngSize(job.hires.url, cache);
        if (!apiSize) {
          stats.missing += 1;
          return;
        }
        const oursUrl = absoluteCdnUrl(job.card.gridImageUrl || job.card.heroImageUrl || job.card.imageUrl);
        const ours = await jpegSize(oursUrl, cache);
        const better = isBetterDefinition(apiSize, ours);
        const row = {
          id: job.card.id,
          name: job.card.name,
          set: job.expansion.name,
          number: job.hires.number,
          api: `${apiSize.width}x${apiSize.height}`,
          ours: ours ? `${ours.width}x${ours.height}` : 'missing',
          url: job.hires.url,
          better,
        };
        if (!better) {
          stats.skipped += 1;
          log.push(row);
          return;
        }
        stats.better += 1;
        if (options.dryRun) {
          log.push(row);
          return;
        }
        if (stats.wrote >= options.limit) {
          return;
        }
        const sharedKey = `${job.hires.setId}-${job.hires.number}`;
        if (!cache.encode.has(sharedKey)) {
          cache.encode.set(sharedKey, (async () => {
            const png = await fetchBuffer(job.hires.url);
            return catalogJpegFromPokemontcgPng(png, {
              sharp,
              sanitizeCardImage,
              filename: `${job.card.id}_${job.card.name}.jpg`,
            });
          })());
        }
        const encoded = await cache.encode.get(sharedKey);
        const filename = jpegFilename(job.card, job.hires.setId, job.hires.number);
        fs.writeFileSync(path.join(options.out, filename), encoded.body);
        stats.wrote += 1;
        log.push({ ...row, jpeg: filename, jpegSize: encoded.body.length, out: `${encoded.width}x${encoded.height}` });
      } catch (error) {
        stats.errors += 1;
        log.push({
          id: job.card.id,
          name: job.card.name,
          url: job.hires.url,
          error: String(error.message || error),
        });
      }
    });
  }

  const report = { ...stats, dryRun: options.dryRun, out: options.out, sample: log.slice(0, 40) };
  const reportPath = path.join(options.dryRun ? '/tmp' : options.out, 'pokemontcg-wizards-jpg.json');
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, `${JSON.stringify({ ...report, log }, null, 2)}\n`);
  console.log(JSON.stringify(report, null, 2));
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exit(1);
  });
}

module.exports = { parseArgs, jpegFilename };
