'use strict';

const assert = require('node:assert/strict');
const { test } = require('node:test');
const rules = require('./_scan_connect');
const http = require('./_scan_http');

test('PIN is exactly four digits from the injected CSPRNG, zero padded', () => {
  assert.equal(rules.randomPin(() => 7), '0007');
  assert.equal(rules.randomPin(() => 9999), '9999');
  let seenArgs;
  rules.randomPin((min, max) => {
    seenArgs = [min, max];
    return 0;
  });
  assert.deepEqual(seenArgs, [0, 10000]);
  for (let i = 0; i < 2000; i += 1) {
    assert.match(rules.randomPin(), /^[0-9]{4}$/);
  }
  assert.equal(rules.isPin('0123'), true);
  for (const bad of ['123', '12345', '12a4', ' 1234', '', null, 1234.5]) {
    assert.equal(rules.isPin(bad), false, String(bad));
  }
});

test('phone tokens are 256-bit url-safe secrets and stored only as sha256', () => {
  const token = rules.randomSecret(32);
  assert.match(token, /^[A-Za-z0-9_-]{43}$/);
  assert.notEqual(rules.randomSecret(32), token);
  assert.match(rules.sha256(token), /^[0-9a-f]{64}$/);
  assert.notEqual(rules.sha256(token), token);
});

test('classification: matched needs 0.80 and a 0.08 margin; ambiguous 0.60+; else unmatched', () => {
  const hit = (id, score) => ({ public_id: id, score, name: `c${id}` });
  assert.equal(rules.classifyRecognition([hit('2', 0.91)]).state, 'matched');
  assert.equal(rules.classifyRecognition([hit('2', 0.91), hit('4', 0.82)]).state, 'matched');
  assert.equal(rules.classifyRecognition([hit('2', 0.91), hit('4', 0.84)]).state, 'ambiguous');
  assert.equal(rules.classifyRecognition([hit('2', 0.79)]).state, 'ambiguous');
  assert.equal(rules.classifyRecognition([hit('2', 0.60)]).state, 'ambiguous');
  assert.equal(rules.classifyRecognition([hit('2', 0.59)]).state, 'unmatched');
  assert.equal(rules.classifyRecognition([]).state, 'unmatched');
  const amb = rules.classifyRecognition([hit('2', 0.7), hit('4', 0.66), hit('6', 0.4)]);
  assert.deepEqual(amb.candidates.map((c) => c.cardId), ['2', '4']);
});

test('candidates use public_id only, never a TCGplayer id, and dedupe', () => {
  const list = rules.candidatesFromHits([
    { id: '632917', score: 0.99 },
    { public_id: '220962', score: 0.9 },
    { public_id: '220962', score: 0.85 },
    { public_id: 'abc', score: 0.95 },
    { public_id: '10', score: 'x' },
  ]);
  assert.deepEqual(list, [{ cardId: '220962', score: 0.9, name: '' }]);
});

test('defaults snapshot is the version in force at capture time', () => {
  const history = [
    { version: 1, changedAt: 1000, defaults: { language: 'IT' } },
    { version: 2, changedAt: 5000, defaults: { language: 'EN' } },
    { version: 3, changedAt: 9000, defaults: { language: 'JP', location: 'Box B' } },
  ];
  assert.equal(rules.pickDefaults(history, 4999).defaults.language, 'IT');
  assert.equal(rules.pickDefaults(history, 5000).defaults.language, 'EN');
  assert.equal(rules.pickDefaults(history, 8999).version, 2);
  const late = rules.pickDefaults(history, 12000);
  assert.equal(late.defaults.language, 'JP');
  assert.equal(late.defaults.location, 'Box B');
  // Captured before the first entry → first entry, never undefined.
  assert.equal(rules.pickDefaults(history, 10).defaults.language, 'IT');
  assert.equal(rules.pickDefaults([], 10).defaults.language, 'EN');
});

