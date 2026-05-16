function baseUsernameFrom(value) {
  const raw = String(value || '')
    .trim()
    .toLowerCase()
    .split('@')[0]
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9_]/g, '');
  const compact = raw.replace(/_+/g, '_').replace(/^_+|_+$/g, '');
  return compact.length >= 3 ? compact.slice(0, 24) : 'pokoin';
}

async function ensureUniqueUsername({ firestore, admin, uid, email, displayName }) {
  const userRef = firestore.collection('users').doc(uid);
  const now = admin.firestore.FieldValue.serverTimestamp();
  let assigned = '';

  await firestore.runTransaction(async (transaction) => {
    const userDoc = await transaction.get(userRef);
    const existing = String(userDoc.data()?.username || '').trim().toLowerCase();
    if (existing) {
      assigned = existing;
      return;
    }

    const base = baseUsernameFrom(email || displayName || uid);
    for (let suffix = 0; suffix < 10000; suffix += 1) {
      const candidate = suffix === 0 ? base : `${base}${suffix}`;
      const usernameRef = firestore.collection('usernames').doc(candidate);
      const usernameDoc = await transaction.get(usernameRef);
      const owner = usernameDoc.data()?.uid;
      if (usernameDoc.exists && owner !== uid) {
        continue;
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

module.exports = { baseUsernameFrom, ensureUniqueUsername };
