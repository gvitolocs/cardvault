const assert = require('node:assert/strict');
const test = require('node:test');

const {
  isPromotionalSellerComment,
  publicSellerComment,
} = require('./_seller_comment_filter');

test('seller comment filter hides promotional store messages', () => {
  assert.equal(isPromotionalSellerComment('Check my store, more cards available! :3'), true);
  assert.equal(publicSellerComment('Check my store, more cards available! :3'), '');
  assert.equal(publicSellerComment('Visit my shop for more cards'), '');
  assert.equal(publicSellerComment('More cards available'), '');
  assert.equal(publicSellerComment('DM me on Instagram'), '');
  assert.equal(publicSellerComment('www.example.com'), '');
});

test('seller comment filter preserves condition notes and strips markup', () => {
  assert.equal(publicSellerComment('Tiny edge whitening'), 'Tiny edge whitening');
  assert.equal(publicSellerComment('Available photos show whitening on back'), 'Available photos show whitening on back');
  assert.equal(publicSellerComment('Please check photos for corner wear'), 'Please check photos for corner wear');
  assert.equal(publicSellerComment('<b>Small scratch</b> on holo'), 'Small scratch on holo');
  assert.equal(publicSellerComment('<script>alert(1)</script>Clean front'), 'Clean front');
});
