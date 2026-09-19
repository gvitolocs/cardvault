'use strict';

// Pure Scan Connect rules. No I/O here so every rule is unit-testable.
// Spec: pokoin-web docs/SCAN_CONNECT.md, docs/SCAN_LISTING_WORKFLOW.md.

const crypto = require('crypto');

const PAIRING_TTL_MS = 120_000;
/** Abandoned waiting/desk session (pairing idle, no phone). */
const SESSION_IDLE_MS = 30 * 60_000;
/** Connected phone with no accepted scan for this long → disconnect phone, keep batch. */
const SCAN_IDLE_MS = 10 * 60_000;
const EXPIRY_UPLOAD_GRACE_MS = 120_000;
const PHONE_LOST_MS = 12_000;
const SCANNING_MS = 20_000;

// BattleScan server/app.py `_immediate`: top >= 0.80 and margin >= 0.08.
// 0.60 is its "possible match" floor. Stricter than the 0.72 page redirect.
const MATCH_SCORE = 0.80;
const MATCH_MARGIN = 0.08;
const CANDIDATE_FLOOR = 0.60;
const MAX_CANDIDATES = 5;
const MAX_HITS = 10;
const MAX_IMAGE_BYTES = 45_000;

const CONDITIONS = ['NM', 'SP', 'MP', 'PL', 'Poor'];
const LANGUAGES = ['EN', 'IT', 'FR', 'DE', 'ES', 'JP', 'PT', 'NL', 'PL', 'RU', 'KO', 'ZH', 'ZHT', 'ID', 'TH', 'VI'];
const FINISHES = ['standard', 'holo', 'reverse', 'stamped', 'promo', 'other'];

const DEFAULT_BATCH_DEFAULTS = Object.freeze({
  language: 'EN',
  condition: 'NM',
  foilState: 'standard',
  firstEdition: false,
  signed: false,
  altered: false,
  location: '',
  startPosition: 1,
  quantity: 1,
  mergeRepeats: true,
});

const LIMITS = Object.freeze({
  pairFailPerIp: { max: 8, windowMs: 10 * 60_000 },
  pairTryPerIp: { max: 30, windowMs: 10 * 60_000 },
  pairFailGlobal: { max: 300, windowMs: 10 * 60_000 },
  sessionStartPerSeller: { max: 12, windowMs: 10 * 60_000 },
  pairingRegenPerSession: { max: 30, windowMs: 10 * 60_000 },
  // ~2 scans/s sustained; a leaked phone token cannot flood a batch.
  scanPerSession: { max: 1200, windowMs: 10 * 60_000 },
});

function httpError(statusCode, message, extra = {}) {
  return Object.assign(new Error(message), { statusCode, ...extra });
}

function randomPin(randomInt = crypto.randomInt) {
  return String(randomInt(0, 10000)).padStart(4, '0');
}

function isPin(value) {
  return /^[0-9]{4}$/.test(String(value || ''));
}

function randomSecret(bytes = 32) {
  return crypto.randomBytes(bytes).toString('base64url');
}

function sha256(value) {
  return crypto.createHash('sha256').update(String(value)).digest('hex');
}

function cleanText(value, max = 240) {
  return String(value ?? '').replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, max);
}

function isUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(value || ''));
}

function cleanCardId(value) {
  const text = String(value ?? '').trim();
  return /^[0-9]{1,18}$/.test(text) ? text : '';
}

function pick(list, value, fallback) {
  const text = String(value ?? '').trim();
  const hit = list.find((entry) => entry.toLowerCase() === text.toLowerCase());
  return hit || fallback;
}

function clampInt(value, min, max, fallback) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.min(max, Math.max(min, Math.trunc(n)));
}

function normalizeDefaults(input = {}, base = DEFAULT_BATCH_DEFAULTS) {
  const src = input && typeof input === 'object' ? input : {};
  const has = (key) => Object.prototype.hasOwnProperty.call(src, key);
  return {
    language: has('language') ? pick(LANGUAGES, src.language, base.language) : base.language,
    condition: has('condition') ? pick(CONDITIONS, src.condition, base.condition) : base.condition,
    foilState: has('foilState') ? pick(FINISHES, src.foilState, base.foilState) : base.foilState,
    firstEdition: has('firstEdition') ? src.firstEdition === true : base.firstEdition,
    signed: has('signed') ? src.signed === true : base.signed,
    altered: has('altered') ? src.altered === true : base.altered,
    location: has('location') ? cleanText(src.location, 64) : base.location,
    startPosition: has('startPosition') ? clampInt(src.startPosition, 1, 9999, base.startPosition ?? 1) : (base.startPosition ?? 1),
    quantity: has('quantity') ? clampInt(src.quantity, 1, 99, base.quantity) : base.quantity,
    mergeRepeats: has('mergeRepeats') ? src.mergeRepeats !== false : base.mergeRepeats,
  };
}

