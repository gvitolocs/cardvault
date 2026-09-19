'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');

// Count-invariant contract: displayed_count(Q) must be the count of results
// matching the exact normalized query, produced by the SAME query object as
// the rows. "pikachu gx 30th" must never be counted (or retrieved) as
// "pikachu" via Meili's token-dropping "last" strategy.

const apiDir = __dirname;
const meiliSource = fs.readFileSync(path.join(apiDir, '_meili_marketplace.js'), 'utf8');
const candidatesSource = fs.readFileSync(path.join(apiDir, 'marketplace-search-candidates.js'), 'utf8');
const cardsSource = fs.readFileSync(path.join(apiDir, 'marketplace-cards.js'), 'utf8');
const searchPageSource = fs.readFileSync(path.join(apiDir, 'marketplace-search-page.js'), 'utf8');

test('search candidates run match=all so multi-token queries never shrink', () => {
  const candidatesBody = meiliSource.slice(
    meiliSource.indexOf('async function meiliMarketplaceCandidates'),
    meiliSource.indexOf('async function meiliMarketplaceSuggestHits'),
  );
  assert.match(candidatesBody, /matchingStrategy: 'all',/);
  assert.doesNotMatch(candidatesBody, /matchingStrategy === 'all'/);
});

test('candidates return the estimatedTotalHits of that exact query', () => {
  const candidatesBody = meiliSource.slice(
    meiliSource.indexOf('async function meiliMarketplaceCandidates'),
    meiliSource.indexOf('async function meiliMarketplaceSuggestHits'),
  );
  assert.match(candidatesBody, /estimatedTotalHits: Number\(response\.estimatedTotalHits \|\| response\.nbHits \|\| hits\.length\) \|\| 0/);
});

test('search rows and total share one candidates query; no hot-pool rows', () => {
  assert.doesNotMatch(candidatesSource, /takeHotSuggestCandidates/);
  assert.match(candidatesSource, /withTotal === true/);
  assert.match(candidatesSource, /total: Number\(loaded\.total\) \|\| 0/);
});

test('rowsForCards threads the same-predicate total through both engines', () => {
  // Meili window: the { rows, total } payload rides the candidates load.
  assert.match(cardsSource, /withTotal: withTotal === true/);
  assert.match(cardsSource, /return \{ rows: next, total: Number\.isFinite\(meiliTotal\) \? meiliTotal : null \};/);
  // Legacy SQL path: same-WHERE exact count via a window function evaluated
  // before LIMIT — no second query, no divergent predicate.
  assert.match(cardsSource, /count\(\*\) over \(\) as total_count/);
  assert.match(cardsSource, /return \{ rows, total: Number\.isFinite\(firstRowCount\) \? firstRowCount : null \};/);
});

test('marketplace-search-page exposes total beside count', () => {
  assert.match(searchPageSource, /withTotal: true/);
  assert.match(searchPageSource, /total: queryTotal,/);
});
