// Pure direct-conversation core for the Pokoin chat pipeline. No Firebase —
// the endpoint (chat.js) wires this to Firestore transactions.
//
// CANONICAL_DIRECT_CONVERSATION: one conversation per unordered user pair.
// The doc id IS the sorted pair key, so A/B and B/A resolve to the same doc.

const EVENT_TYPES = Object.freeze({
  TEXT: 'text',
  MONEY_REQUEST: 'money_request',
  PAYMENT: 'payment',
  SYSTEM: 'system',
});

const USERNAME_RE = /^[a-z0-9]{3,32}$/;
const UID_RE = /^[a-zA-Z0-9]{1,128}$/;
const TEXT_MAX = 1000;
const NOTE_MAX = 140;

/** Deterministic conversation id for an unordered pair of uids. */
function pairKeyFor(uidA, uidB) {
  const a = String(uidA || '').trim();
  const b = String(uidB || '').trim();
  if (!a || !b) throw new Error('Two participants are required.');
  if (a === b) throw new Error('A conversation needs two different users.');
  return [a, b].sort().join('__');
}

function isParticipant(pairKey, uid) {
  return String(pairKey || '').split('__').includes(String(uid || ''));
}

function otherMember(pairKey, uid) {
  const members = String(pairKey || '').split('__');
  return members.find((member) => member !== String(uid)) || '';
}

/** Trim + normalise a chat text message. Returns '' when empty. */
function cleanText(text) {
  return String(text || '').replace(/\s+/g, ' ').trim().slice(0, TEXT_MAX);
}

function cleanNote(note) {
  return String(note || '').trim().slice(0, NOTE_MAX);
}

function validateAmountPkn(value) {
  const amount = Number(value);
  if (!Number.isInteger(amount) || amount <= 0) {
    return { error: 'Enter a whole PKN amount greater than zero.' };
  }
  if (amount > 1000000000) {
    return { error: 'That amount is too large.' };
  }
  return { amount };
}

/** Sanitised event doc payload. Returns { error } or { value }. */
function validateEvent(input = {}) {
  const type = String(input.type || '');
  if (!Object.values(EVENT_TYPES).includes(type)) {
    return { error: 'Unknown event type.' };
  }
  if (type === EVENT_TYPES.TEXT) {
    const text = cleanText(input.text);
    if (!text) return { error: 'Message is empty.' };
    return { value: { type, text } };
  }
  if (type === EVENT_TYPES.MONEY_REQUEST || type === EVENT_TYPES.PAYMENT) {
    const amount = validateAmountPkn(input.amountPkn);
    if (amount.error) return amount;
    return {
      value: {
        type,
        amountPkn: amount.amount,
        note: cleanNote(input.note),
        ...(type === EVENT_TYPES.MONEY_REQUEST ? { requestId: String(input.requestId || '') } : {}),
        ...(type === EVENT_TYPES.PAYMENT ? { transactionId: String(input.transactionId || '') } : {}),
      },
    };
  }
  return { value: { type, text: cleanText(input.text).slice(0, 240) } };
}

/** Unread map: only the OTHER participants' counters move; the map always
 * ends well-formed (every member has a key). */
function bumpUnread(unreadMap = {}, members = [], senderUid) {
  const next = { ...(unreadMap || {}) };
  for (const member of members) {
    next[member] = member === String(senderUid)
      ? Number(next[member] || 0)
      : Number(next[member] || 0) + 1;
  }
  return next;
}

function unreadFor(conversationData = {}, uid) {
  return Number((conversationData.unread || {})[String(uid)] || 0);
}

/** Conversations-list preview copy — human text, never event type names. */
function previewForEvent(lastEvent = {}) {
  const amount = `${lastEvent.amountPkn || 0} PKN`;
  switch (String(lastEvent.type || '')) {
    case EVENT_TYPES.TEXT:
      return String(lastEvent.text || '').slice(0, 80);
    case EVENT_TYPES.MONEY_REQUEST:
      return lastEvent.paid ? `Paid ✓ ${amount}` : `Requested ${amount}`;
    case EVENT_TYPES.PAYMENT:
      return lastEvent.incoming ? `Sent you ${amount}` : `You sent ${amount}`;
    default:
      return '';
  }
}

module.exports = {
  EVENT_TYPES,
  USERNAME_RE,
  UID_RE,
  TEXT_MAX,
  pairKeyFor,
  isParticipant,
  otherMember,
  cleanText,
  cleanNote,
  validateAmountPkn,
  validateEvent,
  bumpUnread,
  unreadFor,
  previewForEvent,
};