test('defaults changed while a scan is in flight: capture time wins, not receipt', () => {
  const history = [
    { version: 1, changedAt: 0, defaults: { language: 'IT' } },
    { version: 2, changedAt: 10_000, defaults: { language: 'EN' } },
  ];
  // Phone clock is 3 s behind the server. Captured at server 9 500, arrived 10 400.
  const inFlight = rules.capturedAtServer({ capturedAt: 6_500, clockOffsetMs: 3_000, receivedAtMs: 10_400 });
  assert.equal(inFlight, 9_500);
  assert.equal(rules.pickDefaults(history, inFlight).defaults.language, 'IT');
  // Captured 100 ms after the change even though the phone never saw it.
  const after = rules.capturedAtServer({ capturedAt: 7_100, clockOffsetMs: 3_000, receivedAtMs: 10_300 });
  assert.equal(rules.pickDefaults(history, after).defaults.language, 'EN');
});

test('capturedAtServer clamps skewed clocks and falls back to receipt', () => {
  assert.equal(rules.capturedAtServer({ capturedAt: 99_999_999, clockOffsetMs: 0, receivedAtMs: 1000 }), 1000);
  assert.equal(rules.capturedAtServer({ capturedAt: 1, clockOffsetMs: 0, receivedAtMs: 1000, floorMs: 500 }), 500);
  assert.equal(rules.capturedAtServer({ capturedAt: 'x', clockOffsetMs: 0, receivedAtMs: 1000 }), 1000);
  assert.equal(rules.capturedAtServer({ capturedAt: 900, clockOffsetMs: 90_000_000, receivedAtMs: 1000 }), 1000);
});

test('defaults normalize to Pokoin values and keep the base for missing keys', () => {
  const d = rules.normalizeDefaults({ language: 'it', condition: 'Mint', quantity: 400, location: ' Box A12 ', foilState: 'REVERSE' });
  assert.deepEqual(d, { ...rules.DEFAULT_BATCH_DEFAULTS, language: 'IT', condition: 'NM', quantity: 99, location: 'Box A12', foilState: 'reverse' });
  const partial = rules.normalizeDefaults({ signed: true }, d);
  assert.equal(partial.language, 'IT');
  assert.equal(partial.signed, true);
  // Start position rides beside the box: the label shows where the pile continues.
  assert.equal(rules.defaultsLabel(d), 'IT · NM · Reverse · Box A12·1 · Qty 99');
  // Size 1: startPosition is legacy flat counter → lands on stack.
  assert.equal(rules.normalizeDefaults({ startPosition: 3000 }).stack, 3000);
  assert.equal(rules.normalizeDefaults({ startPosition: 3000 }).startPosition, 1);
  assert.equal(rules.normalizeDefaults({ startPosition: 0 }, d).stack, 1);
  assert.equal(rules.normalizeDefaults({ startPosition: 99999 }, d).stack, 9999);
  assert.equal(rules.normalizeDefaults({ signed: true }, d).startPosition, 1);
  assert.equal(rules.normalizeDefaults({ signed: true }, d).stack, 1);
});

test('stack key: PowerTools identity mapped to Pokoin plus location', () => {
  const base = { cardId: '220962', condition: 'NM', language: 'IT', foilState: 'standard', firstEdition: false, signed: false, altered: false, graded: false, gradingCompany: '', grade: '', location: 'Box A12' };
  assert.equal(rules.stackKey(base), rules.stackKey({ ...base, location: 'box a12 ' }));
  for (const [key, value] of Object.entries({ cardId: '220964', condition: 'SP', language: 'EN', foilState: 'reverse', firstEdition: true, signed: true, altered: true, graded: true, gradingCompany: 'PSA', grade: '10', location: 'Binder 3' })) {
    assert.notEqual(rules.stackKey(base), rules.stackKey({ ...base, [key]: value }), key);
  }
  // snake_case rows from Postgres produce the same key.
  assert.equal(rules.stackKey(base), rules.stackKey({ card_id: '220962', condition: 'NM', language: 'IT', foil_state: 'standard', first_edition: false, signed: false, altered: false, graded: false, grading_company: '', grade: '', location: 'Box A12' }));
});

