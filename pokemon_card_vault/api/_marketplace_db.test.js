const assert = require('node:assert/strict');
const test = require('node:test');

const {
  configuredMarketplaceReadReplicaDatabaseUrls,
  marketplaceDatabaseUrl,
  marketplaceAnalyticsSearchDatabaseUrls,
  marketplaceDimensionSearchDatabaseUrls,
  marketplaceDimensionSearchRoute,
  marketplaceNameSearchDatabaseUrl,
  marketplaceVariationSearchDatabaseUrls,
  supabaseNameIndexConfigured,
  supabaseNameIndexDatabaseUrl,
} = require('./_marketplace_db');

test('marketplace search replica env defaults to primary urls', () => {
  const originalPrimary = process.env.MARKETPLACE_DATABASE_URL;
  const originalName = process.env.MARKETPLACE_NAME_SEARCH_DATABASE_URL;
  const originalVariation = process.env.MARKETPLACE_VARIATION_SEARCH_DATABASE_URL;
  const originalVariationList = process.env.MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS;
  const originalAnalyticsList = process.env.MARKETPLACE_ANALYTICS_SEARCH_REPLICA_URLS;
  const originalPeer1 = process.env.MARKETPLACE_PEER1_DATABASE_URL;
  const originalPeer2 = process.env.MARKETPLACE_PEER2_DATABASE_URL;
  const originalPeer3 = process.env.MARKETPLACE_PEER3_DATABASE_URL;
  const originalPeer4 = process.env.MARKETPLACE_PEER4_DATABASE_URL;
  try {
    process.env.MARKETPLACE_DATABASE_URL = 'postgres://primary.example/db';
    delete process.env.MARKETPLACE_NAME_SEARCH_DATABASE_URL;
    delete process.env.MARKETPLACE_VARIATION_SEARCH_DATABASE_URL;
    delete process.env.MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS;
    delete process.env.MARKETPLACE_ANALYTICS_SEARCH_REPLICA_URLS;
    delete process.env.MARKETPLACE_PEER1_DATABASE_URL;
    delete process.env.MARKETPLACE_PEER2_DATABASE_URL;
    delete process.env.MARKETPLACE_PEER3_DATABASE_URL;
    delete process.env.MARKETPLACE_PEER4_DATABASE_URL;

    assert.equal(marketplaceDatabaseUrl(), 'postgres://primary.example/db');
    assert.equal(marketplaceNameSearchDatabaseUrl(), 'postgres://primary.example/db');
    assert.deepEqual(marketplaceVariationSearchDatabaseUrls(), ['postgres://primary.example/db']);
  } finally {
    if (originalPrimary === undefined) delete process.env.MARKETPLACE_DATABASE_URL;
    else process.env.MARKETPLACE_DATABASE_URL = originalPrimary;
    if (originalName === undefined) delete process.env.MARKETPLACE_NAME_SEARCH_DATABASE_URL;
    else process.env.MARKETPLACE_NAME_SEARCH_DATABASE_URL = originalName;
    if (originalVariation === undefined) delete process.env.MARKETPLACE_VARIATION_SEARCH_DATABASE_URL;
    else process.env.MARKETPLACE_VARIATION_SEARCH_DATABASE_URL = originalVariation;
    if (originalVariationList === undefined) delete process.env.MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS;
    else process.env.MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS = originalVariationList;
    if (originalAnalyticsList === undefined) delete process.env.MARKETPLACE_ANALYTICS_SEARCH_REPLICA_URLS;
    else process.env.MARKETPLACE_ANALYTICS_SEARCH_REPLICA_URLS = originalAnalyticsList;
    if (originalPeer1 === undefined) delete process.env.MARKETPLACE_PEER1_DATABASE_URL;
    else process.env.MARKETPLACE_PEER1_DATABASE_URL = originalPeer1;
    if (originalPeer2 === undefined) delete process.env.MARKETPLACE_PEER2_DATABASE_URL;
    else process.env.MARKETPLACE_PEER2_DATABASE_URL = originalPeer2;
    if (originalPeer3 === undefined) delete process.env.MARKETPLACE_PEER3_DATABASE_URL;
    else process.env.MARKETPLACE_PEER3_DATABASE_URL = originalPeer3;
    if (originalPeer4 === undefined) delete process.env.MARKETPLACE_PEER4_DATABASE_URL;
    else process.env.MARKETPLACE_PEER4_DATABASE_URL = originalPeer4;
  }
});

