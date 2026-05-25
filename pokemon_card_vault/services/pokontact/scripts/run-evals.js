const fs = require('fs');
const path = require('path');

const DEFAULT_ENDPOINT = process.env.POKONTACT_EVAL_ENDPOINT || 'http://127.0.0.1:8787/chat';
const SERVICE_TOKEN = process.env.POKONTACT_SERVICE_TOKEN || '';
const CASES_PATH = process.env.POKONTACT_EVAL_CASES ||
  path.join(__dirname, '..', 'evals', 'pokontact-eval-cases.json');
const MAX_LATENCY_MS = Number(process.env.POKONTACT_EVAL_MAX_LATENCY_MS || 1500);
const ESCALATED_MAX_LATENCY_MS = Number(process.env.POKONTACT_EVAL_ESCALATED_MAX_LATENCY_MS || 7000);

function includesAll(text, values = []) {
  return values.every((value) => text.includes(value));
}

function includesAny(text, values = []) {
  return values.length === 0 || values.some((value) => text.includes(value));
}

function fail(reason) {
  return { ok: false, reason };
}

function checkCase(testCase, payload, elapsed) {
  const reply = String(payload.reply || '');
  const source = String(payload.source || payload.serviceDelivery?.source || '');
  const maxLatency = testCase.expectSourceAny?.includes('model-escalated') ||
    testCase.expectSourceAny?.includes('curated-escalation-fallback')
    ? ESCALATED_MAX_LATENCY_MS
    : MAX_LATENCY_MS;

  if (payload.intent !== testCase.expectIntent) {
    return fail(`intent ${payload.intent} !== ${testCase.expectIntent}`);
  }
  if (testCase.expectSource && source !== testCase.expectSource) {
    return fail(`source ${source} !== ${testCase.expectSource}`);
  }
  if (testCase.expectSourceAny && !testCase.expectSourceAny.includes(source)) {
    return fail(`source ${source} not in ${testCase.expectSourceAny.join(', ')}`);
  }
  if (!includesAll(reply, testCase.mustInclude || [])) {
    return fail(`missing required text in reply: ${(testCase.mustInclude || []).join(', ')}`);
  }
  if (!includesAny(reply, testCase.mustIncludeAny || [])) {
    return fail(`missing one of: ${(testCase.mustIncludeAny || []).join(', ')}`);
  }
  const forbidden = (testCase.mustNotInclude || []).find((value) => reply.includes(value));
  if (forbidden) {
    return fail(`reply includes forbidden text: ${forbidden}`);
  }
  if (elapsed > maxLatency) {
    return fail(`latency ${elapsed}ms > ${maxLatency}ms`);
  }
  return { ok: true };
}

async function ask(testCase) {
  const started = Date.now();
  const headers = { 'Content-Type': 'application/json' };
  if (SERVICE_TOKEN) {
    headers.Authorization = `Bearer ${SERVICE_TOKEN}`;
  }
  const response = await fetch(DEFAULT_ENDPOINT, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      message: testCase.message,
      messages: testCase.history || [],
      user: { username: 'Eval Runner' },
    }),
  });
  const elapsed = Date.now() - started;
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload.error || `HTTP ${response.status}`);
  }
  return { payload, elapsed };
}

async function main() {
  const cases = JSON.parse(fs.readFileSync(CASES_PATH, 'utf8'));
  let failed = 0;

  for (const testCase of cases) {
    try {
      const { payload, elapsed } = await ask(testCase);
      const result = checkCase(testCase, payload, elapsed);
      const source = payload.source || payload.serviceDelivery?.source || '';
      if (result.ok) {
        console.log(`PASS ${testCase.id} (${payload.intent}/${source}, ${elapsed}ms)`);
      } else {
        failed += 1;
        console.error(`FAIL ${testCase.id}: ${result.reason}`);
        console.error(`  reply=${JSON.stringify(payload.reply || '')}`);
      }
    } catch (error) {
      failed += 1;
      console.error(`FAIL ${testCase.id}: ${error.message || error}`);
    }
  }

  if (failed > 0) {
    console.error(`\n${failed} eval case(s) failed.`);
    process.exit(1);
  }
  console.log(`\nAll ${cases.length} eval case(s) passed.`);
}

main();
