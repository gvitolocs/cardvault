// In-memory Firebase Admin + Firestore fake for the email-signup flow tests.
// underscore-prefixed on purpose: never deployed as a route.
//
// Supports exactly the surface register-email.js / verify-email-signup.js /
// _username.js / _email.js touch: collection().doc().get/set/delete,
// runTransaction pass-through, FieldValue.serverTimestamp/increment,
// Timestamp.fromMillis, and the auth() methods used by finalization. One-shot
// failure injection via admin.__failNextSet = '<collection>' simulates a
// database write failing mid-finalization.

'use strict';

function deepClone(value) {
  if (value === null || typeof value !== 'object') return value;
  if (Array.isArray(value)) return value.map(deepClone);
  const out = {};
  for (const [key, entry] of Object.entries(value)) {
    out[key] = deepClone(entry);
  }
  return out;
}

function createFakeAdmin() {
  const collections = new Map();
  const userRecords = new Map();
  const uidByEmail = new Map();
  let uidCounter = 0;
  let failNextSet = null;

  function collectionStore(name) {
    if (!collections.has(name)) {
      collections.set(name, new Map());
    }
    return collections.get(name);
  }

  function maybeFailSet(colName) {
    if (failNextSet && failNextSet === colName) {
      failNextSet = null;
      throw new Error(`Injected write failure on ${colName}`);
    }
  }

  function resolveValue(value) {
    if (value && value.__serverTimestamp) {
      return { __timestamp: true, toMillis: () => Date.now() };
    }
    return value;
  }

  function resolveData(data) {
    const out = {};
    for (const [key, value] of Object.entries(data || {})) {
      out[key] = resolveValue(value);
    }
    return out;
  }

  function makeDocRef(colName, docId) {
    return {
      id: docId,
      get colName() { return colName; },
      async get() {
        return makeSnapshot(colName, docId);
      },
      async set(data, opts = {}) {
        maybeFailSet(colName);
        const store = collectionStore(colName);
        const existing = store.get(docId) || {};
        store.set(docId, opts.merge ? { ...existing, ...resolveData(data) } : resolveData(data));
      },
      async delete() {
        maybeFailSet(colName);
        collectionStore(colName).delete(docId);
      },
    };
  }

  function makeSnapshot(colName, docId) {
    const raw = collectionStore(colName).get(docId);
    return {
      exists: raw !== undefined,
      id: docId,
      ref: makeDocRef(colName, docId),
      data() {
        return raw === undefined ? undefined : deepClone(raw);
      },
    };
  }

  function publicRecord(record) {
    return {
      uid: record.uid,
      email: record.email,
      displayName: record.displayName,
      emailVerified: record.emailVerified,
      customClaims: { ...record.customClaims },
      providerData: record.providerData.map((entry) => ({ ...entry })),
    };
  }

  const firestoreInstance = {
    collection: (name) => ({
      doc: (docId) => makeDocRef(name, docId),
    }),
    runTransaction: async (updateFn) => {
      const transaction = {
        get: (ref) => ref.get(),
        set: (ref, data, opts) => ref.set(data, opts || {}),
        delete: (ref) => ref.delete(),
      };
      return updateFn(transaction);
    },
    FieldValue: {
      serverTimestamp: () => ({ __serverTimestamp: true }),
      increment: (n) => ({ __increment: n }),
    },
    Timestamp: {
      fromMillis: (ms) => ({ __timestamp: true, toMillis: () => ms }),
    },
  };

  // admin.firestore is a factory with statics in the real SDK
  // (admin.firestore.FieldValue / admin.firestore.Timestamp).
  const firestoreFactory = () => firestoreInstance;
  firestoreFactory.FieldValue = firestoreInstance.FieldValue;
  firestoreFactory.Timestamp = firestoreInstance.Timestamp;

  const auth = {
    async getUserByEmail(email) {
      const uid = uidByEmail.get(String(email).toLowerCase());
      if (!uid) {
        throw Object.assign(new Error('auth/user-not-found'), { code: 'auth/user-not-found' });
      }
      return publicRecord(userRecords.get(uid));
    },
    async createUser({ email, password, displayName, emailVerified }) {
      maybeFailSet('auth.createUser');
      if (uidByEmail.has(String(email).toLowerCase())) {
        throw Object.assign(new Error('auth/email-already-exists'), { code: 'auth/email-already-exists' });
      }
      const uid = `uid-${++uidCounter}`;
      const record = {
        uid,
        email: String(email),
        password: String(password || ''),
        displayName: String(displayName || ''),
        emailVerified: Boolean(emailVerified),
        customClaims: {},
        providerData: [{ providerId: 'password' }],
      };
      userRecords.set(uid, record);
      uidByEmail.set(record.email.toLowerCase(), uid);
      return publicRecord(record);
    },
    async deleteUser(uid) {
      const record = userRecords.get(uid);
      if (record) {
        userRecords.delete(uid);
        uidByEmail.delete(record.email.toLowerCase());
      }
    },
    async setCustomUserClaims(uid, claims) {
      const record = userRecords.get(uid);
      if (!record) {
        throw Object.assign(new Error('auth/user-not-found'), { code: 'auth/user-not-found' });
      }
      record.customClaims = { ...record.customClaims, ...claims };
    },
    async createCustomToken(uid) {
      return `custom-token-${uid}`;
    },
  };

  const admin = {
    firestore: firestoreFactory,
    auth: () => auth,
    __collections: collections,
    __userRecords: userRecords,
    __uidByEmail: uidByEmail,
    __failNextSet: null,
  };

  Object.defineProperty(admin, '__failNextSet', {
    get: () => failNextSet,
    set: (value) => { failNextSet = value; },
  });

  return admin;
}

function createResponse() {
  const res = {
    statusCode: 200,
    body: null,
    headers: {},
    ended: false,
    status(code) {
      res.statusCode = code;
      return res;
    },
    json(payload) {
      res.body = payload;
      return res;
    },
    setHeader(key, value) {
      res.headers[String(key).toLowerCase()] = value;
      return res;
    },
    end() {
      res.ended = true;
      return res;
    },
  };
  return res;
}

module.exports = {
  createFakeAdmin,
  createResponse,
};
