// Canonical PKN money-request pipeline (shared by the Receive panel and the
// chat timeline — one request object, one state machine, multiple UI entries).
//
//   POST /api/money-request?action=create    { recipientUsername, amountPkn, note?, clientToken? }
//   POST /api/money-request?action=pay       { requestId }
//   POST /api/money-request?action=decline   { requestId }
//   POST /api/money-request?action=cancel    { requestId }
//   POST /api/money-request?action=read-notifications
//   GET  /api/money-request?action=list
//   GET  /api/money-request?action=notifications
//
// Financial invariants enforced here (never in the client):
// - Firestore transactions own every status change; `pending -> paid` moves
//   balances, ledger entries, status, the chat event and the notification in
//   ONE transaction, so double taps / two devices cannot pay twice.
// - Only `toUid` may pay or decline, only `fromUid` may cancel; a requester
//   can never pay their own request. Parties are fixed at creation.
// - Terminal states are final: every mutation re-reads status === 'pending'
//   inside the transaction (lazy 14-day expiry included).
// - Each request also lands as a typed `money_request` event in the two
//   users' canonical conversation (see chat.js), so paying happens in chat
//   context and the ledger stays the audit trail.

const { getFirebaseAdmin, verifyBearerToken } = require('../server/_firebase');
const {
  STATUS,
  canPay,
  canRespond,
  effectiveStatus,
  pairKeyFor,
  bumpUnread,
  validateCreate,
} = require('./_money_request_core.js');

function requestDocId(fromUid, clientToken) {
  return `req_${fromUid}_${clientToken}`.replace(/[^a-zA-Z0-9_]/g, '');
}

