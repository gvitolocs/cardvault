'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const {
  STATUS,
  canPay,
  canRespond,
  effectiveStatus,
  validateAmountPkn,
  validateCreate,
} = require('./_money_request_core.js');

const NOW = Date.parse('2026-09-19T12:00:00Z');
const DAY = 24 * 60 * 60 * 1000;

function request(overrides = {}) {
  return {
    status: STATUS.PENDING,
    fromUid: 'requester',
    toUid: 'payer',
    amountPkn: 125,
    createdAt: NOW - DAY,
    ...overrides,
  };
}

test('amounts must be positive integers within range', () => {
  assert.deepEqual(validateAmountPkn(125), { amount: 125 });
  assert.ok(validateAmountPkn(0).error);
  assert.ok(validateAmountPkn(-5).error);
  assert.ok(validateAmountPkn(12.5).error);
  assert.ok(validateAmountPkn('abc').error);
  assert.ok(validateAmountPkn(2e9).error);
});

test('create validation normalises username, note and client token', () => {
  const ok = validateCreate({ recipientUsername: ' Ash ', amountPkn: 25, note: '  cards  ', clientToken: 'abc' });
  assert.equal(ok.value.toUsername, 'ash');
  assert.equal(ok.value.amountPkn, 25);
  assert.equal(ok.value.note, 'cards');
  assert.equal(ok.value.clientToken, 'abc');
  assert.ok(validateCreate({ recipientUsername: 'nope!', amountPkn: 25 }).error);
  assert.ok(validateCreate({ amountPkn: 25 }).error);
});

test('pending requests past the TTL read as expired; others keep their status', () => {
  assert.equal(effectiveStatus(request(), NOW), STATUS.PENDING);
  assert.equal(effectiveStatus(request({ createdAt: NOW - 15 * DAY }), NOW), STATUS.EXPIRED);
  assert.equal(effectiveStatus(request({ status: STATUS.PAID, createdAt: NOW - 40 * DAY }), NOW), STATUS.PAID);
});

test('only the recipient can pay a pending, unexpired request', () => {
  assert.equal(canPay(request(), 'payer').ok, true);
  assert.equal(canPay(request(), 'requester').ok, false);
  assert.equal(canPay(request({ status: STATUS.PAID }), 'payer').error, 'This request was already paid.');
  assert.equal(canPay(request({ status: STATUS.DECLINED }), 'payer').ok, false);
  assert.equal(canPay(request({ status: STATUS.CANCELLED }), 'payer').ok, false);
  assert.equal(canPay(request({ createdAt: NOW - 15 * DAY }), 'payer').error, 'This request has expired.');
  assert.equal(canPay(request(), '').ok, false);
});

test('decline is recipient-only, cancel is requester-only, both pending-only', () => {
  assert.equal(canRespond(request(), 'payer', 'decline').ok, true);
  assert.equal(canRespond(request(), 'requester', 'decline').ok, false);
  assert.equal(canRespond(request(), 'requester', 'cancel').ok, true);
  assert.equal(canRespond(request(), 'payer', 'cancel').ok, false);
  assert.equal(canRespond(request({ status: STATUS.PAID }), 'payer', 'decline').ok, false);
  assert.equal(canRespond(request(), 'payer', 'frobnicate').ok, false);
});
