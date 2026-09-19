'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { assembleHomeVector, publicizeCards } = require('./_marketplace_rails');

test('assembleHomeVector uses Pi source and public ids only', () => {
  const vector = assembleHomeVector([
    {
      id: 'new_cards',
      meta: { pknUsdt: 0.005 },
      cards: [{
        card_id: 668126,
        ct_id: 334063,
        name: 'Levincia',
        set_name: 'Destined Rivals',
        card_number: '244/182',
        image_url: '/card-images/334063_levincia.jpg',
      }],
    },
    {
      id: 'featured',
      cards: [{ card_id: '703382', name: 'Mega Lucario ex', card_number: '188/132' }],
    },
  ], '2026-09-06T00:00:00.000Z');
  assert.equal(vector.source, 'pi');
  assert.deepEqual(vector.sections.newArrivalIds, ['668126']);
  const levincia = vector.cards.find((card) => card.id === '668126');
  assert.equal(levincia.ct_id, undefined);
  assert.match(levincia.imageUrl, /\/card-images\/668126_levincia/);
});

test('publicizeCards strips leftover blueprint field', () => {
  const [card] = publicizeCards([{
    card_id: 220962,
    ct_id: 110481,
    name: 'Espurr',
    card_number: '58/122',
    image_url: 'https://cdn.pokoin.com/110481_espurr.jpg',
  }]);
  assert.equal(card.id, '220962');
  assert.equal(card.ct_id, undefined);
  assert.equal(card.imageUrl, '/card-images/220962_espurr.jpg');
});

test('new_cards rail keeps twenty curated ids in published order', () => {
  const cards = Array.from({ length: 20 }, (_, index) => ({
    card_id: String(index + 1),
    name: index % 3 === 0 ? 'Mega Rayquaza ex' : `Card ${index + 1}`,
    card_number: `${String(113 - index).padStart(3, '0')}/076`,
    image_url: `/card-images/${index + 1}_card.jpg`,
  }));
  const vector = assembleHomeVector([{ id: 'new_cards', cards }]);
  assert.equal(vector.sections.newArrivalIds.length, 20);
  assert.deepEqual(vector.sections.newArrivalIds, cards.map((card) => card.card_id));
});

test('featured rail keeps thirty 30th Anniversary ids', () => {
  const cards = Array.from({ length: 30 }, (_, index) => ({
    card_id: String(index + 1),
    name: `Anniversary ${index + 1}`,
    set_name: '30th Celebration JP',
    image_url: `/card-images/${index + 1}_card.jpg`,
  }));
  const vector = assembleHomeVector([{ id: 'featured', cards }]);
  assert.equal(vector.sections.featuredIds.length, 30);
  assert.deepEqual(vector.sections.featuredIds, cards.map((card) => card.card_id));
});