test('merge: only matched repeats with identical attributes into an active matched head', () => {
  const snapshot = rules.normalizeDefaults({ language: 'EN', location: 'Box A12' });
  const previous = { status: 'active', recognition_state: 'matched', card_id: '220962', condition: 'NM', language: 'EN', foil_state: 'standard', first_edition: false, signed: false, altered: false, graded: false, location: 'Box A12' };
  const matched = { state: 'matched' };
  assert.equal(rules.shouldMerge({ previous, recognition: matched, cardId: '220962', snapshot }), true);
  assert.equal(rules.shouldMerge({ previous, recognition: matched, cardId: '220964', snapshot }), false);
  assert.equal(rules.shouldMerge({ previous, recognition: { state: 'ambiguous' }, cardId: '220962', snapshot }), false);
  assert.equal(rules.shouldMerge({ previous: { ...previous, recognition_state: 'ambiguous' }, recognition: matched, cardId: '220962', snapshot }), false);
  assert.equal(rules.shouldMerge({ previous: { ...previous, recognition_state: 'ambiguous', reviewed: true }, recognition: matched, cardId: '220962', snapshot }), true);
  assert.equal(rules.shouldMerge({ previous: { ...previous, language: 'IT' }, recognition: matched, cardId: '220962', snapshot }), false);
  assert.equal(rules.shouldMerge({ previous: { ...previous, status: 'removed' }, recognition: matched, cardId: '220962', snapshot }), false);
  assert.equal(rules.shouldMerge({ previous, recognition: matched, cardId: '220962', snapshot: { ...snapshot, mergeRepeats: false } }), false);
  assert.equal(rules.shouldMerge({ previous: null, recognition: matched, cardId: '220962', snapshot }), false);
});

test('scan event parsing rejects bad ids, oversize and non-JPEG images', () => {
  const jpeg = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(100)]).toString('base64');
  const ok = rules.parseScanEvent({ scanEventId: '8f14e45f-ceea-4e7b-a3d2-5b6a3c9f1a2b', clientSequence: 3, capturedAt: 1, image: jpeg, recognition: { hits: [] }, timings: { identifyMs: 240.4, evil: 1 } });
  assert.equal(ok.clientSequence, 3);
  assert.equal(ok.image.length, 104);
  assert.deepEqual(ok.timings, { identifyMs: 240 });
  assert.throws(() => rules.parseScanEvent({ scanEventId: 'nope', clientSequence: 1 }), /UUID/);
  assert.throws(() => rules.parseScanEvent({ scanEventId: '8f14e45f-ceea-4e7b-a3d2-5b6a3c9f1a2b' }), /clientSequence/);
  assert.throws(() => rules.parseScanEvent({ scanEventId: '8f14e45f-ceea-4e7b-a3d2-5b6a3c9f1a2b', clientSequence: 1, image: Buffer.from('GIF89a').toString('base64') }), /JPEG/);
  const big = Buffer.concat([Buffer.from([0xff, 0xd8]), Buffer.alloc(rules.MAX_IMAGE_BYTES)]).toString('base64');
  assert.throws(() => rules.parseScanEvent({ scanEventId: '8f14e45f-ceea-4e7b-a3d2-5b6a3c9f1a2b', clientSequence: 1, image: big }), (e) => e.statusCode === 413);
});

test('item patch validates Pokoin values and maps to columns', () => {
  const cols = rules.parseItemPatch({ language: 'jp', quantity: 4, pricePkn: 12.345, foilState: 'reverse', confirm: true, unknown: 1 });
  assert.deepEqual(cols, [
    { column: 'language', value: 'JP' },
    { column: 'foil_state', value: 'reverse' },
    { column: 'quantity', value: 4 },
    { column: 'price_pkn', value: 12.35 },
    { column: 'price_suggested', value: false },
    { column: 'reviewed', value: true },
  ]);
  assert.throws(() => rules.parseItemPatch({ quantity: 0 }), /Quantity/);
  assert.throws(() => rules.parseItemPatch({ quantity: 100 }), /Quantity/);
  assert.throws(() => rules.parseItemPatch({ condition: 'EX' }), /condition/);
  assert.throws(() => rules.parseItemPatch({ cardId: '12a' }), /card id/);
  assert.throws(() => rules.parseItemPatch({ pricePkn: -1 }), /price/);
});

test('submit readiness', () => {
  const ok = { status: 'active', card_id: '220962', recognition_state: 'matched', price_pkn: 10, quantity: 1 };
  assert.equal(rules.submitProblem(ok), '');
  assert.equal(rules.submitProblem({ ...ok, status: 'removed', card_id: null }), '');
  assert.equal(rules.submitProblem({ ...ok, card_id: null }), 'no_printing');
  assert.equal(rules.submitProblem({ ...ok, recognition_state: 'ambiguous' }), 'needs_review');
  assert.equal(rules.submitProblem({ ...ok, recognition_state: 'ambiguous', reviewed: true }), '');
  assert.equal(rules.submitProblem({ ...ok, price_pkn: null }), 'no_price');
  assert.equal(rules.submitProblem({ ...ok, graded: true, grading_company: 'PSA' }), 'grading_incomplete');
});

