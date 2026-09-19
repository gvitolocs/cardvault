#!/usr/bin/env node
'use strict';

/**
 * stdin CSV: listing_id,removed_day,blueprint_id
 * stdout CSV: listing_id,removed_day,blueprint_id  (still live on CT blueprint GET)
 *
 * Expansion dump absence is not a sale. Giuseppe 2026-09-14 Glalie 287734.
 */

const { fetchMarketplaceProducts } = require('../api/_cardtrader_client');

function tokenFromEnv(env = process.env) {
  return String(env.CARDTRADER_AUTH_TOKEN || env.CARDTRADER_API_TOKEN || '').trim();
}

function listingIdsFromPayload(payload, blueprintId) {
  const ids = new Set();
  const rows = payload && typeof payload === 'object' && !Array.isArray(payload)
    ? payload[String(blueprintId)] || payload[blueprintId] || []
    : Array.isArray(payload) ? payload : [];
  for (const row of rows) {
    const id = row && (row.id ?? row.product_id ?? row.listing_id);
    if (id != null && id !== '') ids.add(String(id));
  }
  return ids;
}

async function fetchBlueprint(token, blueprintId) {
  const maxAttempts = 6;
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    try {
      return await fetchMarketplaceProducts(token, { blueprint_id: blueprintId });
    } catch (error) {
      const message = String(error && error.message ? error.message : error);
      const retryable = /HTTP 429|HTTP 502|HTTP 503|HTTP 504/.test(message);
      if (!retryable || attempt === maxAttempts) throw error;
      const waitMs = Math.min(30_000, 2000 * 2 ** (attempt - 1));
      process.stderr.write(`retry ${blueprintId} ${message} wait ${waitMs}ms\n`);
      await new Promise((resolve) => setTimeout(resolve, waitMs));
    }
  }
  return {};
}
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return Buffer.concat(chunks).toString('utf8');
}

function parseCsv(text) {
  const byBlueprint = new Map();
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('listing_id')) continue;
    const [listingId, removedDay, blueprintId] = trimmed.split(',');
    const bp = Number(blueprintId);
    const id = String(listingId || '').trim();
    const day = String(removedDay || '').trim();
    if (!id || !day || !Number.isFinite(bp) || bp <= 0) continue;
    if (!byBlueprint.has(bp)) byBlueprint.set(bp, []);
    byBlueprint.get(bp).push({ listingId: id, removedDay: day, blueprintId: bp });
  }
  return byBlueprint;
}

async function main() {
  const token = tokenFromEnv();
  if (token.length < 16) {
    throw new Error('CARDTRADER_AUTH_TOKEN / CARDTRADER_API_TOKEN missing');
  }
  const byBlueprint = parseCsv(await readStdin());
  const concurrency = Math.max(1, Math.min(2, Number(process.env.DUMP_MISS_CONCURRENCY || 1)));
  const delayMs = Math.max(0, Number(process.env.DUMP_MISS_DELAY_MS || 350));
  const blueprints = [...byBlueprint.keys()];
  let next = 0;
  let done = 0;
  const live = [];

  async function worker() {
    while (next < blueprints.length) {
      const index = next;
      next += 1;
      if (index > 0 && delayMs) {
        await new Promise((resolve) => setTimeout(resolve, delayMs));
      }
      const blueprintId = blueprints[index];
      const wanted = byBlueprint.get(blueprintId) || [];
      try {
        const payload = await fetchBlueprint(token, blueprintId);
        const liveIds = listingIdsFromPayload(payload, blueprintId);
        for (const row of wanted) {
          if (liveIds.has(row.listingId)) live.push(row);
        }
      } catch (error) {
        process.stderr.write(`blueprint ${blueprintId} ${error.message}\n`);
      }
      done += 1;
      if (done === 1 || done % 100 === 0 || done === blueprints.length) {
        process.stderr.write(`scanned ${done}/${blueprints.length} live_hits ${live.length}\n`);
      }
    }
  }

  await Promise.all(Array.from({ length: Math.min(concurrency, blueprints.length) }, worker));
  process.stdout.write('listing_id,removed_day,blueprint_id\n');
  for (const row of live) {
    process.stdout.write(`${row.listingId},${row.removedDay},${row.blueprintId}\n`);
  }
}

main().catch((error) => {
  process.stderr.write(`${error && error.stack ? error.stack : error}\n`);
  process.exit(1);
});