function defaultsLabel(defaults = DEFAULT_BATCH_DEFAULTS) {
  const d = normalizeDefaults(defaults);
  const finish = d.foilState === 'standard' ? '' : d.foilState[0].toUpperCase() + d.foilState.slice(1);
  return [
    d.language,
    d.condition,
    finish,
    d.firstEdition ? '1st' : '',
    d.signed ? 'Signed' : '',
    d.altered ? 'Altered' : '',
    d.location ? `${d.location}·${d.startPosition}` : '',
    d.quantity > 1 ? `Qty ${d.quantity}` : '',
  ].filter(Boolean).join(' · ');
}

// History entries are appended with a server-clock changedAt. A scan takes
// the entry in force at capture time, not at receipt.
function pickDefaults(history, capturedAtMs) {
  const list = Array.isArray(history) ? history : [];
  if (!list.length) {
    return { version: 1, changedAt: 0, defaults: { ...DEFAULT_BATCH_DEFAULTS } };
  }
  let chosen = list[0];
  for (const entry of list) {
    if (Number(entry.changedAt) <= capturedAtMs && Number(entry.version) >= Number(chosen.version)) {
      chosen = entry;
    }
  }
  return {
    version: Number(chosen.version),
    changedAt: Number(chosen.changedAt),
    defaults: normalizeDefaults(chosen.defaults),
  };
}

function appendDefaults(history, defaults, version, nowMs, keep = 500) {
  const list = Array.isArray(history) ? history.slice() : [];
  list.push({ version, changedAt: nowMs, defaults: normalizeDefaults(defaults) });
  return list.length > keep ? list.slice(list.length - keep) : list;
}

// Phone clock → server clock, clamped so a skewed phone cannot push a scan
// before pairing or after it arrived.
function capturedAtServer({ capturedAt, clockOffsetMs, receivedAtMs, floorMs = 0 }) {
  const phone = Number(capturedAt);
  const offset = Number(clockOffsetMs);
  if (!Number.isFinite(phone) || phone <= 0 || !Number.isFinite(offset) || Math.abs(offset) > 24 * 3600_000) {
    return receivedAtMs;
  }
  return Math.min(receivedAtMs, Math.max(floorMs, Math.round(phone + offset)));
}

function candidatesFromHits(hits) {
  const seen = new Set();
  const out = [];
  const list = Array.isArray(hits) ? hits.slice(0, MAX_HITS) : [];
  for (const hit of list) {
    if (!hit || typeof hit !== 'object') continue;
    // Pokoin catalogs index `public_id`. A TCGplayer `id` is never a card id.
    const cardId = cleanCardId(hit.public_id ?? hit.publicId ?? hit.cardId);
    const score = Number(hit.score);
    if (!cardId || !Number.isFinite(score) || seen.has(cardId)) continue;
    seen.add(cardId);
    out.push({
      cardId,
      score: Math.max(0, Math.min(1, Math.round(score * 10000) / 10000)),
      name: cleanText(hit.name || hit.card_name, 160),
    });
  }
  out.sort((a, b) => b.score - a.score);
  return out.slice(0, MAX_CANDIDATES);
}

function classifyRecognition(hits) {
  const candidates = candidatesFromHits(hits);
  const top = candidates[0];
  const second = candidates[1];
  if (!top || top.score < CANDIDATE_FLOOR) {
    return { state: 'unmatched', candidates: candidates.filter((c) => c.score >= 0.3), topScore: top ? top.score : 0, margin: 0 };
  }
  const margin = second ? Math.round((top.score - second.score) * 10000) / 10000 : 1;
  const plausible = candidates.filter((c) => c.score >= CANDIDATE_FLOOR);
  if (top.score >= MATCH_SCORE && margin >= MATCH_MARGIN) {
    return { state: 'matched', candidates: plausible, topScore: top.score, margin };
  }
  return { state: 'ambiguous', candidates: plausible, topScore: top.score, margin };
}

