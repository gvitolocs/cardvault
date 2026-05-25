const assert = require('node:assert/strict');
const Module = require('node:module');
const test = require('node:test');

function loadWorkerWithStubs() {
  const target = require.resolve('./cardtrader-oracle-import-worker');
  const originalLoad = Module._load;
  delete require.cache[target];
  Module._load = function load(request, parent, isMain) {
    if (request === './cardtrader-multigame-import') {
      return {
        parseArgs(argv) {
          return { argv };
        },
        run: async () => ({ counts: { missingRaw: 0 } }),
      };
    }
    return originalLoad.apply(this, arguments);
  };
  try {
    return require('./cardtrader-oracle-import-worker');
  } finally {
    Module._load = originalLoad;
    delete require.cache[target];
  }
}

test('Oracle import worker parseArgs defaults to Pokemon dry-run poll-safe options', () => {
  const worker = loadWorkerWithStubs();
  const options = worker.parseArgs(['--once']);

  assert.equal(options.game, 'pokemon');
  assert.equal(options.mode, 'dry_run');
  assert.equal(options.streamAll, true);
  assert.equal(options.images, true);
  assert.equal(options.refresh, true);
  assert.equal(options.syncSearch, true);
  assert.equal(options.once, true);
});

test('Oracle import worker maps DB job payload to multigame importer args', () => {
  const worker = loadWorkerWithStubs();
  const options = worker.importOptionsFromJob({
    job_id: 'cti_1',
    game: 'pokemon',
    mode: 'apply',
    request_payload: {
      game: 'pokemon',
      mode: 'apply',
      streamAll: false,
      expansionIds: [4611, 4639],
      limit: '5000',
      batchSize: 250,
      concurrency: 3,
      imageConcurrency: 2,
      imageChunkSize: 25,
      images: true,
      refresh: true,
      syncSearch: true,
      ensureSchema: false,
      languages: 'en,it',
      supabaseTransport: 'rest',
    },
  });

  assert.deepEqual(options.argv, [
    '--game=pokemon',
    '--apply',
    '--no-stream-all',
    '--expansion-ids=4611,4639',
    '--limit=5000',
    '--batch-size=250',
    '--concurrency=3',
    '--image-concurrency=2',
    '--image-chunk-size=25',
    '--images',
    '--refresh',
    '--sync-search',
    '--languages=en,it',
    '--supabase-transport=rest',
  ]);
});

test('Oracle import worker acquireNextJob uses skip locked queue claim', async () => {
  const worker = loadWorkerWithStubs();
  const calls = [];
  const pool = {
    query: async (sql, values) => {
      calls.push({ sql, values });
      return { rows: [{ job_id: 'cti_1' }] };
    },
  };

  const job = await worker.acquireNextJob(pool, 'worker-1');

  assert.equal(job.job_id, 'cti_1');
  assert.match(calls[0].sql, /for update skip locked/i);
  assert.match(calls[0].sql, /status = 'running'/i);
  assert.deepEqual(calls[0].values, ['worker-1']);
});
