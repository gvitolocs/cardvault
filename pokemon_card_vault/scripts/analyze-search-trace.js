#!/usr/bin/env node

const fs = require('node:fs');

function usage() {
  console.error('Usage: node scripts/analyze-search-trace.js trace.json');
  process.exit(1);
}

const file = process.argv[2];
if (!file) usage();

const trace = JSON.parse(fs.readFileSync(file, 'utf8'));
const events = Array.isArray(trace.events) ? trace.events : [];

function byType(type) {
  return events.filter((event) => event.type === type);
}

function data(event) {
  return event && typeof event.data === 'object' ? event.data : {};
}

function cardsFrom(event) {
  const top = data(event).top;
  return Array.isArray(top) ? top.map((card) => `${card.id}:${card.name}`) : [];
}

function markdownList(items) {
  return items.length ? items.map((item) => `- ${item}`).join('\n') : '- none';
}

const inputEvents = byType('flutter.input.changed');
const serviceResponses = byType('service.autocomplete.response');
const serviceErrors = byType('service.autocomplete.error');
const serviceDebug = byType('service.autocomplete.debug');
const rendered = byType('provider.preview.render');
const staleDrops = byType('provider.preview.remote_drop_stale');
const selected = byType('flutter.preview.selected');

const latencies = serviceResponses
  .map((event) => Number(data(event).elapsedMs || 0))
  .filter((value) => Number.isFinite(value) && value > 0);
const averageLatency = latencies.length
  ? Math.round(latencies.reduce((sum, value) => sum + value, 0) / latencies.length)
  : 0;
const maxLatency = latencies.length ? Math.max(...latencies) : 0;

const renderedByQuery = new Map();
for (const event of rendered) {
  renderedByQuery.set(String(data(event).query || ''), cardsFrom(event));
}

const mismatches = [];
for (const event of serviceDebug) {
  const debug = data(event).debug || {};
  const query = String(data(event).query || debug.searchTerm || '');
  const ranked = (((debug || {}).ranked || []))
    .slice(0, 5)
    .map((row) => `${row.card_id}:${row.name}`);
  const ui = (renderedByQuery.get(query) || []).slice(0, 5);
  if (ranked.length && ui.length && ranked.join('|') !== ui.join('|')) {
    mismatches.push(`${query}: API ${ranked.join(', ')} != UI ${ui.join(', ')}`);
  }
}

const fallbackEvents = [];
for (const event of serviceDebug) {
  const debug = data(event).debug || {};
  const candidateDebug = debug.candidateDebug || {};
  if (candidateDebug.searchPath && !String(candidateDebug.searchPath).includes('split')) {
    fallbackEvents.push(`${debug.searchTerm || data(event).query}: ${candidateDebug.searchPath}`);
  }
}

const report = [
  '# Search Trace Analysis',
  '',
  `Session: ${trace.session?.id || 'unknown'}`,
  `Events: ${events.length}`,
  '',
  '## Typing',
  `- Input events: ${inputEvents.length}`,
  `- Final query: ${inputEvents.length ? data(inputEvents[inputEvents.length - 1]).query : ''}`,
  '',
  '## Latency',
  `- Autocomplete responses: ${serviceResponses.length}`,
  `- Average client-observed latency: ${averageLatency} ms`,
  `- Max client-observed latency: ${maxLatency} ms`,
  `- Errors: ${serviceErrors.length}`,
  '',
  '## Flow Signals',
  `- Render snapshots: ${rendered.length}`,
  `- Stale remote responses dropped: ${staleDrops.length}`,
  `- Selection events: ${selected.length}`,
  `- API/UI top-row mismatches: ${mismatches.length}`,
  `- Split-search fallback events: ${fallbackEvents.length}`,
  '',
  '## Issues',
  markdownList([
    ...serviceErrors.map((event) => `${data(event).query}: ${data(event).error}`),
    ...mismatches.map((item) => `API/UI mismatch: ${item}`),
    ...fallbackEvents.map((item) => `Search fallback: ${item}`),
    ...staleDrops.map((event) => `Stale response dropped for ${data(event).query}`),
  ]),
  '',
  '## Last Rendered Suggestions',
  markdownList(
    rendered.length
      ? cardsFrom(rendered[rendered.length - 1]).map((item, index) => `${index + 1}. ${item}`)
      : [],
  ),
  '',
  '## Recommended Next Checks',
  markdownList([
    serviceErrors.length ? 'Inspect service/API errors first.' : '',
    mismatches.length ? 'Compare API debug ranked rows against provider local reranking.' : '',
    fallbackEvents.length ? 'Check peer3 name-search latency and circuit state.' : '',
    staleDrops.length ? 'Review debounce timing and stale-response policy.' : '',
    !serviceErrors.length && !mismatches.length && !fallbackEvents.length
      ? 'Use DB probe output to tune ranking/indexes for bad result order.'
      : '',
  ].filter(Boolean)),
].join('\n');

console.log(report);
