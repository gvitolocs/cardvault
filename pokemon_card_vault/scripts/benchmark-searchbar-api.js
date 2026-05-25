#!/usr/bin/env node

const { performance } = require('node:perf_hooks');

const DEFAULT_QUERIES = [
  'pikachu',
  'mew ex 216',
  'mimikyu',
  'charizard',
  'pikchu',
  'charzard',
];

function parseArgs(argv) {
  const options = {
    baseUrl: process.env.SEARCHBAR_BASE_URL || process.env.BASE_URL || 'https://pokoin.com',
    endpoint: process.env.SEARCHBAR_ENDPOINT || '/api/marketplace-autocomplete',
    runs: Number(process.env.SEARCHBAR_RUNS || 1),
    limit: Number(process.env.SEARCHBAR_LIMIT || 20),
    poolLimit: Number(process.env.SEARCHBAR_POOL_LIMIT || 5000),
    language: process.env.SEARCHBAR_LANGUAGE || 'en',
    queries: [...DEFAULT_QUERIES],
    debug: process.env.SEARCHBAR_DEBUG === '1',
    timeoutMs: Number(process.env.SEARCHBAR_TIMEOUT_MS || 15000),
    topRows: Number(process.env.SEARCHBAR_TOP_ROWS || 5),
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = argv[index + 1];
    if (arg === '--base-url' && next) {
      options.baseUrl = next;
      index += 1;
    } else if (arg === '--endpoint' && next) {
      options.endpoint = next;
      index += 1;
    } else if (arg === '--runs' && next) {
      options.runs = Number(next);
      index += 1;
    } else if (arg === '--limit' && next) {
      options.limit = Number(next);
      index += 1;
    } else if (arg === '--pool-limit' && next) {
      options.poolLimit = Number(next);
      index += 1;
    } else if (arg === '--language' && next) {
      options.language = next;
      index += 1;
    } else if (arg === '--timeout-ms' && next) {
      options.timeoutMs = Number(next);
      index += 1;
    } else if (arg === '--top-rows' && next) {
      options.topRows = Number(next);
      index += 1;
    } else if (arg === '--queries' && next) {
      options.queries = next.split(',').map((item) => item.trim()).filter(Boolean);
      index += 1;
    } else if (arg === '--query' && next) {
      options.queries.push(next);
      index += 1;
    } else if (arg === '--debug') {
      options.debug = true;
    } else if (arg === '--help') {
      printHelp();
      process.exit(0);
    }
  }
  options.runs = Number.isFinite(options.runs) ? Math.max(1, Math.trunc(options.runs)) : 1;
  options.limit = Number.isFinite(options.limit) ? Math.max(1, Math.trunc(options.limit)) : 20;
  options.poolLimit = Number.isFinite(options.poolLimit) ? Math.max(1, Math.trunc(options.poolLimit)) : 5000;
  options.timeoutMs = Number.isFinite(options.timeoutMs) ? Math.max(1000, Math.trunc(options.timeoutMs)) : 15000;
  options.topRows = Number.isFinite(options.topRows) ? Math.max(1, Math.trunc(options.topRows)) : 5;
  return options;
}

function printHelp() {
  console.log(`Usage: node scripts/benchmark-searchbar-api.js [options]

Named workflow: 2pikabench (char-by-char searchbar prefix benchmark with
context forwarding, reusable for Pikachu or any other card/search phrase)

Options:
  --base-url <url>      Base URL, default SEARCHBAR_BASE_URL or https://pokoin.com
  --endpoint <path>     Endpoint path, default /api/marketplace-autocomplete
  --runs <n>            Runs per query, default 1
  --queries <csv>       Comma-separated final queries
  --query <text>        Add one final query
  --limit <n>           Visible row cap, default 20
  --pool-limit <n>      Requested candidate pool cap, default 5000
  --language <code>     Search language, default en
  --timeout-ms <n>      Per-request timeout, default 15000
  --top-rows <n>        Top rows to print for ranking checks, default 5
  --debug               Request debug fields

Reports backend/API timing and ranking traces only. Flutter-side local fallback
correctness must be reported from the Flutter 2pikabench/provider harness.
`);
}

function searchbarPayload(endpoint, step, options, previousSearchContext) {
  if (endpoint.includes('searchbar-cards')) {
    return {
      query: step,
      search_language: options.language,
      limit: options.limit,
      pool_limit: options.poolLimit,
      previous_search_context: previousSearchContext,
      debug: options.debug,
      mode: 'benchmark_step',
    };
  }
  return {
    search_term: step,
    search_language: options.language,
    result_limit: options.limit,
    pool_limit: options.poolLimit,
    previous_search_context: previousSearchContext,
    debug: options.debug,
  };
}

function typedSteps(query) {
  const chars = [...String(query)];
  return chars.map((_, index) => chars.slice(0, index + 1).join(''));
}

function percentile(values, p) {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const index = Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length));
  return sorted[index];
}

