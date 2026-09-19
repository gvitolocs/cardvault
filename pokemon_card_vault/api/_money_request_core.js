// Pure money-request core: status vocabulary, transitions, validation and
// expiry rules for /api/money-request. Kept free of Firebase so the state
// machine is unit-testable — the endpoint only wires it to Firestore.
//
// State machine (terminal states never re-enter pending):
//   pending -> paid | declined | cancelled | expired
// `expired` is evaluated lazily from createdAt + TTL; nothing writes it.

const STATUS = Object.freeze({
  PENDING: 'pending',
  PAID: 'paid',
  DECLINED: 'declined',
  CANCELLED: 'cancelled',
  EXPIRED: 'expired',
});

const TERMINAL = new Set([STATUS.PAID, STATUS.DECLINED, STATUS.CANCELLED, STATUS.EXPIRED]);

const TTL_DAYS = 14;
const TTL_MS = TTL_DAYS * 24 * 60 * 60 * 1000;

const TRANSITIONS = Object.freeze({
  [STATUS.PENDING]: new Set([STATUS.PAID, STATUS.DECLINED, STATUS.CANCELLED, STATUS.EXPIRED]),
});

const USERNAME_RE = /^[a-z0-9]{3,32}$/;

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

function validateNote(note) {
  const clean = String(note || '').trim().slice(0, 140);
  return clean;
}

/** Validate a create payload. Returns { error } or { value }. */
function validateCreate({ recipientUsername, amountPkn, note, clientToken } = {}) {
  const toUsername = String(recipientUsername || '').trim().toLowerCase();
  if (!USERNAME_RE.test(toUsername)) {
    return { error: 'Enter a valid recipient username.' };
  }
  const amount = validateAmountPkn(amountPkn);
  if (amount.error) {
    return amount;
  }
  return {
    value: {
      toUsername,
      amountPkn: amount.amount,
      note: validateNote(note),
      clientToken: String(clientToken || '').trim().slice(0, 64) || null,
    },
  };
}

function createdAtMs(requestData = {}, fallback = 0) {
  const value = requestData.createdAt;
  if (!value) return fallback;
  if (typeof value.toMillis === 'function') return value.toMillis();
  const ms = Number(value);
  return Number.isFinite(ms) ? ms : fallback;
}

/** Pending requests older than the TTL read as expired — lazily, no cron. */
function effectiveStatus(requestData = {}, nowMs = Date.now()) {
  const status = String(requestData.status || STATUS.PENDING);
  if (status === STATUS.PENDING && nowMs - createdAtMs(requestData, nowMs) > TTL_MS) {
    return STATUS.EXPIRED;
  }
  return status;
}

/** May `uid` pay this request right now? Returns { ok } or { ok:false, error }. */
function canPay(requestData = {}, uid, nowMs = Date.now()) {
  if (!uid) return { ok: false, error: 'Sign in to pay a request.' };
  const status = effectiveStatus(requestData, nowMs);
  if (status === STATUS.PAID) return { ok: false, error: 'This request was already paid.' };
  if (status === STATUS.DECLINED) return { ok: false, error: 'This request was declined.' };
  if (status === STATUS.CANCELLED) return { ok: false, error: 'This request was cancelled.' };
  if (status === STATUS.EXPIRED) return { ok: false, error: 'This request has expired.' };
  if (String(requestData.toUid || '') !== String(uid)) {
    return { ok: false, error: 'Only the request recipient can pay it.' };
  }
  if (String(requestData.fromUid || '') === String(uid)) {
    return { ok: false, error: 'You cannot pay your own request.' };
  }
  return { ok: true };
}

/** May `uid` apply `action` (decline|cancel)? */
function canRespond(requestData = {}, uid, action, nowMs = Date.now()) {
  const status = effectiveStatus(requestData, nowMs);
  if (status !== STATUS.PENDING) {
    return { ok: false, error: 'Only pending requests can be updated.' };
  }
  if (action === 'decline') {
    if (String(requestData.toUid || '') !== String(uid)) {
      return { ok: false, error: 'Only the request recipient can decline it.' };
    }
    return { ok: true };
  }
  if (action === 'cancel') {
    if (String(requestData.fromUid || '') !== String(uid)) {
      return { ok: false, error: 'Only the requester can cancel it.' };
    }
    return { ok: true };
  }
  return { ok: false, error: 'Unknown action.' };
}

module.exports = {
  STATUS,
  TERMINAL,
  TTL_DAYS,
  USERNAME_RE,
  validateAmountPkn,
  validateNote,
  validateCreate,
  effectiveStatus,
  canPay,
  canRespond,
  createdAtMs,
};
