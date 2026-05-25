const {
  cancelSearchSession,
  cleanSearchSessionId,
} = require('./_searchbar_session');
const { cleanSearchTerm } = require('./marketplace-search-candidates');

function readInput(req) {
  const source = req.method === 'GET' ? req.query || {} : req.body || {};
  return {
    sessionId: cleanSearchSessionId(
      source.search_session_id ??
        source.searchSessionId ??
        source.session_id ??
        source.sessionId,
    ),
    query: cleanSearchTerm(source.query ?? source.last_query ?? source.lastQuery),
    reason: cleanSearchTerm(source.reason || 'exit'),
  };
}

async function handler(req, res) {
  if (req.method !== 'POST' && req.method !== 'GET') {
    res.setHeader('Allow', 'GET, POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  const input = readInput(req);
  const entry = cancelSearchSession(input.sessionId, {
    query: input.query,
    reason: input.reason,
  });
  res.setHeader('Cache-Control', 'no-store');
  return res.status(200).json({
    ok: true,
    canceled: Boolean(entry),
    session_id: input.sessionId,
  });
}

module.exports = handler;
module.exports.readInput = readInput;