test('session view derives lost / scanning / expired', () => {
  const now = 1_000_000;
  const base = { id: 's', batch_id: 'b', status: 'connected', phone_last_seen_at: new Date(now - 1000), last_scan_at: null, version: 1 };
  assert.equal(rules.sessionView(base, now).phase, 'connected');
  assert.equal(rules.sessionView({ ...base, last_scan_at: new Date(now - 2000) }, now).phase, 'scanning');
  assert.equal(rules.sessionView({ ...base, phone_last_seen_at: new Date(now - rules.PHONE_LOST_MS) }, now).phase, 'lost');
  assert.equal(rules.sessionView({ ...base, status: 'ended', end_reason: 'expired' }, now).phase, 'expired');
  assert.equal(rules.sessionView({ ...base, status: 'ended', end_reason: 'logout' }, now).phase, 'completed');
  assert.equal(rules.sessionView({ ...base, status: 'waiting' }, now).phase, 'waiting');
  assert.equal(rules.isIdleExpired({ status: 'waiting', last_activity_at: new Date(now - rules.SESSION_IDLE_MS) }, now), true);
  assert.equal(rules.isIdleExpired({ status: 'ended', last_activity_at: new Date(0) }, now), false);
  // Connected phones use scan-idle, not the 30-minute waiting timer.
  assert.equal(rules.isIdleExpired({
    status: 'connected',
    last_activity_at: new Date(now - rules.SESSION_IDLE_MS),
  }, now), false);
});

test('scan idle: last_scan_at ?? phone_connected_at; heartbeat presence does not count', () => {
  const now = 2_000_000;
  const connected = {
    status: 'connected',
    phone_connected_at: new Date(now - rules.SCAN_IDLE_MS),
    last_scan_at: null,
    phone_last_seen_at: new Date(now), // fresh heartbeat must not keep the phone alive
    last_activity_at: new Date(now),
  };
  assert.equal(rules.scanIdleActivityMs(connected), now - rules.SCAN_IDLE_MS);
  assert.equal(rules.isScanIdleExpired(connected, now), true);
  assert.equal(rules.isScanIdleExpired({
    ...connected,
    phone_connected_at: new Date(now - rules.SCAN_IDLE_MS + 1),
  }, now), false);

  const scanned = {
    ...connected,
    phone_connected_at: new Date(now - 60 * 60_000),
    last_scan_at: new Date(now - rules.SCAN_IDLE_MS + 5_000),
  };
  assert.equal(rules.isScanIdleExpired(scanned, now), false);
  assert.equal(rules.isScanIdleExpired({
    ...scanned,
    last_scan_at: new Date(now - rules.SCAN_IDLE_MS),
  }, now), true);

  assert.equal(rules.isScanIdleExpired({ status: 'waiting', phone_connected_at: new Date(0) }, now), false);
  assert.equal(rules.isScanIdleExpired({ status: 'ended', phone_connected_at: new Date(0) }, now), false);
});

test('device label never echoes arbitrary user agents', () => {
  assert.equal(rules.deviceLabel('Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)'), 'iPhone');
  assert.equal(rules.deviceLabel('Mozilla/5.0 (Linux; Android 15; Pixel 9) Mobile'), 'Android phone');
  assert.equal(rules.deviceLabel('curl/8'), 'Phone');
  assert.equal(rules.deviceLabel('', '  Giuseppe iPhone  '), 'Giuseppe iPhone');
});

test('CORS allowlist: production origins only; localhost outside production', () => {
  assert.equal(http.allowedOrigin('https://scan.pokoin.com', { NODE_ENV: 'production' }), 'https://scan.pokoin.com');
  assert.equal(http.allowedOrigin('https://pokoin.com', { NODE_ENV: 'production' }), 'https://pokoin.com');
  assert.equal(http.allowedOrigin('https://evil.example', { NODE_ENV: 'production' }), '');
  assert.equal(http.allowedOrigin('https://scan.pokoin.com.evil.example', { NODE_ENV: 'production' }), '');
  assert.equal(http.allowedOrigin('http://localhost:5174', { NODE_ENV: 'production' }), '');
  assert.equal(http.allowedOrigin('http://localhost:5174', { NODE_ENV: 'development' }), 'http://localhost:5174');
});

