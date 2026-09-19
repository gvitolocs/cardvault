'use strict';

const WORKING_MESSAGE = 'We are working on a solution.';
const PIPELINE_FAILURE_RE = /ECONNREFUSED|ETIMEDOUT|ENOTFOUND|ECONNRESET|EHOSTUNREACH|EPIPE|EAI_AGAIN|connect E[A-Z]+|127\.0\.0\.1:\d+|connection refused|too many clients|remaining connection slots|the database system is (starting|shutting)|could not connect to server/i;

function isPipelineFailure(text) {
  return PIPELINE_FAILURE_RE.test(String(text || ''));
}

function sanitizeCheckError(text) {
  const raw = String(text || '').trim();
  if (!raw) {
    return 'down';
  }
  if (/ECONNREFUSED/i.test(raw)) {
    return 'econnrefused';
  }
  if (/ETIMEDOUT|timeout/i.test(raw)) {
    return 'timeout';
  }
  if (/ENOTFOUND|EAI_AGAIN/i.test(raw)) {
    return 'unresolved';
  }
  if (isPipelineFailure(raw)) {
    return 'down';
  }
  return raw.slice(0, 80);
}

function sanitizeHealthPayload(payload) {
  const checks = {};
  for (const [name, row] of Object.entries(payload.checks || {})) {
    if (!row || typeof row !== 'object') {
      checks[name] = row;
      continue;
    }
    if (!row.error) {
      checks[name] = row;
      continue;
    }
    checks[name] = { ...row, error: sanitizeCheckError(row.error) };
  }
  return { ...payload, checks };
}

function publicErrorBody(error, fallback = WORKING_MESSAGE) {
  const text = String((error && error.message) || error || '').trim();
  if (!text || isPipelineFailure(text) || (error && isPipelineFailure(error.code))) {
    return { error: WORKING_MESSAGE };
  }
  return { error: text || fallback };
}

function publicErrorStatus(error, fallback = 500) {
  const text = String((error && (error.message || error.code)) || error || '');
  if (isPipelineFailure(text)) {
    return 503;
  }
  const code = Number(error && error.statusCode);
  return Number.isFinite(code) && code >= 400 ? code : fallback;
}

function sanitizePublicJson(statusCode, payload) {
  const status = Number(statusCode) || 200;
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    return { statusCode: status, payload };
  }
  if (payload.checks && payload.service) {
    return { statusCode: status, payload: sanitizeHealthPayload(payload) };
  }
  const text = String(payload.error || payload.message || '');
  if (isPipelineFailure(text)) {
    return { statusCode: 503, payload: { error: WORKING_MESSAGE } };
  }
  return { statusCode: status, payload };
}

module.exports = {
  WORKING_MESSAGE,
  isPipelineFailure,
  publicErrorBody,
  publicErrorStatus,
  sanitizeCheckError,
  sanitizePublicJson,
};