// PowerTools identity key mapped to Pokoin columns + location. Used for
// merging consecutive scans. Keep in sync with market/src/scan-model.js.
function stackKey(row = {}) {
  return [
    cleanCardId(row.cardId ?? row.card_id),
    row.condition || '',
    row.language || '',
    row.foilState ?? row.foil_state ?? '',
    (row.firstEdition ?? row.first_edition) ? '1' : '0',
    row.signed ? '1' : '0',
    row.altered ? '1' : '0',
    row.graded ? '1' : '0',
    row.gradingCompany ?? row.grading_company ?? '',
    row.grade ?? '',
    String(row.location ?? '').trim().toLowerCase(),
  ].join('|');
}

// `previous` is the last active row of the batch (by position), or null.
function shouldMerge({ previous, recognition, cardId, snapshot }) {
  if (!previous || !snapshot || snapshot.mergeRepeats === false) return false;
  if (recognition.state !== 'matched') return false;
  if (previous.status !== 'active') return false;
  const prevState = previous.recognition_state ?? previous.recognitionState;
  const prevOk = prevState === 'matched' || prevState === 'manual' || previous.reviewed === true;
  if (!prevOk) return false;
  const nextRow = {
    cardId,
    condition: snapshot.condition,
    language: snapshot.language,
    foilState: snapshot.foilState,
    firstEdition: snapshot.firstEdition,
    signed: snapshot.signed,
    altered: snapshot.altered,
    graded: false,
    gradingCompany: '',
    grade: '',
    location: snapshot.location,
  };
  const prevRow = {
    cardId: previous.card_id ?? previous.cardId,
    condition: previous.condition,
    language: previous.language,
    foilState: previous.foil_state ?? previous.foilState,
    firstEdition: previous.first_edition ?? previous.firstEdition,
    signed: previous.signed,
    altered: previous.altered,
    graded: previous.graded,
    gradingCompany: previous.grading_company ?? previous.gradingCompany ?? '',
    grade: previous.grade ?? '',
    location: previous.location,
  };
  return stackKey(prevRow) === stackKey(nextRow) && Boolean(nextRow.cardId);
}

function decodeImage(value) {
  if (value == null || value === '') return null;
  const text = String(value).replace(/^data:image\/jpeg;base64,/, '');
  if (!/^[A-Za-z0-9+/=_-]+$/.test(text)) throw httpError(400, 'Image must be base64 JPEG.');
  const buffer = Buffer.from(text, 'base64');
  if (buffer.length > MAX_IMAGE_BYTES) throw httpError(413, 'Scan image too large.');
  if (buffer.length < 4 || buffer[0] !== 0xff || buffer[1] !== 0xd8) throw httpError(400, 'Image must be JPEG.');
  return buffer;
}

function parseScanEvent(body = {}) {
  const scanEventId = String(body.scanEventId || '').toLowerCase();
  if (!isUuid(scanEventId)) throw httpError(400, 'scanEventId must be a UUID.');
  const clientSequence = clampInt(body.clientSequence, 0, 2_000_000_000, null);
  if (clientSequence === null) throw httpError(400, 'clientSequence is required.');
  const recognition = body.recognition && typeof body.recognition === 'object' ? body.recognition : {};
  const hits = Array.isArray(recognition.hits) ? recognition.hits.slice(0, MAX_HITS) : [];
  const timings = {};
  for (const key of ['captureToRequestMs', 'identifyMs', 'uploadQueuedMs', 'attempt']) {
    const n = Number(body.timings?.[key]);
    if (Number.isFinite(n) && n >= 0 && n < 3_600_000) timings[key] = Math.round(n);
  }
  return {
    scanEventId,
    clientSequence,
    capturedAt: Number(body.capturedAt),
    clockOffsetMs: Number(body.clockOffsetMs),
    catalog: cleanText(recognition.catalog, 64),
    hits,
    image: decodeImage(body.image),
    timings,
  };
}

const ITEM_PATCH_FIELDS = {
  cardId: 'card_id',
  condition: 'condition',
  language: 'language',
  foilState: 'foil_state',
  firstEdition: 'first_edition',
  signed: 'signed',
  altered: 'altered',
  graded: 'graded',
  gradingCompany: 'grading_company',
  grade: 'grade',
  certificationId: 'certification_id',
  location: 'location',
  quantity: 'quantity',
  pricePkn: 'price_pkn',
  sellerComment: 'seller_comment',
};

