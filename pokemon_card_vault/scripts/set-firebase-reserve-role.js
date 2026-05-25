#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');

const { getFirebaseAdmin } = require('../api/_firebase');

const ROOT_DIR = path.resolve(__dirname, '..');

function loadLocalEnv() {
  const envPath = path.join(ROOT_DIR, '.env.local');
  if (!fs.existsSync(envPath)) {
    return;
  }
  const content = fs.readFileSync(envPath, 'utf8');
  for (const line of content.split(/\r?\n/)) {
    const stripped = line.trim();
    if (!stripped || stripped.startsWith('#') || !stripped.includes('=')) {
      continue;
    }
    const separator = stripped.indexOf('=');
    const key = stripped
      .slice(0, separator)
      .replace(/^export\s+/, '')
      .trim();
    if (!key || process.env[key]) {
      continue;
    }
    process.env[key] = cleanEnvValue(stripped.slice(separator + 1));
  }
}

function cleanEnvValue(value) {
  const trimmed = value.trim();
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1).replace(/\\n/g, '\n');
  }
  return trimmed;
}

function parseArgs(argv) {
  const options = {
    apply: false,
    identifier: 'pknreserve',
  };
  for (const arg of argv) {
    if (arg === '--apply') {
      options.apply = true;
    } else if (arg.startsWith('--identifier=')) {
      options.identifier = arg.slice('--identifier='.length).trim();
    }
  }
  if (!options.identifier) {
    throw new Error('--identifier is required.');
  }
  return options;
}

function normalize(value) {
  return String(value || '').trim().toLowerCase();
}

function safeUserSummary(entry) {
  return {
    uid: entry.uid,
    email: entry.email || '',
    displayName: entry.displayName || '',
    username: entry.username || '',
    source: [...entry.sources].sort().join(','),
    customClaimReserve: entry.customClaimReserve === true,
    profileReserve: entry.profileReserve === true,
  };
}

function mergeCandidate(candidates, candidate) {
  const uid = String(candidate.uid || '').trim();
  if (!uid) return;
  const existing = candidates.get(uid) || {
    uid,
    email: '',
    displayName: '',
    username: '',
    sources: new Set(),
    customClaims: {},
    customClaimReserve: false,
    profileReserve: false,
  };
  existing.email = candidate.email || existing.email;
  existing.displayName = candidate.displayName || existing.displayName;
  existing.username = candidate.username || existing.username;
  for (const source of candidate.sources || []) {
    existing.sources.add(source);
  }
  existing.customClaims = {
    ...existing.customClaims,
    ...(candidate.customClaims || {}),
  };
  existing.customClaimReserve = existing.customClaimReserve || candidate.customClaimReserve === true;
  existing.profileReserve = existing.profileReserve || candidate.profileReserve === true;
  candidates.set(uid, existing);
}

async function findFirestoreCandidates(firestore, identifier) {
  const normalized = normalize(identifier);
  const checks = [
    ['username', identifier],
    ['username', normalized],
    ['displayName', identifier],
    ['email', normalized],
  ];
  const candidates = new Map();
  for (const [field, value] of checks) {
    if (!value) continue;
    const snapshot = await firestore.collection('users').where(field, '==', value).limit(5).get();
    for (const doc of snapshot.docs) {
      const data = doc.data() || {};
      mergeCandidate(candidates, {
        uid: doc.id,
        email: data.email,
        displayName: data.displayName,
        username: data.username,
        profileReserve: data.reserve === true ||
          data.isReserve === true ||
          data.hasReserveAccess === true ||
          normalize(data.role) === 'reserve' ||
          (Array.isArray(data.roles) && data.roles.map(normalize).includes('reserve')),
        sources: [`firestore:${field}`],
      });
    }
  }
  return candidates;
}

async function findAuthCandidates(auth, identifier) {
  const normalized = normalize(identifier);
  const candidates = new Map();
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    for (const user of page.users) {
      const email = normalize(user.email);
      const displayName = normalize(user.displayName);
      const localPart = email.split('@')[0] || '';
      const matched = user.uid === identifier ||
        email === normalized ||
        displayName === normalized ||
        localPart === normalized;
      if (!matched) {
        continue;
      }
      mergeCandidate(candidates, {
        uid: user.uid,
        email: user.email,
        displayName: user.displayName,
        customClaims: user.customClaims || {},
        customClaimReserve: user.customClaims?.reserve === true,
        sources: ['auth'],
      });
    }
    pageToken = page.pageToken;
  } while (pageToken);
  return candidates;
}

function mergeCandidateMaps(...maps) {
  const merged = new Map();
  for (const map of maps) {
    for (const candidate of map.values()) {
      mergeCandidate(merged, candidate);
    }
  }
  return merged;
}

async function assignReserveRole({ admin, candidate }) {
  const auth = admin.auth();
  const firestore = admin.firestore();
  const authUser = await auth.getUser(candidate.uid);
  const customClaims = {
    ...(authUser.customClaims || {}),
    reserve: true,
  };
  await auth.setCustomUserClaims(candidate.uid, customClaims);
  await firestore.collection('users').doc(candidate.uid).set(
    {
      hasReserveAccess: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

async function main() {
  loadLocalEnv();
  const options = parseArgs(process.argv.slice(2));
  const admin = getFirebaseAdmin();
  const firestoreCandidates = await findFirestoreCandidates(
    admin.firestore(),
    options.identifier,
  );
  const authCandidates = await findAuthCandidates(admin.auth(), options.identifier);
  const candidates = [...mergeCandidateMaps(firestoreCandidates, authCandidates).values()];

  if (candidates.length !== 1) {
    console.log(JSON.stringify({
      action: options.apply ? 'not_applied' : 'dry_run',
      reason: candidates.length === 0 ? 'no_unique_match' : 'ambiguous_match',
      identifier: options.identifier,
      candidates: candidates.map(safeUserSummary),
    }, null, 2));
    process.exitCode = 1;
    return;
  }

  const [candidate] = candidates;
  if (!options.apply) {
    console.log(JSON.stringify({
      action: 'dry_run',
      nextStep: `node scripts/set-firebase-reserve-role.js --identifier=${options.identifier} --apply`,
      candidate: safeUserSummary(candidate),
    }, null, 2));
    return;
  }

  await assignReserveRole({ admin, candidate });
  console.log(JSON.stringify({
    action: 'applied',
    candidate: safeUserSummary({
      ...candidate,
      customClaimReserve: true,
      profileReserve: true,
    }),
    note: 'User must sign out/in or refresh their Firebase ID token before the custom claim is present in new requests.',
  }, null, 2));
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}

module.exports = {
  findAuthCandidates,
  findFirestoreCandidates,
  mergeCandidateMaps,
  parseArgs,
};
