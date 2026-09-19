const assert = require('node:assert/strict');
const test = require('node:test');
const {
  attachExpansionNationality,
  resetExpansionNationalityCache,
} = require('./_expansion_nationality');
const { createHandler } = require('./marketplace-suggest');

function mockRes() {
  const res = {
    statusCode: 200,
    headers: {},
    body: null,
    setHeader(key, value) {
      this.headers[key] = value;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
    end() {
      return this;
    },
  };
  return res;
}

test('attachExpansionNationality stamps japanese and chinese from the expansion table', async () => {
  resetExpansionNationalityCache();
  const groups = await attachExpansionNationality(
    [
      {
        name: 'Pikachu',
        printings: [
          { id: '1', set: 'Terastal Festival ex' },
          { id: '2', set: 'Phantasmal Flames' },
          { id: '3', set_name: 'Gem Pack Vol.1' },
        ],
      },
    ],
    async () => ({
      rows: [
        { name: 'Terastal Festival ex', normalized_name: 'terastal festival ex', nationality: 'japanese' },
        { name: 'Phantasmal Flames', normalized_name: 'phantasmal flames', nationality: 'western' },
        { name: 'Gem Pack Vol.1', normalized_name: 'gem pack vol 1', nationality: 'chinese' },
      ],
    }),
  );
  assert.equal(groups[0].printings[0].nationality, 'japanese');
  assert.equal(groups[0].printings[1].nationality, 'western');
  assert.equal(groups[0].printings[2].nationality, 'chinese');
});

test('suggest handler attaches nationality when a query fn is injected', async () => {
  resetExpansionNationalityCache();
  const handler = createHandler({
    meiliConfigured: () => true,
    useMeiliSearchForLanguage: () => true,
    marketplaceDatabaseUrl: () => '',
    marketplaceQuery: async () => ({
      rows: [{ name: 'Night Wanderer', normalized_name: 'night wanderer', nationality: 'japanese' }],
    }),
    meiliMarketplaceSuggestHits: async () => [{
      card_id: '10',
      name: 'Mimikyu',
      name_group: 'Mimikyu',
      set_name: 'Night Wanderer',
      card_number: '1/1',
    }],
  });
  const res = mockRes();
  await handler({
    method: 'GET',
    url: '/api/marketplace-suggest?q=mimikyu&limit=8',
    headers: { host: 'api.pokoin.com' },
  }, res);
  assert.equal(res.body.groups[0].printings[0].nationality, 'japanese');
});