// Returns [{column, value}] for a validated patch. Unknown keys are ignored.
function parseItemPatch(patch = {}) {
  const out = [];
  const src = patch && typeof patch === 'object' ? patch : {};
  const has = (key) => Object.prototype.hasOwnProperty.call(src, key);
  if (has('cardId')) {
    const cardId = cleanCardId(src.cardId);
    if (!cardId) throw httpError(400, 'cardId must be a public card id.');
    out.push({ column: 'card_id', value: cardId });
  }
  if (has('condition')) out.push({ column: 'condition', value: pick(CONDITIONS, src.condition, null) ?? badField('condition') });
  if (has('language')) out.push({ column: 'language', value: pick(LANGUAGES, src.language, null) ?? badField('language') });
  if (has('foilState')) out.push({ column: 'foil_state', value: pick(FINISHES, src.foilState, null) ?? badField('foilState') });
  for (const key of ['firstEdition', 'signed', 'altered', 'graded']) {
    if (has(key)) out.push({ column: ITEM_PATCH_FIELDS[key], value: src[key] === true });
  }
  if (has('gradingCompany')) out.push({ column: 'grading_company', value: cleanText(src.gradingCompany, 80) || null });
  if (has('grade')) out.push({ column: 'grade', value: cleanText(src.grade, 40) || null });
  if (has('certificationId')) out.push({ column: 'certification_id', value: cleanText(src.certificationId, 120) || null });
  if (has('location')) out.push({ column: 'location', value: cleanText(src.location, 64) });
  if (has('quantity')) {
    const q = Number(src.quantity);
    if (!Number.isSafeInteger(q) || q < 1 || q > 99) throw httpError(400, 'Quantity must be between 1 and 99.');
    out.push({ column: 'quantity', value: q });
  }
  if (has('pricePkn')) {
    if (src.pricePkn === null || src.pricePkn === '') {
      out.push({ column: 'price_pkn', value: null });
    } else {
      const p = Number(src.pricePkn);
      if (!Number.isFinite(p) || p <= 0 || p > 1e9) throw httpError(400, 'Enter a valid PKN price.');
      out.push({ column: 'price_pkn', value: Math.round(p * 100) / 100 });
    }
    out.push({ column: 'price_suggested', value: src.priceSuggested === true });
  }
  if (has('sellerComment')) out.push({ column: 'seller_comment', value: cleanText(src.sellerComment, 500) });
  if (src.confirm === true) out.push({ column: 'reviewed', value: true });
  return out;
}

function badField(name) {
  throw httpError(400, `Invalid ${name}.`);
}

// Why a row cannot be submitted, or '' when it can.
// intent "collection": skip marketplace-only blockers (price). Recognition /
// integrity blockers still apply.
function submitProblem(row, { intent = 'list' } = {}) {
  if (row.status !== 'active') return '';
  if (!cleanCardId(row.card_id)) return 'no_printing';
  if ((row.recognition_state === 'ambiguous' || row.recognition_state === 'unmatched') && !row.reviewed) {
    return 'needs_review';
  }
  if (row.graded && (!row.grading_company || !row.grade)) return 'grading_incomplete';
  if (!Number.isSafeInteger(Number(row.quantity)) || row.quantity < 1 || row.quantity > 99) {
    return 'bad_quantity';
  }
  if (intent !== 'collection') {
    const price = Number(row.price_pkn);
    if (!Number.isFinite(price) || price <= 0) return 'no_price';
  }
  return '';
}

// Session state as the desktop shows it. `DISCONNECTED` is derived from
// presence because a phone losing Wi-Fi cannot report it.
function sessionView(row, nowMs = Date.now()) {
  if (!row) return null;
  const lastSeen = row.phone_last_seen_at ? new Date(row.phone_last_seen_at).getTime() : 0;
  const lastScan = row.last_scan_at ? new Date(row.last_scan_at).getTime() : 0;
  let phase = row.status;
  if (row.status === 'connected') {
    if (nowMs - lastSeen >= PHONE_LOST_MS) phase = 'lost';
    else if (lastScan && nowMs - lastScan < SCANNING_MS) phase = 'scanning';
  }
  if (row.status === 'ended') phase = row.end_reason === 'expired' ? 'expired' : 'completed';
  return {
    id: row.id,
    batchId: row.batch_id,
    status: row.status,
    phase,
    endReason: row.end_reason || null,
    paused: row.paused === true,
    phoneLabel: row.phone_label || '',
    phoneConnectedAt: row.phone_connected_at || null,
    phoneLastSeenAt: row.phone_last_seen_at || null,
    lastScanAt: row.last_scan_at || null,
    phoneScans: Number(row.phone_scans || 0),
    lastActivityAt: row.last_activity_at || null,
    version: Number(row.version || 1),
    createdAt: row.created_at || null,
    endedAt: row.ended_at || null,
  };
}