test('client IP prefers Cloudflare header', () => {
  assert.equal(http.clientIp({ headers: { 'cf-connecting-ip': '1.2.3.4', 'x-forwarded-for': '9.9.9.9' } }), '1.2.3.4');
  assert.equal(http.clientIp({ headers: { 'x-forwarded-for': '9.9.9.9, 10.0.0.1' } }), '9.9.9.9');
  assert.equal(http.clientIp({ headers: {}, socket: { remoteAddress: '127.0.0.1' } }), '127.0.0.1');
  assert.equal(http.phoneToken({ headers: { authorization: 'Scan abc' } }), 'abc');
  assert.equal(http.phoneToken({ headers: { authorization: 'Bearer abc' } }), '');
});

test('stack defaults: size 1 hides position in label; size >1 shows stack·pos', () => {
  const d1 = rules.normalizeDefaults({ location: 'box1', stack: 3, stackSize: 1, startPosition: 9 });
  assert.equal(d1.startPosition, 1);
  assert.equal(d1.stack, 3);
  assert.equal(rules.locationDefaultsText(d1), 'box1·3');
  const d10 = rules.normalizeDefaults({ location: 'box1', stack: 2, stackSize: 10, startPosition: 5 });
  assert.equal(rules.locationDefaultsText(d10), 'box1·2·5');
});

test('boxSlots size 1: legacy flat startPosition still yields box·N', () => {
  const rows = [
    { id: 'a', location: 'box1', quantity: 1, defaults_snapshot: { startPosition: 47 } },
    { id: 'b', location: 'box1', quantity: 3, defaults_snapshot: { startPosition: 47 } },
  ];
  const slots = rules.boxSlots(rows);
  assert.equal(rules.slotText(slots.get('a')), '·47');
  assert.equal(rules.slotText(slots.get('b')), '·48-50');
});

test('boxSlots sized stacks: listing uses stack·pos and flags filledStack', () => {
  const rows = [
    { id: 'a', location: 'box1', quantity: 1, defaults_snapshot: { stack: 1, stackSize: 5, startPosition: 4 } },
    { id: 'b', location: 'box1', quantity: 2, defaults_snapshot: { stack: 1, stackSize: 5, startPosition: 4 } },
  ];
  const slots = rules.boxSlots(rows);
  assert.equal(rules.slotText(slots.get('a')), '·1·4');
  assert.equal(slots.get('a').filledStack, false);
  // b starts at max(5,4)=5 then takes 2 → abs 5-6 → stack1 pos5 + spill stack2 pos1
  assert.equal(slots.get('b').filledStack, true);
  assert.ok(rules.slotText(slots.get('b')).includes('·'));
});

// ---- Printing choice (artwork → print family → printings) ----
// Fixtures mirror production catalog rows (marketplace_search_candidates +
// pokoin_pokemon_expansions). No set or program is special-cased in code.

const hit = (public_id, score) => ({ public_id, score, name: 'Card' });
const p = (card_id, set_name, card_number, version, nationality, kind = 'official', code = '') => ({
  card_id, name: 'Card', set_name, card_number, version, nationality, kind, code, symbol_image_url: '', image_url: '',
});
const GRASS = 'v222492';
const ENERGY = [
  p('242396', 'HeartGold & SoulSilver', '115/123', GRASS, 'western', 'official', 'hgs'),
  p('224950', 'Call of Legends', '88/95', GRASS, 'western', 'official', 'clo'),
  p('279166', 'HeartGold Collection', '2009', GRASS, 'japanese'),
  p('525054', 'League Promos', 'Play! Pokemon | Holo Promo 88/95', GRASS, 'western', 'promo', 'lpr'),
  p('222492', 'Base Set', '99/102', GRASS, 'western'),
  p('268388', 'Base Set Shadowless', 'Shadowless | 99/102', GRASS, 'western', 'subset'),
  p('264058', 'XY', '132/146', GRASS, 'western'),
  p('242398', 'HeartGold & SoulSilver', '116/123', 'v222490', 'western'),
];
const PUMPKABOO = [
  p('332628', 'Evolving Skies', '076/203', 'v332628', 'western'),
  p('484518', 'Play! Pokémon Prize Pack Series', '076/203', 'v332628', 'western', 'promo', 'playprizep'),
  p('609516', 'World Championship Decks 2022', 'WCD 2022 | Ondrej Skubal | 076/203', 'v332628', 'western', 'side_product'),
  p('448040', 'Trick or Trade', '076/203', 'v332628', 'american', 'side_product', 'trickortrade'),
  p('270600', 'Towering Perfection', '016/067', 'v332628', 'japanese'),
];
const WOCHIEN = [
  p('540696', 'Shiny Treasure ex', 'Gold Secret Rare | 355/190', 'v540696', 'japanese'),
  p('548848', 'Paldean Fates', 'Gold Secret Rare | 240/091', 'v540696', 'western'),
  p('722606', 'CSVL2: Travel Special Pack', 'CSVL2C | Gold Secret Rare 129/052', 'v540696', 'chinese'),
];
const ids = (res) => res.printings.map((row) => row.card_id);

