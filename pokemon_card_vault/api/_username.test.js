const assert = require('node:assert/strict');
const test = require('node:test');
const {
  claimExactUsername,
  ensureUniqueUsername,
  updateUniqueUsername,
  usernameForRequest,
} = require('./_username');

// Minimal Firestore double: collections of plain objects; a transaction
// buffers writes and applies them on commit (reads see committed state).
function fakeFirestore(seed = {}) {
  const data = {};
  for (const [path, value] of Object.entries(seed)) data[path] = { ...value };
  const ref = (collection, id) => ({ path: `${collection}/${id}`, id });
  const snapshot = (path) => ({
    exists: path in data,
    data: () => (path in data ? { ...data[path] } : undefined),
  });
  const firestore = {
    data,
    collection: (collection) => ({
      doc: (id) => ({
        ...ref(collection, id),
        get: async () => snapshot(`${collection}/${id}`),
      }),
    }),
    async runTransaction(fn) {
      const writes = [];
      const transaction = {
        get: async (docRef) => snapshot(docRef.path),
        set: (docRef, value, options = {}) => writes.push(['set', docRef.path, value, options.merge === true]),
        delete: (docRef) => writes.push(['delete', docRef.path]),
      };
      const result = await fn(transaction);
      for (const [kind, path, value, merge] of writes) {
        if (kind === 'delete') delete data[path];
        else data[path] = merge ? { ...(data[path] || {}), ...value } : { ...value };
      }
      return result;
    },
  };
  return firestore;
}

const admin = { firestore: { FieldValue: { serverTimestamp: () => 'now' } } };

test('ensure re-registers a profile username missing from the registry (dratini case)', async () => {
  const firestore = fakeFirestore({
    'users/wallet:abc': { username: 'dratini', usernameLower: 'dratini', displayName: 'dratini' },
  });
  const username = await ensureUniqueUsername({ firestore, admin, uid: 'wallet:abc', email: '', displayName: 'dratini' });
  assert.equal(username, 'dratini');
  assert.equal(firestore.data['usernames/dratini'].uid, 'wallet:abc');
});

test('ensure assigns a username when the profile has none', async () => {
  const firestore = fakeFirestore({
    'users/u1': { displayName: 'Gianluca Di Luca' },
    'usernames/gianluca': { uid: 'someone-else', username: 'gianluca' },
  });
  const username = await ensureUniqueUsername({ firestore, admin, uid: 'u1', email: 'gianluca@example.com', displayName: 'Gianluca Di Luca' });
  assert.equal(username, 'gianluca1');
  assert.equal(firestore.data['usernames/gianluca1'].uid, 'u1');
  assert.equal(firestore.data['users/u1'].username, 'gianluca1');
  assert.equal(firestore.data['usernames/gianluca'].uid, 'someone-else');
});

test('ensure replaces a profile name the registry gives to another account, without deleting theirs', async () => {
  const firestore = fakeFirestore({
    'users/u1': { username: 'ash', displayName: 'Ash' },
    'usernames/ash': { uid: 'u2', username: 'ash' },
  });
  const username = await ensureUniqueUsername({ firestore, admin, uid: 'u1', email: 'ash@example.com', displayName: 'Ash' });
  assert.equal(username, 'ash1');
  assert.equal(firestore.data['usernames/ash'].uid, 'u2');
  assert.equal(firestore.data['users/u1'].username, 'ash1');
});

test('ensure keeps a healthy username untouched', async () => {
  const firestore = fakeFirestore({
    'users/u1': { username: 'pokoin', usernameLower: 'pokoin' },
    'usernames/pokoin': { uid: 'u1', username: 'pokoin', createdAt: 'then' },
  });
  assert.equal(await ensureUniqueUsername({ firestore, admin, uid: 'u1', email: '', displayName: '' }), 'pokoin');
  assert.equal(firestore.data['usernames/pokoin'].createdAt, 'then');
});

test('change claims the new name, releases the old one, keeps email and display name', async () => {
  const firestore = fakeFirestore({
    'users/u1': { username: 'mario', usernameLower: 'mario', displayName: 'Mario Rossi', email: 'mario@example.com' },
    'usernames/mario': { uid: 'u1', username: 'mario' },
  });
  assert.equal(await updateUniqueUsername({ firestore, admin, uid: 'u1', desiredUsername: 'SuperMario' }), 'supermario');
  assert.equal(firestore.data['usernames/supermario'].uid, 'u1');
  assert.equal(firestore.data['usernames/mario'], undefined);
  assert.equal(firestore.data['users/u1'].username, 'supermario');
  assert.equal(firestore.data['users/u1'].displayName, 'Mario Rossi');
  assert.equal(firestore.data['users/u1'].email, 'mario@example.com');
});

test('change never deletes an old name owned by another account', async () => {
  const firestore = fakeFirestore({
    'users/u1': { username: 'shared' },
    'usernames/shared': { uid: 'u2', username: 'shared' },
  });
  await updateUniqueUsername({ firestore, admin, uid: 'u1', desiredUsername: 'mine' });
  assert.equal(firestore.data['usernames/shared'].uid, 'u2');
  assert.equal(firestore.data['usernames/mine'].uid, 'u1');
});

test('claiming the current name repairs a missing registry entry instead of a silent no-op', async () => {
  const firestore = fakeFirestore({ 'users/u1': { username: 'dratini' } });
  assert.equal(await updateUniqueUsername({ firestore, admin, uid: 'u1', desiredUsername: 'dratini' }), 'dratini');
  assert.equal(firestore.data['usernames/dratini'].uid, 'u1');
});

test('change rejects a taken or invalid name without writing anything', async () => {
  const firestore = fakeFirestore({
    'users/u1': { username: 'mario' },
    'usernames/mario': { uid: 'u1', username: 'mario' },
    'usernames/luigi': { uid: 'u2', username: 'luigi' },
  });
  const before = JSON.stringify(firestore.data);
  await assert.rejects(() => updateUniqueUsername({ firestore, admin, uid: 'u1', desiredUsername: 'luigi' }), (e) => e.statusCode === 409);
  await assert.rejects(() => updateUniqueUsername({ firestore, admin, uid: 'u1', desiredUsername: 'a b' }), (e) => e.statusCode === 400);
  assert.equal(JSON.stringify(firestore.data), before);
});

test('signup claim keeps working with its display name and email', async () => {
  const firestore = fakeFirestore({});
  await claimExactUsername({ firestore, admin, uid: 'new', username: 'misty', displayName: 'misty', email: 'misty@example.com' });
  assert.equal(firestore.data['users/new'].email, 'misty@example.com');
  assert.equal(firestore.data['users/new'].displayName, 'misty');
  assert.equal(firestore.data['usernames/misty'].uid, 'new');
});

test('usernameForRequest: empty body ensures, username claims', async () => {
  const firestore = fakeFirestore({ 'users/u1': { username: 'brock' } });
  assert.equal(await usernameForRequest({ firestore, admin, decoded: { uid: 'u1' } }), 'brock');
  assert.equal(firestore.data['usernames/brock'].uid, 'u1');
  assert.equal(await usernameForRequest({ firestore, admin, decoded: { uid: 'u1' }, requestedUsername: 'rock' }), 'rock');
  assert.equal(firestore.data['usernames/brock'], undefined);
});