test('Supabase name index is optional and separately configured', () => {
  const originalNameIndex = process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
  const originalPoolerUrl = process.env.SUPABASE_DB_POOLER_URL;
  const originalDbUrl = process.env.SUPABASE_DB_URL;
  try {
    delete process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
    delete process.env.SUPABASE_DB_POOLER_URL;
    delete process.env.SUPABASE_DB_URL;
    assert.equal(supabaseNameIndexDatabaseUrl(), '');
    assert.equal(supabaseNameIndexConfigured(), false);

    process.env.SUPABASE_DB_URL = 'postgres://supabase.example/forum-and-name-index';
    assert.equal(supabaseNameIndexDatabaseUrl(), 'postgres://supabase.example/forum-and-name-index');
    assert.equal(supabaseNameIndexConfigured(), true);

    process.env.SUPABASE_DB_POOLER_URL = 'postgres://supabase.example/pooler-name-index';
    assert.equal(supabaseNameIndexDatabaseUrl(), 'postgres://supabase.example/pooler-name-index');
    assert.equal(supabaseNameIndexConfigured(), true);

    process.env.SUPABASE_NAME_INDEX_DATABASE_URL = 'postgres://supabase.example/name-index';
    assert.equal(supabaseNameIndexDatabaseUrl(), 'postgres://supabase.example/name-index');
    assert.equal(supabaseNameIndexConfigured(), true);
  } finally {
    if (originalNameIndex === undefined) delete process.env.SUPABASE_NAME_INDEX_DATABASE_URL;
    else process.env.SUPABASE_NAME_INDEX_DATABASE_URL = originalNameIndex;
    if (originalPoolerUrl === undefined) delete process.env.SUPABASE_DB_POOLER_URL;
    else process.env.SUPABASE_DB_POOLER_URL = originalPoolerUrl;
    if (originalDbUrl === undefined) delete process.env.SUPABASE_DB_URL;
    else process.env.SUPABASE_DB_URL = originalDbUrl;
  }
});