/** Effective scan-activity clock while a phone is connected. */
function scanIdleActivityMs(row) {
  if (!row) return NaN;
  const lastScan = row.last_scan_at ? new Date(row.last_scan_at).getTime() : NaN;
  if (Number.isFinite(lastScan)) return lastScan;
  const connected = row.phone_connected_at ? new Date(row.phone_connected_at).getTime() : NaN;
  return connected;
}

/** Phone connected but no accepted scan for SCAN_IDLE_MS. Waiting/pairing does not count. */
function isScanIdleExpired(row, nowMs = Date.now()) {
  if (!row || row.status !== 'connected') return false;
  const last = scanIdleActivityMs(row);
  return Number.isFinite(last) && nowMs - last >= SCAN_IDLE_MS;
}

function isIdleExpired(row, nowMs = Date.now()) {
  if (!row || row.status === 'ended') return false;
  // Connected phones use scan-idle disconnect, not this desk-abandon timer.
  if (row.status === 'connected') return false;
  const last = new Date(row.last_activity_at).getTime();
  return Number.isFinite(last) && nowMs - last >= SESSION_IDLE_MS;
}

function deviceLabel(userAgent, provided) {
  const clean = cleanText(provided, 40);
  if (clean) return clean;
  const ua = String(userAgent || '');
  if (/iPhone/.test(ua)) return 'iPhone';
  if (/iPad/.test(ua)) return 'iPad';
  if (/Android/.test(ua)) return /Mobile/.test(ua) ? 'Android phone' : 'Android tablet';
  return 'Phone';
}

function itemView(row) {
  return {
    id: row.id,
    batchId: row.batch_id,
    seq: Number(row.seq),
    position: Number(row.position),
    status: row.status,
    mergedInto: row.merged_into || null,
    scanEventId: row.scan_event_id || null,
    sessionId: row.session_id || null,
    clientSequence: row.client_sequence ?? null,
    capturedAt: row.captured_at || null,
    receivedAt: row.received_at || null,
    recognitionState: row.recognition_state,
    recognition: row.recognition || {},
    defaultsVersion: row.defaults_version ?? null,
    defaultsSnapshot: row.defaults_snapshot || {},
    hasImage: row.has_image === true,
    reviewed: row.reviewed === true,
    cardId: row.card_id || '',
    cardName: row.card_name || '',
    setName: row.set_name || '',
    collectorNumber: row.collector_number || '',
    imageUrl: row.image_url || '',
    nationality: row.nationality || '',
    condition: row.condition,
    language: row.language,
    foilState: row.foil_state,
    firstEdition: row.first_edition === true,
    signed: row.signed === true,
    altered: row.altered === true,
    graded: row.graded === true,
    gradingCompany: row.grading_company || '',
    grade: row.grade || '',
    certificationId: row.certification_id || '',
    location: row.location || '',
    quantity: Number(row.quantity),
    pricePkn: row.price_pkn == null ? null : Number(row.price_pkn),
    priceSuggested: row.price_suggested === true,
    sellerComment: row.seller_comment || '',
    listingId: row.listing_id || null,
    timings: row.timings || {},
    updatedAt: row.updated_at || null,
  };
}

function batchView(row) {
  if (!row) return null;
  return {
    id: row.id,
    status: row.status,
    title: row.title || '',
    defaults: normalizeDefaults(row.defaults),
    defaultsVersion: Number(row.defaults_version || 1),
    cursor: Number(row.item_seq || 0),
    submitResult: row.submit_result || null,
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
    submittedAt: row.submitted_at || null,
  };
}

module.exports = {
  PAIRING_TTL_MS,
  SESSION_IDLE_MS,
  SCAN_IDLE_MS,
  EXPIRY_UPLOAD_GRACE_MS,
  PHONE_LOST_MS,
  MATCH_SCORE,
  MATCH_MARGIN,
  CANDIDATE_FLOOR,
  MAX_IMAGE_BYTES,
  CONDITIONS,
  LANGUAGES,
  FINISHES,
  DEFAULT_BATCH_DEFAULTS,
  LIMITS,
  httpError,
  randomPin,
  isPin,
  randomSecret,
  sha256,
  cleanText,
  isUuid,
  cleanCardId,
  normalizeDefaults,
  defaultsLabel,
  pickDefaults,
  appendDefaults,
  capturedAtServer,
  candidatesFromHits,
  classifyRecognition,
  stackKey,
  shouldMerge,
  decodeImage,
  parseScanEvent,
  parseItemPatch,
  submitProblem,
  sessionView,
  scanIdleActivityMs,
  isScanIdleExpired,
  isIdleExpired,
  deviceLabel,
  itemView,
  batchView,
};
