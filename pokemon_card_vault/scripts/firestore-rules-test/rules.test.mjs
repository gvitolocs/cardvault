import { readFileSync } from 'node:fs';
import test, { after, before } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc, addDoc, collection, serverTimestamp, getDoc } from 'firebase/firestore';

const RULES = process.env.RULES_FILE || new URL('../../firestore.rules', import.meta.url).pathname;
const PORT = Number(process.env.FIRESTORE_EMULATOR_PORT || 18471);
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'pokoin-rules-test',
    firestore: { rules: readFileSync(RULES, 'utf8'), host: '127.0.0.1', port: PORT },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/alice'), { email: 'a@x.com', displayName: 'Alice', username: 'alice', walletAddress: '0x' + '1'.repeat(40) });
    await setDoc(doc(db, 'orders/o1'), { uid: 'alice', sellerUids: ['bob'], paymentStatus: 'escrow' });
  });
});

after(async () => { await env?.cleanup(); });

const alice = () => env.authenticatedContext('alice').firestore();
const mallory = () => env.authenticatedContext('mallory').firestore();

test('profile: Flutter ensureUserProfile create and merge updates still work', async () => {
  await assertSucceeds(setDoc(doc(mallory(), 'users/mallory'), {
    email: 'm@x.com', displayName: 'M', walletAddress: null, createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(setDoc(doc(alice(), 'users/alice'), { displayName: 'Alice B', updatedAt: serverTimestamp() }, { merge: true }));
  await assertSucceeds(setDoc(doc(alice(), 'users/alice'), { lastLoginAt: serverTimestamp(), lastSeenAt: serverTimestamp() }, { merge: true }));
  await assertSucceeds(getDoc(doc(alice(), 'users/alice')));
});

test('profile: privilege and trust fields are server-only', async () => {
  for (const patch of [
    { admin: true }, { isAdmin: true }, { hasAdminAccess: true }, { role: 'admin' }, { role: 'silver' },
    { roles: ['reserve'] }, { reserve: true }, { silverUntil: new Date('2099-01-01') },
    { username: 'vitologiuseppe17' }, { walletAddress: '0x' + '2'.repeat(40) }, { photoUrl: 'https://x' },
  ]) {
    await assertFails(setDoc(doc(alice(), 'users/alice'), patch, { merge: true }));
  }
  await assertFails(setDoc(doc(env.authenticatedContext('eve').firestore(), 'users/eve'), { email: 'e@x.com', role: 'admin' }));
  await assertFails(setDoc(doc(env.authenticatedContext('eve2').firestore(), 'users/eve2'), { email: 'e@x.com', walletAddress: '0x' + '3'.repeat(40) }));
  await assertFails(setDoc(doc(mallory(), 'users/alice'), { displayName: 'pwned' }, { merge: true }));
});

test('registries: clients cannot squat usernames, wallets or email wallets', async () => {
  await assertFails(setDoc(doc(mallory(), 'usernames/newname'), { uid: 'mallory', username: 'newname' }));
  await assertFails(setDoc(doc(mallory(), 'wallet_addresses/0x' + '4'.repeat(40)), { uid: 'mallory', address: '0x' + '4'.repeat(40), email: 'm@x.com' }));
  await assertFails(setDoc(doc(mallory(), 'email_wallets/victim@x.com'), { uid: 'mallory', email: 'victim@x.com', address: '0x' + '5'.repeat(40) }));
  await assertSucceeds(getDoc(doc(mallory(), 'usernames/alice')));
});

test('orders and withdraw requests cannot be forged by clients', async () => {
  await assertFails(addDoc(collection(mallory(), 'orders'), {
    uid: 'mallory', buyerUid: 'mallory', paymentStatus: 'escrow', totalPkn: 1e9,
    items: [{ sellerUid: 'mallory', quantity: 1, totalPricePkn: 1e9 }], sellerUids: ['mallory'],
  }));
  await assertFails(setDoc(doc(alice(), 'orders/o1'), { paymentStatus: 'released' }, { merge: true }));
  await assertSucceeds(getDoc(doc(alice(), 'orders/o1')));
  await assertFails(addDoc(collection(mallory(), 'withdraw_requests'), {
    uid: 'mallory', status: 'pending', amountPkn: 1000, toAddress: '0x' + '6'.repeat(40),
  }));
});

test('unchanged: balances create at zero, wallet_activity, recents', async () => {
  await assertSucceeds(setDoc(doc(env.authenticatedContext('newbie').firestore(), 'balances/newbie'), { availablePkn: 0, lockedPkn: 0 }));
  await assertFails(setDoc(doc(env.authenticatedContext('newbie2').firestore(), 'balances/newbie2'), { availablePkn: 1000, lockedPkn: 0 }));
  await assertSucceeds(addDoc(collection(alice(), 'wallet_activity'), { uid: 'alice', title: 't', detail: 'd', kind: 'inbound' }));
});
