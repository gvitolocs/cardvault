const assert = require('node:assert/strict');
const test = require('node:test');

const {
  parseArgs,
  timestampOrNull,
  upsertFirebaseUsersSql,
  upsertValues,
  userRow,
} = require('./sync-firebase-users-to-oracle');

test('parseArgs defaults to dry-run with bounded Firebase page size', () => {
  assert.deepEqual(parseArgs([]), {
    apply: false,
    limit: Infinity,
    pageSize: 1000,
    batchSize: 250,
  });
});

test('userRow keeps minimal Firebase Auth metadata', () => {
  const row = userRow({
    uid: 'abc123',
    email: ' Collector@Example.COM ',
    displayName: 'Collector',
    photoURL: 'https://example.com/avatar.png',
    disabled: true,
    emailVerified: true,
    providerData: [
      { providerId: 'google.com' },
      { providerId: 'password' },
      { providerId: 'google.com' },
    ],
    metadata: {
      creationTime: 'Thu, 21 May 2026 09:00:00 GMT',
      lastSignInTime: 'Thu, 21 May 2026 10:00:00 GMT',
    },
  });

  assert.equal(row.user_uid, 'abc123');
  assert.equal(row.email, 'collector@example.com');
  assert.equal(row.display_name, 'Collector');
  assert.deepEqual(row.provider_ids, ['google.com', 'password']);
  assert.equal(row.disabled, true);
  assert.equal(row.email_verified, true);
  assert.equal(row.firebase_created_at.toISOString(), '2026-05-21T09:00:00.000Z');
  assert.equal(row.firebase_last_sign_in_at.toISOString(), '2026-05-21T10:00:00.000Z');
});

test('timestampOrNull ignores missing or invalid metadata timestamps', () => {
  assert.equal(timestampOrNull(''), null);
  assert.equal(timestampOrNull('not a date'), null);
});

test('upsert SQL targets marketplace_firebase_users by uid', () => {
  const sql = upsertFirebaseUsersSql(2);

  assert.match(sql, /insert into public\.marketplace_firebase_users/);
  assert.match(sql, /on conflict \(user_uid\) do update/);
  assert.match(sql, /firebase_last_sign_in_at = excluded\.firebase_last_sign_in_at/);
  assert.match(sql, /synced_at = now\(\)/);
});

test('upsertValues serializes rows in SQL column order', () => {
  const values = upsertValues([
    {
      user_uid: 'uid-1',
      email: 'a@example.com',
      display_name: 'A',
      photo_url: null,
      disabled: false,
      email_verified: true,
      provider_ids: ['password'],
      firebase_created_at: new Date('2026-05-21T09:00:00.000Z'),
      firebase_last_sign_in_at: null,
    },
  ]);

  assert.deepEqual(values.slice(0, 7), [
    'uid-1',
    'a@example.com',
    'A',
    null,
    false,
    true,
    ['password'],
  ]);
});

