// Pokoin direct-conversation chat endpoint.
//
//   GET  /api/chat?action=list                     — my conversations (preview + unread)
//   GET  /api/chat?action=get&peer=<username>      — one conversation + its events (marks read)
//   POST /api/chat?action=message  { peer, text }  — append a text event
//   POST /api/chat?action=pay      { peer, amountPkn, note? } — balance transfer + typed payment event in ONE transaction
//   POST /api/chat?action=read     { peer }        — mark the conversation read
//
// Invariants (all server-side):
// - CANONICAL_DIRECT_CONVERSATION: the doc id is the sorted uid pair key, so
//   A→B and B→A share one conversation. `members` is the authority; every
//   read/write re-checks membership, so a third user can never read, post,
//   pay, or inject events.
// - NO_NEGATIVE_TRANSFER / NO_DOUBLE_TRANSFER: amounts are validated positive
//   integers and balances move in the same transaction as the payment event.
// - NO_CLIENT_AUTHORITY_OVER_LEDGER: event ids, ledger ids, timestamps and
//   balances are minted here; the client only supplies peer, text, amount.

const { getFirebaseAdmin, verifyBearerToken } = require('../server/_firebase');
const {
  cleanText,
  isParticipant,
  otherMember,
  pairKeyFor,
  previewForEvent,
  unreadFor,
  bumpUnread,
  validateAmountPkn,
  validateEvent,
} = require('./_chat_core.js');
const { USERNAME_RE } = require('./_money_request_core.js');

const EVENT_LIMIT = 120;

function conversationRef(firestore, pairKey) {
  return firestore.collection('conversations').doc(pairKey);
}

async function resolvePeer(firestore, peerUsername) {
  const name = String(peerUsername || '').trim().toLowerCase();
  if (!USERNAME_RE.test(name)) {
    throw Object.assign(new Error('Enter a valid username.'), { statusCode: 400 });
  }
  const doc = await firestore.collection('usernames').doc(name).get();
  if (!doc.exists || !doc.data()?.uid) {
    throw Object.assign(new Error('No Pokoin account was found for that username.'), { statusCode: 404 });
  }
  return { uid: doc.data().uid, username: name };
}

/** Ensure the canonical conversation doc exists; returns { ref, pairKey, members }. */
async function ensureConversation(firestore, me, peer) {
  const pairKey = pairKeyFor(me.uid, peer.uid);
  const ref = conversationRef(firestore, pairKey);
  const doc = await ref.get();
  if (!doc.exists) {
    const members = [me.uid, peer.uid].sort();
    await ref.set({
      pairKey,
      members,
      memberUsernames: { [me.uid]: me.username, [peer.uid]: peer.username },
      unread: {},
      createdAt: admin_now(firestore),
    });
  }
  return { ref, pairKey, members: (doc.exists ? doc.data().members : [me.uid, peer.uid].sort()) };
}

function admin_now(firestore) {
  return require('firebase-admin').firestore.FieldValue.serverTimestamp();
}

