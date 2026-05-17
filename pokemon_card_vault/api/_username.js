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
    const cleanBase = baseUsernameFrom(base);
    for (let suffix = 0; suffix < 10000; suffix += 1) {
      const candidate = suffix === 0 ? cleanBase : `${cleanBase}${suffix}`;
      const usernameRef = firestore.collection('usernames').doc(candidate);
      const usernameDoc = await transaction.get(usernameRef);
      const owner = usernameDoc.data()?.uid;
      if (usernameDoc.exists && owner !== uid) {
        continue;
      }

      const oldUsername = String(previousUsername || '').trim().toLowerCase();
      if (oldUsername && oldUsername !== candidate) {
        transaction.delete(firestore.collection('usernames').doc(oldUsername));
      }
      transaction.set(
        usernameRef,
        {
          uid,
          username: candidate,
          displayName: String(displayName || ''),
          createdAt: usernameDoc.exists ? usernameDoc.data()?.createdAt || now : now,
          updatedAt: now,
        },
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

  await firestore.runTransaction(async (transaction) => {
    const userDoc = await transaction.get(userRef);
    const existing = String(userDoc.data()?.username || '').trim().toLowerCase();
    if (existing && !shouldReplaceExistingUsername({
      username: existing,
      uid,
      email,
      forcePokemon: preferPokemon,
    })) {
      assigned = existing;
      return;
    }
  });

  if (assigned) {
    return assigned;
  }

  const userDoc = await userRef.get();
  const previousUsername = String(userDoc.data()?.username || '').trim().toLowerCase();
  const base = preferPokemon ? randomPokemonUsernameBase() : baseUsernameFrom(email || displayName || uid);
  assigned = await assignUniqueUsername({
    firestore,
    admin,
    uid,
    base,
    displayName,
    previousUsername,
  });

  return assigned;
}

async function updateUniqueUsername({ firestore, admin, uid, desiredUsername }) {
  const clean = normalizeRequestedUsername(desiredUsername);
  const userDoc = await firestore.collection('users').doc(uid).get();
  const previousUsername = String(userDoc.data()?.username || '').trim().toLowerCase();
  if (previousUsername === clean) {
    return clean;
  }
  return claimExactUsername({
    firestore,
    admin,
    uid,
    username: clean,
    displayName: userDoc.data()?.displayName || clean,
    email: userDoc.data()?.email || '',
    previousUsername,
  });
}

async function claimExactUsername({
  firestore,
  admin,
  uid,
  username,
  displayName = '',
  email = '',
  previousUsername = '',
}) {
  const clean = normalizeRequestedUsername(username);
  const userRef = firestore.collection('users').doc(uid);
  const usernameRef = firestore.collection('usernames').doc(clean);
  const now = admin.firestore.FieldValue.serverTimestamp();

  await firestore.runTransaction(async (transaction) => {
    const usernameDoc = await transaction.get(usernameRef);
    const owner = String(usernameDoc.data()?.uid || '');
    if (usernameDoc.exists && owner !== uid) {
      throw Object.assign(new Error('Username is already taken.'), {
        statusCode: 409,
      });
    }

    const oldUsername = String(previousUsername || '').trim().toLowerCase();
    if (oldUsername && oldUsername !== clean) {
      transaction.delete(firestore.collection('usernames').doc(oldUsername));
    }

    transaction.set(
      usernameRef,
      {
        uid,
        username: clean,
        displayName: String(displayName || clean),
        createdAt: usernameDoc.exists ? usernameDoc.data()?.createdAt || now : now,
        updatedAt: now,
      },
      { merge: true },
    );
    transaction.set(
      userRef,
      {
        uid,
        email: String(email || ''),
        displayName: String(displayName || clean),
        username: clean,
        usernameLower: clean,
        updatedAt: now,
      },
      { merge: true },
    );
  });

  return clean;
}

module.exports = {
  baseUsernameFrom,
  claimExactUsername,
  ensureUniqueUsername,
  normalizeRequestedUsername,
  randomPokemonUsernameBase,
  updateUniqueUsername,
};