test('printFamily: the batch language fixes the candidate universe before any printing choice', () => {
  for (const lang of ['EN', 'IT', 'FR', 'DE', 'ES', 'PT', 'NL', 'PL', 'RU']) {
    assert.deepEqual(rules.printFamily(lang).tiers, [['western']], lang);
  }
  assert.deepEqual(rules.printFamily('JP').tiers, [['japanese'], ['korean']]);
  assert.deepEqual(rules.printFamily('KO').tiers, [['korean'], ['japanese']]);
  assert.deepEqual(rules.printFamily('ZH').tiers, [['chinese']]);
  assert.deepEqual(rules.printFamily('ZHT').tiers, [['chinese']]);
  assert.equal(rules.printFamily('').id, 'western');
});

test('A. one western printing: no choice, today\'s automatic match', () => {
  const res = rules.resolvePrintings({
    hits: [hit('548848', 0.95), hit('540696', 0.9)],
    rows: WOCHIEN,
    language: 'EN',
  });
  assert.equal(res.state, 'matched');
  assert.equal(res.choose, false);
  assert.equal(res.cardId, '548848');
});

test('B. HGSS energy: the artwork matches, the printing is asked, never picked', () => {
  const hits = [hit('242396', 0.95), hit('224950', 0.949), hit('279166', 0.93), hit('222492', 0.8)];
  const res = rules.resolvePrintings({ hits, rows: ENERGY, language: 'EN' });
  assert.equal(res.state, 'ambiguous');
  assert.equal(res.choose, true);
  // Tied in-family hits + the unscored same-number stamped reprint (COL 88/95 Play! promo).
  // Base Set 99/102 was scored and ruled out (0.80 < 0.95 − 0.08); XY 132/146 is another number.
  assert.deepEqual(ids(res), ['224950', '242396', '525054']);
  assert.equal(res.cardId, '242396', 'provisional card is the best-scored one, pending review');
  const tiles = res.printings.map(rules.printingTile);
  assert.deepEqual(tiles.map((t) => [t.setName, t.number, t.setCode]), [
    ['Call of Legends', '88/95', 'CLO'],
    ['HeartGold & SoulSilver', '115/123', 'HGS'],
    ['League Promos', '88/95', 'LPR'],
  ]);
  assert.equal(tiles[1].symbolUrl, 'https://cdn.pokoin.com/expansions/symbols/heartgold-and-soulsilver.png?v=cm1');
  assert.equal(tiles[2].detail, 'Play! Pokemon · Holo Promo');
  assert.equal(tiles[0].label, 'Call of Legends, card 88/95');

  const picked = rules.resolvePrintings({ hits, rows: ENERGY, language: 'EN', choice: '224950' });
  assert.equal(picked.state, 'matched');
  assert.equal(picked.cardId, '224950');
  assert.equal(picked.chosen, '224950');
});

test('B. a choice the server does not offer is ignored', () => {
  const hits = [hit('242396', 0.95), hit('224950', 0.949)];
  const res = rules.resolvePrintings({ hits, rows: ENERGY, language: 'EN', choice: '264058' });
  assert.equal(res.state, 'ambiguous');
  assert.equal(res.chosen, '');
});

