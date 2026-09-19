'use strict';

/**
 * Qwen VL (local Ollama qwen3-vl:32b-instruct) compares our catalog JPEG
 * to a pokemontcg.io scan. Pixel size still decides obvious wins; Qwen is
 * for close calls and "is this the same card?" Giuseppe: helper, not source
 * of truth — verify the JSON before acting on it.
 */

const DEFAULT_OLLAMA = process.env.OLLAMA_HOST || 'http://127.0.0.1:11434';
const DEFAULT_MODEL = process.env.QWEN_VL_MODEL || 'qwen3-vl:32b-instruct';

function parseQwenJson(text) {
  const raw = String(text || '').trim();
  const fenced = raw.match(/\{[\s\S]*\}/);
  if (!fenced) {
    return null;
  }
  try {
    const parsed = JSON.parse(fenced[0]);
    const winner = String(parsed.winner || '').toLowerCase();
    if (!['ours', 'api', 'tie'].includes(winner)) {
      return null;
    }
    return {
      same_card: parsed.same_card === true,
      winner,
      reason: String(parsed.reason || '').slice(0, 400),
    };
  } catch {
    return null;
  }
}

function shouldAskQwen({ better, ratio, mapped }) {
  if (!mapped) {
    return false;
  }
  if (ratio == null || !Number.isFinite(ratio)) {
    return true;
  }
  if (better && ratio >= 2) {
    return false;
  }
  if (!better && ratio <= 0.85) {
    return false;
  }
  if (ratio >= 0.99 && ratio <= 1.01) {
    return false;
  }
  return ratio >= 0.85 && ratio <= 2;
}

async function jpegThumb(buffer, sharp, maxEdge = 512) {
  return sharp(buffer, { failOn: 'none' })
    .rotate()
    .resize({ width: maxEdge, height: maxEdge, fit: 'inside', withoutEnlargement: true })
    .jpeg({ quality: 85 })
    .toBuffer();
}

async function qwenCompareCardImages({
  oursJpeg,
  apiBytes,
  name,
  set,
  sharp,
  fetchImpl = fetch,
  ollamaHost = DEFAULT_OLLAMA,
  model = DEFAULT_MODEL,
} = {}) {
  if (!sharp) {
    throw new Error('sharp is required');
  }
  const ours = await jpegThumb(oursJpeg, sharp);
  const api = await jpegThumb(apiBytes, sharp);
  const prompt =
    `Two photos of a Pokemon TCG single "${name}" from "${set}". ` +
    'Image 1 is our catalog. Image 2 is pokemontcg.io. ' +
    'Reply JSON only: {"same_card":true|false,"winner":"ours"|"api"|"tie","reason":"one sentence"}. ' +
    'winner is the sharper complete printed card face.';
  const response = await fetchImpl(`${String(ollamaHost).replace(/\/+$/, '')}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model,
      stream: false,
      think: false,
      messages: [
        {
          role: 'user',
          content: prompt,
          images: [ours.toString('base64'), api.toString('base64')],
        },
      ],
    }),
  });
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`qwen-vl ${response.status} ${body.slice(0, 200)}`);
  }
  const payload = await response.json();
  const text = payload.message && payload.message.content;
  const parsed = parseQwenJson(text);
  if (!parsed) {
    throw new Error(`qwen-vl unparsed: ${String(text || '').slice(0, 200)}`);
  }
  return { ...parsed, raw: String(text || '').slice(0, 500), model };
}

module.exports = {
  DEFAULT_OLLAMA,
  DEFAULT_MODEL,
  parseQwenJson,
  shouldAskQwen,
  jpegThumb,
  qwenCompareCardImages,
};
