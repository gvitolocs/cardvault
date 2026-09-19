const assert = require('node:assert/strict');
const test = require('node:test');
const { familyForPath, groupRoutes, FAMILIES } = require('../server/api-route-families');

test('page BFFs stay in page-bff even when the path contains expansion', () => {
  assert.equal(familyForPath('/api/marketplace-expansion-page'), 'page-bff');
  assert.equal(familyForPath('/api/marketplace-card-page'), 'page-bff');
  assert.equal(familyForPath('/api/marketplace-home-page'), 'page-bff');
  assert.equal(familyForPath('/api/marketplace-search-page'), 'page-bff');
  assert.equal(familyForPath('/api/marketplace-portfolio'), 'page-bff');
});

test('catalog routes are not page BFFs', () => {
  assert.equal(familyForPath('/api/marketplace-expansion-symbols'), 'catalog');
  assert.equal(familyForPath('/api/marketplace-expansions'), 'catalog');
});

test('groupRoutes keeps family titles and drops empty families', () => {
  const grouped = groupRoutes([
    { path: '/api/marketplace-expansion-page', methods: ['GET'], file: 'marketplace-expansion-page.js', purpose: 'set desk' },
    { path: '/api/auth-login', methods: ['POST'], file: 'auth-login.js', purpose: 'login' },
  ]);
  assert.deepEqual(grouped.map((row) => row.id), ['page-bff', 'auth']);
  assert.equal(grouped[0].title, FAMILIES.find((row) => row.id === 'page-bff').title);
  assert.equal(grouped[0].routes[0].family, 'page-bff');
});
