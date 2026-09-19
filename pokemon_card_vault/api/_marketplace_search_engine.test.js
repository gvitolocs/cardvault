const assert = require('node:assert/strict');
const test = require('node:test');

const {
  marketplaceSearchEngine,
  useMeiliSearchForLanguage,
} = require('./_marketplace_search_engine');

test('search engine defaults to legacy', () => {
  const original = process.env.MARKETPLACE_SEARCH_ENGINE;
  delete process.env.MARKETPLACE_SEARCH_ENGINE;
  try {
    assert.equal(marketplaceSearchEngine(), 'legacy');
  } finally {
    if (original === undefined) delete process.env.MARKETPLACE_SEARCH_ENGINE;
    else process.env.MARKETPLACE_SEARCH_ENGINE = original;
  }
});

test('meili serves every title-language against the English identity index', () => {
  const original = process.env.MARKETPLACE_SEARCH_ENGINE;
  process.env.MARKETPLACE_SEARCH_ENGINE = 'meili';
  try {
    assert.equal(useMeiliSearchForLanguage('en'), true);
    assert.equal(useMeiliSearchForLanguage('EN'), true);
    assert.equal(useMeiliSearchForLanguage('it'), true);
    assert.equal(useMeiliSearchForLanguage('fr'), true);
    assert.equal(useMeiliSearchForLanguage('jp'), true);
    assert.equal(useMeiliSearchForLanguage(''), true);
  } finally {
    if (original === undefined) delete process.env.MARKETPLACE_SEARCH_ENGINE;
    else process.env.MARKETPLACE_SEARCH_ENGINE = original;
  }
});