test('explicit peer urls support four-instance read routing', () => {
  const original = {
    primary: process.env.MARKETPLACE_DATABASE_URL,
    peer1: process.env.MARKETPLACE_PEER1_DATABASE_URL,
    peer2: process.env.MARKETPLACE_PEER2_DATABASE_URL,
    peer3: process.env.MARKETPLACE_PEER3_DATABASE_URL,
    peer4: process.env.MARKETPLACE_PEER4_DATABASE_URL,
    name: process.env.MARKETPLACE_NAME_SEARCH_DATABASE_URL,
    variation: process.env.MARKETPLACE_VARIATION_SEARCH_DATABASE_URL,
    variationList: process.env.MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS,
    analyticsList: process.env.MARKETPLACE_ANALYTICS_SEARCH_REPLICA_URLS,
  };
  try {
    delete process.env.MARKETPLACE_DATABASE_URL;
    delete process.env.MARKETPLACE_NAME_SEARCH_DATABASE_URL;
    delete process.env.MARKETPLACE_VARIATION_SEARCH_DATABASE_URL;
    delete process.env.MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS;
    delete process.env.MARKETPLACE_ANALYTICS_SEARCH_REPLICA_URLS;
    process.env.MARKETPLACE_PEER4_DATABASE_URL = 'postgres://peer4.example/db';
    process.env.MARKETPLACE_PEER3_DATABASE_URL = 'postgres://peer3.example/db';
    process.env.MARKETPLACE_PEER2_DATABASE_URL = 'postgres://peer2.example/db';
    process.env.MARKETPLACE_PEER1_DATABASE_URL = 'postgres://peer1.example/db';

    assert.equal(marketplaceDatabaseUrl(), 'postgres://peer4.example/db');
    assert.equal(marketplaceNameSearchDatabaseUrl(), 'postgres://peer3.example/db');
    assert.deepEqual(marketplaceVariationSearchDatabaseUrls(), [
      'postgres://peer2.example/db',
      'postgres://peer1.example/db',
    ]);
    assert.deepEqual(configuredMarketplaceReadReplicaDatabaseUrls(), [
      'postgres://peer2.example/db',
      'postgres://peer1.example/db',
      'postgres://peer3.example/db',
    ]);
    assert.deepEqual(marketplaceAnalyticsSearchDatabaseUrls(), [
      'postgres://peer2.example/db',
      'postgres://peer1.example/db',
      'postgres://peer3.example/db',
    ]);
  } finally {
    for (const [key, value] of Object.entries({
      MARKETPLACE_DATABASE_URL: original.primary,
      MARKETPLACE_PEER1_DATABASE_URL: original.peer1,
      MARKETPLACE_PEER2_DATABASE_URL: original.peer2,
      MARKETPLACE_PEER3_DATABASE_URL: original.peer3,
      MARKETPLACE_PEER4_DATABASE_URL: original.peer4,
      MARKETPLACE_NAME_SEARCH_DATABASE_URL: original.name,
      MARKETPLACE_VARIATION_SEARCH_DATABASE_URL: original.variation,
      MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS: original.variationList,
      MARKETPLACE_ANALYTICS_SEARCH_REPLICA_URLS: original.analyticsList,
    })) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
});

test('marketplace variation replicas accept comma-separated peer urls', () => {
  const originalPrimary = process.env.MARKETPLACE_DATABASE_URL;
  const originalVariationList = process.env.MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS;
  const originalPeer1 = process.env.MARKETPLACE_PEER1_DATABASE_URL;
  const originalPeer2 = process.env.MARKETPLACE_PEER2_DATABASE_URL;
  try {
    process.env.MARKETPLACE_DATABASE_URL = 'postgres://primary.example/db';
    process.env.MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS =
      ' postgres://peer2.example/db , postgres://peer1.example/db ,, ';
    delete process.env.MARKETPLACE_PEER1_DATABASE_URL;
    delete process.env.MARKETPLACE_PEER2_DATABASE_URL;

    assert.deepEqual(marketplaceVariationSearchDatabaseUrls(), [
      'postgres://peer2.example/db',
      'postgres://peer1.example/db',
    ]);
  } finally {
    if (originalPrimary === undefined) delete process.env.MARKETPLACE_DATABASE_URL;
    else process.env.MARKETPLACE_DATABASE_URL = originalPrimary;
    if (originalVariationList === undefined) delete process.env.MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS;
    else process.env.MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS = originalVariationList;
    if (originalPeer1 === undefined) delete process.env.MARKETPLACE_PEER1_DATABASE_URL;
    else process.env.MARKETPLACE_PEER1_DATABASE_URL = originalPeer1;
    if (originalPeer2 === undefined) delete process.env.MARKETPLACE_PEER2_DATABASE_URL;
    else process.env.MARKETPLACE_PEER2_DATABASE_URL = originalPeer2;
  }
});

test('dimension routes map specialized sources across configured peers', () => {
  const original = {
    primary: process.env.MARKETPLACE_DATABASE_URL,
    peer1: process.env.MARKETPLACE_PEER1_DATABASE_URL,
    peer2: process.env.MARKETPLACE_PEER2_DATABASE_URL,
    peer3: process.env.MARKETPLACE_PEER3_DATABASE_URL,
    peer4: process.env.MARKETPLACE_PEER4_DATABASE_URL,
    number: process.env.MARKETPLACE_NUMBER_SEARCH_DATABASE_URL,
    expansion: process.env.MARKETPLACE_EXPANSION_SEARCH_DATABASE_URL,
    rarity: process.env.MARKETPLACE_RARITY_SEARCH_DATABASE_URL,
    owner: process.env.MARKETPLACE_VARIATION_OWNER_SEARCH_DATABASE_URL,
  };
  try {
    delete process.env.MARKETPLACE_DATABASE_URL;
    process.env.MARKETPLACE_PEER4_DATABASE_URL = 'postgres://peer4.example/db';
    process.env.MARKETPLACE_PEER3_DATABASE_URL = 'postgres://peer3.example/db';
    process.env.MARKETPLACE_PEER2_DATABASE_URL = 'postgres://peer2.example/db';
    process.env.MARKETPLACE_PEER1_DATABASE_URL = 'postgres://peer1.example/db';
    delete process.env.MARKETPLACE_NUMBER_SEARCH_DATABASE_URL;
    delete process.env.MARKETPLACE_EXPANSION_SEARCH_DATABASE_URL;
    delete process.env.MARKETPLACE_RARITY_SEARCH_DATABASE_URL;
    delete process.env.MARKETPLACE_VARIATION_OWNER_SEARCH_DATABASE_URL;

    assert.deepEqual(marketplaceDimensionSearchDatabaseUrls(), {
      number: 'postgres://peer2.example/db',
      expansion: 'postgres://peer1.example/db',
      rarity: 'postgres://peer3.example/db',
      variation_owner: 'postgres://peer2.example/db',
    });
    assert.equal(marketplaceDimensionSearchRoute('number').configured, true);
    assert.equal(marketplaceDimensionSearchRoute('number').fallbackToPrimary, false);
  } finally {
    for (const [key, value] of Object.entries({
      MARKETPLACE_DATABASE_URL: original.primary,
      MARKETPLACE_PEER1_DATABASE_URL: original.peer1,
      MARKETPLACE_PEER2_DATABASE_URL: original.peer2,
      MARKETPLACE_PEER3_DATABASE_URL: original.peer3,
      MARKETPLACE_PEER4_DATABASE_URL: original.peer4,
      MARKETPLACE_NUMBER_SEARCH_DATABASE_URL: original.number,
      MARKETPLACE_EXPANSION_SEARCH_DATABASE_URL: original.expansion,
      MARKETPLACE_RARITY_SEARCH_DATABASE_URL: original.rarity,
      MARKETPLACE_VARIATION_OWNER_SEARCH_DATABASE_URL: original.owner,
    })) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
});

test('dimension routes expose primary fallback when peers are missing', () => {
  const originalPrimary = process.env.MARKETPLACE_DATABASE_URL;
  const originalPeer1 = process.env.MARKETPLACE_PEER1_DATABASE_URL;
  const originalPeer2 = process.env.MARKETPLACE_PEER2_DATABASE_URL;
  const originalPeer3 = process.env.MARKETPLACE_PEER3_DATABASE_URL;
  try {
    process.env.MARKETPLACE_DATABASE_URL = 'postgres://primary.example/db';
    delete process.env.MARKETPLACE_PEER1_DATABASE_URL;
    delete process.env.MARKETPLACE_PEER2_DATABASE_URL;
    delete process.env.MARKETPLACE_PEER3_DATABASE_URL;

    assert.equal(marketplaceDimensionSearchRoute('number').configured, false);
    assert.equal(marketplaceDimensionSearchRoute('number').fallbackToPrimary, true);
  } finally {
    if (originalPrimary === undefined) delete process.env.MARKETPLACE_DATABASE_URL;
    else process.env.MARKETPLACE_DATABASE_URL = originalPrimary;
    if (originalPeer1 === undefined) delete process.env.MARKETPLACE_PEER1_DATABASE_URL;
    else process.env.MARKETPLACE_PEER1_DATABASE_URL = originalPeer1;
    if (originalPeer2 === undefined) delete process.env.MARKETPLACE_PEER2_DATABASE_URL;
    else process.env.MARKETPLACE_PEER2_DATABASE_URL = originalPeer2;
    if (originalPeer3 === undefined) delete process.env.MARKETPLACE_PEER3_DATABASE_URL;
    else process.env.MARKETPLACE_PEER3_DATABASE_URL = originalPeer3;
  }
});

test('legacy single variation replica env is still supported', () => {
  const originalPrimary = process.env.MARKETPLACE_DATABASE_URL;
  const originalVariation = process.env.MARKETPLACE_VARIATION_SEARCH_DATABASE_URL;
  const originalVariationList = process.env.MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS;
  const originalPeer1 = process.env.MARKETPLACE_PEER1_DATABASE_URL;
  const originalPeer2 = process.env.MARKETPLACE_PEER2_DATABASE_URL;
  try {
    process.env.MARKETPLACE_DATABASE_URL = 'postgres://primary.example/db';
    process.env.MARKETPLACE_VARIATION_SEARCH_DATABASE_URL = 'postgres://peer2.example/db';
    delete process.env.MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS;
    delete process.env.MARKETPLACE_PEER1_DATABASE_URL;
    delete process.env.MARKETPLACE_PEER2_DATABASE_URL;

    assert.deepEqual(marketplaceVariationSearchDatabaseUrls(), ['postgres://peer2.example/db']);
  } finally {
    if (originalPrimary === undefined) delete process.env.MARKETPLACE_DATABASE_URL;
    else process.env.MARKETPLACE_DATABASE_URL = originalPrimary;
    if (originalVariation === undefined) delete process.env.MARKETPLACE_VARIATION_SEARCH_DATABASE_URL;
    else process.env.MARKETPLACE_VARIATION_SEARCH_DATABASE_URL = originalVariation;
    if (originalVariationList === undefined) delete process.env.MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS;
    else process.env.MARKETPLACE_VARIATION_SEARCH_REPLICA_URLS = originalVariationList;
    if (originalPeer1 === undefined) delete process.env.MARKETPLACE_PEER1_DATABASE_URL;
    else process.env.MARKETPLACE_PEER1_DATABASE_URL = originalPeer1;
    if (originalPeer2 === undefined) delete process.env.MARKETPLACE_PEER2_DATABASE_URL;
    else process.env.MARKETPLACE_PEER2_DATABASE_URL = originalPeer2;
  }
});