function average(values) {
  if (values.length === 0) return null;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function firstNumber(...values) {
  for (const value of values) {
    const number = Number(value);
    if (Number.isFinite(number)) return number;
  }
  return null;
}

function parseServerTiming(value) {
  const timings = {};
  for (const part of String(value || '').split(',')) {
    const [name, ...params] = part.trim().split(';');
    const durParam = params.find((param) => param.trim().startsWith('dur='));
    if (name && durParam) timings[name] = Number(durParam.trim().slice(4));
  }
  return timings;
}

async function requestStep(url, payload, timeoutMs) {
  const started = performance.now();
  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(timeoutMs),
    });
    const text = await response.text();
    const durationMs = performance.now() - started;
    const serverTiming = response.headers.get('server-timing');
    let json = null;
    try {
      json = text ? JSON.parse(text) : null;
    } catch {
      json = null;
    }
    return {
      ok: response.ok,
      status: response.status,
      durationMs,
      payloadBytes: Buffer.byteLength(text),
      serverTiming,
      serverTimings: parseServerTiming(serverTiming),
      body: json,
      error: response.ok ? null : (json?.error || text.slice(0, 200)),
    };
  } catch (error) {
    return {
      ok: false,
      status: 0,
      durationMs: performance.now() - started,
      payloadBytes: 0,
      serverTiming: null,
      serverTimings: {},
      body: null,
      error: error.name === 'TimeoutError'
        ? `request timed out after ${timeoutMs}ms`
        : (error.message || String(error)),
    };
  }
}

function normalizeResult(result, endpoint) {
  const body = result.body;
  if (Array.isArray(body)) {
    return {
      rows: body,
      searchContext: null,
      searchPath: null,
      poolSize: null,
      contextCardIds: 0,
      contextCandidateLabels: 0,
      timings: {
        durationMs: firstNumber(
          result.serverTimings.autocomplete,
          result.serverTimings['autocomplete-empty'],
          result.serverTimings.search,
        ),
        candidateMs: result.serverTimings.candidate ?? null,
        analyticsMs: result.serverTimings.analytics ?? null,
        rankMs: result.serverTimings.rank ?? null,
      },
    };
  }
  const metaTimings = body?.meta?.timings || {};
  const debug = body?.debug || {};
  const searchContext = body?.search_context || null;
  return {
    rows: body?.rows || [],
    searchContext,
    searchPath: body?.meta?.search_path || body?.debug?.searchPath || body?.pool?.strategy || null,
    poolSize: body?.meta?.candidate_counts?.pool_size ?? body?.debug?.poolSize ?? body?.pool?.size ?? null,
    contextCardIds: body?.meta?.candidate_counts?.context_card_ids ?? searchContext?.card_ids?.length ?? 0,
    contextCandidateLabels: body?.meta?.candidate_counts?.context_candidate_labels ??
      searchContext?.candidate_labels?.length ??
      0,
    timings: {
      durationMs: firstNumber(
        metaTimings.duration_ms,
        debug.durationMs,
        result.serverTimings.autocomplete,
        result.serverTimings['autocomplete-empty'],
        result.serverTimings['autocomplete-canceled'],
        result.serverTimings.search,
      ),
      candidateMs: firstNumber(metaTimings.candidate_ms, debug.candidateDurationMs, result.serverTimings.candidate),
      analyticsMs: firstNumber(metaTimings.analytics_ms, debug.analyticsDurationMs, result.serverTimings.analytics),
      rankMs: firstNumber(metaTimings.rank_ms, debug.rankDurationMs, result.serverTimings.rank),
    },
    endpoint,
  };
}

async function runBenchmark(options) {
  const endpoint = options.endpoint.startsWith('/') ? options.endpoint : `/${options.endpoint}`;
  const url = new URL(endpoint, options.baseUrl).toString();
  const samples = [];
  const failures = [];
  const finals = [];

  for (let run = 1; run <= options.runs; run += 1) {
    for (const finalQuery of options.queries) {
      let previousSearchContext = null;
      const steps = typedSteps(finalQuery);
      for (const step of steps) {
        const payload = searchbarPayload(endpoint, step, options, previousSearchContext);
        const result = await requestStep(url, payload, options.timeoutMs);
        const normalized = normalizeResult(result, endpoint);
        const depth = [...step.replace(/\s+/g, '')].length;
        const sample = {
          run,
          finalQuery,
          step,
          depth,
          ok: result.ok,
          status: result.status,
          durationMs: result.durationMs,
          serverDurationMs: normalized.timings.durationMs,
          candidateMs: normalized.timings.candidateMs,
          analyticsMs: normalized.timings.analyticsMs,
          rankMs: normalized.timings.rankMs,
          payloadBytes: result.payloadBytes,
          searchPath: normalized.searchPath,
          poolSize: normalized.poolSize,
          contextCardIds: normalized.contextCardIds,
          contextCandidateLabels: normalized.contextCandidateLabels,
          rowCount: normalized.rows.length,
          topResults: normalized.rows.slice(0, options.topRows).map((row) => ({
            id: row.card_id || row.id,
            name: row.name,
            set: row.set_name,
            number: row.card_number,
            rarity: row.rarity,
            label: row.label || row.display_label || row.subtitle,
          })),
        };
        samples.push(sample);
        if (!result.ok) {
          failures.push({ ...sample, error: result.error });
        }
        previousSearchContext = normalized.searchContext || previousSearchContext;
        if (step === finalQuery) {
          finals.push(sample);
        }
      }
    }
  }

  return { url, options, samples, failures, finals };
}

