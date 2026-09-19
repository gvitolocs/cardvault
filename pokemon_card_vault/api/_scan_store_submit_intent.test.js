'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { createStore } = require('./_scan_store');

const BATCH = '22222222-2222-4222-8222-222222222222';
const ITEM = '11111111-1111-4111-8111-111111111111';

function itemRow(overrides = {}) {
  return {
    id: ITEM,
    batch_id: BATCH,
    seller_uid: 'seller',
    status: 'active',
    card_id: '220962',
    recognition_state: 'matched',
    reviewed: false,
    quantity: 2,
    price_pkn: 10,
    condition: 'NM',
    language: 'EN',
    foil_state: 'standard',
    signed: false,
    first_edition: false,
    graded: false,
    grading_company: null,
    grade: null,
    certification_id: null,
    seller_comment: '',
    card_name: 'Espurr',
    image_url: '',
    set_name: 'XY',
    collector_number: '1/100',
    location: '',
    altered: false,
    position: 1,
    ...overrides,
  };
}

function createHarness({ ownershipImpl } = {}) {
  const state = {
    batchStatus: 'open',
    submitResult: null,
    item: itemRow(),
    listings: new Map(), // source_listing_id -> { id, status }
    ownershipCalls: [],
    activateCalls: [],
  };

  const store = createStore({
    pool: {
      async connect() {
        return {
          async query(sql, params = []) {
            const text = String(sql);
            if (/^begin|^commit|^rollback/i.test(text.trim())) return { rows: [] };
            if (/select \* from public\.scan_batches where id = \$1 and seller_uid = \$2 for update/i.test(text)) {
              return {
                rows: [{
                  id: BATCH,
                  seller_uid: 'seller',
                  status: state.batchStatus,
                  defaults: {},
                  submit_result: state.submitResult,
                  version: 1,
                }],
              };
            }
            if (/select \* from public\.scan_items where batch_id = \$1 and status = 'active'/i.test(text)) {
              const items = state.items || [state.item];
              return { rows: items.filter((it) => it.status === 'active').map((it) => ({ ...it })) };
            }
            if (/insert into public\.marketplace_user_listings/i.test(text)) {
              const sourceListingId = params[16];
              const existing = state.listings.get(sourceListingId);
              if (existing) {
                if (existing.status === 'inactive') {
                  existing.price = params[5];
                  existing.qty = params[6];
                  existing.location = params[21];
                  return { rows: [{ id: existing.id, status: 'inactive' }] };
                }
                return { rows: [] };
              }
              const id = `L${state.listings.size + 1}`;
              state.listings.set(sourceListingId, { id, status: 'inactive', price: params[5], qty: params[6], location: params[21] });
              return { rows: [{ id, status: 'inactive' }] };
            }
            if (/select id, status from public\.marketplace_user_listings where source = 'pokoin_scan_batch'/i.test(text)
              || /select id from public\.marketplace_user_listings where source = 'pokoin_scan_batch'/i.test(text)) {
              const row = state.listings.get(params[0]);
              return { rows: row ? [{ id: row.id, status: row.status }] : [] };
            }
            if (/update public\.marketplace_user_listings\s+set status = 'active'/i.test(text)) {
              state.activateCalls.push({ listingId: params[0], sourceListingId: params[1] });
              for (const row of state.listings.values()) {
                if (row.id === params[0] && row.status === 'inactive') {
                  row.status = 'active';
                  return { rows: [{ id: row.id }] };
                }
              }
              return { rows: [] };
            }
            if (/update public\.scan_batches\s+set item_seq/i.test(text)) {
              return { rows: [{ item_seq: 9, item_position: 1 }] };
            }
            if (/update public\.scan_items set status = 'submitted'/i.test(text)) {
              const items = state.items || [state.item];
              const target = items.find((it) => it.id === params[0]) || state.item;
              target.status = 'submitted';
              target.listing_id = params[1];
              return { rows: [] };
            }
            if (/update public\.scan_batches\s+set status = 'submitted'/i.test(text)) {
              state.batchStatus = 'submitted';
              state.submitResult = params[2];
              return {
                rows: [{
                  id: BATCH,
                  seller_uid: 'seller',
                  status: 'submitted',
                  defaults: {},
                  submit_result: state.submitResult,
                  version: 2,
                }],
              };
            }
            if (/select id from public\.scan_sessions where batch_id/i.test(text)) {
              return { rows: [] };
            }
            throw new Error(`unexpected SQL: ${text.slice(0, 180)}`);
          },
          release() {},
        };
      },
    },
    upsertScanOwnership: async (args) => {
      state.ownershipCalls.push(args);
      if (ownershipImpl) return ownershipImpl(args, state);
      return {
        docId: `scan:${args.row.id}`,
        listingId: args.listingId,
        quantity: args.row.quantity,
        created: true,
      };
    },
  });

  return { store, state };
}

function listingStatus(state) {
  return [...state.listings.values()][0]?.status || null;
}

test('collection intent: ownership only, no listing, no price required', async () => {
  const { store, state } = createHarness();
  state.item = itemRow({ price_pkn: null });
  const out = await store.submitBatch({
    sellerUid: 'seller',
    batchId: BATCH,
    submitKey: 'c1',
    intent: 'collection',
  });
  assert.equal(out.result.intent, 'collection');
  assert.equal(out.result.listings, 0);
  assert.equal(out.result.ownership, 1);
  assert.equal(state.listings.size, 0);
  assert.equal(state.ownershipCalls[0].listingId, null);
});