test('C. western batch: Japanese / Chinese printings of the same artwork are never offered', () => {
  const hits = [hit('279166', 0.99), hit('242396', 0.95), hit('224950', 0.95)];
  const res = rules.resolvePrintings({ hits, rows: ENERGY, language: 'IT' });
  assert.ok(!ids(res).includes('279166'));
  assert.ok(res.printings.every((row) => ['western', 'american'].includes(row.nationality)));
  const wo = rules.resolvePrintings({ hits: [hit('540696', 0.97), hit('722606', 0.93), hit('548848', 0.9)], rows: WOCHIEN, language: 'EN' });
  assert.deepEqual(ids(wo), ['548848']);
  assert.equal(wo.cardId, '548848');
});

test('D. Japanese batch: only the Japanese print family is considered', () => {
  const hits = [hit('242396', 0.99), hit('224950', 0.99), hit('279166', 0.93)];
  const res = rules.resolvePrintings({ hits, rows: ENERGY, language: 'JP' });
  assert.deepEqual(ids(res), ['279166']);
  assert.equal(res.state, 'matched');
  assert.equal(res.choose, false);
});

test('E. Chinese batch: the Chinese printing, never the western duplicate', () => {
  const hits = [hit('548848', 0.97), hit('540696', 0.93), hit('722606', 0.9)];
  const res = rules.resolvePrintings({ hits, rows: WOCHIEN, language: 'ZH' });
  assert.deepEqual(ids(res), ['722606']);
  assert.equal(res.cardId, '722606');
});

test('F. Trick or Trade: original and pumpkin reprint are separate printings with their own mark', () => {
  const hits = [hit('332628', 0.96), hit('484518', 0.955), hit('270600', 0.85)];
  const res = rules.resolvePrintings({ hits, rows: PUMPKABOO, language: 'EN' });
  assert.equal(res.choose, true);
  // Trick or Trade (american print → western family) and WCD are not in the
  // recognition gallery, so they are offered by printed number.
  assert.deepEqual(ids(res), ['332628', '484518', '448040', '609516']);
  const tot = rules.printingTile(res.printings[2]);
  assert.equal(tot.symbolUrl, 'https://cdn.pokoin.com/expansions/symbols/trick-or-trade.png?v=cm1');
  assert.equal(tot.number, '076/203');
  assert.equal(tot.setCode, 'TRICKORTRADE');
  assert.equal(rules.printingTile(res.printings[3]).detail, 'WCD 2022 · Ondrej Skubal');
});

test('G. Play! Pokémon / League stamp: offered when unscored, not when the camera ruled it out', () => {
  const rows = [
    p('332574', 'Evolving Skies', '049/203', 'v332574', 'western'),
    p('600010', 'League Promos', 'League Promo | 049/203', 'v332574', 'western', 'promo', 'lpr'),
  ];
  const unscored = rules.resolvePrintings({ hits: [hit('332574', 0.95)], rows, language: 'EN' });
  assert.deepEqual(ids(unscored), ['332574', '600010']);
  assert.equal(rules.printingTile(unscored.printings[1]).detail, 'League Promo');
  const ruledOut = rules.resolvePrintings({ hits: [hit('332574', 0.95), hit('600010', 0.8)], rows, language: 'EN' });
  assert.deepEqual(ids(ruledOut), ['332574']);
  assert.equal(ruledOut.choose, false);
});

test('only another region\'s printing was seen: family siblings are offered, a long list stays a desk review', () => {
  const two = rules.resolvePrintings({ hits: [hit('270600', 0.95)], rows: PUMPKABOO.filter((r) => r.card_id !== '609516'), language: 'EN' });
  assert.deepEqual(ids(two), ['332628', '484518', '448040']);
  const many = Array.from({ length: rules.MAX_SIBLING_PRINTINGS + 1 }, (_, i) => p(String(900000 + i * 2), `Set ${i}`, `${i + 1}/99`, 'vX', 'western'));
  assert.equal(rules.resolvePrintings({ hits: [hit('279166', 0.95)], rows: [...many, { ...ENERGY[2], version: 'vX' }], language: 'EN' }), null);
});