module.exports = async function handler(req, res) {
  if (req.method !== 'GET' && req.method !== 'POST') {
    res.setHeader('Allow', 'GET, POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const decoded = await verifyBearerToken(req);
    const admin = getFirebaseAdmin();
    const firestore = admin.firestore();
    const me = { uid: decoded.uid };
    const url = new URL(req.url, 'https://local');
    const action = String(url.searchParams.get('action') || 'list');

    // ---- GET list: every conversation I participate in ----
    if (req.method === 'GET' && action === 'list') {
      const snap = await firestore
        .collection('conversations')
        .where('members', 'array-contains', me.uid)
        .limit(100)
        .get();
      const conversations = snap.docs
        .map((doc) => {
          const data = doc.data() || {};
          const pairKey = data.pairKey || doc.id;
          if (!isParticipant(pairKey, me.uid)) return null; // defence in depth
          const peerUid = otherMember(pairKey, me.uid);
          const lastEvent = data.lastEvent || {};
          return {
            pairKey,
            peerUid,
            peerUsername: (data.memberUsernames || {})[peerUid] || '',
            preview: previewForEvent({ ...lastEvent, incoming: lastEvent.senderUid && lastEvent.senderUid !== me.uid }),
            unread: unreadFor(data, me.uid),
            updatedAt: lastEvent.at || data.createdAt || null,
          };
        })
        .filter(Boolean)
        .sort((a, b) => JSON.stringify(b.updatedAt || '').localeCompare(JSON.stringify(a.updatedAt || '')));
      return res.status(200).json({ conversations });
    }

    // ---- every other action names a peer ----
    const peerUsername = String(
      (req.method === 'GET' ? url.searchParams.get('peer') : req.body?.peer) || '',
    ).trim().toLowerCase();
    const peer = await resolvePeer(firestore, peerUsername);
    if (peer.uid === me.uid) {
      return res.status(400).json({ error: 'You cannot open a conversation with yourself.' });
    }
    const pairKey = pairKeyFor(me.uid, peer.uid);
    const ref = conversationRef(firestore, pairKey);

    // ---- GET one conversation + events (reading marks it read) ----
    if (req.method === 'GET' && action === 'get') {
      const doc = await ref.get();
      if (doc.exists && !isParticipant(pairKey, me.uid)) {
        return res.status(403).json({ error: 'Not your conversation.' });
      }
      let unread = 0;
      if (doc.exists) {
        unread = unreadFor(doc.data(), me.uid);
        if (unread) {
          await ref.update({ [`unread.${me.uid}`]: 0 });
        }
      }
      const eventsSnap = await ref
        .collection('events')
        .orderBy('createdAt', 'asc')
        .limitToLast(EVENT_LIMIT)
        .get();
      const events = eventsSnap.docs.map((eventDoc) => {
        const data = eventDoc.data() || {};
        return {
          id: eventDoc.id,
          type: data.type,
          senderUid: data.senderUid,
          senderUsername: data.senderUsername,
          text: data.text || '',
          amountPkn: Number(data.amountPkn || 0),
          note: data.note || '',
          requestId: data.requestId || '',
          transactionId: data.transactionId || '',
          createdAt: data.createdAt,
          mine: data.senderUid === me.uid,
        };
      });
      return res.status(200).json({
        pairKey,
        peer: { uid: peer.uid, username: peer.username },
        unread,
        events,
      });
    }

    if (req.method !== 'POST') {
      return res.status(405).json({ error: 'Unsupported action.' });
    }

    // ---- POST message ----
    if (action === 'message') {
      const event = validateEvent({ type: 'text', text: req.body?.text });
      if (event.error) {
        return res.status(400).json({ error: event.error });
      }
      await firestore.runTransaction(async (transaction) => {
        const doc = await transaction.get(ref);
        if (!doc.exists) {
          transaction.set(ref, {
            pairKey,
            members: [me.uid, peer.uid].sort(),
            memberUsernames: { [me.uid]: me.username || '', [peer.uid]: peer.username },
            unread: {},
            createdAt: admin_now(firestore),
          });
        }
        const data = doc.exists ? doc.data() : {};
        const members = data.members || [me.uid, peer.uid].sort();
        if (!members.includes(me.uid)) {
          throw Object.assign(new Error('Not your conversation.'), { statusCode: 403 });
        }
        transaction.set(ref.collection('events').doc(), {
          type: 'text',
          senderUid: me.uid,
          senderUsername: me.username || '',
          text: event.value.text,
          createdAt: admin_now(firestore),
        });
        transaction.update(ref, {
          unread: bumpUnread(data.unread, members, me.uid),
          lastEvent: { type: 'text', text: event.value.text, senderUid: me.uid, at: admin_now(firestore) },
        });
      });
      return res.status(200).json({ ok: true });
    }

    // ---- POST pay: transfer + payment event in ONE transaction ----
    if (action === 'pay') {
      const amount = validateAmountPkn(req.body?.amountPkn);
      if (amount.error) {
        return res.status(400).json({ error: amount.error });
      }
      const note = require('./_chat_core.js').cleanNote(req.body?.note);

      let result = {};
      await firestore.runTransaction(async (transaction) => {
        const convoDoc = await transaction.get(ref);
        if (convoDoc.exists && !isParticipant(pairKey, me.uid)) {
          throw Object.assign(new Error('Not your conversation.'), { statusCode: 403 });
        }
        const data = convoDoc.exists ? convoDoc.data() : {};
        const members = data.members || [me.uid, peer.uid].sort();

        const payerBalanceRef = firestore.collection('balances').doc(me.uid);
        const payerBalance = await transaction.get(payerBalanceRef);
        const available = Number(payerBalance.data()?.availablePkn || 0);
        if (available < amount.amount) {
          throw Object.assign(new Error('Your account balance is too low.'), { statusCode: 400 });
        }

        const now = admin_now(firestore);
        const outLedger = firestore.collection('ledger_entries').doc();
        const inLedger = firestore.collection('ledger_entries').doc();
        const eventRef = ref.collection('events').doc();

        if (!convoDoc.exists) {
          transaction.set(ref, {
            pairKey,
            members,
            memberUsernames: { [me.uid]: me.username || '', [peer.uid]: peer.username },
            unread: {},
            createdAt: now,
          });
        }

        transaction.set(
          payerBalanceRef,
          { availablePkn: admin.firestore.FieldValue.increment(-amount.amount), updatedAt: now },
          { merge: true },
        );
        transaction.set(
          firestore.collection('balances').doc(peer.uid),
          { availablePkn: admin.firestore.FieldValue.increment(amount.amount), updatedAt: now },
          { merge: true },
        );
        transaction.set(outLedger, {
          uid: me.uid,
          type: 'chat_payment_sent',
          amountPkn: -amount.amount,
          counterpartyUid: peer.uid,
          counterpartyUsername: peer.username,
          note,
          createdAt: now,
        });
        transaction.set(inLedger, {
          uid: peer.uid,
          type: 'chat_payment_received',
          amountPkn: amount.amount,
          counterpartyUid: me.uid,
          counterpartyUsername: me.username || '',
          note,
          createdAt: now,
        });
        transaction.set(eventRef, {
          type: 'payment',
          senderUid: me.uid,
          senderUsername: me.username || '',
          amountPkn: amount.amount,
          note,
          transactionId: outLedger.id,
          createdAt: now,
        });
        transaction.update(ref, {
          unread: bumpUnread(data.unread, members, me.uid),
          lastEvent: { type: 'payment', amountPkn: amount.amount, senderUid: me.uid, at: now },
        });
        transaction.set(firestore.collection('notifications').doc(), {
          uid: peer.uid,
          type: 'chat_payment_received',
          requestId: '',
          actorUsername: me.username || '',
          amountPkn: amount.amount,
          read: false,
          createdAt: now,
        });
        result = { amountPkn: amount.amount, ledgerId: outLedger.id };
      });
      return res.status(200).json({ ok: true, ...result });
    }

    // ---- POST read ----
    if (action === 'read') {
      await ref.update({ [`unread.${me.uid}`]: 0 });
      return res.status(200).json({ ok: true });
    }

    return res.status(400).json({ error: 'Unknown action.' });
  } catch (error) {
    console.error('chat failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Chat failed.',
    });
  }
};
