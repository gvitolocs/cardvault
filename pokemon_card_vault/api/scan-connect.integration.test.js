'use strict';

// Scan Connect against a real Postgres through the real Oracle API server
// (routing, body parsing, streaming). Needs a throwaway database:
//
//   SCAN_TEST_DATABASE_URL=postgres://postgres:scantest@127.0.0.1:55432/scantest \
//     node --test api/scan-connect.integration.test.js
//
// Skipped when the variable is unset. Never point it at a real marketplace DB:
// the suite drops and recreates the scan tables.

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { after, before, beforeEach, test } = require('node:test');

const DB_URL = process.env.SCAN_TEST_DATABASE_URL || '';
const skip = !DB_URL ? 'SCAN_TEST_DATABASE_URL not set' : false;

process.env.SCAN_STREAM_MS = process.env.SCAN_STREAM_MS || '1500';
process.env.NODE_ENV = 'test';

let pool;
let server;
let base;
let refreshed = [];

const CARDS = new Map([
  ['220962', { name: 'Espurr', setName: 'Nihil Zero', number: '087/080', imageUrl: '', nationality: 'western' }],
  ['220964', { name: 'Espurr', setName: 'Nihil Zero', number: '032/080', imageUrl: '', nationality: 'western' }],
  ['504600', { name: 'Pikachu δ', setName: 'PCG Promos', number: 'PCG-P 112', imageUrl: '', nationality: 'japanese' }],
  ['233564', { name: 'Pikachu δ', setName: 'Legend Maker', number: '093/92', imageUrl: '', nationality: 'western' }],
]);

const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), crypto.randomBytes(2000)]).toString('base64');

async function resetSchema() {
  await pool.query(`
    drop table if exists public.scan_items, public.scan_pairings, public.scan_rate_limits,
      public.scan_sessions, public.scan_batches, public.marketplace_user_listings cascade;
    create table public.marketplace_user_listings (
      id uuid primary key default gen_random_uuid(),
      card_id text not null, seller_uid text not null,
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
  `);
  const sql = fs.readFileSync(path.join(__dirname, '..', 'oracle-postgres', 'schema', '082_scan_connect.sql'), 'utf8');
  await pool.query(sql);
}

before(async () => {
  if (skip) return;
  const { Pool } = require('pg');
  pool = new Pool({ connectionString: DB_URL, max: 12 });
  await resetSchema();
  const { createStore, setScanStoreForTests } = require('./_scan_store');
  setScanStoreForTests(createStore({
    pool,
    lookupCards: async (ids) => new Map(ids.filter((id) => CARDS.has(id)).map((id) => [id, CARDS.get(id)])),
    onListingsCreated: async (ids) => {
      refreshed.push(...ids);
    },
  }));
  require('./_scan_http').setDesktopVerifierForTests(async (req) => {
    const auth = String(req.headers.authorization || '');
    if (!auth.startsWith('Bearer seller:')) {
      throw Object.assign(new Error('Sign in again to use Scan.'), { statusCode: 401 });
    }
    return { uid: auth.slice('Bearer seller:'.length), email: 'seller@example.com' };
  });
  const { createOracleApiServer } = require('../server/oracle-api-server');
  server = createOracleApiServer();
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  base = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  if (skip) return;
  await new Promise((resolve) => server.close(resolve));
  server.closeAllConnections?.();
  await pool.end();
});

beforeEach(async () => {
  if (skip) return;
  await pool.query('truncate public.scan_items, public.scan_pairings, public.scan_rate_limits, public.scan_sessions, public.scan_batches, public.marketplace_user_listings cascade');
  refreshed = [];
});