function groupedByDepth(samples) {
  const groups = new Map();
  for (const sample of samples) {
    if (!groups.has(sample.depth)) groups.set(sample.depth, []);
    groups.get(sample.depth).push(sample);
  }
  return [...groups.entries()].sort((a, b) => a[0] - b[0]);
}

function formatMs(value) {
  return Number.isFinite(value) ? value.toFixed(1) : 'n/a';
}

function formatTopRows(rows) {
  return rows
    .map((row, index) => {
      const parts = [row.name, row.set, row.number, row.rarity, row.label].filter(Boolean);
      const suffix = row.id ? ` (${row.id})` : '';
      return `${index + 1}. ${parts.join(' | ') || 'unnamed'}${suffix}`;
    })
    .join(' ; ') || 'no rows';
}

function printReport(result) {
  console.log(`Searchbar benchmark: ${result.url}`);
  console.log('Benchmark layer: backend/API only (not Flutter-side local fallback).');
  console.log(`Runs=${result.options.runs} queries=${result.options.queries.length} steps=${result.samples.length}`);
  console.log(`Failures=${result.failures.length}`);
  console.log('');
  console.log('Latency by depth (client/server/candidate/analytics/rank ms / payload bytes):');
  for (const [depth, samples] of groupedByDepth(result.samples)) {
    const durations = samples.map((sample) => sample.durationMs);
    const serverDurations = samples.map((sample) => sample.serverDurationMs).filter(Number.isFinite);
    const candidateDurations = samples.map((sample) => sample.candidateMs).filter(Number.isFinite);
    const analyticsDurations = samples.map((sample) => sample.analyticsMs).filter(Number.isFinite);
    const rankDurations = samples.map((sample) => sample.rankMs).filter(Number.isFinite);
    const bytes = samples.map((sample) => sample.payloadBytes);
    const paths = [...new Set(samples.map((sample) => sample.searchPath).filter(Boolean))].join(', ') || 'n/a';
    console.log([
      `depth=${depth}`,
      `n=${samples.length}`,
      `avg=${average(durations).toFixed(1)}`,
      `p50=${percentile(durations, 50).toFixed(1)}`,
      `p95=${percentile(durations, 95).toFixed(1)}`,
      `server_avg=${serverDurations.length ? average(serverDurations).toFixed(1) : 'n/a'}`,
      `candidate_avg=${candidateDurations.length ? average(candidateDurations).toFixed(1) : 'n/a'}`,
      `analytics_avg=${analyticsDurations.length ? average(analyticsDurations).toFixed(1) : 'n/a'}`,
      `rank_avg=${rankDurations.length ? average(rankDurations).toFixed(1) : 'n/a'}`,
      `bytes_avg=${average(bytes).toFixed(0)}`,
      `paths=${paths}`,
    ].join(' '));
  }
  console.log('');
  console.log('Per-prefix ranking trace (judge correctness from top rows):');
  for (const sample of result.samples) {
    console.log([
      `query="${sample.finalQuery}"`,
      `run=${sample.run}`,
      `prefix="${sample.step}"`,
      `depth=${sample.depth}`,
      `status=${sample.status}`,
      `client=${formatMs(sample.durationMs)}ms`,
      `server=${formatMs(sample.serverDurationMs)}ms`,
      `candidate=${formatMs(sample.candidateMs)}ms`,
      `analytics=${formatMs(sample.analyticsMs)}ms`,
      `rank=${formatMs(sample.rankMs)}ms`,
      `bytes=${sample.payloadBytes}`,
      `path=${sample.searchPath || 'n/a'}`,
      `rows=${sample.rowCount}`,
      `context_ids=${sample.contextCardIds}`,
      `context_labels=${sample.contextCandidateLabels}`,
      `pool=${sample.poolSize ?? 'n/a'}`,
    ].join(' '));
    console.log(`  top=${formatTopRows(sample.topResults)}`);
  }
  console.log('');
  console.log('Representative final results:');
  for (const sample of result.finals) {
    console.log(`${sample.finalQuery}: ${sample.durationMs.toFixed(1)}ms ${sample.rowCount} rows path=${sample.searchPath || 'n/a'} top=${formatTopRows(sample.topResults)}`);
  }
  if (result.failures.length > 0) {
    console.log('');
    console.log('Failures:');
    for (const failure of result.failures.slice(0, 20)) {
      console.log(`${failure.finalQuery} step="${failure.step}" status=${failure.status} error=${failure.error}`);
    }
  }
}

if (require.main === module) {
  runBenchmark(parseArgs(process.argv.slice(2)))
    .then(printReport)
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
}

module.exports = {
  parseArgs,
  typedSteps,
  searchbarPayload,
  parseServerTiming,
  runBenchmark,
};
