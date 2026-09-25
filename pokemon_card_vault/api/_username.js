const pokemonUsernameBases = [
  'pikachu',
  'squirtle',
  'bulbasaur',
  'charmander',
  'eevee',
  'mew',
  'jigglypuff',
  'psyduck',
  'snorlax',
  'meowth',
  'vulpix',
  'dratini',
];

function baseUsernameFrom(value) {
  const raw = String(value || '')
    .trim()
    .toLowerCase()
    .split('@')[0]
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]/g, '');
  const compact = raw;
  return compact.length >= 3 ? compact.slice(0, 24) : 'pokoin';
}

/** Compact letters/digits for display-name prefix search (spaces stripped). */
function displayNameSearchKey(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]/g, '')
    .slice(0, 48);
}

function normalizeRequestedUsername(value) {
  const clean = String(value || '').trim().toLowerCase();
  if (!/^[a-z0-9]{3,32}$/.test(clean)) {
    throw Object.assign(new Error('Username must be 3-32 letters or numbers, with no spaces.'), {
      statusCode: 400,
    });
  }
  return clean;
}

function randomPokemonUsernameBase() {
  return pokemonUsernameBases[Math.floor(Math.random() * pokemonUsernameBases.length)];
}

function isGeneratedWalletUsername(username, uid, email) {
  const normalized = String(username || '').trim().toLowerCase();
  const walletAddress = String(uid || '').startsWith('wallet:')
    ? String(uid).slice('wallet:'.length).replace(/^0x/, '')
    : '';
  const emailPrefix = String(email || '').split('@')[0].toLowerCase();
  return /^[a-f0-9]{40}$/.test(normalized) ||
    (walletAddress && normalized === walletAddress) ||
    (emailPrefix && normalized === emailPrefix && /^[a-f0-9]{40}$/.test(emailPrefix));
}

function shouldReplaceExistingUsername({ username, uid, email, forcePokemon }) {
  return Boolean(forcePokemon && isGeneratedWalletUsername(username, uid, email));
}

const USERNAME_RE = /^[a-z0-9]{3,32}$/;

function registryPayload({ uid, username, displayName, existing, now }) {
  return {
    uid,
    username,
    displayName: String(displayName || ''),
    displayNameSearch: displayNameSearchKey(displayName || username),
    createdAt: existing?.exists ? existing.data()?.createdAt || now : now,
    updatedAt: now,
  };
}

/** Read the registry entry for `name` and say whether `uid` owns it.
 * Only an owned entry may be deleted: a profile that drifted from the
 * registry must never delete somebody else's name. */
async function readOwnedRegistry(transaction, firestore, name, uid) {
  if (!USERNAME_RE.test(name)) return { ref: null, owned: false };
  const ref = firestore.collection('usernames').doc(name);
  const doc = await transaction.get(ref);
  return { ref, doc, owned: doc.exists && doc.data()?.uid === uid };
}

async function assignUniqueUsername({
  firestore,
  admin,
  uid,
  base,
  displayName,
  previousUsername = '',
}) {
  const userRef = firestore.collection('users').doc(uid);
  const now = admin.firestore.FieldValue.serverTimestamp();
  let assigned = '';
  await firestore.runTransaction(async (transaction) => {
    const oldUsername = String(previousUsername || '').trim().toLowerCase();
    const old = await readOwnedRegistry(transaction, firestore, oldUsername, uid);
    const cleanBase = baseUsernameFrom(base);
    for (let suffix = 0; suffix < 10000; suffix += 1) {
      const candidate = suffix === 0 ? cleanBase : `${cleanBase}${suffix}`;
      const usernameRef = firestore.collection('usernames').doc(candidate);
      const usernameDoc = await transaction.get(usernameRef);
      const owner = usernameDoc.data()?.uid;
      if (usernameDoc.exists && owner !== uid) {
        continue;
      }
      if (old.owned && oldUsername !== candidate) {
        transaction.delete(old.ref);
      }
      transaction.set(
        usernameRef,
        registryPayload({ uid, username: candidate, displayName, existing: usernameDoc, now }),
        { merge: true },
      );
      transaction.set(
        userRef,
        {
          username: candidate,
          usernameLower: candidate,
          updatedAt: now,
        },
        { merge: true },
      );
      assigned = candidate;
      return;
    }
    throw Object.assign(new Error('Could not allocate a unique username.'), {
      statusCode: 409,
    });
  });
  return assigned;
}

/** The username transfers and receive codes resolve for `uid`. Keeps a
 * valid profile name, re-registering it when the `usernames` entry is
 * missing; assigns a fresh one when the profile has none, an invalid one,
 * or one the registry gives to another account. */
