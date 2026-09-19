'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {
  bumpUnread,
  isParticipant,
  otherMember,
  pairKeyFor,
  previewForEvent,
  unreadFor,
  validateAmountPkn,
  validateEvent,
} = require('./_chat_core.js');

const A = 'uid-aaa';
const B = 'uid-bbb';

test('pair keys are canonical: A/B and B/A resolve to the same id', () => {
  assert.equal(pairKeyFor(A, B), pairKeyFor(B, A));
  assert.equal(pairKeyFor(A, B), `${A}__${B}`); // sorted
  assert.throws(() => pairKeyFor(A, A));
  assert.throws(() => pairKeyFor(A, ''));
});

test('participant checks accept both members and reject everyone else', () => {
  const key = pairKeyFor(A, B);
  assert.equal(isParticipant(key, A), true);
  assert.equal(isParticipant(key, B), true);
  assert.equal(isParticipant(key, 'uid-intruder'), false);
  assert.equal(otherMember(key, A), B);
  assert.equal(otherMember(key, B), A);
});

test('event validation accepts typed events and rejects junk', () => {
  assert.deepEqual(
    validateEvent({ type: 'text', text: '  hello   world ' }).value,
    { type: 'text', text: 'hello world' },
  );
  assert.ok(validateEvent({ type: 'text', text: '   ' }).error);
  const request = validateEvent({ type: 'money_request', amountPkn: 125, requestId: 'req_1', note: 'cards' });
  assert.equal(request.value.requestId, 'req_1');
  assert.equal(request.value.note, 'cards');
  assert.ok(validateEvent({ type: 'money_request', amountPkn: -1 }).error);
  const payment = validateEvent({ type: 'payment', amountPkn: 5, transactionId: 'ledger_9' });
  assert.equal(payment.value.transactionId, 'ledger_9');
  assert.ok(validateEvent({ type: 'hologram' }).error);
  assert.equal(validateAmountPkn(1e10).error, 'That amount is too large.');
});

test('unread bumps only move the non-sender counter', () => {
  const members = [A, B];
  let unread = bumpUnread({}, members, B);
  assert.equal(unread[A], 1);
  assert.equal(unread[B], 0);
  unread = bumpUnread(unread, members, B);
  unread = bumpUnread(unread, members, A);
  assert.equal(unread[A], 2);
  assert.equal(unread[B], 1);
  assert.equal(unreadFor({ unread }, A), 2);
  assert.equal(unreadFor({}, A), 0);
});

test('previews are human sentences, not event type names', () => {
  assert.equal(previewForEvent({ type: 'text', text: "I'll ship it tomorrow" }), "I'll ship it tomorrow");
  assert.equal(previewForEvent({ type: 'money_request', amountPkn: 50 }), 'Requested 50 PKN');
  assert.equal(previewForEvent({ type: 'money_request', amountPkn: 125, paid: true }), 'Paid ✓ 125 PKN');
  assert.equal(previewForEvent({ type: 'payment', amountPkn: 125, incoming: true }), 'Sent you 125 PKN');
  assert.equal(previewForEvent({ type: 'payment', amountPkn: 40 }), 'You sent 40 PKN');
});