async function call(method, route, { body, seller, phone, ip = '10.0.0.1', headers = {} } = {}) {
  const res = await fetch(`${base}${route}`, {
    method,
    headers: {
      'content-type': 'application/json',
      'cf-connecting-ip': ip,
      ...(seller ? { authorization: `Bearer seller:${seller}` } : {}),
      ...(phone ? { authorization: `Scan ${phone}` } : {}),
      ...headers,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch (_) {
    json = text;
  }
  return { status: res.status, body: json, headers: res.headers };
}

const desktop = {
  start: (seller, batchId) => call('POST', '/api/scan-session?action=start', { seller, body: batchId ? { batchId } : {} }),
  session: (seller, sessionId, action, extra = {}) => call('POST', `/api/scan-session?action=${action}`, { seller, body: { sessionId, ...extra } }),
  batch: (seller, batchId) => call('GET', `/api/scan-batch?batchId=${batchId}`, { seller }),
  act: (seller, action, body) => call('POST', `/api/scan-batch?action=${action}`, { seller, body }),
};

async function pair(seller = 'seller-a', { device = '' } = {}) {
  const started = await desktop.start(seller);
  assert.equal(started.status, 200, JSON.stringify(started.body));
  const claimed = await call('POST', '/api/scan-pair', { body: { pin: started.body.pairing.pin, device }, ip: `10.9.${Math.floor(Math.random() * 250)}.1` });
  assert.equal(claimed.status, 200, JSON.stringify(claimed.body));
  return { ...started.body, phone: claimed.body.phoneToken, claim: claimed.body };
}

let seqCounter = 0;
function scanBody(hits, extra = {}) {
  seqCounter += 1;
  return {
    scanEventId: crypto.randomUUID(),
    clientSequence: seqCounter,
    capturedAt: Date.now(),
    clockOffsetMs: 0,
    recognition: { catalog: 'pokemon_generic', hits },
    ...extra,
  };
}

const hit = (id, score) => ({ public_id: id, score, name: CARDS.get(id)?.name || id });
const scan = (phone, body) => call('POST', '/api/scan-phone?action=scan', { phone, body });

// Minimal SSE-over-fetch reader.
function openStream(seller, batchId, after = 0) {
  const controller = new AbortController();
  const events = [];
  const waiters = [];
  let closed = false;
  const done = (async () => {
    const res = await fetch(`${base}/api/scan-stream?batchId=${batchId}&after=${after}`, {
      headers: { authorization: `Bearer seller:${seller}` },
      signal: controller.signal,
    });
    events.status = res.status;
    if (res.status !== 200) {
      closed = true;
      return;
    }
    const decoder = new TextDecoder();
    let buffer = '';
    try {
      for await (const chunk of res.body) {
        buffer += decoder.decode(chunk, { stream: true });
        let index;
        while ((index = buffer.indexOf('\n\n')) >= 0) {
          const raw = buffer.slice(0, index);
          buffer = buffer.slice(index + 2);
          const lines = raw.split('\n');
          const name = lines.find((l) => l.startsWith('event: '))?.slice(7);
          const data = lines.find((l) => l.startsWith('data: '))?.slice(6);
          if (!name) continue;
          const event = { name, data: data ? JSON.parse(data) : null, at: Date.now() };
          events.push(event);
          for (const w of waiters.splice(0)) w();
        }
      }
    } catch (_) {
      // aborted
    }
    closed = true;
    for (const w of waiters.splice(0)) w();
  })();
  async function waitFor(predicate, timeoutMs = 4000) {
    const deadline = Date.now() + timeoutMs;
    for (;;) {
      const found = events.find(predicate);
      if (found) return found;
      if (closed || Date.now() > deadline) return null;
      await new Promise((resolve) => {
        waiters.push(resolve);
        setTimeout(resolve, 50);
      });
    }
  }
  return {
    events,
    waitFor,
    close: () => {
      controller.abort();
      return done;
    },
    done,
  };
}

const itemsIn = (events) => events.filter((e) => e.name === 'items').flatMap((e) => e.data.items);

// ---------------------------------------------------------------- pairing

test('desktop start returns a 4-digit PIN and QR; a second tab gets the same session and PIN', { skip }, async () => {
  const one = await desktop.start('seller-a');
  assert.equal(one.status, 200);
  assert.match(one.body.pairing.pin, /^[0-9]{4}$/);
  assert.match(one.body.pairing.qrSecret, /^[A-Za-z0-9_-]{32}$/);
  assert.equal(one.body.session.phase, 'waiting');
  const two = await desktop.start('seller-a');
  assert.equal(two.body.session.id, one.body.session.id);
  assert.equal(two.body.batch.id, one.body.batch.id);
  assert.equal(two.body.pairing.pin, one.body.pairing.pin);
});

test('unauthenticated desktop calls are rejected', { skip }, async () => {
  const res = await call('POST', '/api/scan-session?action=start', { body: {} });
  assert.equal(res.status, 401);
});

test('wrong, expired and reused PINs get the same answer; a used PIN dies immediately', { skip }, async () => {
  const started = await desktop.start('seller-a');
  const pin = started.body.pairing.pin;
  const wrong = String((Number(pin) + 1) % 10000).padStart(4, '0');
  const bad = await call('POST', '/api/scan-pair', { body: { pin: wrong }, ip: '10.1.0.1' });
  assert.equal(bad.status, 400);
  assert.deepEqual(bad.body, { error: 'Code not valid or expired.', code: 'invalid_code' });

  const good = await call('POST', '/api/scan-pair', { body: { pin }, ip: '10.1.0.2' });
  assert.equal(good.status, 200);
  assert.equal(good.body.label, 'Pokoin Dashboard');
  assert.equal(good.body.sellerUid, undefined);
  assert.match(good.body.phoneToken, /^[A-Za-z0-9_-]{43}$/);
  assert.notEqual(good.body.phoneToken, pin);

  const reused = await call('POST', '/api/scan-pair', { body: { pin }, ip: '10.1.0.3' });
  assert.deepEqual(reused.body, bad.body);
  assert.equal(reused.status, 400);

  // Expired: regenerate on a second seller and age the row.
  const other = await desktop.start('seller-b');
  await pool.query("update public.scan_pairings set expires_at = now() - interval '1 second' where session_id = $1", [other.body.session.id]);
  const expired = await call('POST', '/api/scan-pair', { body: { pin: other.body.pairing.pin }, ip: '10.1.0.4' });
  assert.deepEqual(expired.body, bad.body);

  // The PIN is never stored as the credential.
  const row = (await pool.query('select phone_token_hash from public.scan_sessions where id = $1', [started.body.session.id])).rows[0];
  assert.equal(row.phone_token_hash, crypto.createHash('sha256').update(good.body.phoneToken).digest('hex'));
});

test('QR secret pairs without the PIN and is single use', { skip }, async () => {
  const started = await desktop.start('seller-a');
  const ok = await call('POST', '/api/scan-pair', { body: { qr: started.body.pairing.qrSecret } });
  assert.equal(ok.status, 200);
  const again = await call('POST', '/api/scan-pair', { body: { qr: started.body.pairing.qrSecret }, ip: '10.1.1.9' });
  assert.equal(again.status, 400);
  const pinAfter = await call('POST', '/api/scan-pair', { body: { pin: started.body.pairing.pin }, ip: '10.1.1.8' });
  assert.equal(pinAfter.status, 400);
});

test('dashboard QR link: PIN + secret connect together; a mismatched PIN is refused and counts as a failure', { skip }, async () => {
  const started = await desktop.start('seller-a');
  const { pin, qrSecret } = started.body.pairing;
  const wrongPin = String((Number(pin) + 1) % 10000).padStart(4, '0');
  const mismatch = await call('POST', '/api/scan-pair', { body: { pin: wrongPin, qr: qrSecret }, ip: '11.0.0.1' });
  assert.equal(mismatch.status, 400);
  assert.deepEqual(mismatch.body, { error: 'Code not valid or expired.', code: 'invalid_code' });
  const fails = (await pool.query("select hits from public.scan_rate_limits where bucket = 'pairfail:ip:11.0.0.1'")).rows[0];
  assert.equal(fails.hits, 1);
  // The pairing survived the mismatch; the real QR link still connects.
  const ok = await call('POST', '/api/scan-pair', { body: { pin, qr: qrSecret }, ip: '11.0.0.2' });
  assert.equal(ok.status, 200);
  assert.equal((await call('POST', '/api/scan-pair', { body: { pin, qr: qrSecret }, ip: '11.0.0.3' })).status, 400, 'single use');
});

test('PIN brute force: 8 failures lock that IP (even the right PIN) but not other IPs', { skip }, async () => {
  const started = await desktop.start('seller-a');
  const pin = started.body.pairing.pin;
  let guess = 0;
  for (let i = 0; i < 8; i += 1) {
    let candidate = String(guess).padStart(4, '0');
    if (candidate === pin) {
      guess += 1;
      candidate = String(guess).padStart(4, '0');
    }
    guess += 1;
    const res = await call('POST', '/api/scan-pair', { body: { pin: candidate }, ip: '66.6.6.6' });
    assert.equal(res.status, 400);
  }
  const locked = await call('POST', '/api/scan-pair', { body: { pin }, ip: '66.6.6.6' });
  assert.equal(locked.status, 429);
  assert.ok(Number(locked.headers.get('retry-after')) > 0);
  const elsewhere = await call('POST', '/api/scan-pair', { body: { pin }, ip: '77.7.7.7' });
  assert.equal(elsewhere.status, 200);
});

test('global failure cap trips for every IP (distributed brute force)', { skip }, async () => {
  const started = await desktop.start('seller-a');
  const window = new Date(Math.floor(Date.now() / 600_000) * 600_000);
  await pool.query(
    "insert into public.scan_rate_limits (bucket, window_start, hits) values ('pairfail:global', $1, 300)",
    [window],
  );
  const res = await call('POST', '/api/scan-pair', { body: { pin: started.body.pairing.pin }, ip: '5.5.5.5' });
  assert.equal(res.status, 429);
});

test('scan ingest is rate limited per session and capped per batch; retries of stored scans still succeed', { skip }, async () => {
  const s = await pair();
  const stored = scanBody([hit('220962', 0.95)]);
  assert.equal((await scan(s.phone, stored)).status, 200);
  const window = new Date(Math.floor(Date.now() / 600_000) * 600_000);
  await pool.query(
    "insert into public.scan_rate_limits (bucket, window_start, hits) values ($1, $2, 1200) on conflict (bucket, window_start) do update set hits = 1200",
    [`scan:${s.session.id}`, window],
  );
  const limited = await scan(s.phone, scanBody([hit('504600', 0.95)]));
  assert.equal(limited.status, 429);
  assert.equal(limited.body.code, 'rate_limited');
  assert.equal((await scan(s.phone, stored)).body.duplicate, true, 'retry of an accepted scan is not rate limited');
  await pool.query('delete from public.scan_rate_limits');
  await pool.query('update public.scan_batches set item_position = 10000 where id = $1', [s.batch.id]);
  const full = await scan(s.phone, scanBody([hit('504600', 0.95)]));
  assert.equal(full.status, 409);
  assert.equal(full.body.code, 'batch_full');
});

test('malformed ids and tokens never reach SQL errors', { skip }, async () => {
  const s = await pair();
  for (const route of [
    '/api/scan-batch?batchId=not-a-uuid',
    "/api/scan-batch?batchId=' or 1=1 --",
    '/api/scan-session?sessionId=123',
  ]) {
    const res = await call('GET', route, { seller: 'seller-a' });
    assert.equal(res.status, 404, route);
  }
  assert.equal((await desktop.act('seller-a', 'item', { itemId: '../../etc', patch: { quantity: 2 } })).status, 404);
  assert.equal((await call('POST', '/api/scan-phone?action=scan', { phone: 'x'.repeat(10), body: scanBody([]) })).status, 401);
  assert.equal((await call('POST', '/api/scan-phone?action=scan', { headers: { authorization: `Bearer ${s.phone}` }, body: scanBody([]) })).status, 401, 'phone token only as Scan scheme');
  assert.equal((await call('POST', '/api/scan-pair', { body: { pin: "12' or '1'='1", qr: '<script>' }, ip: '12.0.0.1' })).status, 400);
  assert.equal((await scan(s.phone, { ...scanBody([]), scanEventId: 'nope' })).status, 400);
  // A phone token cannot use desktop endpoints.
  assert.equal((await call('GET', `/api/scan-batch?batchId=${s.batch.id}`, { phone: s.phone })).status, 401);
});

test('writer database unavailable → 500 with a generic message, no stack or connection string', { skip }, async () => {
  const { createStore, setScanStoreForTests } = require('./_scan_store');
  const brokenPool = { connect: async () => { throw Object.assign(new Error('connect ECONNREFUSED 192.168.178.55:25432'), { code: 'ECONNREFUSED' }); }, query: async () => { throw new Error('connect ECONNREFUSED 192.168.178.55:25432'); } };
  setScanStoreForTests(createStore({ pool: brokenPool }));
  try {
    const res = await call('POST', '/api/scan-session?action=start', { seller: 'seller-a', body: {} });
    assert.equal(res.status, 500);
    assert.doesNotMatch(JSON.stringify(res.body), /ECONNREFUSED|192\.168|postgres/i);
    const pairRes = await call('POST', '/api/scan-pair', { body: { pin: '1234' }, ip: '13.0.0.1' });
    assert.equal(pairRes.status, 500);
  } finally {
    setScanStoreForTests(createStore({
      pool,
      lookupCards: async (ids) => new Map(ids.filter((id) => CARDS.has(id)).map((id) => [id, CARDS.get(id)])),
      onListingsCreated: async (ids) => { refreshed.push(...ids); },
    }));
  }
});

test('migration is repeatable and upgrades a database that already has part of the schema', { skip }, async () => {
  const sql = fs.readFileSync(path.join(__dirname, '..', 'oracle-postgres', 'schema', '082_scan_connect.sql'), 'utf8');
  await pool.query(sql);
  await pool.query(sql);
  // Partial state: listings column present, one scan table missing.
  await pool.query('drop table public.scan_rate_limits');
  await pool.query(sql);
  const tables = (await pool.query("select count(*)::int as n from pg_tables where schemaname = 'public' and tablename in ('scan_batches','scan_sessions','scan_pairings','scan_rate_limits','scan_items')")).rows[0].n;
  assert.equal(tables, 5);
  const cols = (await pool.query("select count(*)::int as n from information_schema.columns where table_name = 'marketplace_user_listings' and column_name in ('location','altered')")).rows[0].n;
  assert.equal(cols, 2);
  const idx = (await pool.query("select count(*)::int as n from pg_indexes where indexname = 'marketplace_user_listings_scan_row_uidx'")).rows[0].n;
  assert.equal(idx, 1);
});

test('deploy grants are enough for a non-superuser API role (the Pi writer role)', { skip }, async () => {
  const grants = fs.readFileSync(path.join(__dirname, '..', 'oracle-postgres', 'schema', '082_scan_connect.grants.sql'), 'utf8');
  await pool.query("do $$ begin if not exists (select 1 from pg_roles where rolname = 'scan_api_test') then create role scan_api_test login password 'x'; end if; end $$");
  await pool.query('grant usage on schema public to scan_api_test');
  await pool.query('grant select, insert, update on public.marketplace_user_listings to scan_api_test');
  await pool.query(grants.replaceAll(':"api_role"', 'scan_api_test'));
  const client = await pool.connect();
  try {
    await client.query('set role scan_api_test');
    const { createStore } = require('./_scan_store');
    const limited = createStore({ pool: { connect: async () => ({ query: (...a) => client.query(...a), release() {} }), query: (...a) => client.query(...a) } });
    const started = await limited.startSession({ sellerUid: 'grant-seller' });
    const claimed = await limited.claimPairing({ pin: started.pairing.pin, ip: '14.0.0.1', userAgent: 'iPhone' });
    const res = await limited.ingestScan({ token: claimed.phoneToken, body: scanBody([hit('220962', 0.95)]) });
    await limited.patchItem({ sellerUid: 'grant-seller', itemId: res.itemId, patch: { pricePkn: 10 } });
    const done = await limited.submitBatch({ sellerUid: 'grant-seller', batchId: started.batch.id, submitKey: 'g' });
    assert.equal(done.result.listings, 1);
  } finally {
    await client.query('reset role');
    client.release();
  }
});

test('two phones racing on one PIN: exactly one wins', { skip }, async () => {
  const started = await desktop.start('seller-a');
  const results = await Promise.all(
    Array.from({ length: 6 }, (_, i) => call('POST', '/api/scan-pair', { body: { pin: started.body.pairing.pin }, ip: `20.0.0.${i}` })),
  );
  assert.equal(results.filter((r) => r.status === 200).length, 1);
  assert.equal(results.filter((r) => r.status === 400).length, 5);
});

test('live PINs stay unique across many concurrent sessions', { skip }, async () => {
  const sellers = Array.from({ length: 60 }, (_, i) => `seller-u${i}`);
  const results = await Promise.all(sellers.map((s) => desktop.start(s)));
  const pins = results.map((r) => r.body.pairing.pin);
  assert.equal(new Set(pins).size, pins.length);
  const rows = (await pool.query('select count(distinct pin)::int as n, count(*)::int as c from public.scan_pairings')).rows[0];
  assert.equal(rows.n, rows.c);
});

test('regenerate kills the old PIN; regenerate is refused while a phone is connected', { skip }, async () => {
  const started = await desktop.start('seller-a');
  const regen = await desktop.session('seller-a', started.body.session.id, 'pairing');
  assert.equal(regen.status, 200);
  const old = await call('POST', '/api/scan-pair', { body: { pin: started.body.pairing.pin }, ip: '30.0.0.1' });
  if (regen.body.pairing.pin !== started.body.pairing.pin) assert.equal(old.status, 400);
  const ok = await call('POST', '/api/scan-pair', { body: { pin: regen.body.pairing.pin }, ip: '30.0.0.2' });
  assert.equal(ok.status, 200);
  const refused = await desktop.session('seller-a', started.body.session.id, 'pairing');
  assert.equal(refused.status, 409);
});

// ---------------------------------------------------------------- phone & stream

test('scan is delivered to the desktop stream and to a second tab', { skip }, async () => {
  const s = await pair('seller-a', { device: 'Test iPhone' });
  const tab1 = openStream('seller-a', s.batch.id);
  const tab2 = openStream('seller-a', s.batch.id);
  assert.ok(await tab1.waitFor((e) => e.name === 'hello'));
  await tab2.waitFor((e) => e.name === 'hello');
  const sentAt = Date.now();
  const res = await scan(s.phone, scanBody([hit('220962', 0.93)]));
  assert.equal(res.status, 200);
  assert.equal(res.body.recognitionState, 'matched');
  const got1 = await tab1.waitFor((e) => e.name === 'items' && e.data.items.some((i) => i.id === res.body.itemId));
  const got2 = await tab2.waitFor((e) => e.name === 'items' && e.data.items.some((i) => i.id === res.body.itemId));
  assert.ok(got1 && got2, 'both tabs receive the row');
  assert.ok(got1.at - sentAt < 1500, `delivered in ${got1.at - sentAt} ms`);
  const row = got1.data.items.find((i) => i.id === res.body.itemId);
  assert.equal(row.cardName, 'Espurr');
  assert.equal(row.language, 'EN');
  const session = await tab1.waitFor((e) => e.name === 'session' && e.data.session.phoneLabel === 'Test iPhone')
    || tab1.events.find((e) => e.name === 'hello');
  assert.ok(session);
  await Promise.all([tab1.close(), tab2.close()]);
});

test('duplicate network request / retry does not create a second row', { skip }, async () => {
  const s = await pair();
  const body = scanBody([hit('220962', 0.93)]);
  const [a, b] = await Promise.all([scan(s.phone, body), scan(s.phone, body)]);
  const c = await scan(s.phone, body);
  const statuses = [a.status, b.status, c.status];
  assert.deepEqual(statuses, [200, 200, 200]);
  assert.equal([a, b, c].filter((r) => r.body.duplicate === true).length, 2);
  const rows = (await pool.query('select count(*)::int as n from public.scan_items where scan_event_id = $1', [body.scanEventId])).rows[0];
  assert.equal(rows.n, 1);
});

test('event replay and out-of-order reconnect: cursor replay returns each row once, newest seq wins', { skip }, async () => {
  const s = await pair();
  const ids = [];
  for (let i = 0; i < 5; i += 1) {
    ids.push((await scan(s.phone, scanBody([hit(i % 2 ? '220962' : '504600', 0.95)], { recognition: { hits: [hit(i % 2 ? '220962' : '504600', 0.95), hit('220964', 0.1)] } }))).body.itemId);
  }
  const first = openStream('seller-a', s.batch.id, 0);
  await first.waitFor((e) => e.name === 'items');
  await new Promise((r) => setTimeout(r, 200));
  const replayed = itemsIn(first.events);
  const cursor = Math.max(...replayed.map((i) => i.seq));
  await first.close();
  // Edit one row and add one while "disconnected".
  await desktop.act('seller-a', 'item', { itemId: ids[0], patch: { condition: 'SP' } });
  const late = await scan(s.phone, scanBody([hit('233564', 0.9)]));
  const second = openStream('seller-a', s.batch.id, cursor);
  await second.waitFor((e) => e.name === 'items' && e.data.items.some((i) => i.id === late.body.itemId));
  const delta = itemsIn(second.events);
  assert.deepEqual(new Set(delta.map((i) => i.id)), new Set([ids[0], late.body.itemId]));
  assert.equal(delta.find((i) => i.id === ids[0]).condition, 'SP');
  // Full replay from 0 again shows every row exactly once with its latest state.
  const full = openStream('seller-a', s.batch.id, 0);
  await full.waitFor((e) => e.name === 'items');
  await new Promise((r) => setTimeout(r, 200));
  const all = itemsIn(full.events);
  assert.equal(new Set(all.map((i) => i.id)).size, all.length);
  assert.equal(all.find((i) => i.id === ids[0]).condition, 'SP');
  await Promise.all([second.close(), full.close()]);
});

test('stream closes itself and a reconnect with the cursor misses nothing', { skip }, async () => {
  const s = await pair();
  const stream = openStream('seller-a', s.batch.id, 0);
  await stream.waitFor((e) => e.name === 'hello');
  const bye = await stream.waitFor((e) => e.name === 'bye', 4000);
  assert.ok(bye, 'server ended the stream');
  await stream.done;
  const res = await scan(s.phone, scanBody([hit('220962', 0.95)]));
  const resumed = openStream('seller-a', s.batch.id, bye.data.cursor);
  assert.ok(await resumed.waitFor((e) => e.name === 'items' && e.data.items.some((i) => i.id === res.body.itemId)));
  await resumed.close();
});

test('batch defaults snapshot: Italian rows stay Italian after switching to English, including an in-flight scan', { skip }, async () => {
  const s = await pair();
  await desktop.act('seller-a', 'defaults', { batchId: s.batch.id, defaults: { language: 'IT', location: 'Box A12' } });
  const italian = [];
  for (let i = 0; i < 3; i += 1) {
    italian.push((await scan(s.phone, scanBody([hit(['220962', '504600', '233564'][i], 0.95)]))).body.itemId);
  }
  const inFlight = scanBody([hit('220964', 0.95)], { capturedAt: Date.now() });
  await new Promise((r) => setTimeout(r, 30));
  await desktop.act('seller-a', 'defaults', { batchId: s.batch.id, defaults: { language: 'EN', location: 'Binder 3' } });
  const lateArrival = await scan(s.phone, inFlight);
  const english = await scan(s.phone, scanBody([hit('504600', 0.95)]));
  const snap = (await desktop.batch('seller-a', s.batch.id)).body;
  const byId = new Map(snap.items.map((i) => [i.id, i]));
  for (const id of italian) {
    assert.equal(byId.get(id).language, 'IT');
    assert.equal(byId.get(id).location, 'Box A12');
    assert.equal(byId.get(id).defaultsSnapshot.language, 'IT');
  }
  assert.equal(byId.get(lateArrival.body.itemId).language, 'IT', 'captured before the switch');
  assert.equal(byId.get(english.body.itemId).language, 'EN');
  assert.equal(byId.get(english.body.itemId).location, 'Binder 3');
  assert.equal(snap.batch.defaults.language, 'EN');
});

test('four identical copies become one row with qty 4; undo splits one back out', { skip }, async () => {
  const s = await pair();
  const results = [];
  for (let i = 0; i < 4; i += 1) results.push((await scan(s.phone, scanBody([hit('220962', 0.94)]))).body);
  assert.deepEqual(results.map((r) => r.merged), [false, true, true, true]);
  assert.deepEqual(results.slice(1).map((r) => r.headQuantity), [2, 3, 4]);
  const head = results[0].itemId;
  let snap = (await desktop.batch('seller-a', s.batch.id)).body;
  assert.equal(snap.items.filter((i) => i.status === 'active').length, 1);
  assert.equal(snap.items.find((i) => i.id === head).quantity, 4);
  assert.equal(snap.items.filter((i) => i.status === 'merged').length, 3);
  const undo = await desktop.act('seller-a', 'unmerge', { itemId: results[3].itemId });
  assert.equal(undo.status, 200);
  snap = (await desktop.batch('seller-a', s.batch.id)).body;
  assert.equal(snap.items.find((i) => i.id === head).quantity, 3);
  assert.equal(snap.items.find((i) => i.id === results[3].itemId).status, 'active');
});

test('A B A does not merge; different attributes do not merge; merge can be turned off', { skip }, async () => {
  const s = await pair();
  const a1 = (await scan(s.phone, scanBody([hit('220962', 0.94)]))).body;
  await scan(s.phone, scanBody([hit('504600', 0.94)]));
  const a2 = (await scan(s.phone, scanBody([hit('220962', 0.94)]))).body;
  assert.equal(a2.merged, false);
  await desktop.act('seller-a', 'item', { itemId: a2.itemId, patch: { condition: 'SP' } });
  const a3 = (await scan(s.phone, scanBody([hit('220962', 0.94)]))).body;
  assert.equal(a3.merged, false, 'row edited to SP no longer matches NM default');
  await desktop.act('seller-a', 'defaults', { batchId: s.batch.id, defaults: { mergeRepeats: false } });
  const a4 = (await scan(s.phone, scanBody([hit('220962', 0.94)]))).body;
  assert.equal(a4.merged, false);
  assert.ok(a1.itemId);
});

test('ambiguous and unmatched scans never merge, block submit, and are fixed by confirm or replace', { skip }, async () => {
  const s = await pair();
  const amb1 = (await scan(s.phone, scanBody([hit('504600', 0.83), hit('233564', 0.8)], { image: JPEG }))).body;
  const amb2 = (await scan(s.phone, scanBody([hit('504600', 0.83), hit('233564', 0.8)]))).body;
  const none = (await scan(s.phone, scanBody([hit('233564', 0.3)], { image: JPEG }))).body;
  assert.equal(amb1.recognitionState, 'ambiguous');
  assert.equal(amb2.merged, false);
  assert.equal(none.recognitionState, 'unmatched');
  // Scanning continues while those wait.
  const clean = (await scan(s.phone, scanBody([hit('220962', 0.95)]))).body;
  assert.equal(clean.recognitionState, 'matched');

  const snap = (await desktop.batch('seller-a', s.batch.id)).body;
  const rowAmb = snap.items.find((i) => i.id === amb1.itemId);
  assert.deepEqual(rowAmb.recognition.candidates.map((c) => c.cardId), ['504600', '233564']);
  assert.equal(rowAmb.cardId, '504600', 'best candidate preselected');
  assert.equal(rowAmb.hasImage, true);
  const unmatchedRow = snap.items.find((i) => i.id === none.itemId);
  assert.equal(unmatchedRow.cardId, '');

  const image = await fetch(`${base}/api/scan-batch?action=image&itemId=${amb1.itemId}`, { headers: { authorization: 'Bearer seller:seller-a' } });
  assert.equal(image.headers.get('content-type'), 'image/jpeg');
  const imageOther = await fetch(`${base}/api/scan-batch?action=image&itemId=${amb1.itemId}`, { headers: { authorization: 'Bearer seller:seller-b' } });
  assert.equal(imageOther.status, 404);

  for (const id of [amb1.itemId, amb2.itemId, none.itemId, clean.itemId]) {
    await desktop.act('seller-a', 'item', { itemId: id, patch: { pricePkn: 50 } });
  }
  const blocked = await desktop.act('seller-a', 'submit', { batchId: s.batch.id, submitKey: 'k1' });
  assert.equal(blocked.status, 409);
  assert.deepEqual(new Set(blocked.body.problems.map((p) => p.reason)), new Set(['needs_review', 'no_printing']));

  await desktop.act('seller-a', 'item', { itemId: amb1.itemId, patch: { confirm: true } });
  const replaced = await desktop.act('seller-a', 'item', { itemId: amb2.itemId, patch: { cardId: '233564' } });
  assert.equal(replaced.body.items[0].cardName, 'Pikachu δ');
  assert.equal(replaced.body.items[0].reviewed, true);
  assert.equal(replaced.body.items[0].pricePkn, null, 'price cleared when the printing changes');
  await desktop.act('seller-a', 'item', { itemId: amb2.itemId, patch: { pricePkn: 40 } });
  await desktop.act('seller-a', 'item', { itemId: none.itemId, patch: { cardId: '220964', pricePkn: 12 } });
  const submitted = await desktop.act('seller-a', 'submit', { batchId: s.batch.id, submitKey: 'k1' });
  assert.equal(submitted.status, 200, JSON.stringify(submitted.body));
  assert.equal(submitted.body.result.listings, 4);
});

test('immutable scan event columns cannot be rewritten', { skip }, async () => {
  const s = await pair();
  const res = (await scan(s.phone, scanBody([hit('220962', 0.94)]))).body;
  await assert.rejects(
    pool.query("update public.scan_items set defaults_snapshot = '{}'::jsonb where id = $1", [res.itemId]),
    /immutable/,
  );
  await pool.query("update public.scan_items set condition = 'SP' where id = $1", [res.itemId]);
});

test('end-to-end: IT pile, EN pile, ambiguous fix, finish, qty, submit → inventory has exactly the intended articles', { skip }, async () => {
  const s = await pair();
  await desktop.act('seller-a', 'defaults', { batchId: s.batch.id, defaults: { language: 'IT', condition: 'NM', location: 'Box A12' } });
  const it1 = (await scan(s.phone, scanBody([hit('220962', 0.95)]))).body;
  const it2 = (await scan(s.phone, scanBody([hit('220962', 0.95)]))).body; // merges → qty 2
  const it3 = (await scan(s.phone, scanBody([hit('504600', 0.81), hit('233564', 0.78)]))).body; // ambiguous
  await desktop.act('seller-a', 'defaults', { batchId: s.batch.id, defaults: { language: 'EN' } });
  const en1 = (await scan(s.phone, scanBody([hit('233564', 0.96)]))).body;
  assert.equal(it2.merged, true);

  await desktop.act('seller-a', 'item', { itemId: it3.itemId, patch: { cardId: '233564' } });
  await desktop.act('seller-a', 'item', { itemId: en1.itemId, patch: { foilState: 'reverse', quantity: 3 } });
  for (const id of [it1.itemId, it3.itemId, en1.itemId]) {
    await desktop.act('seller-a', 'item', { itemId: id, patch: { pricePkn: 25, priceSuggested: true, onlyIfEmptyPrice: true } });
  }
  // A seller price is not overwritten by a late suggestion.
  await desktop.act('seller-a', 'item', { itemId: en1.itemId, patch: { pricePkn: 99 } });
  await desktop.act('seller-a', 'item', { itemId: en1.itemId, patch: { pricePkn: 25, priceSuggested: true, onlyIfEmptyPrice: true } });

  const key = crypto.randomUUID();
  const [x, y] = await Promise.all([
    desktop.act('seller-a', 'submit', { batchId: s.batch.id, submitKey: key }),
    desktop.act('seller-a', 'submit', { batchId: s.batch.id, submitKey: key }),
  ]);
  assert.deepEqual([x.status, y.status], [200, 200]);
  const again = await desktop.act('seller-a', 'submit', { batchId: s.batch.id, submitKey: 'refresh' });
  assert.equal(again.status, 200);
  assert.equal(again.body.alreadySubmitted, true);

  const listings = (await pool.query(
    `select card_id, language, condition, foil_state, reverse, quantity_available, price_pkn::float, location, source
     from public.marketplace_user_listings where seller_uid = 'seller-a' order by card_id, language`,
  )).rows;
  assert.deepEqual(listings, [
    { card_id: '220962', language: 'IT', condition: 'NM', foil_state: 'standard', reverse: false, quantity_available: 2, price_pkn: 25, location: 'Box A12', source: 'pokoin_scan_batch' },
    { card_id: '233564', language: 'EN', condition: 'NM', foil_state: 'reverse', reverse: true, quantity_available: 3, price_pkn: 99, location: 'Box A12', source: 'pokoin_scan_batch' },
    { card_id: '233564', language: 'IT', condition: 'NM', foil_state: 'standard', reverse: false, quantity_available: 1, price_pkn: 25, location: 'Box A12', source: 'pokoin_scan_batch' },
  ]);
  assert.deepEqual(new Set(refreshed), new Set(['220962', '233564']));
  // The phone is done too.
  const hb = await call('POST', '/api/scan-phone?action=heartbeat', { phone: s.phone });
  assert.equal(hb.status, 401);
});

// ---------------------------------------------------------------- lifecycle

test('desktop disconnects the phone: token dies, a new PIN pairs again, batch intact', { skip }, async () => {
  const s = await pair();
  const r1 = await scan(s.phone, scanBody([hit('220962', 0.95)]));
  const disc = await desktop.session('seller-a', s.session.id, 'disconnect');
  assert.equal(disc.body.session.phase, 'waiting');
  assert.equal((await scan(s.phone, scanBody([hit('220962', 0.95)]))).status, 401);
  const re = await call('POST', '/api/scan-pair', { body: { pin: disc.body.pairing.pin }, ip: '40.0.0.1' });
  assert.equal(re.status, 200);
  const r2 = await scan(re.body.phoneToken, scanBody([hit('504600', 0.95)]));
  assert.equal(r2.status, 200);
  const snap = (await desktop.batch('seller-a', s.batch.id)).body;
  assert.deepEqual(snap.items.map((i) => i.id), [r1.body.itemId, r2.body.itemId]);
});

test('phone reconnect after losing the network: heartbeat revives presence, outbox retry is idempotent', { skip }, async () => {
  const s = await pair();
  const body = scanBody([hit('220962', 0.95)]);
  await pool.query("update public.scan_sessions set phone_last_seen_at = now() - interval '30 seconds' where id = $1", [s.session.id]);
  let view = (await desktop.session('seller-a', s.session.id, 'pause', { paused: false })).body;
  assert.equal(view.session.phase, 'lost');
  const hb = await call('POST', '/api/scan-phone?action=heartbeat', { phone: s.phone });
  assert.equal(hb.status, 200);
  assert.ok(Math.abs(hb.body.serverTime - Date.now()) < 5000);
  view = (await call('GET', `/api/scan-session?sessionId=${s.session.id}`, { seller: 'seller-a' })).body;
  assert.equal(view.session.phase, 'connected');
  assert.equal((await scan(s.phone, body)).body.duplicate, false);
  assert.equal((await scan(s.phone, body)).body.duplicate, true);
});

test('pause rejects scans with a code the phone understands', { skip }, async () => {
  const s = await pair();
  await desktop.session('seller-a', s.session.id, 'pause', { paused: true });
  const res = await scan(s.phone, scanBody([hit('220962', 0.95)]));
  assert.equal(res.status, 409);
  assert.equal(res.body.code, 'paused');
  const hb = await call('POST', '/api/scan-phone?action=heartbeat', { phone: s.phone });
  assert.equal(hb.body.paused, true);
});

test('session expiry waiting: 30 min desk-abandon ends session; batch survives', { skip }, async () => {
  const s = await pair();
  const kept = (await scan(s.phone, scanBody([hit('220962', 0.95)]))).body;
  // Disconnect first so the session is waiting — the 30-minute timer only applies there.
  await desktop.session('seller-a', s.session.id, 'disconnect');
  await pool.query("update public.scan_sessions set last_activity_at = now() - interval '31 minutes' where id = $1", [s.session.id]);
  const view = (await call('GET', `/api/scan-session?sessionId=${s.session.id}`, { seller: 'seller-a' })).body;
  assert.equal(view.session.phase, 'expired');
  assert.equal((await call('POST', '/api/scan-phone?action=heartbeat', { phone: s.phone })).status, 401);
  const resumed = await desktop.start('seller-a');
  assert.equal(resumed.body.batch.id, s.batch.id);
  assert.notEqual(resumed.body.session.id, s.session.id);
  const snap = (await desktop.batch('seller-a', s.batch.id)).body;
  assert.ok(snap.items.some((i) => i.id === kept.itemId));
});

test('scan idle: 10 min without a scan disconnects phone, keeps batch, rejects further uploads', { skip }, async () => {
  const s = await pair();
  const kept = (await scan(s.phone, scanBody([hit('220962', 0.95)]))).body;
  // Heartbeat / presence alone must not extend the timer.
  await pool.query(
    `update public.scan_sessions
       set last_scan_at = now() - interval '11 minutes',
           phone_connected_at = now() - interval '20 minutes',
           phone_last_seen_at = now(),
           last_activity_at = now()
     where id = $1`,
    [s.session.id],
  );
  const hb = await call('POST', '/api/scan-phone?action=heartbeat', { phone: s.phone });
  assert.equal(hb.status, 401);
  assert.equal(hb.body.code, 'session_idle');
  // Token already cleared — further uploads are rejected (code may be session_ended).
  const late = await scan(s.phone, scanBody([hit('504600', 0.95)]));
  assert.equal(late.status, 401);
  const view = (await call('GET', `/api/scan-session?sessionId=${s.session.id}`, { seller: 'seller-a' })).body;
  assert.equal(view.session.status, 'waiting');
  assert.equal(view.justIdleDisconnected, false, 'already disconnected by heartbeat');
  assert.ok(view.pairing?.pin);
  // Reconnect continues the same batch.
  const re = await call('POST', '/api/scan-pair', { body: { pin: view.pairing.pin }, ip: '41.0.0.1' });
  assert.equal(re.status, 200);
  const r2 = await scan(re.body.phoneToken, scanBody([hit('504600', 0.95)]));
  assert.equal(r2.status, 200);
  const snap = (await desktop.batch('seller-a', s.batch.id)).body;
  assert.ok(snap.items.some((i) => i.id === kept.itemId));
  assert.ok(snap.items.some((i) => i.id === r2.body.itemId));
});

test('scan idle: accepted scan (incl. merge) resets the 10-minute clock; desktop edits do not', { skip }, async () => {
  const s = await pair();
  await desktop.act('seller-a', 'defaults', { batchId: s.batch.id, defaults: { mergeRepeats: true } });
  const first = await scan(s.phone, scanBody([hit('220962', 0.95)]));
  assert.equal(first.status, 200);
  // Nine minutes since last scan — still alive.
  await pool.query(
    `update public.scan_sessions
       set last_scan_at = now() - interval '9 minutes',
           phone_connected_at = now() - interval '30 minutes',
           last_activity_at = now() - interval '9 minutes'
     where id = $1`,
    [s.session.id],
  );
  // Desktop patch bumps last_activity_at but must not save the phone.
  await desktop.act('seller-a', 'item', { itemId: first.body.itemId, patch: { pricePkn: 12 } });
  await pool.query(
    `update public.scan_sessions
       set last_scan_at = now() - interval '9 minutes',
           phone_last_seen_at = now()
     where id = $1`,
    [s.session.id],
  );
  const still = await call('POST', '/api/scan-phone?action=heartbeat', { phone: s.phone });
  assert.equal(still.status, 200);
  // Merge-repeat scan resets last_scan_at.
  const merge = await scan(s.phone, scanBody([hit('220962', 0.95)]));
  assert.equal(merge.status, 200);
  assert.equal(merge.body.merged, true);
  await pool.query(
    `update public.scan_sessions
       set last_scan_at = now() - interval '9 minutes',
           phone_last_seen_at = now()
     where id = $1`,
    [s.session.id],
  );
  assert.equal((await call('POST', '/api/scan-phone?action=heartbeat', { phone: s.phone })).status, 200);
  // Eleven minutes after that merge → idle disconnect.
  await pool.query(
    `update public.scan_sessions set last_scan_at = now() - interval '11 minutes' where id = $1`,
    [s.session.id],
  );
  const gone = await call('POST', '/api/scan-phone?action=heartbeat', { phone: s.phone });
  assert.equal(gone.status, 401);
  assert.equal(gone.body.code, 'session_idle');
  const snap = (await desktop.batch('seller-a', s.batch.id)).body;
  assert.ok(snap.items.length >= 1);
  assert.equal(snap.batch.status, 'open');
});

test('scan idle from connect with no scans: disconnect after 10 min', { skip }, async () => {
  const s = await pair();
  await pool.query(
    `update public.scan_sessions
       set phone_connected_at = now() - interval '10 minutes',
           last_scan_at = null,
           phone_last_seen_at = now(),
           last_activity_at = now()
     where id = $1`,
    [s.session.id],
  );
  const view = (await call('GET', `/api/scan-session?sessionId=${s.session.id}`, { seller: 'seller-a' })).body;
  assert.equal(view.session.status, 'waiting');
  assert.equal(view.justIdleDisconnected, true);
  assert.ok(view.pairing?.pin);
  assert.equal((await scan(s.phone, scanBody([hit('220962', 0.95)]))).status, 401);
});

test('seller logs out: session ends, phone token dies, batch stays', { skip }, async () => {
  const s = await pair();
  await scan(s.phone, scanBody([hit('220962', 0.95)]));
  const ended = await desktop.session('seller-a', s.session.id, 'end', { reason: 'logout' });
  assert.equal(ended.body.session.endReason, 'logout');
  assert.equal((await scan(s.phone, scanBody([hit('220962', 0.95)]))).status, 401);
  assert.equal((await desktop.batch('seller-a', s.batch.id)).body.items.length, 1);
});

test('another account cannot see or touch the batch, session, stream or rows', { skip }, async () => {
  const s = await pair('seller-a');
  const row = (await scan(s.phone, scanBody([hit('220962', 0.95)]))).body;
  assert.equal((await desktop.batch('seller-b', s.batch.id)).status, 404);
  assert.equal((await call('GET', `/api/scan-session?sessionId=${s.session.id}`, { seller: 'seller-b' })).status, 404);
  assert.equal((await desktop.act('seller-b', 'item', { itemId: row.itemId, patch: { quantity: 9 } })).status, 404);
  assert.equal((await desktop.act('seller-b', 'submit', { batchId: s.batch.id, submitKey: 'x' })).status, 404);
  const stream = openStream('seller-b', s.batch.id);
  await stream.done;
  assert.equal(stream.events.status, 404);
  // seller-b's own start creates an unrelated batch.
  const b = await desktop.start('seller-b');
  assert.notEqual(b.body.batch.id, s.batch.id);
});

test('two independent scan sessions do not see each other', { skip }, async () => {
  const a = await pair('seller-a');
  const b = await pair('seller-b');
  const streamA = openStream('seller-a', a.batch.id);
  await streamA.waitFor((e) => e.name === 'hello');
  const rb = (await scan(b.phone, scanBody([hit('504600', 0.95)]))).body;
  const ra = (await scan(a.phone, scanBody([hit('220962', 0.95)]))).body;
  await streamA.waitFor((e) => e.name === 'items' && e.data.items.some((i) => i.id === ra.itemId));
  assert.equal(itemsIn(streamA.events).some((i) => i.id === rb.itemId), false);
  await streamA.close();
});

test('manual add and duplicate (PowerTools C) sit next to the original', { skip }, async () => {
  const s = await pair();
  const first = (await scan(s.phone, scanBody([hit('220962', 0.95)]))).body;
  const second = (await scan(s.phone, scanBody([hit('504600', 0.95)]))).body;
  const copy = await desktop.act('seller-a', 'duplicate', { itemId: first.itemId });
  assert.equal(copy.status, 200);
  const manual = await desktop.act('seller-a', 'add', { batchId: s.batch.id, cardId: '233564', language: 'JP' });
  assert.equal(manual.body.items[0].language, 'JP');
  const order = (await desktop.batch('seller-a', s.batch.id)).body.items.map((i) => i.id);
  assert.deepEqual(order, [first.itemId, copy.body.items[0].id, second.itemId, manual.body.items[0].id]);
  assert.equal((await desktop.act('seller-a', 'remove', { itemId: second.itemId })).body.items[0].status, 'removed');
  assert.equal((await desktop.act('seller-a', 'restore', { itemId: second.itemId })).body.items[0].status, 'active');
});

test('1000-scan batch: every scan stored once, stream replays all, submit creates one listing per row', { skip, timeout: 240_000 }, async () => {
  const s = await pair();
  const ids = ['220962', '220964', '504600', '233564'];
  const bodies = Array.from({ length: 1000 }, (_, i) => scanBody([hit(ids[i % 4], 0.95)]));
  const started = Date.now();
  for (let i = 0; i < bodies.length; i += 8) {
    const chunk = bodies.slice(i, i + 8);
    // A phone sends in order; retry a few to prove idempotency under load.
    for (const body of chunk) {
      const res = await scan(s.phone, body);
      assert.equal(res.status, 200);
    }
    await scan(s.phone, chunk[0]);
  }
  const elapsed = Date.now() - started;
  const counts = (await pool.query(
    "select count(*)::int as events, count(*) filter (where status = 'active')::int as active from public.scan_items where batch_id = $1",
    [s.batch.id],
  )).rows[0];
  assert.equal(counts.events, 1000);
  assert.equal(counts.active, 1000, 'rotating printings never merge');
  const stream = openStream('seller-a', s.batch.id, 0);
  await stream.waitFor((e) => e.name === 'items' && itemsIn(stream.events).length >= 1000, 10_000);
  assert.equal(new Set(itemsIn(stream.events).map((i) => i.id)).size, 1000);
  await stream.close();
  await pool.query('update public.scan_items set price_pkn = 10 where batch_id = $1', [s.batch.id]);
  const submitted = await desktop.act('seller-a', 'submit', { batchId: s.batch.id, submitKey: 'big' });
  assert.equal(submitted.status, 200);
  assert.equal(submitted.body.result.listings, 1000);
  const listed = (await pool.query("select count(*)::int as n from public.marketplace_user_listings where source = 'pokoin_scan_batch'")).rows[0];
  assert.equal(listed.n, 1000);
  console.log(`1000 scans ingested sequentially in ${elapsed} ms`);
});