async function ensureUniqueUsername({
  firestore,
  admin,
  uid,
  email,
  displayName,
  preferPokemon = false,
}) {
  const userRef = firestore.collection('users').doc(uid);
  const now = admin.firestore.FieldValue.serverTimestamp();
  let assigned = '';
  let previousUsername = '';
  await firestore.runTransaction(async (transaction) => {
    assigned = '';
    const userDoc = await transaction.get(userRef);
    const data = userDoc.data() || {};
    const existing = String(data.username || '').trim().toLowerCase();
    previousUsername = existing;
    if (!USERNAME_RE.test(existing) || shouldReplaceExistingUsername({
      username: existing,
      uid,
      email,
      forcePokemon: preferPokemon,
    })) {
      return;
    }
    const registry = await readOwnedRegistry(transaction, firestore, existing, uid);
    if (registry.doc.exists && !registry.owned) {
      return;
    }
    if (!registry.doc.exists) {
      transaction.set(
        registry.ref,
        registryPayload({ uid, username: existing, displayName: data.displayName || displayName, existing: registry.doc, now }),
        { merge: true },
      );
    }
    if (data.username !== existing || data.usernameLower !== existing) {
      transaction.set(userRef, { username: existing, usernameLower: existing, updatedAt: now }, { merge: true });
    }
    assigned = existing;
  });
  if (assigned) {
    return assigned;
  }
  const base = preferPokemon ? randomPokemonUsernameBase() : baseUsernameFrom(email || displayName || uid);
  return assignUniqueUsername({
    firestore,
    admin,
    uid,
    base,
    displayName,
    previousUsername,
  });
}

async function updateUniqueUsername({ firestore, admin, uid, desiredUsername }) {
  return claimExactUsername({
    firestore,
    admin,
    uid,
    username: normalizeRequestedUsername(desiredUsername),
  });
}

/** Give `uid` exactly `username`. Idempotent: claiming the current name
 * repairs a missing registry entry. The previous name is read inside the
 * transaction and released only if this account owns it. */
async function claimExactUsername({
  firestore,
  admin,
  uid,
  username,
  displayName = '',
  email = '',
}) {
  const clean = normalizeRequestedUsername(username);
  const userRef = firestore.collection('users').doc(uid);
  const usernameRef = firestore.collection('usernames').doc(clean);
  const now = admin.firestore.FieldValue.serverTimestamp();
  await firestore.runTransaction(async (transaction) => {
    const userDoc = await transaction.get(userRef);
    const data = userDoc.data() || {};
    const usernameDoc = await transaction.get(usernameRef);
    const oldUsername = String(data.username || '').trim().toLowerCase();
    const old = oldUsername && oldUsername !== clean
      ? await readOwnedRegistry(transaction, firestore, oldUsername, uid)
      : { owned: false };
    const owner = String(usernameDoc.data()?.uid || '');
    if (usernameDoc.exists && owner !== uid) {
      throw Object.assign(new Error('Username is already taken.'), {
        statusCode: 409,
      });
    }
    if (old.owned) {
      transaction.delete(old.ref);
    }
    const profileDisplayName = String(data.displayName || displayName || '');
    transaction.set(
      usernameRef,
      registryPayload({ uid, username: clean, displayName: profileDisplayName || clean, existing: usernameDoc, now }),
      { merge: true },
    );
    const profile = { uid, username: clean, usernameLower: clean, updatedAt: now };
    if (!data.displayName) profile.displayName = profileDisplayName || clean;
    if (!data.email && email) profile.email = String(email);
    transaction.set(userRef, profile, { merge: true });
  });
  return clean;
}

/** POST body handling shared by /api/ensure-username and
 * /api/search-recipient-emails: `{username}` claims it, `{}` ensures one. */
async function usernameForRequest({ firestore, admin, decoded, requestedUsername = '' }) {
  const requested = String(requestedUsername || '').trim();
  if (requested) {
    return updateUniqueUsername({
      firestore,
      admin,
      uid: decoded.uid,
      desiredUsername: requested,
    });
  }
  const userDoc = await firestore.collection('users').doc(decoded.uid).get();
  const profile = userDoc.data() || {};
  return ensureUniqueUsername({
    firestore,
    admin,
    uid: decoded.uid,
    email: decoded.email || profile.email || '',
    displayName: profile.displayName || decoded.name || '',
  });
}

module.exports = {
  assignUniqueUsername,
  baseUsernameFrom,
  claimExactUsername,
  displayNameSearchKey,
  ensureUniqueUsername,
  normalizeRequestedUsername,
  randomPokemonUsernameBase,
  updateUniqueUsername,
  usernameForRequest,
};