test('printing layer steps aside: artwork doubt, weak top, no artwork key, no printing in the family', () => {
  // Two artworks within 0.08: recognition doubt, not a printing choice.
  assert.equal(rules.resolvePrintings({ hits: [hit('242396', 0.9), hit('242398', 0.86)], rows: ENERGY, language: 'EN' }), null);
  assert.equal(rules.resolvePrintings({ hits: [hit('242396', 0.79), hit('224950', 0.79)], rows: ENERGY, language: 'EN' }), null);
  assert.equal(rules.resolvePrintings({ hits: [hit('999998', 0.95)], rows: [p('999998', 'X', '1/2', '', 'western')], language: 'EN' }), null);
  assert.equal(rules.resolvePrintings({ hits: [hit('279166', 0.95)], rows: [ENERGY[2]], language: 'EN' }), null);
  assert.equal(rules.resolvePrintings({ hits: [hit('242396', 0.95)], rows: ENERGY, language: 'VI' }), null);
  assert.equal(rules.resolvePrintings({ hits: [hit('242396', 0.95)], rows: [], language: 'EN' }), null);
});

test('printed numbers keep every qualifier and compare n/m without leading zeros', () => {
  assert.deepEqual(rules.printedNumber('Rare | 076/203'), { number: '076/203', key: '76/203', detail: 'Rare' });
  assert.deepEqual(rules.printedNumber('Play! Pokemon | Holo Promo 88/95'), { number: '88/95', key: '88/95', detail: 'Play! Pokemon · Holo Promo' });
  assert.equal(rules.printedNumber('TG01/TG30').key, 'TG1/TG30');
  assert.deepEqual(rules.printedNumber('SVP 135'), { number: 'SVP 135', key: 'SVP135', detail: '' });
  assert.equal(rules.printedNumber('BW-P 140').number, 'BW-P 140');
  assert.deepEqual(rules.printedNumber('2011 Unnumbered'), { number: '', key: '', detail: '2011 Unnumbered' });
  assert.equal(rules.printedNumber('Non-Holo | Trainer Kit 5/30').detail, 'Non-Holo · Trainer Kit');
});

test('printing tile: subset variants stay visible, stored marks are a second source', () => {
  const tile = rules.printingTile({
    card_id: '700002',
    name: 'Eevee',
    set_name: 'Prismatic Evolutions - Master Ball Reverse Holo',
    card_number: '074/131',
    kind: 'subset',
    nationality: 'western',
    code: 'pre',
    symbol_image_url: 'https://cdn.pokoin.com/expansions/symbols/prismatic-evolutions.png',
  });
  assert.equal(tile.detail, 'Master Ball Reverse Holo');
  assert.equal(tile.symbolAltUrl, 'https://cdn.pokoin.com/expansions/symbols/prismatic-evolutions.png');
  assert.equal(tile.label, 'Prismatic Evolutions - Master Ball Reverse Holo, card 074/131, Master Ball Reverse Holo');
});

test('scan event carries the phone printing choice as a public card id only', () => {
  const base = { scanEventId: '5f0c7a4e-2b7c-4c55-9a4e-0d9e3f0a1b2c', clientSequence: 1 };
  assert.equal(rules.parseScanEvent({ ...base, printing: { cardId: '242396' } }).printingChoice, '242396');
  assert.equal(rules.parseScanEvent({ ...base, printing: { cardId: 'x' } }).printingChoice, '');
  assert.equal(rules.parseScanEvent(base).printingChoice, '');
  const req = rules.parsePrintingRequest({ recognition: { hits: Array.from({ length: 20 }, (_, i) => hit(String(i + 2), 0.5)) } });
  assert.equal(req.hits.length, 10);
});

test('ambiguous rows preselect the best candidate of the batch print family, else the best overall', () => {
  const cands = [
    { cardId: '504600', score: 0.83, nationality: 'japanese' },
    { cardId: '233564', score: 0.8, nationality: 'western' },
    { cardId: '722606', score: 0.7, nationality: 'chinese' },
  ];
  assert.equal(rules.provisionalCandidate(cands, 'EN').cardId, '233564');
  assert.equal(rules.provisionalCandidate(cands, 'JP').cardId, '504600');
  assert.equal(rules.provisionalCandidate(cands, 'ZHT').cardId, '722606');
  assert.equal(rules.provisionalCandidate(cands.slice(0, 1), 'EN').cardId, '504600', 'no western candidate: keep the best');
  assert.equal(rules.provisionalCandidate([], 'EN'), null);
});
