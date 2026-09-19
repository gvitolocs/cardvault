'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const rules = require('./_scan_connect');

test('submitProblem: list still requires price; collection does not', () => {
  const base = {
    status: 'active',
    card_id: '220962',
    recognition_state: 'matched',
    quantity: 1,
    price_pkn: null,
  };
  assert.equal(rules.submitProblem(base), 'no_price');
  assert.equal(rules.submitProblem(base, { intent: 'list' }), 'no_price');
  assert.equal(rules.submitProblem(base, { intent: 'collection' }), '');
  assert.equal(rules.submitProblem({ ...base, price_pkn: 10 }), '');
});

test('submitProblem: recognition blockers still apply in collection mode', () => {
  const base = {
    status: 'active',
    card_id: '220962',
    recognition_state: 'ambiguous',
    reviewed: false,
    quantity: 1,
    price_pkn: null,
  };
  assert.equal(rules.submitProblem(base, { intent: 'collection' }), 'needs_review');
  assert.equal(rules.submitProblem({ ...base, card_id: null }, { intent: 'collection' }), 'no_printing');
  assert.equal(
    rules.submitProblem({
      ...base,
      recognition_state: 'matched',
      graded: true,
      grading_company: 'PSA',
      grade: null,
    }, { intent: 'collection' }),
    'grading_incomplete',
  );
  assert.equal(
    rules.submitProblem({ ...base, recognition_state: 'matched', quantity: 0 }, { intent: 'collection' }),
    'bad_quantity',
  );
});

test('submitProblem: missing intent defaults to list (price required)', () => {
  assert.equal(
    rules.submitProblem({
      status: 'active',
      card_id: '1',
      recognition_state: 'matched',
      quantity: 1,
      price_pkn: 0,
    }),
    'no_price',
  );
});