function serializeRequest(doc) {
  const data = doc.data() || {};
  return {
    id: doc.id,
    requestId: doc.id,
    fromUid: data.fromUid,
    fromUsername: data.fromUsername,
    toUid: data.toUid,
    toUsername: data.toUsername,
    amountPkn: Number(data.amountPkn || 0),
    note: String(data.note || ''),
    status: data.status,
    createdAt: data.createdAt,
    paidAt: data.paidAt || null,
  };
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
    const url = new URL(req.url, 'https://local');
    const action = String(url.searchParams.get('action') || (req.method === 'POST' ? 'create' : 'list'));

    // ---- GET list: requests addressed to me or created by me ----
    if (req.method === 'GET' && action === 'list') {
      const [incoming, outgoing] = await Promise.all([
        firestore.collection('money_requests').where('toUid', '==', decoded.uid).limit(50).get(),
        firestore.collection('money_requests').where('fromUid', '==', decoded.uid).limit(50).get(),
      ]);
      const now = Date.now();
      const map = (docs) => docs.docs
        .map(serializeRequest)
        .map((row) => ({ ...row, status: effectiveStatus({ ...row, createdAt: row.createdAt }, now) }))
        .sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')));
      return res.status(200).json({ incoming: map(incoming), outgoing: map(outgoing) });
    }

    // ---- GET notifications: unread, newest first ----
    if (req.method === 'GET' && action === 'notifications') {
      const snap = await firestore
        .collection('notifications')
        .where('uid', '==', decoded.uid)
        .orderBy('createdAt', 'desc')
        .limit(30)
        .get();
      const notifications = snap.docs.map((doc) => {
        const data = doc.data() || {};
        return {
          id: doc.id,
          type: data.type,
          requestId: data.requestId,
          actorUsername: data.actorUsername,
          amountPkn: Number(data.amountPkn || 0),
          read: Boolean(data.read),
          createdAt: data.createdAt,
        };
      });
      return res.status(200).json({ notifications });
    }

    if (req.method === 'POST' && action === 'read-notifications') {
      const snap = await firestore
        .collection('notifications')
        .where('uid', '==', decoded.uid)
        .where('read', '==', false)
        .limit(100)
        .get();
      const now = admin.firestore.FieldValue.serverTimestamp();
      const batch = firestore.batch();
      snap.docs.forEach((doc) => batch.update(doc.ref, { read: true, readAt: now }));
      await batch.commit();
      return res.status(200).json({ ok: true, marked: snap.size });
    }

    if (req.method !== 'POST') {
      return res.status(405).json({ error: 'Unsupported action.' });
    }

    // ---- POST create: request + chat event + notification in one transaction ----
    if (action === 'create') {
      const check = validateCreate(req.body || {});
      if (check.error) {
        return res.status(400).json({ error: check.error });
      }
      const { toUsername, amountPkn: amount, note, clientToken } = check.value;

      const usernameDoc = await firestore.collection('usernames').doc(toUsername).get();
      if (!usernameDoc.exists || !usernameDoc.data()?.uid) {
        return res.status(404).json({ error: 'No Pokoin account was found for that username.' });
      }
      const toUid = usernameDoc.data().uid;
      if (toUid === decoded.uid) {
        return res.status(400).json({ error: 'You cannot request PKN from your own account.' });
      }

      const meDoc = await firestore.collection('users').doc(decoded.uid).get();
      const fromUsername = String(meDoc.data()?.username || '').trim().toLowerCase();

      const docId = clientToken
        ? requestDocId(decoded.uid, clientToken)
        : firestore.collection('money_requests').doc().id;
      const requestRef = firestore.collection('money_requests').doc(docId);
      const pairKey = pairKeyFor(decoded.uid, toUid);
      const convoRef = firestore.collection('conversations').doc(pairKey);
      const eventRef = convoRef.collection('events').doc();
      const nref = firestore.collection('notifications').doc();
      const members = [decoded.uid, toUid].sort();
      const now = admin.firestore.FieldValue.serverTimestamp();

      let duplicate = false;
      await firestore.runTransaction(async (transaction) => {
        const existing = await transaction.get(requestRef);
        if (existing.exists) {
          duplicate = true;
          return;
        }
        transaction.set(requestRef, {
          fromUid: decoded.uid,
          fromUsername,
          toUid,
          toUsername: toUsername,
          amountPkn: amount,
          note,
          status: STATUS.PENDING,
          ...(clientToken ? { clientToken } : {}),
          createdAt: now,
        });
        const convo = await transaction.get(convoRef);
        const convoData = convo.exists ? convo.data() : {};
        if (!convo.exists) {
          transaction.set(convoRef, {
            pairKey,
            members,
            memberUsernames: { [decoded.uid]: fromUsername, [toUid]: toUsername },
            unread: {},
            createdAt: now,
          });
        }
        transaction.set(eventRef, {
          type: 'money_request',
          senderUid: decoded.uid,
          senderUsername: fromUsername,
          amountPkn: amount,
          note,
          requestId: docId,
          createdAt: now,
        });
        transaction.update(convoRef, {
          unread: bumpUnread(convoData.unread, members, decoded.uid),
          lastEvent: { type: 'money_request', amountPkn: amount, requestId: docId, senderUid: decoded.uid, at: now },
        });
        transaction.set(nref, {
          uid: toUid,
          type: 'money_request_created',
          requestId: docId,
          actorUsername: fromUsername,
          amountPkn: amount,
          read: false,
          createdAt: now,
        });
      });

      return res.status(200).json({ ok: true, requestId: docId, duplicate });
    }

    // ---- POST pay: balances + ledger + status + chat + notification, atomic ----
    if (action === 'pay') {
      const requestId = String(req.body?.requestId || '');
      if (!requestId) {
        return res.status(400).json({ error: 'Missing request id.' });
      }

      const requests = firestore.collection('money_requests');
      const ledger = firestore.collection('ledger_entries');
      const notifications = firestore.collection('notifications');

      let outcome = {};
      await firestore.runTransaction(async (transaction) => {
        const requestDoc = await transaction.get(requests.doc(requestId));
        if (!requestDoc.exists) {
          throw Object.assign(new Error('Request not found.'), { statusCode: 404 });
        }
        const data = requestDoc.data() || {};
        const guard = canPay(data, decoded.uid);
        if (!guard.ok) {
          throw Object.assign(new Error(guard.error), { statusCode: 400 });
        }

        const payerBalanceRef = firestore.collection('balances').doc(decoded.uid);
        const payerBalance = await transaction.get(payerBalanceRef);
        const available = Number(payerBalance.data()?.availablePkn || 0);
        if (available < Number(data.amountPkn)) {
          throw Object.assign(new Error('Your account balance is too low.'), { statusCode: 400 });
        }

        const pairKey = pairKeyFor(decoded.uid, data.fromUid);
        const convoRef = firestore.collection('conversations').doc(pairKey);
        const convo = await transaction.get(convoRef);
        const members = convo.exists ? convo.data().members : [decoded.uid, data.fromUid].sort();
        const convoData = convo.exists ? convo.data() : {};
        const now = admin.firestore.FieldValue.serverTimestamp();
        const outLedger = ledger.doc();
        const inLedger = ledger.doc();

        if (!convo.exists) {
          transaction.set(convoRef, {
            pairKey,
            members,
            memberUsernames: { [decoded.uid]: data.toUsername, [data.fromUid]: data.fromUsername },
            unread: {},
            createdAt: now,
          });
        }

        transaction.set(
          payerBalanceRef,
          { availablePkn: admin.firestore.FieldValue.increment(-Number(data.amountPkn)), updatedAt: now },
          { merge: true },
        );
        transaction.set(
          firestore.collection('balances').doc(data.fromUid),
          { availablePkn: admin.firestore.FieldValue.increment(Number(data.amountPkn)), updatedAt: now },
          { merge: true },
        );
        transaction.set(outLedger, {
          uid: decoded.uid,
          type: 'money_request_paid_sent',
          amountPkn: -Number(data.amountPkn),
          counterpartyUid: data.fromUid,
          counterpartyUsername: data.fromUsername,
          requestId,
          createdAt: now,
        });
        transaction.set(inLedger, {
          uid: data.fromUid,
          type: 'money_request_paid_received',
          amountPkn: Number(data.amountPkn),
          counterpartyUid: decoded.uid,
          counterpartyUsername: data.toUsername,
          requestId,
          createdAt: now,
        });
        transaction.update(requestDoc.ref, {
          status: STATUS.PAID,
          paidAt: now,
          paidBy: decoded.uid,
          paymentLedgerId: outLedger.id,
        });
        transaction.update(convoRef, {
          unread: bumpUnread(convoData.unread, members, decoded.uid),
          lastEvent: { type: 'money_request', amountPkn: Number(data.amountPkn), requestId, paid: true, senderUid: data.fromUid, at: now },
        });
        transaction.set(notifications.doc(), {
          uid: data.fromUid,
          type: 'money_request_paid',
          requestId,
          actorUsername: data.toUsername,
          amountPkn: Number(data.amountPkn),
          read: false,
          createdAt: now,
        });
        outcome = { amountPkn: Number(data.amountPkn), fromUsername: data.fromUsername };
      });

      return res.status(200).json({ ok: true, ...outcome });
    }

    // ---- POST decline / cancel ----
    if (action === 'decline' || action === 'cancel') {
      const requestId = String(req.body?.requestId || '');
      if (!requestId) {
        return res.status(400).json({ error: 'Missing request id.' });
      }
      const requestRef = firestore.collection('money_requests').doc(requestId);
      const requestDoc = await requestRef.get();
      if (!requestDoc.exists) {
        return res.status(404).json({ error: 'Request not found.' });
      }
      const data = requestDoc.data() || {};
      const guard = canRespond(data, decoded.uid, action);
      if (!guard.ok) {
        return res.status(400).json({ error: guard.error });
      }
      const pairKey = pairKeyFor(data.fromUid, data.toUid);
      const convoRef = firestore.collection('conversations').doc(pairKey);
      const now = admin.firestore.FieldValue.serverTimestamp();
      const status = action === 'decline' ? STATUS.DECLINED : STATUS.CANCELLED;
      const notifyUid = action === 'decline' ? data.fromUid : data.toUid;

      await firestore.runTransaction(async (transaction) => {
        const fresh = await transaction.get(requestRef);
        const guardAgain = canRespond(fresh.data() || {}, decoded.uid, action);
        if (!guardAgain.ok) {
          throw Object.assign(new Error(guardAgain.error), { statusCode: 400 });
        }
        transaction.update(requestRef, { status, resolvedAt: now });
        const convo = await transaction.get(convoRef);
        const members = convo.exists ? convo.data().members : [data.fromUid, data.toUid].sort();
        const convoData = convo.exists ? convo.data() : {};
        transaction.update(convoRef, {
          unread: bumpUnread(convoData.unread, members, decoded.uid),
          lastEvent: { type: 'money_request', amountPkn: Number(data.amountPkn || 0), requestId, paid: false, cancelled: action === 'cancel', declined: action === 'decline', senderUid: data.fromUid, at: now },
        });
      });

      const nref = firestore.collection('notifications').doc();
      await nref.set({
        uid: notifyUid,
        type: action === 'decline' ? 'money_request_declined' : 'money_request_cancelled',
        requestId,
        actorUsername: action === 'decline' ? data.toUsername : data.fromUsername,
        amountPkn: Number(data.amountPkn || 0),
        read: false,
        createdAt: now,
      });
      return res.status(200).json({ ok: true, status });
    }

    return res.status(400).json({ error: 'Unknown action.' });
  } catch (error) {
    console.error('money-request failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Money request failed.',
    });
  }
};
