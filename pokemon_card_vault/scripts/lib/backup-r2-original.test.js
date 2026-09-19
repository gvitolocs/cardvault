const assert = require('node:assert/strict');
const test = require('node:test');
const {
  CopyObjectCommand,
  HeadObjectCommand,
} = require('@aws-sdk/client-s3');
const {
  originalsKeyFor,
  siblingPngKey,
  copySource,
  backupExistingObject,
} = require('./backup-r2-original');

test('originalsKeyFor prefixes leftover keys once', () => {
  assert.equal(originalsKeyFor('299026_dachsbun.jpg'), 'originals/299026_dachsbun.jpg');
  assert.equal(originalsKeyFor('previews/110481_espurr.jpg'), 'originals/previews/110481_espurr.jpg');
  assert.equal(originalsKeyFor('originals/299026_dachsbun.jpg'), null);
  assert.equal(originalsKeyFor(''), null);
});

test('siblingPngKey keeps leftover prefix and folder, swaps extension', () => {
  assert.equal(siblingPngKey('351691_mega-lucario-ex.jpg'), '351691_mega-lucario-ex.png');
  assert.equal(
    siblingPngKey('previews/110481_espurr-58-122-breakpoint.webp'),
    'previews/110481_espurr-58-122-breakpoint.png',
  );
  assert.equal(siblingPngKey('122576_mimikyu-gx.png'), '122576_mimikyu-gx.png');
  assert.equal(siblingPngKey('originals/351691_mega-lucario-ex.jpg'), null);
});

test('copySource encodes each key segment', () => {
  assert.equal(
    copySource('cardvault-images', 'previews/a b.jpg'),
    'cardvault-images/previews/a%20b.jpg',
  );
});

test('backupExistingObject copies a live key once and never overwrites originals/', async () => {
  const keys = new Set(['351691_mega-lucario-ex.jpg']);
  const copies = [];
  const client = {
    async send(command) {
      const key = command.input.Key;
      if (command instanceof HeadObjectCommand) {
        if (keys.has(key)) {
          return {};
        }
        const error = new Error('not found');
        error.name = 'NotFound';
        error.$metadata = { httpStatusCode: 404 };
        throw error;
      }
      if (command instanceof CopyObjectCommand) {
        copies.push({ from: command.input.CopySource, to: key });
        keys.add(key);
        return {};
      }
      throw new Error(`unexpected ${command.constructor.name}`);
    },
  };

  const first = await backupExistingObject(client, {
    bucket: 'cardvault-images',
    key: '351691_mega-lucario-ex.jpg',
  });
  assert.equal(first.backedUp, true);
  assert.equal(first.originalsKey, 'originals/351691_mega-lucario-ex.jpg');
  assert.equal(copies.length, 1);

  const second = await backupExistingObject(client, {
    bucket: 'cardvault-images',
    key: '351691_mega-lucario-ex.jpg',
  });
  assert.equal(second.backedUp, false);
  assert.equal(second.reason, 'already-backed-up');
  assert.equal(copies.length, 1);
});

test('backupExistingObject skips missing live objects', async () => {
  const client = {
    async send(command) {
      if (command instanceof HeadObjectCommand) {
        const error = new Error('not found');
        error.name = 'NoSuchKey';
        error.$metadata = { httpStatusCode: 404 };
        throw error;
      }
      throw new Error('should not copy');
    },
  };
  const result = await backupExistingObject(client, {
    bucket: 'cardvault-images',
    key: 'missing.jpg',
  });
  assert.equal(result.reason, 'missing');
});
