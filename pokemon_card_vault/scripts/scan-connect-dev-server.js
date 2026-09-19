#!/usr/bin/env node
'use strict';

// Local Scan Connect API for E2E and benchmarks (never production):
//   /api/scan-*  → real handlers on a throwaway Postgres (SCAN_TEST_DATABASE_URL)
//   /api/*       → proxied to https://api.pokoin.com (read-only desk data)
// Desktop auth is faked ONLY with SCAN_DEV_FAKE_AUTH=1: `Bearer seller:<uid>`.
//
//   SCAN_TEST_DATABASE_URL=postgres://postgres:scantest@127.0.0.1:55432/scantest \
//   SCAN_DEV_FAKE_AUTH=1 PORT=18990 node scripts/scan-connect-dev-server.js --reset

const fs = require('fs');
const http = require('http');
const path = require('path');

const DB_URL = process.env.SCAN_TEST_DATABASE_URL || '';
const PORT = Number(process.env.PORT || 18990);
const UPSTREAM = process.env.SCAN_DEV_UPSTREAM || 'https://api.pokoin.com';

if (!DB_URL || process.env.SCAN_DEV_FAKE_AUTH !== '1' || process.env.NODE_ENV === 'production') {
  console.error('Refusing to start: needs SCAN_TEST_DATABASE_URL, SCAN_DEV_FAKE_AUTH=1, and NODE_ENV != production.');
  process.exit(2);
}

// A tiny catalog for recognition rows. Public ids from docs/VERSIONS.md so art
// and price series resolve against production reads; names are fixtures.
const FIXTURE_CARDS = {
  '220962': { name: 'Espurr', setName: 'Fixture set', number: '001', nationality: '' },
  '504600': { name: 'Pikachu δ', setName: 'PCG Promos', number: 'PCG-P 112', nationality: 'japanese' },
  '233564': { name: 'Pikachu δ', setName: 'EX Legend Maker', number: '093/92', nationality: 'western' },
  '233090': { name: 'Pikachu δ', setName: 'EX Holon Phantoms', number: '079/110', nationality: 'western' },
  '240808': { name: 'Tapu Lele GX', setName: 'Guardians Rising', number: '60/145', nationality: 'western' },
  '241092': { name: 'Tapu Lele GX', setName: 'Guardians Rising', number: '137/145', nationality: 'western' },
  '227266': { name: 'DP34 promo', setName: 'DP Black Star Promos', number: 'DP34', nationality: 'western' },
  '256260': { name: 'Stormfront 16', setName: 'Stormfront', number: '16/100', nationality: 'western' },
};

async function resetSchema(pool) {
  await pool.query(`
    drop table if exists public.scan_items, public.scan_pairings, public.scan_rate_limits,
      public.scan_sessions, public.scan_batches cascade;
    create table if not exists public.marketplace_user_listings (
      id uuid primary key default gen_random_uuid(), card_id text not null, seller_uid text not null,
      seller_name text not null default 'Pokoin seller', seller_country text not null default 'EU',
      seller_reputation_label text not null default 'New', condition text not null default 'NM',
      language text not null default 'EN', price_pkn numeric not null check (price_pkn > 0),
      quantity_available integer not null default 1, signed boolean not null default false,
      reverse boolean not null default false, first_edition boolean not null default false,
      foil_state text not null default 'standard', variant_state text not null default '',
      sealed boolean not null default false, graded boolean not null default false,
      grading_company text, grade text, certification_id text,
      shipping_available boolean not null default true, reserve_available boolean not null default false,
      nft_available boolean not null default false, seller_comment text not null default '',
      source text not null default 'pokoin_user_listing', source_listing_id text not null default '',
      status text not null default 'active', card_name text not null default '',
      card_image_url text not null default '', set_name text not null default '',
      collector_number text not null default '', created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    );
    delete from public.marketplace_user_listings;
  `);
  await pool.query(fs.readFileSync(path.join(__dirname, '..', 'oracle-postgres', 'schema', '082_scan_connect.sql'), 'utf8'));
}

async function proxy(req, res) {
  if (req.method !== 'GET') {
    res.statusCode = 405;
    return res.end('{"error":"dev proxy is read-only"}');
  }
  try {
    const upstream = await fetch(`${UPSTREAM}${req.url}`, { headers: { accept: req.headers.accept || '*/*' } });
    res.statusCode = upstream.status;
    const type = upstream.headers.get('content-type');
    if (type) res.setHeader('content-type', type);
    res.end(Buffer.from(await upstream.arrayBuffer()));
  } catch (error) {
    res.statusCode = 502;
    res.end(JSON.stringify({ error: error.message }));
  }
}

async function main() {
  const { Pool } = require('pg');
  const pool = new Pool({ connectionString: DB_URL, max: Number(process.env.SCAN_DEV_POOL || 8) });
  if (process.argv.includes('--reset')) await resetSchema(pool);
  const { createStore, setScanStoreForTests } = require('../api/_scan_store');
  setScanStoreForTests(createStore({
    pool,
    lookupCards: async (ids) => new Map(ids.filter((id) => FIXTURE_CARDS[id]).map((id) => [id, { imageUrl: '', ...FIXTURE_CARDS[id] }])),
  }));
  require('../api/_scan_http').setDesktopVerifierForTests(async (req) => {
    const auth = String(req.headers.authorization || '');
    if (!auth.startsWith('Bearer seller:')) {
      throw Object.assign(new Error('Sign in again to use Scan.'), { statusCode: 401 });
    }
    return { uid: auth.slice('Bearer seller:'.length), email: 'e2e@example.com' };
  });
  const { createOracleApiServer } = require('../server/oracle-api-server');
  const api = createOracleApiServer();
  const server = http.createServer((req, res) => {
    if (/^\/api\/scan-(session|pair|phone|batch|stream)(\?|$)/.test(req.url)) {
      api.emit('request', req, res);
      return;
    }
    proxy(req, res);
  });
  server.listen(PORT, '127.0.0.1', () => {
    console.log(`scan-connect dev API on http://127.0.0.1:${PORT} (upstream ${UPSTREAM})`);
  });
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
