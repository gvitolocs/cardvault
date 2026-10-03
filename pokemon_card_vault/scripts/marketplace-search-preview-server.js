#!/usr/bin/env node
'use strict';

// Local-only preview without database credentials. Uses public live reads;
// search-page is composed locally from the working upstream candidate search.
// node scripts/marketplace-search-preview-server.js
// flutter run -d web-server --web-port=5000 --web-hostname=127.0.0.1 \
//   --dart-define=MARKETPLACE_API_BASE_URL=http://127.0.0.1:5001
const http = require('node:http');
const { createHandler } = require('../api/marketplace-search-page');
const { effectivePrintBucket, printLangMatchesBucket } = require('../api/_print_bucket');
const UPSTREAM = 'https://api.pokoin.com';

async function publicRead(path, body) {
  const response = await fetch(`${UPSTREAM}${path}`, {
    method: body ? 'POST' : 'GET',
    headers: { accept: 'application/json', ...(body ? { 'content-type': 'application/json' } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}),
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw new Error(`Upstream read failed (${response.status})`);
  return response.json();
}

async function candidateRead(body, read = publicRead) {
  // Forward only public search inputs, never tokens or debug/auth parameters.
  return read('/api/marketplace-search-candidates', {
    search_term: String(body.search_term || '').slice(0, 80),
    result_limit: Math.min(Math.max(Number(body.result_limit) || 100, 1), 100),
    result_offset: Math.min(Math.max(Number(body.result_offset) || 0, 0), 10000),
    search_language: String(body.search_language || 'en').slice(0, 12),
  });
}

function createPreviewHandler({ read = publicRead } = {}) {
const searchPage = createHandler({
  rowsForCards: async ({ query, limit, offset, searchLanguage, productType, productSearchOnly, printLanguage }) => {
    const rows = await candidateRead({ search_term: query, result_limit: limit, result_offset: offset, search_language: searchLanguage }, read);
    return rows.filter((row) =>
      (!productType || row.product_type === productType) &&
      (!productSearchOnly || row.item_kind === 'product') &&
      (printLanguage === 'all' || printLangMatchesBucket(printLanguage, effectivePrintBucket(row))));
  },
  // Candidate rows already carry availability and theme data from production.
  overlayCheapestOnRows: async (rows) => rows,
  attachTitleLanguageOnRows: null,
  productFacetRows: async ({ query, searchLanguage }) => read(
    `/api/marketplace-cards?${new URLSearchParams({ facets: 'products', query, lang: searchLanguage })}`,
  ),
});

async function handle(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Cache-Control', 'no-store');
  res.status = (code) => { res.statusCode = code; return res; };
  res.json = (body) => { res.setHeader('content-type', 'application/json'); res.end(JSON.stringify(body)); return res; };
  if (req.method === 'OPTIONS') return res.status(204).end();
  const url = new URL(req.url, 'http://127.0.0.1:5001');
  try {
    if (req.method === 'GET' && url.pathname === '/api/marketplace-search-page') {
      return await searchPage(req, res);
    }
    // These POST endpoints are public read-only searches, not mutations.
    if (req.method === 'POST' && [
      '/api/marketplace-search-candidates',
      '/api/marketplace-autocomplete',
      '/api/searchbar-token-predict',
    ].includes(url.pathname)) {
      let body = '';
      for await (const chunk of req) {
        body += chunk.toString();
        if (body.length > 32768) return res.status(413).json({ error: 'Request too large.' });
      }
      const input = JSON.parse(body);
      if (url.pathname === '/api/marketplace-search-candidates') {
        return res.json(await candidateRead(input, read));
      }
      const language = String(input.search_language || 'en').slice(0, 12);
      const payload = url.pathname === '/api/marketplace-autocomplete'
        ? {
          search_term: String(input.search_term || '').slice(0, 80),
          result_limit: Math.min(Math.max(Number(input.result_limit) || 20, 1), 100),
          pool_limit: Math.min(Math.max(Number(input.pool_limit) || 1000, 1), 15874),
          search_language: language,
          preview_mode: String(input.preview_mode || '').slice(0, 24),
        }
        : {
          query: String(input.query || '').slice(0, 80),
          limit: Math.min(Math.max(Number(input.limit) || 5, 1), 5),
          search_language: language,
        };
      // Never forward authorization, personalization, debug or session inputs.
      return res.json(await read(url.pathname, payload));
    }
    if (req.method === 'GET' && url.pathname.startsWith('/api/')) {
      return res.json(await read(`${url.pathname}${url.search}`));
    }
    return res.status(405).json({ error: 'This preview supports public reads only.' });
  } catch (error) {
    console.error('Preview read failed:', error.message);
    return res.status(503).json({ error: 'We are working on a solution.' });
  }
}
return handle;
}

module.exports = { createPreviewHandler };

if (require.main === module) {
  if (process.env.NODE_ENV === 'production') throw new Error('This server is for local previews only.');
  http.createServer(createPreviewHandler()).listen(5001, '127.0.0.1', () => {
    console.log('Read-only marketplace preview API: http://127.0.0.1:5001');
  });
}
