#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');

const ROOT_DIR = path.resolve(__dirname, '..');
const FIXTURE_PATH = path.join(
  ROOT_DIR,
  'test',
  'fixtures',
  'pokemon_card_names_by_generation.txt',
);
const LANGUAGES = ['it', 'fr', 'de', 'es', 'pt', 'ja', 'zh-cn', 'zh-tw'];
const CHUNK_SIZE = 100;
const ENGLISH_ID_WIDTH = 5;
const FETCH_RETRIES = 3;

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

function chunked(values, size) {
  const chunks = [];
  for (let index = 0; index < values.length; index += size) {
    chunks.push(values.slice(index, index + size));
  }
  return chunks;
}

function isCommentOrBlank(line) {
  const trimmed = line.trim();
  return !trimmed || trimmed.startsWith('#');
}

function isHeading(line) {
  return line.trim().startsWith('## ');
}

function stripExistingIndex(line) {
  return line.replace(/^\s*\[(\d+)]\s+/, '').trim();
}

function normalizeAscii(value) {
  return String(value || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '');
}

function readEnglishEntries() {
  const lines = fs.readFileSync(FIXTURE_PATH, 'utf8').split(/\r?\n/);
  const entries = [];
  const body = [];
  let inTranslations = false;

  for (const line of lines) {
    if (line.trim() === '## TCGdex localized name variants') {
      inTranslations = true;
      continue;
    }
    if (inTranslations) continue;

    body.push(line);
    if (isCommentOrBlank(line) || isHeading(line)) continue;

    const name = stripExistingIndex(line);
    if (!name) continue;
    entries.push({
      index: entries.length + 1,
      name,
    });
  }

  return { body, entries };
}

function indexedEnglishBody(body) {
  let nextIndex = 1;
  return body.map((line) => {
    if (isCommentOrBlank(line) || isHeading(line)) return line;
    const name = stripExistingIndex(line);
    if (!name) return line;
    const id = String(nextIndex++).padStart(ENGLISH_ID_WIDTH, '0');
    return `[${id}] ${name}`;
  });
}

async function fetchJson(url) {
  for (let attempt = 1; attempt <= FETCH_RETRIES; attempt += 1) {
    try {
      const response = await fetch(url);
      if (!response.ok) {
        if (attempt < FETCH_RETRIES && response.status >= 500) {
          await sleep(500 * attempt);
          continue;
        }
        throw new Error(`${url} failed ${response.status}: ${await response.text()}`);
      }
      return response.json();
    } catch (error) {
      if (attempt >= FETCH_RETRIES) throw error;
      await sleep(500 * attempt);
  }
  }
  throw new Error(`${url} failed after ${FETCH_RETRIES} attempts`);
}

async function fetchLanguageCards(language) {
  return fetchJson(`https://api.tcgdex.net/v2/${language}/cards`);
}

async function fetchCardDetails(language, cardIds) {
  const rows = await Promise.all(
    cardIds.map(async (id) => {
      const url = `https://api.tcgdex.net/v2/${language}/cards/${encodeURIComponent(id)}`;
      let card;
      try {
        card = await fetchJson(url);
      } catch (error) {
        return null;
      }
      return typeof card?.name === 'string' && card.name.trim()
        ? {
            id,
            name: card.name.trim(),
            category: normalizeAscii(card.category).trim().toLowerCase(),
            dexId: Array.isArray(card.dexId) ? card.dexId.map(String).sort() : [],
          }
        : null;
    }),
  );
  return rows.filter(Boolean);
}

function sameDexId(left, right) {
  if (!left.dexId.length || !right.dexId.length) return false;
  if (left.dexId.length !== right.dexId.length) return false;
  return left.dexId.every((value, index) => value === right.dexId[index]);
}

function addTranslation(translationsByName, englishName, language, localizedName, sourceCardId) {
  if (!englishName || !localizedName) return;
  if (localizedName.toLowerCase() === englishName.toLowerCase()) return;
  let byLanguage = translationsByName.get(englishName);
  if (!byLanguage) {
    byLanguage = new Map();
    translationsByName.set(englishName, byLanguage);
  }
  let values = byLanguage.get(language);
  if (!values) {
    values = new Map();
    byLanguage.set(language, values);
  }
  values.set(localizedName, sourceCardId);
}

