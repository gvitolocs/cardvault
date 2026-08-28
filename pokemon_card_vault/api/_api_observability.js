const DEFAULT_SLOW_MS = 1000;

function finiteDurationMs(startedAt) {
  const elapsedNs = process.hrtime.bigint() - startedAt;
  return Math.round(Number(elapsedNs) / 1e6);
}

function trimErrorMessage(error) {
  return String(error?.message || error || '')
    .replace(/\s+/g, ' ')
    .slice(0, 500);
}

function observabilityEnabled() {
  return process.env.ORACLE_API_OBSERVABILITY !== '0';
}

function slowRequestThresholdMs() {
  const value = Number(process.env.ORACLE_API_SLOW_MS || DEFAULT_SLOW_MS);
  return Number.isFinite(value) && value >= 0 ? value : DEFAULT_SLOW_MS;
}

function shouldLogRequest({ durationMs, statusCode, error }) {
  if (!observabilityEnabled()) return false;
  if (process.env.ORACLE_API_LOG_ALL_REQUESTS === '1') return true;
  if (error) return true;
  if (Number(statusCode) >= 500) return true;
  return durationMs >= slowRequestThresholdMs();
}

function statusCodeForObservation(res, error) {
  if (error) {
    if (Number(error.statusCode)) return Number(error.statusCode);
    if (error instanceof SyntaxError) return 400;
    return 500;
  }
  return res.statusCode || 200;
}

function safePath(req) {
  try {
    return new URL(req.url || '/', `http://${req.headers?.host || 'localhost'}`).pathname;
  } catch (_) {
    return String(req.url || '').split('?')[0] || '/';
  }
}

function logApiObservation(record) {
  const line = JSON.stringify({
    type: 'api_request',
    ...record,
  });
  if (record.error || Number(record.statusCode) >= 500) {
    console.error(line);
  } else {
    console.warn(line);
  }
}

async function observeApiRequest({ req, res, route }, handler) {
  const startedAt = process.hrtime.bigint();
  let error = null;
  try {
    return await handler();
  } catch (caught) {
    error = caught;
    throw caught;
  } finally {
    const durationMs = finiteDurationMs(startedAt);
    const statusCode = statusCodeForObservation(res, error);
    if (shouldLogRequest({ durationMs, statusCode, error })) {
      logApiObservation({
        route: route?.path || safePath(req),
        file: route?.file || '',
        method: req.method || '',
        path: safePath(req),
        statusCode,
        durationMs,
        ...(error ? {
          error: error.name || 'Error',
          message: trimErrorMessage(error),
        } : {}),
      });
    }
  }
}

module.exports = {
  observeApiRequest,
  _test: {
    finiteDurationMs,
    safePath,
    shouldLogRequest,
    slowRequestThresholdMs,
    statusCodeForObservation,
    trimErrorMessage,
  },
};