test('list intent defaults when intent omitted; requires price; writes listing+ownership', async () => {
  const { store, state } = createHarness();
  state.item = itemRow({ price_pkn: null });
  await assert.rejects(
    () => store.submitBatch({ sellerUid: 'seller', batchId: BATCH, submitKey: 'l0' }),
    (err) => err.code === 'not_ready',
  );

  state.item = itemRow({ price_pkn: 42 });
  state.batchStatus = 'open';
  state.submitResult = null;
  state.item.status = 'active';
  state.listings.clear();
  state.ownershipCalls.length = 0;
  state.activateCalls.length = 0;

  const out = await store.submitBatch({
    sellerUid: 'seller',
    batchId: BATCH,
    submitKey: 'l1',
  });
  assert.equal(out.result.intent, 'list');
  assert.equal(out.result.listings, 1);
  assert.equal(state.ownershipCalls[0].listingId, 'L1');
  assert.equal(listingStatus(state), 'active');
  assert.equal(state.activateCalls.length, 1);
  assert.equal(state.batchStatus, 'submitted');
});

test('already submitted returns cached result without second ownership write', async () => {
  const { store, state } = createHarness();
  const first = await store.submitBatch({
    sellerUid: 'seller',
    batchId: BATCH,
    submitKey: 'l2',
    intent: 'list',
  });
  state.ownershipCalls.length = 0;
  state.activateCalls.length = 0;
  const again = await store.submitBatch({
    sellerUid: 'seller',
    batchId: BATCH,
    submitKey: 'l2',
    intent: 'list',
  });
  assert.equal(again.alreadySubmitted, true);
  assert.deepEqual(again.result, first.result);
  assert.equal(state.ownershipCalls.length, 0);
  assert.equal(state.activateCalls.length, 0);
});

test('list race: listing stays inactive/non-purchasable until ownership+finalize; retry activates', async () => {
  let failOnce = true;
  const { store, state } = createHarness({
    ownershipImpl: async (args) => {
      if (failOnce) {
        failOnce = false;
        throw new Error('firestore down');
      }
      return { docId: `scan:${args.row.id}`, listingId: args.listingId, quantity: 1, created: true };
    },
  });

  await assert.rejects(
    () => store.submitBatch({
      sellerUid: 'seller',
      batchId: BATCH,
      submitKey: 'r1',
      intent: 'list',
    }),
    (err) => err.code === 'ownership_write_failed',
  );
  assert.equal(state.batchStatus, 'open');
  assert.equal(state.listings.size, 1);
  assert.equal(listingStatus(state), 'inactive', 'listing must not be purchasable before finalize');
  assert.equal(state.activateCalls.length, 0);

  const ok = await store.submitBatch({
    sellerUid: 'seller',
    batchId: BATCH,
    submitKey: 'r1',
    intent: 'list',
  });
  assert.equal(ok.result.intent, 'list');
  assert.equal(state.batchStatus, 'submitted');
  assert.equal(listingStatus(state), 'active');
  assert.equal(state.activateCalls.length, 1);
});

test('invariant: activating a scan listing only happens with batch submit in the same finalize path', async () => {
  const { store, state } = createHarness();
  await store.submitBatch({
    sellerUid: 'seller',
    batchId: BATCH,
    submitKey: 'inv',
    intent: 'list',
  });
  assert.equal(listingStatus(state), 'active');
  assert.equal(state.batchStatus, 'submitted');
  // Activate was recorded only during finalize (after ownership).
  assert.ok(state.activateCalls.length >= 1);
  assert.ok(state.ownershipCalls.length >= 1);
});

test('submit composes the position inside the box into the listing location', async () => {
  const { store, state } = createHarness();
  // Queue order: box1 continues at 47, a stack of 3 takes 48-50, a pile
  // re-anchored at 100 starts there, box2 anchors on its own capture-time 12.
  state.items = [
    itemRow({ id: 'a', position: 1, quantity: 1, location: 'box1', defaults_snapshot: { startPosition: 47 } }),
    itemRow({ id: 'b', position: 2, quantity: 3, location: 'box1', defaults_snapshot: { startPosition: 47 } }),
    itemRow({ id: 'c', position: 3, quantity: 2, location: 'box1', defaults_snapshot: { startPosition: 100 } }),
    itemRow({ id: 'd', position: 4, quantity: 1, location: 'box2', defaults_snapshot: { startPosition: 12 } }),
  ];
  const out = await store.submitBatch({
    sellerUid: 'seller',
    batchId: BATCH,
    submitKey: 'slots',
    intent: 'list',
  });
  assert.equal(out.result.listings, 4);
  assert.deepEqual(
    [...state.listings.values()].map((l) => l.location),
    ['box1·47', 'box1·48-50', 'box1·100-101', 'box2·12'],
  );
});

test('rows without a location submit an empty location and take no slot', async () => {
  const { store, state } = createHarness();
  state.items = [
    itemRow({ id: 'a', position: 1, quantity: 2, location: '', defaults_snapshot: { startPosition: 47 } }),
    itemRow({ id: 'b', position: 2, quantity: 1, location: 'box1', defaults_snapshot: { startPosition: 47 } }),
  ];
  await store.submitBatch({ sellerUid: 'seller', batchId: BATCH, submitKey: 'slots2', intent: 'list' });
  const bySource = new Map([...state.listings.entries()]);
  assert.equal(bySource.get('scan:a').location, '');
  assert.equal(bySource.get('scan:b').location, 'box1·47');
});

test('rows without a captured start position anchor at 1', async () => {
  const { store, state } = createHarness();
  state.items = [
    itemRow({ id: 'a', position: 1, quantity: 2, location: 'box1' }),
    itemRow({ id: 'b', position: 2, quantity: 1, location: 'box1' }),
  ];
  await store.submitBatch({ sellerUid: 'seller', batchId: BATCH, submitKey: 'slots3', intent: 'list' });
  assert.deepEqual(
    [...state.listings.values()].map((l) => l.location),
    ['box1·1-2', 'box1·3'],
  );
});