async function translationsForLanguage(language, englishFixtureNames) {
  const localizedCards = await fetchLanguageCards(language);
  const translationsByName = new Map();
  const cardChunks = chunked(localizedCards.filter((card) => card?.id && card?.name), CHUNK_SIZE);
  let processed = 0;

  for (const cardChunk of cardChunks) {
    const cardIds = cardChunk.map((card) => card.id);
    const [englishRows, localizedRows] = await Promise.all([
      fetchCardDetails('en', cardIds),
      fetchCardDetails(language, cardIds),
    ]);
    const englishById = new Map(englishRows.map((row) => [row.id, row]));
    const localizedById = new Map(localizedRows.map((row) => [row.id, row]));
    for (const localizedCard of cardChunk) {
      const englishCard = englishById.get(localizedCard.id);
      const localizedDetail = localizedById.get(localizedCard.id);
      if (englishCard?.category !== 'pokemon' || localizedDetail?.category !== 'pokemon') {
        continue;
      }
      if (!sameDexId(englishCard, localizedDetail)) {
        continue;
      }
      const englishName = englishCard.name;
      const localizedName = localizedDetail.name;
      if (!englishFixtureNames.has(englishName)) continue;
      addTranslation(
        translationsByName,
        englishName,
        language,
        localizedName,
        localizedCard.id,
      );
    }
    processed += cardChunk.length;
    if (processed % 1000 === 0 || processed === localizedCards.length) {
      console.log(`${language}: processed ${processed}/${localizedCards.length}`);
    }
  }

  return translationsByName;
}

function mergeTranslationMaps(target, source) {
  for (const [englishName, byLanguage] of source.entries()) {
    let targetByLanguage = target.get(englishName);
    if (!targetByLanguage) {
      targetByLanguage = new Map();
      target.set(englishName, targetByLanguage);
    }
    for (const [language, values] of byLanguage.entries()) {
      let targetValues = targetByLanguage.get(language);
      if (!targetValues) {
        targetValues = new Map();
        targetByLanguage.set(language, targetValues);
      }
      for (const [localizedName, sourceCardId] of values.entries()) {
        targetValues.set(localizedName, sourceCardId);
      }
    }
  }
}

function translationLines(entries, translationsByName) {
  const lines = [
    '',
    '## TCGdex localized name variants',
    '# Format: [EnglishIndex] <language> | <localized name> | tcgdex:<source card id>',
    '# Source: https://api.tcgdex.net/v2/<language>/cards, matched by shared TCGdex card id.',
    '# Processed in chunks of 100 with concurrent lookups within each chunk.',
    '',
  ];

  for (const entry of entries) {
    const byLanguage = translationsByName.get(entry.name);
    if (!byLanguage) continue;
    const englishId = String(entry.index).padStart(ENGLISH_ID_WIDTH, '0');
    lines.push(`### [${englishId}] ${entry.name}`);
    for (const language of LANGUAGES) {
      const values = byLanguage.get(language);
      if (!values) continue;
      const localizedRows = [...values.entries()].sort(([left], [right]) =>
        left.localeCompare(right),
      );
      for (const [localizedName, sourceCardId] of localizedRows) {
        lines.push(`[${englishId}] ${language} | ${localizedName} | tcgdex:${sourceCardId}`);
      }
    }
    lines.push('');
  }

  return lines;
}

async function main() {
  const { body, entries } = readEnglishEntries();
  const englishFixtureNames = new Set(entries.map((entry) => entry.name));
  const translationsByName = new Map();

  for (const language of LANGUAGES) {
    console.log(`${language}: fetching localized variants`);
    const translations = await translationsForLanguage(language, englishFixtureNames);
    mergeTranslationMaps(translationsByName, translations);
  }

  const nextContents = [
    ...indexedEnglishBody(body),
    ...translationLines(entries, translationsByName),
  ].join('\n');
  fs.writeFileSync(FIXTURE_PATH, `${nextContents.replace(/\s+$/u, '')}\n`);
  console.log(
    `Updated ${path.relative(ROOT_DIR, FIXTURE_PATH)} with ${entries.length} indexed names.`,
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
