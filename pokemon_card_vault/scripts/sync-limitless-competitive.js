#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { Pool } = require('pg');

const ROOT_DIR = path.resolve(__dirname, '..');
const POKOINPOS_ROOT = process.env.POKOINPOS_ROOT || '/Users/giuseppe/pokoinpos';
const DEFAULT_ENV_FILE = path.join(POKOINPOS_ROOT, 'deploy/env/peer4-postgres.env');
const DEFAULT_API_BASE = 'https://play.limitlesstcg.com/api';
const DEFAULT_PUBLIC_BASE = 'https://limitlesstcg.com';

function cleanEnvValue(value) {
  const trimmed = String(value || '').trim();
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1).replace(/\\n/g, '\n');
  }
  return trimmed;
}

function loadEnvFile(filePath) {
  const resolved = path.resolve(filePath);
  if (!fs.existsSync(resolved)) return { path: resolved, loaded: false };
  for (const line of fs.readFileSync(resolved, 'utf8').split(/\r?\n/)) {
    const stripped = line.trim();
    if (!stripped || stripped.startsWith('#') || !stripped.includes('=')) continue;
    const separator = stripped.indexOf('=');
    const key = stripped.slice(0, separator).replace(/^export\s+/, '').trim();
    if (!key || process.env[key]) continue;
    process.env[key] = cleanEnvValue(stripped.slice(separator + 1));
  }
  return { path: resolved, loaded: true };
}

function loadDefaultFallbackEnvFiles(primaryPath, fallbackPaths = [path.join(ROOT_DIR, '.env.local')]) {
  const loaded = [];
  for (const filePath of [primaryPath, ...fallbackPaths]) {
    const result = loadEnvFile(filePath);
    if (result.loaded) loaded.push(result.path);
  }
  return loaded;
}

function integerOption(value, name) {
  const number = Number(value);
  if (!Number.isSafeInteger(number)) {
    throw new Error(`${name} must be an integer.`);
  }
  return number;
}

function parseArgs(argv) {
  const options = {
    envFile: process.env.LIMITLESS_SYNC_ENV_FILE || DEFAULT_ENV_FILE,
    apiBase: process.env.LIMITLESS_API_BASE_URL || DEFAULT_API_BASE,
    dryRun: true,
    maxTournaments: 50,
    tournamentIds: [],
    games: [],
    includeDetails: true,
    includeStandings: true,
    includePairings: true,
    includeDecklists: false,
    includePublic: true,
    publicBase: process.env.LIMITLESS_PUBLIC_BASE_URL || DEFAULT_PUBLIC_BASE,
    publicDeckLimit: 25,
    publicTournamentLimit: 25,
    publicDeckResultLimit: 80,
    publicDecklistLimit: 12,
    requestDelayMs: 350,
    retries: 3,
  };

  for (const arg of argv) {
    if (arg === '--dry-run') {
      options.dryRun = true;
    } else if (arg === '--apply') {
      options.dryRun = false;
    } else if (arg === '--skip-details') {
      options.includeDetails = false;
    } else if (arg === '--skip-standings') {
      options.includeStandings = false;
    } else if (arg === '--skip-pairings') {
      options.includePairings = false;
    } else if (arg === '--include-decklists') {
      options.includeDecklists = true;
    } else if (arg === '--skip-public') {
      options.includePublic = false;
    } else if (arg === '--include-public') {
      options.includePublic = true;
    } else if (arg.startsWith('--env-file=')) {
      options.envFile = arg.slice('--env-file='.length).trim();
    } else if (arg.startsWith('--api-base=')) {
      options.apiBase = arg.slice('--api-base='.length).trim();
    } else if (arg.startsWith('--public-base=')) {
      options.publicBase = arg.slice('--public-base='.length).trim();
    } else if (arg.startsWith('--max-tournaments=')) {
      options.maxTournaments = integerOption(arg.slice('--max-tournaments='.length), '--max-tournaments');
    } else if (arg.startsWith('--public-deck-limit=')) {
      options.publicDeckLimit = integerOption(arg.slice('--public-deck-limit='.length), '--public-deck-limit');
    } else if (arg.startsWith('--public-tournament-limit=')) {
      options.publicTournamentLimit = integerOption(arg.slice('--public-tournament-limit='.length), '--public-tournament-limit');
    } else if (arg.startsWith('--public-deck-result-limit=')) {
      options.publicDeckResultLimit = integerOption(arg.slice('--public-deck-result-limit='.length), '--public-deck-result-limit');
    } else if (arg.startsWith('--public-decklist-limit=')) {
      options.publicDecklistLimit = integerOption(arg.slice('--public-decklist-limit='.length), '--public-decklist-limit');
    } else if (arg.startsWith('--tournament-id=')) {
      const id = arg.slice('--tournament-id='.length).trim();
      if (id) options.tournamentIds.push(id);
    } else if (arg.startsWith('--tournament-ids=')) {
      options.tournamentIds.push(...arg.slice('--tournament-ids='.length)
        .split(',')
        .map((value) => value.trim())
        .filter(Boolean));
    } else if (arg.startsWith('--game=')) {
      const game = arg.slice('--game='.length).trim().toUpperCase();
      if (game) options.games.push(game);
    } else if (arg.startsWith('--games=')) {
      options.games.push(...arg.slice('--games='.length)
        .split(',')
        .map((value) => value.trim().toUpperCase())
        .filter(Boolean));
    } else if (arg.startsWith('--request-delay-ms=')) {
      options.requestDelayMs = integerOption(arg.slice('--request-delay-ms='.length), '--request-delay-ms');
    } else if (arg.startsWith('--retries=')) {
      options.retries = integerOption(arg.slice('--retries='.length), '--retries');
    } else {
      throw new Error(`Unknown option: ${arg}`);
    }
  }

  options.apiBase = options.apiBase.replace(/\/+$/, '');
  options.publicBase = options.publicBase.replace(/\/+$/, '');
  options.maxTournaments = Math.min(Math.max(options.maxTournaments, 1), 1000);
  options.publicDeckLimit = Math.min(Math.max(options.publicDeckLimit, 1), 100);
  options.publicTournamentLimit = Math.min(Math.max(options.publicTournamentLimit, 1), 100);
  options.publicDeckResultLimit = Math.min(Math.max(options.publicDeckResultLimit, 1), 500);
  options.publicDecklistLimit = Math.min(Math.max(options.publicDecklistLimit, 0), 100);
  options.requestDelayMs = Math.min(Math.max(options.requestDelayMs, 0), 10_000);
  options.retries = Math.min(Math.max(options.retries, 0), 8);
  options.games = [...new Set(options.games)];
  options.tournamentIds = [...new Set(options.tournamentIds)];
  return options;
}

function databaseUrl(env = process.env) {
  return String(env.MARKETPLACE_DATABASE_URL || env.MARKETPLACE_PEER4_DATABASE_URL || '').trim();
}

function createPool(env = process.env) {
  const connectionString = databaseUrl(env);
  if (!connectionString) {
    throw new Error('MARKETPLACE_DATABASE_URL is required unless running a network-only dry-run.');
  }
  return new Pool({
    connectionString,
    max: 2,
    idleTimeoutMillis: 10_000,
    connectionTimeoutMillis: 10_000,
    ssl: { rejectUnauthorized: process.env.MARKETPLACE_DATABASE_SSL_VERIFY === '1' },
  });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

class LimitlessClient {
  constructor(options = {}) {
    this.apiBase = (options.apiBase || DEFAULT_API_BASE).replace(/\/+$/, '');
    this.requestDelayMs = options.requestDelayMs ?? 350;
    this.retries = options.retries ?? 3;
    this.lastRequestAt = 0;
    this.fetchImpl = options.fetchImpl || fetch;
    this.apiKey = options.apiKey || process.env.LIMITLESS_API_KEY || '';
  }

  async get(apiPath) {
    const cleanPath = apiPath.startsWith('/') ? apiPath : `/${apiPath}`;
    const url = `${this.apiBase}${cleanPath}`;
    let lastError;
    for (let attempt = 0; attempt <= this.retries; attempt += 1) {
      await this.waitForSlot();
      try {
        const headers = { accept: 'application/json' };
        if (this.apiKey) headers.authorization = `Bearer ${this.apiKey}`;
        const response = await this.fetchImpl(url, { headers });
        if (response.status === 401 || response.status === 403) {
          const error = new Error(`Limitless API authorization required for ${cleanPath}.`);
          error.statusCode = response.status;
          throw error;
        }
        if (response.status === 404) {
          const error = new Error(`Limitless API path not found: ${cleanPath}.`);
          error.statusCode = response.status;
          throw error;
        }
        if (!response.ok) {
          const error = new Error(`Limitless API ${cleanPath} failed: ${response.status} ${await response.text()}`);
          error.statusCode = response.status;
          throw error;
        }
        return response.json();
      } catch (error) {
        lastError = error;
        if (error.statusCode && error.statusCode < 500 && error.statusCode !== 429) {
          throw error;
        }
        if (attempt < this.retries) {
          await sleep(500 * 2 ** attempt);
        }
      }
    }
    throw lastError;
  }

  async waitForSlot() {
    if (this.requestDelayMs <= 0) return;
    const elapsed = Date.now() - this.lastRequestAt;
    if (elapsed < this.requestDelayMs) {
      await sleep(this.requestDelayMs - elapsed);
    }
    this.lastRequestAt = Date.now();
  }
}

class LimitlessPublicClient {
  constructor(options = {}) {
    this.publicBase = (options.publicBase || DEFAULT_PUBLIC_BASE).replace(/\/+$/, '');
    this.requestDelayMs = options.requestDelayMs ?? 350;
    this.retries = options.retries ?? 3;
    this.lastRequestAt = 0;
    this.fetchImpl = options.fetchImpl || fetch;
  }

  async getHtml(publicPath) {
    const cleanPath = publicPath.startsWith('/') ? publicPath : `/${publicPath}`;
    const url = `${this.publicBase}${cleanPath}`;
    let lastError;
    for (let attempt = 0; attempt <= this.retries; attempt += 1) {
      await this.waitForSlot();
      try {
        const response = await this.fetchImpl(url, {
          headers: {
            accept: 'text/html,application/xhtml+xml',
            'user-agent': 'Pokoin competitive importer (contact: market@pokoin.com)',
          },
        });
        if (response.status === 404) {
          const error = new Error(`Limitless public page not found: ${cleanPath}.`);
          error.statusCode = response.status;
          throw error;
        }
        if (!response.ok) {
          const error = new Error(`Limitless public page ${cleanPath} failed: ${response.status} ${await response.text()}`);
          error.statusCode = response.status;
          throw error;
        }
        return response.text();
      } catch (error) {
        lastError = error;
        if (error.statusCode && error.statusCode < 500 && error.statusCode !== 429) {
          throw error;
        }
        if (attempt < this.retries) {
          await sleep(500 * 2 ** attempt);
        }
      }
    }
    throw lastError;
  }

  async waitForSlot() {
    if (this.requestDelayMs <= 0) return;
    const elapsed = Date.now() - this.lastRequestAt;
    if (elapsed < this.requestDelayMs) {
      await sleep(this.requestDelayMs - elapsed);
    }
    this.lastRequestAt = Date.now();
  }
}

function decodeHtml(value) {
  return String(value || '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&#039;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>');
}

function stripTags(value) {
  return decodeHtml(String(value || '')
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' '))
    .replace(/\s+/g, ' ')
    .trim();
}

function attrValue(html, name) {
  const match = String(html || '').match(new RegExp(`\\b${name}="([^"]*)"`, 'i'));
  return match ? decodeHtml(match[1]).trim() : '';
}

function firstMatch(text, regex, fallback = '') {
  const match = String(text || '').match(regex);
  return match ? String(match[1] || '').trim() : fallback;
}

function integerFromText(value) {
  const clean = String(value || '').replace(/,/g, '').match(/-?\d+/);
  return clean ? Number.parseInt(clean[0], 10) : null;
}

function numberFromText(value) {
  const clean = String(value || '').replace(/,/g, '').match(/-?\d+(?:\.\d+)?/);
  return clean ? Number.parseFloat(clean[0]) : null;
}

function cleanSourceId(value) {
  return String(value || '').trim().replace(/[^a-zA-Z0-9_-]/g, '');
}

function cellsFromRow(rowHtml) {
  return [...String(rowHtml || '').matchAll(/<t[dh][^>]*>([\s\S]*?)<\/t[dh]>/gi)].map((match) => match[1]);
}

function linksFromHtml(html) {
  return [...String(html || '').matchAll(/<a\b[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi)]
    .map((match) => ({ href: decodeHtml(match[1]).trim(), text: stripTags(match[2]) }));
}

function imageAlts(html, className) {
  const pattern = className
    ? new RegExp(`<img\\b(?=[^>]*class="[^"]*${className}[^"]*")[^>]*>`, 'gi')
    : /<img\b[^>]*>/gi;
  return [...String(html || '').matchAll(pattern)]
    .map((match) => attrValue(match[0], 'alt'))
    .filter(Boolean);
}

function rowsFromFirstTable(html) {
  const table = String(html || '').match(/<table[\s\S]*?<\/table>/i)?.[0] || '';
  return [...table.matchAll(/<tr\b[\s\S]*?<\/tr>/gi)].map((match) => match[0]);
}

function normalizePublicFormat(format) {
  const value = String(format || '').trim().toLowerCase();
  if (!value) return '';
  if (value === 'standard') return 'STANDARD';
  if (value === 'expanded') return 'EXPANDED';
  if (value === 'standard-jp') return 'STANDARD_JP';
  if (value === 'expanded-jp') return 'EXPANDED_JP';
  return value.toUpperCase().replace(/-/g, '_');
}

function publicTournamentDate(value) {
  const text = String(value || '').trim();
  const match = text.match(/(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]{3,})\s+(\d{2,4})/);
  if (!match) return null;
  const months = {
    jan: '01', feb: '02', mar: '03', apr: '04', may: '05', jun: '06',
    jul: '07', aug: '08', sep: '09', oct: '10', nov: '11', dec: '12',
    january: '01', february: '02', march: '03', april: '04', june: '06',
    july: '07', august: '08', september: '09', october: '10',
    november: '11', december: '12',
  };
  const month = months[match[2].toLowerCase()];
  if (!month) return null;
  const year = match[3].length === 2 ? `20${match[3]}` : match[3];
  return `${year}-${month}-${match[1].padStart(2, '0')}`;
}

function parsePublicDecks(html, { publicBase = DEFAULT_PUBLIC_BASE } = {}) {
  return rowsFromFirstTable(html).slice(1).map((rowHtml) => {
    const cells = cellsFromRow(rowHtml);
    const deckCellIndex = cells.findIndex((cell) => /\/decks\/\d+/.test(cell));
    const link = linksFromHtml(cells[deckCellIndex] || '').find((row) => /\/decks\/\d+/.test(row.href));
    const deckId = cleanSourceId(firstMatch(link?.href || '', /\/decks\/(\d+)/));
    return {
      deck_id: deckId,
      name: link?.text || stripTags(cells[deckCellIndex] || ''),
      rank: integerFromText(stripTags(cells[0] || '')),
      points: integerFromText(stripTags(cells[deckCellIndex + 1] || '')) || 0,
      share: numberFromText(stripTags(cells[deckCellIndex + 2] || '')) || 0,
      source_url: deckId ? `${publicBase}/decks/${deckId}` : '',
      raw: { rowHtml },
    };
  }).filter((row) => row.deck_id && row.name);
}

function parsePublicTournaments(html, { publicBase = DEFAULT_PUBLIC_BASE } = {}) {
  return rowsFromFirstTable(html).slice(1).map((rowHtml) => {
    const cells = cellsFromRow(rowHtml);
    const link = linksFromHtml(cells[2] || '').find((row) => /\/tournaments\/\d+/.test(row.href));
    const tournamentId = cleanSourceId(firstMatch(link?.href || '', /\/tournaments\/(\d+)/));
    const winnerLink = linksFromHtml(cells[5] || '').find((row) => /\/players\/\d+/.test(row.href));
    const countryImg = (cells[1] || '').match(/<img\b[^>]*>/i)?.[0] || '';
    const winnerFlag = (cells[5] || '').match(/<img\b[^>]*>/i)?.[0] || '';
    const formatImg = (cells[3] || '').match(/<img\b[^>]*>/i)?.[0] || '';
    return {
      tournament_id: tournamentId,
      name: link?.text || stripTags(cells[2] || ''),
      country: attrValue(countryImg, 'alt'),
      country_name: attrValue(countryImg, 'data-tooltip'),
      format: normalizePublicFormat(attrValue(formatImg, 'alt') || attrValue(rowHtml, 'data-format')),
      format_label: attrValue(formatImg, 'data-tooltip') || attrValue(rowHtml, 'data-format'),
      tournament_date: attrValue(rowHtml, 'data-date') || publicTournamentDate(stripTags(cells[0] || '')),
      player_count: integerFromText(attrValue(rowHtml, 'data-players') || stripTags(cells[4] || '')) || 0,
      winner_player_id: cleanSourceId(firstMatch(winnerLink?.href || '', /\/players\/(\d+)/)),
      winner_name: winnerLink?.text || '',
      winner_country: attrValue(winnerFlag, 'alt'),
      source_url: tournamentId ? `${publicBase}/tournaments/${tournamentId}` : '',
      raw: { rowHtml },
    };
  }).filter((row) => row.tournament_id && row.name);
}

function parseDeckOverview(html, deckId, { publicBase = DEFAULT_PUBLIC_BASE, resultLimit = 80 } = {}) {
  const text = stripTags(html);
  const name = stripTags(firstMatch(html, /<h1[^>]*>([\s\S]*?)<\/h1>/i)) || firstMatch(text, /^(.+?) Totals:/);
  const metaImage = firstMatch(html, /<meta property="og:image" content="([^"]+)"/i);
  const totals = firstMatch(text, /Totals:\s*([^|]+)\|\s*(\d[\d,]*)\s+Points/);
  const totalPoints = integerFromText(firstMatch(text, /Totals:\s*[^|]+\|\s*([\d,]+)\s+Points/));
  const variantsText = firstMatch(text, /Variant\s+([\s\S]*?)\s+Core Cards/);
  const variants = variantsText
    ? variantsText.split(/\s+(?=Dragapult|All|None|[A-Z][A-Za-z' -]+$)/).map((value) => value.trim()).filter(Boolean)
    : [];
  const tables = [...String(html || '').matchAll(/<table[\s\S]*?<\/table>/gi)].map((match) => match[0]);
  const resultRows = [];
  let currentTournament = null;
  for (const rowHtml of (tables[0] ? [...tables[0].matchAll(/<tr\b[\s\S]*?<\/tr>/gi)].map((match) => match[0]) : [])) {
    if (/sub-heading/.test(rowHtml)) {
      const link = linksFromHtml(rowHtml).find((row) => /\/tournaments\/\d+/.test(row.href));
      currentTournament = {
        tournament_id: cleanSourceId(firstMatch(link?.href || '', /\/tournaments\/(\d+)/)),
        tournament_label: link?.text || stripTags(rowHtml),
        tournament_name: (link?.text || '').replace(/^\d{1,2}(?:st|nd|rd|th)\s+\w+\s+\d{4}\s+-\s+/, '').trim(),
        tournament_date: publicTournamentDate(link?.text || ''),
      };
      continue;
    }
    const cells = cellsFromRow(rowHtml);
    if (cells.length < 5 || !currentTournament?.tournament_id) continue;
    const playerLink = linksFromHtml(cells[3] || '').find((row) => /\/players\/\d+/.test(row.href));
    const decklistLink = linksFromHtml(cells[4] || '').find((row) => /\/decks\/list\/\d+/.test(row.href));
    const formatImg = (cells[0] || '').match(/<img\b[^>]*>/i)?.[0] || '';
    const variant = imageAlts(cells[2] || '', 'pokemon').join(' / ');
    const placingLabel = stripTags(cells[1] || '');
    resultRows.push({
      deck_id: deckId,
      tournament_id: currentTournament.tournament_id,
      tournament_name: currentTournament.tournament_name || currentTournament.tournament_label,
      tournament_date: currentTournament.tournament_date,
      format: normalizePublicFormat(attrValue(formatImg, 'alt')),
      placing: integerFromText(placingLabel),
      placing_label: placingLabel,
      variant,
      player_id: cleanSourceId(firstMatch(playerLink?.href || '', /\/players\/(\d+)/)),
      player_name: playerLink?.text || stripTags(cells[3] || ''),
      decklist_id: cleanSourceId(firstMatch(decklistLink?.href || '', /\/decks\/list\/(\d+)/)),
      source_url: decklistLink?.href ? `${publicBase}${decklistLink.href}` : `${publicBase}/decks/${deckId}`,
      raw: { rowHtml, tournament: currentTournament },
    });
    if (resultRows.length >= resultLimit) break;
  }
  const playerRows = [];
  for (const rowHtml of (tables[1] ? [...tables[1].matchAll(/<tr\b[\s\S]*?<\/tr>/gi)].map((match) => match[0]) : [])) {
    const cells = cellsFromRow(rowHtml);
    if (cells.length < 4) continue;
    const playerLink = linksFromHtml(cells[1] || '').find((row) => /\/players\/\d+/.test(row.href));
    const countryImg = (cells[2] || '').match(/<img\b[^>]*>/i)?.[0] || '';
    const playerId = cleanSourceId(firstMatch(playerLink?.href || '', /\/players\/(\d+)/));
    if (!playerId) continue;
    playerRows.push({
      deck_id: deckId,
      player_id: playerId,
      player_name: playerLink?.text || stripTags(cells[1] || ''),
      country: attrValue(countryImg, 'alt'),
      rank: integerFromText(stripTags(cells[0] || '')),
      points: integerFromText(stripTags(cells[3] || '')) || 0,
      source_url: `${publicBase}${playerLink.href}`,
      raw: { rowHtml },
    });
  }
  const coreCardBlocks = String(html || '')
    .split(/<div class="core-card">/i)
    .slice(1)
    .map((block) => block.split(/<div class="core-card">/i)[0])
    .map((block) => block.slice(0, block.indexOf('</div>') >= 0 ? block.indexOf('</div>') : undefined));
  const coreCards = coreCardBlocks.map((block) => {
    const img = block.match(/<img\b[^>]*>/i)?.[0] || '';
    const link = linksFromHtml(block).find((row) => /\/cards\//.test(row.href));
    const shareText = stripTags(firstMatch(block, /<span class="share"[^>]*>([\s\S]*?)<\/span>/i));
    const altText = attrValue(img, 'alt');
    const cardName = altText.replace(/^[A-Z0-9-]+\s+#\d+\s*/, '').trim();
    const setCode = attrValue(img, 'data-set') || firstMatch(link?.href || '', /\/cards\/([^/]+)/);
    const number = attrValue(img, 'data-number') || firstMatch(link?.href || '', /\/cards\/[^/]+\/([^/?]+)/);
    const fallbackName = altText || `${setCode} #${number}`.trim();
    return {
      deck_id: deckId,
      card_key: `${setCode}:${number}`.replace(/^:/, ''),
      display_name: cardName || fallbackName,
      count: numberFromText(shareText),
      inclusion_share: numberFromText(firstMatch(shareText, /in\s+([\d.]+)%/)),
      set_code: setCode,
      collector_number: number,
      source_url: link?.href ? `${publicBase}${link.href}` : '',
      raw: { block, shareText },
    };
  }).filter((row) => row.card_key && row.display_name);
  return {
    deck: {
      deck_id: deckId,
      name,
      earnings_text: totals,
      total_points: totalPoints,
      regional_top8: integerFromText(firstMatch(text, /Regional Top 8:\s*([\d,]+)/)),
      regional_wins: integerFromText(firstMatch(text, /Regional Top 8:[^,]+,\s+including\s+([\d,]+)\s+wins?/)),
      international_top8: integerFromText(firstMatch(text, /International Top 8:\s*([\d,]+)/)),
      international_wins: integerFromText(firstMatch(text, /International Top 8:[^,]+,\s+including\s+([\d,]+)\s+wins?/)),
      variants,
      source_url: `${publicBase}/decks/${deckId}`,
      raw: { metaImage },
    },
    coreCards,
    results: resultRows,
    players: playerRows,
  };
}

function parseTournamentStandings(html, tournamentId, { publicBase = DEFAULT_PUBLIC_BASE, limit = 300 } = {}) {
  return rowsFromFirstTable(html).slice(1).map((rowHtml) => {
    const cells = cellsFromRow(rowHtml);
    if (cells.length < 5) return null;
    const playerLink = linksFromHtml(cells[1] || '').find((row) => /\/players\/\d+/.test(row.href));
    const deckLink = linksFromHtml(cells[3] || '').find((row) => /\/decks\/\d+/.test(row.href));
    const decklistLink = linksFromHtml(cells[4] || '').find((row) => /\/decks\/list\/\d+/.test(row.href));
    const countryImg = (cells[2] || '').match(/<img\b[^>]*>/i)?.[0] || '';
    return {
      tournament_id: tournamentId,
      placing: integerFromText(stripTags(cells[0] || '')) || 0,
      player_id: cleanSourceId(firstMatch(playerLink?.href || '', /\/players\/(\d+)/)),
      player_name: playerLink?.text || stripTags(cells[1] || ''),
      country: attrValue(countryImg, 'alt'),
      deck_id: cleanSourceId(firstMatch(deckLink?.href || '', /\/decks\/(\d+)/)),
      deck_name: deckLink?.text || '',
      variant: imageAlts(cells[3] || '', 'pokemon').join(' / '),
      decklist_id: cleanSourceId(firstMatch(decklistLink?.href || '', /\/decks\/list\/(\d+)/)),
      source_url: decklistLink?.href ? `${publicBase}${decklistLink.href}` : `${publicBase}/tournaments/${tournamentId}`,
      raw: { rowHtml },
    };
  }).filter((row) => row && row.placing > 0 && row.player_name).slice(0, limit);
}

function parsePublicDecklistCards(html, decklistId, { publicBase = DEFAULT_PUBLIC_BASE } = {}) {
  const cards = [];
  let currentSection = 'main';
  const blocks = [...String(html || '').matchAll(/<div class="decklist-column-heading">([\s\S]*?)<\/div>|<div class="decklist-card"([\s\S]*?)<\/div>/gi)];
  for (const match of blocks) {
    if (match[1] != null) {
      currentSection = stripTags(match[1]).replace(/\s*\(\d+\)\s*$/, '').toLowerCase() || 'main';
      continue;
    }
    const block = match[0];
    const setCode = attrValue(block, 'data-set');
    const number = attrValue(block, 'data-number');
    const count = numberFromText(stripTags(firstMatch(block, /<span class="card-count">([\s\S]*?)<\/span>/i))) || 0;
    const cardName = stripTags(firstMatch(block, /<span class="card-name">([\s\S]*?)<\/span>/i));
    const link = linksFromHtml(block).find((row) => /\/cards\//.test(row.href));
    if (!cardName || count <= 0) continue;
    cards.push({
      decklist_id: decklistId,
      card_key: `${setCode}:${number}:${cardName}`.replace(/^:+/, ''),
      card_name: cardName,
      count,
      section: currentSection,
      set_code: setCode,
      collector_number: number,
      source_url: link?.href ? `${publicBase}${link.href}` : '',
      raw: { block },
    });
  }
  return cards;
}

function normalizeTournament(row = {}) {
  return {
    tournament_id: String(row.id || '').trim(),
    game_id: String(row.game || '').trim() || null,
    name: String(row.name || '').trim(),
    format: row.format == null ? null : String(row.format).trim(),
    tournament_date: row.date || null,
    player_count: Number.isFinite(Number(row.players)) ? Math.trunc(Number(row.players)) : 0,
    organizer_id: Number.isFinite(Number(row.organizerId)) ? Math.trunc(Number(row.organizerId)) : null,
    organizer_name: row.organizer?.name ? String(row.organizer.name).trim() : null,
    platform: row.platform == null ? null : String(row.platform).trim(),
    decklists_available: typeof row.decklists === 'boolean' ? row.decklists : null,
    is_public: typeof row.isPublic === 'boolean' ? row.isPublic : null,
    is_online: typeof row.isOnline === 'boolean' ? row.isOnline : null,
    phases: Array.isArray(row.phases) ? row.phases : [],
    raw_listing: row,
    raw_details: row.organizer || Array.isArray(row.phases) ? row : {},
    source_url: row.id ? `https://play.limitlesstcg.com/tournament/${row.id}` : null,
  };
}

function playerIdFromStanding(row = {}) {
  return String(row.player || row.name || '').trim();
}

function deckArchetype(deck = {}) {
  const candidates = [
    deck.name,
    deck.archetype,
    deck.label,
    deck.deck,
    deck.title,
  ];
  return candidates.map((value) => String(value || '').trim()).find(Boolean) || null;
}

function decklistId(tournamentId, standing = {}) {
  const explicit = String(standing.decklist || '').trim();
  if (explicit) return explicit;
  const player = playerIdFromStanding(standing);
  return player ? `${tournamentId}:${player}` : '';
}

function normalizeStanding(tournamentId, row = {}) {
  const playerId = playerIdFromStanding(row);
  const record = row.record || {};
  const deck = row.deck || {};
  return {
    tournament_id: tournamentId,
    player_id: playerId,
    placing: Number.isFinite(Number(row.placing)) ? Math.trunc(Number(row.placing)) : null,
    display_name: String(row.name || playerId).trim(),
    country: row.country == null ? null : String(row.country).trim(),
    wins: Number.isFinite(Number(record.wins)) ? Math.trunc(Number(record.wins)) : 0,
    losses: Number.isFinite(Number(record.losses)) ? Math.trunc(Number(record.losses)) : 0,
    ties: Number.isFinite(Number(record.ties)) ? Math.trunc(Number(record.ties)) : 0,
    drop_round: Number.isFinite(Number(row.drop)) ? Math.trunc(Number(row.drop)) : null,
    deck_name: deckArchetype(deck),
    deck_archetype: deckArchetype(deck),
    decklist_id: row.decklist ? decklistId(tournamentId, row) : null,
    deck_summary: deck && typeof deck === 'object' ? deck : {},
    raw: row,
  };
}

function normalizePairing(tournamentId, row = {}, index = 0) {
  return {
    tournament_id: tournamentId,
    phase: Number.isFinite(Number(row.phase)) ? Math.trunc(Number(row.phase)) : 1,
    round: Number.isFinite(Number(row.round)) ? Math.trunc(Number(row.round)) : 0,
    table_number: Number.isFinite(Number(row.table)) ? Math.trunc(Number(row.table)) : 0,
    match_index: index,
    player1_id: String(row.player1 || '').trim() || null,
    player2_id: String(row.player2 || '').trim() || null,
    winner_player_id: String(row.winner || '').trim() || null,
    result: row.result == null ? null : String(row.result).trim(),
    raw: row,
  };
}

function json(value) {
  return JSON.stringify(value ?? null);
}

async function upsertGames(pool, games) {
  if (!games.length) return 0;
  for (const game of games) {
    await pool.query(
      `
        insert into public.limitless_games (
          game_id, name, formats, platforms, metagame, raw, source_updated_at, updated_at
        )
        values ($1, $2, $3::jsonb, $4::jsonb, $5, $6::jsonb, now(), now())
        on conflict (game_id) do update set
          name = excluded.name,
          formats = excluded.formats,
          platforms = excluded.platforms,
          metagame = excluded.metagame,
          raw = excluded.raw,
          source_updated_at = now(),
          updated_at = now()
      `,
      [
        String(game.id || '').trim(),
        String(game.name || game.id || '').trim(),
        json(game.formats || {}),
        json(game.platforms || {}),
        game.metagame === true,
        json(game),
      ],
    );
  }
  return games.length;
}

async function upsertTournament(pool, row, { details = false } = {}) {
  const tournament = normalizeTournament(row);
  if (!tournament.tournament_id || !tournament.name) return false;
  await pool.query(
    `
      insert into public.limitless_tournaments (
        tournament_id, game_id, name, format, tournament_date, player_count,
        organizer_id, organizer_name, platform, decklists_available, is_public,
        is_online, phases, raw_listing, raw_details, source_url,
        details_fetched_at, updated_at
      )
      values (
        $1, $2, $3, $4, $5, $6,
        $7, $8, $9, $10, $11,
        $12, $13::jsonb, $14::jsonb, $15::jsonb, $16,
        case when $17 then now() else null end, now()
      )
      on conflict (tournament_id) do update set
        game_id = excluded.game_id,
        name = excluded.name,
        format = excluded.format,
        tournament_date = excluded.tournament_date,
        player_count = excluded.player_count,
        organizer_id = coalesce(excluded.organizer_id, limitless_tournaments.organizer_id),
        organizer_name = coalesce(excluded.organizer_name, limitless_tournaments.organizer_name),
        platform = coalesce(excluded.platform, limitless_tournaments.platform),
        decklists_available = coalesce(excluded.decklists_available, limitless_tournaments.decklists_available),
        is_public = coalesce(excluded.is_public, limitless_tournaments.is_public),
        is_online = coalesce(excluded.is_online, limitless_tournaments.is_online),
        phases = case when $17 then excluded.phases else limitless_tournaments.phases end,
        raw_listing = case when $17 then limitless_tournaments.raw_listing else excluded.raw_listing end,
        raw_details = case when $17 then excluded.raw_details else limitless_tournaments.raw_details end,
        source_url = excluded.source_url,
        details_fetched_at = case when $17 then now() else limitless_tournaments.details_fetched_at end,
        updated_at = now()
    `,
    [
      tournament.tournament_id,
      tournament.game_id,
      tournament.name,
      tournament.format,
      tournament.tournament_date,
      tournament.player_count,
      tournament.organizer_id,
      tournament.organizer_name,
      tournament.platform,
      tournament.decklists_available,
      tournament.is_public,
      tournament.is_online,
      json(tournament.phases),
      json(details ? {} : row),
      json(details ? row : {}),
      tournament.source_url,
      details,
    ],
  );
  return true;
}

async function upsertPlayers(pool, players) {
  const unique = new Map();
  for (const player of players) {
    if (!player.player_id) continue;
    unique.set(player.player_id, player);
  }
  for (const player of unique.values()) {
    await pool.query(
      `
        insert into public.limitless_players (player_id, display_name, country, raw, updated_at)
        values ($1, $2, $3, $4::jsonb, now())
        on conflict (player_id) do update set
          display_name = excluded.display_name,
          country = coalesce(excluded.country, limitless_players.country),
          raw = excluded.raw,
          updated_at = now()
      `,
      [player.player_id, player.display_name, player.country, json(player.raw)],
    );
  }
  return unique.size;
}

async function upsertStandings(pool, tournamentId, standings) {
  const rows = standings.map((row) => normalizeStanding(tournamentId, row)).filter((row) => row.player_id);
  await upsertPlayers(pool, rows.map((row) => ({
    player_id: row.player_id,
    display_name: row.display_name,
    country: row.country,
    raw: row.raw,
  })));
  for (const row of rows) {
    await pool.query(
      `
        insert into public.limitless_tournament_standings (
          tournament_id, player_id, "placing", display_name, country, wins, losses,
          ties, drop_round, deck_name, deck_archetype, decklist_id, deck_summary,
          raw, updated_at
        )
        values (
          $1, $2, $3, $4, $5, $6, $7,
          $8, $9, $10, $11, $12, $13::jsonb,
          $14::jsonb, now()
        )
        on conflict (tournament_id, player_id) do update set
          "placing" = excluded."placing",
          display_name = excluded.display_name,
          country = excluded.country,
          wins = excluded.wins,
          losses = excluded.losses,
          ties = excluded.ties,
          drop_round = excluded.drop_round,
          deck_name = excluded.deck_name,
          deck_archetype = excluded.deck_archetype,
          decklist_id = excluded.decklist_id,
          deck_summary = excluded.deck_summary,
          raw = excluded.raw,
          updated_at = now()
      `,
      [
        row.tournament_id,
        row.player_id,
        row.placing,
        row.display_name,
        row.country,
        row.wins,
        row.losses,
        row.ties,
        row.drop_round,
        row.deck_name,
        row.deck_archetype,
        row.decklist_id,
        json(row.deck_summary),
        json(row.raw),
      ],
    );
  }
  await pool.query('update public.limitless_tournaments set standings_fetched_at = now(), updated_at = now() where tournament_id = $1', [tournamentId]);
  return rows.length;
}

async function upsertPairings(pool, tournamentId, pairings) {
  const rows = pairings.map((row, index) => normalizePairing(tournamentId, row, index));
  const playerRows = [];
  for (const row of rows) {
    for (const playerId of [row.player1_id, row.player2_id, row.winner_player_id]) {
      if (playerId) playerRows.push({ player_id: playerId, display_name: playerId, country: null, raw: {} });
    }
  }
  await upsertPlayers(pool, playerRows);
  for (const row of rows) {
    await pool.query(
      `
        insert into public.limitless_tournament_pairings (
          tournament_id, phase, round, table_number, match_index, player1_id,
          player2_id, winner_player_id, result, raw, updated_at
        )
        values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb, now())
        on conflict (tournament_id, phase, round, table_number, match_index) do update set
          player1_id = excluded.player1_id,
          player2_id = excluded.player2_id,
          winner_player_id = excluded.winner_player_id,
          result = excluded.result,
          raw = excluded.raw,
          updated_at = now()
      `,
      [
        row.tournament_id,
        row.phase,
        row.round,
        row.table_number,
        row.match_index,
        row.player1_id,
        row.player2_id,
        row.winner_player_id,
        row.result,
        json(row.raw),
      ],
    );
  }
  await pool.query('update public.limitless_tournaments set pairings_fetched_at = now(), updated_at = now() where tournament_id = $1', [tournamentId]);
  return rows.length;
}

async function upsertPublicDeck(pool, deck, listing = {}) {
  const merged = { ...deck, ...listing, raw: { ...(listing.raw || {}), ...(deck.raw || {}) } };
  await pool.query(
    `
      insert into public.limitless_public_decks (
        deck_id, name, format, format_label, rank, points, share, earnings_text,
        total_points, regional_top8, regional_wins, international_top8,
        international_wins, variants, raw, source_url, source_fetched_at, updated_at
      )
      values (
        $1, $2, $3, $4, $5, $6, $7, $8,
        $9, $10, $11, $12,
        $13, $14::jsonb, $15::jsonb, $16, now(), now()
      )
      on conflict (deck_id) do update set
        name = excluded.name,
        format = coalesce(excluded.format, limitless_public_decks.format),
        format_label = coalesce(excluded.format_label, limitless_public_decks.format_label),
        rank = coalesce(excluded.rank, limitless_public_decks.rank),
        points = excluded.points,
        share = excluded.share,
        earnings_text = coalesce(excluded.earnings_text, limitless_public_decks.earnings_text),
        total_points = coalesce(excluded.total_points, limitless_public_decks.total_points),
        regional_top8 = coalesce(excluded.regional_top8, limitless_public_decks.regional_top8),
        regional_wins = coalesce(excluded.regional_wins, limitless_public_decks.regional_wins),
        international_top8 = coalesce(excluded.international_top8, limitless_public_decks.international_top8),
        international_wins = coalesce(excluded.international_wins, limitless_public_decks.international_wins),
        variants = case when jsonb_array_length(excluded.variants) > 0 then excluded.variants else limitless_public_decks.variants end,
        raw = limitless_public_decks.raw || excluded.raw,
        source_url = excluded.source_url,
        source_fetched_at = now(),
        updated_at = now()
    `,
    [
      merged.deck_id,
      merged.name,
      merged.format || null,
      merged.format_label || null,
      merged.rank || null,
      merged.points || 0,
      merged.share || 0,
      merged.earnings_text || null,
      merged.total_points || null,
      merged.regional_top8 || null,
      merged.regional_wins || null,
      merged.international_top8 || null,
      merged.international_wins || null,
      json(merged.variants || []),
      json(merged.raw || {}),
      merged.source_url || null,
    ],
  );
}

async function replacePublicDeckChildren(pool, deckId, { coreCards = [], results = [], players = [] }) {
  await pool.query('delete from public.limitless_public_deck_core_cards where deck_id = $1', [deckId]);
  for (const card of coreCards) {
    await pool.query(
      `
        insert into public.limitless_public_deck_core_cards (
          deck_id, card_key, display_name, count, inclusion_share, set_code,
          collector_number, source_url, raw, updated_at
        )
        values ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb, now())
      `,
      [
        deckId,
        card.card_key,
        card.display_name,
        card.count,
        card.inclusion_share,
        card.set_code,
        card.collector_number,
        card.source_url,
        json(card.raw || {}),
      ],
    );
  }

  await pool.query('delete from public.limitless_public_deck_results where deck_id = $1', [deckId]);
  for (const row of results) {
    await pool.query(
      `
        insert into public.limitless_public_deck_results (
          deck_id, tournament_id, tournament_name, tournament_date, format,
          "placing", placing_label, variant, player_id, player_name, decklist_id,
          source_url, raw, updated_at
        )
        values (
          $1, $2, $3, $4, $5,
          $6, $7, $8, $9, $10, $11,
          $12, $13::jsonb, now()
        )
        on conflict (deck_id, tournament_id, "placing", player_name) do update set
          tournament_name = excluded.tournament_name,
          tournament_date = excluded.tournament_date,
          format = excluded.format,
          placing_label = excluded.placing_label,
          variant = excluded.variant,
          player_id = excluded.player_id,
          decklist_id = excluded.decklist_id,
          source_url = excluded.source_url,
          raw = excluded.raw,
          updated_at = now()
      `,
      [
        deckId,
        row.tournament_id,
        row.tournament_name,
        row.tournament_date,
        row.format || null,
        row.placing,
        row.placing_label || null,
        row.variant || null,
        row.player_id || null,
        row.player_name,
        row.decklist_id || null,
        row.source_url || null,
        json(row.raw || {}),
      ],
    );
  }

  await pool.query('delete from public.limitless_public_deck_players where deck_id = $1', [deckId]);
  for (const row of players) {
    await pool.query(
      `
        insert into public.limitless_public_deck_players (
          deck_id, player_id, player_name, country, rank, points, source_url, raw, updated_at
        )
        values ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, now())
        on conflict (deck_id, player_id) do update set
          player_name = excluded.player_name,
          country = excluded.country,
          rank = excluded.rank,
          points = excluded.points,
          source_url = excluded.source_url,
          raw = excluded.raw,
          updated_at = now()
      `,
      [deckId, row.player_id, row.player_name, row.country || null, row.rank || null, row.points || 0, row.source_url || null, json(row.raw || {})],
    );
  }
}

async function upsertPublicTournament(pool, row) {
  await pool.query(
    `
      insert into public.limitless_public_tournaments (
        tournament_id, name, country, country_name, format, format_label,
        tournament_date, player_count, winner_player_id, winner_name,
        winner_country, source_url, raw, source_fetched_at, updated_at
      )
      values (
        $1, $2, $3, $4, $5, $6,
        $7, $8, $9, $10,
        $11, $12, $13::jsonb, now(), now()
      )
      on conflict (tournament_id) do update set
        name = excluded.name,
        country = excluded.country,
        country_name = excluded.country_name,
        format = excluded.format,
        format_label = excluded.format_label,
        tournament_date = excluded.tournament_date,
        player_count = excluded.player_count,
        winner_player_id = excluded.winner_player_id,
        winner_name = excluded.winner_name,
        winner_country = excluded.winner_country,
        source_url = excluded.source_url,
        raw = excluded.raw,
        source_fetched_at = now(),
        updated_at = now()
    `,
    [
      row.tournament_id,
      row.name,
      row.country || null,
      row.country_name || null,
      row.format || null,
      row.format_label || null,
      row.tournament_date,
      row.player_count || 0,
      row.winner_player_id || null,
      row.winner_name || null,
      row.winner_country || null,
      row.source_url || null,
      json(row.raw || {}),
    ],
  );
}

async function replacePublicTournamentStandings(pool, tournamentId, standings) {
  await pool.query('delete from public.limitless_public_tournament_standings where tournament_id = $1', [tournamentId]);
  for (const row of standings) {
    await pool.query(
      `
        insert into public.limitless_public_tournament_standings (
          tournament_id, "placing", player_id, player_name, country, deck_id,
          deck_name, variant, decklist_id, source_url, raw, updated_at
        )
        values ($1, $2, $3, $4, $5, nullif($6, ''), $7, $8, $9, $10, $11::jsonb, now())
        on conflict (tournament_id, "placing", player_name) do update set
          player_id = excluded.player_id,
          country = excluded.country,
          deck_id = excluded.deck_id,
          deck_name = excluded.deck_name,
          variant = excluded.variant,
          decklist_id = excluded.decklist_id,
          source_url = excluded.source_url,
          raw = excluded.raw,
          updated_at = now()
      `,
      [
        tournamentId,
        row.placing,
        row.player_id || null,
        row.player_name,
        row.country || null,
        row.deck_id || '',
        row.deck_name || null,
        row.variant || null,
        row.decklist_id || null,
        row.source_url || null,
        json(row.raw || {}),
      ],
    );
  }
}

async function replacePublicDecklistCards(pool, decklistId, cards) {
  await pool.query('delete from public.limitless_public_decklist_cards where decklist_id = $1', [decklistId]);
  for (const card of cards) {
    await pool.query(
      `
        insert into public.limitless_public_decklist_cards (
          decklist_id, card_key, card_name, count, section, set_code,
          collector_number, source_url, raw, updated_at
        )
        values ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb, now())
        on conflict (decklist_id, section, card_key) do update set
          card_name = excluded.card_name,
          count = excluded.count,
          set_code = excluded.set_code,
          collector_number = excluded.collector_number,
          source_url = excluded.source_url,
          raw = excluded.raw,
          updated_at = now()
      `,
      [
        decklistId,
        card.card_key,
        card.card_name,
        card.count,
        card.section || 'main',
        card.set_code || null,
        card.collector_number || null,
        card.source_url || null,
        json(card.raw || {}),
      ],
    );
  }
}

async function createSyncRun(pool, options) {
  if (!pool || options.dryRun) return null;
  const result = await pool.query(
    `
      insert into public.limitless_sync_runs (sync_type, dry_run, metadata)
      values ($1, $2, $3::jsonb)
      returning id
    `,
    [
      options.tournamentIds.length ? 'selected' : 'incremental',
      options.dryRun,
      json({
        maxTournaments: options.maxTournaments,
        games: options.games,
        includeDetails: options.includeDetails,
        includeStandings: options.includeStandings,
        includePairings: options.includePairings,
        includeDecklists: options.includeDecklists,
      }),
    ],
  );
  return result.rows[0]?.id || null;
}

async function finishSyncRun(pool, runId, status, summary, error) {
  if (!pool || !runId) return;
  await pool.query(
    `
      update public.limitless_sync_runs
      set status = $2,
          finished_at = now(),
          tournaments_seen = $3,
          tournaments_upserted = $4,
          details_fetched = $5,
          standings_fetched = $6,
          pairings_fetched = $7,
          decklists_fetched = $8,
          error = $9,
          metadata = metadata || $10::jsonb
      where id = $1
    `,
    [
      runId,
      status,
      summary.tournamentsSeen,
      summary.tournamentsUpserted,
      summary.detailsFetched,
      summary.standingsFetched,
      summary.pairingsFetched,
      summary.decklistsFetched,
      error ? String(error.message || error).slice(0, 2000) : null,
      json({ completedAt: new Date().toISOString(), skippedDecklistsReason: summary.skippedDecklistsReason }),
    ],
  );
}

async function run(options, dependencies = {}) {
  const client = dependencies.client || new LimitlessClient(options);
  const publicClient = dependencies.publicClient || (options.includePublic ? new LimitlessPublicClient(options) : null);
  const pool = dependencies.pool || (!options.dryRun ? createPool() : null);
  const summary = {
    mode: options.dryRun ? 'dry-run' : 'apply',
    tournamentsSeen: 0,
    tournamentsUpserted: 0,
    detailsFetched: 0,
    standingsFetched: 0,
    pairingsFetched: 0,
    decklistsFetched: 0,
    publicDecksSeen: 0,
    publicDecksUpserted: 0,
    publicTournamentsSeen: 0,
    publicTournamentsUpserted: 0,
    publicStandingsFetched: 0,
    publicDecklistsFetched: 0,
    skippedDecklistsReason: options.includeDecklists
      ? 'Limitless decklist endpoint/key not configured; standings decklist references are stored when public.'
      : 'Decklist fetch disabled by default; public standings deck metadata is still stored.',
    errors: [],
  };
  const runId = await createSyncRun(pool, options);

  try {
    const games = await client.get('/games');
    if (!options.dryRun) await upsertGames(pool, Array.isArray(games) ? games : []);

    const tournamentList = options.tournamentIds.length
      ? options.tournamentIds.map((id) => ({ id }))
      : await client.get('/tournaments');
    const filtered = (Array.isArray(tournamentList) ? tournamentList : [])
      .filter((row) => options.tournamentIds.length || options.games.length === 0 || options.games.includes(String(row.game || '').toUpperCase()))
      .slice(0, options.maxTournaments);
    summary.tournamentsSeen = filtered.length;

    for (const listing of filtered) {
      const tournamentId = String(listing.id || '').trim();
      if (!tournamentId) continue;
      try {
        if (!options.dryRun) {
          await upsertTournament(pool, listing, { details: false });
          summary.tournamentsUpserted += 1;
        }

        let details = null;
        if (options.includeDetails) {
          details = await client.get(`/tournaments/${encodeURIComponent(tournamentId)}/details`);
          summary.detailsFetched += 1;
          if (!options.dryRun) {
            await upsertTournament(pool, details, { details: true });
          }
        }

        if (options.includeStandings) {
          const standings = await client.get(`/tournaments/${encodeURIComponent(tournamentId)}/standings`);
          summary.standingsFetched += 1;
          if (!options.dryRun && Array.isArray(standings)) {
            await upsertStandings(pool, tournamentId, standings);
          }
        }

        if (options.includePairings) {
          const pairings = await client.get(`/tournaments/${encodeURIComponent(tournamentId)}/pairings`);
          summary.pairingsFetched += 1;
          if (!options.dryRun && Array.isArray(pairings)) {
            await upsertPairings(pool, tournamentId, pairings);
          }
        }

        if (options.includeDecklists && details?.decklists) {
          console.warn(`Decklist fetch skipped for ${tournamentId}: Limitless decklist endpoint/API key approval is not configured.`);
        }
      } catch (error) {
        summary.errors.push({ tournamentId, message: error.message, statusCode: error.statusCode || null });
        console.warn(`Limitless tournament sync skipped ${tournamentId}: ${error.message}`);
      }
    }

    if (options.includePublic && publicClient) {
      try {
        const tournamentsHtml = await publicClient.getHtml('/tournaments');
        const publicTournaments = parsePublicTournaments(tournamentsHtml, { publicBase: options.publicBase })
          .slice(0, options.publicTournamentLimit);
        summary.publicTournamentsSeen = publicTournaments.length;
        for (const tournament of publicTournaments) {
          try {
            if (!options.dryRun) {
              await upsertPublicTournament(pool, tournament);
              summary.publicTournamentsUpserted += 1;
            }
            const tournamentHtml = await publicClient.getHtml(`/tournaments/${encodeURIComponent(tournament.tournament_id)}`);
            const standings = parseTournamentStandings(tournamentHtml, tournament.tournament_id, {
              publicBase: options.publicBase,
              limit: 300,
            });
            summary.publicStandingsFetched += 1;
            if (!options.dryRun) {
              await replacePublicTournamentStandings(pool, tournament.tournament_id, standings);
            }
          } catch (error) {
            summary.errors.push({ publicTournamentId: tournament.tournament_id, message: error.message, statusCode: error.statusCode || null });
            console.warn(`Limitless public tournament sync skipped ${tournament.tournament_id}: ${error.message}`);
          }
        }

        const decksHtml = await publicClient.getHtml('/decks');
        const publicDecks = parsePublicDecks(decksHtml, { publicBase: options.publicBase })
          .slice(0, options.publicDeckLimit);
        summary.publicDecksSeen = publicDecks.length;
        const decklistIds = new Set();
        for (const listing of publicDecks) {
          try {
            const deckHtml = await publicClient.getHtml(`/decks/${encodeURIComponent(listing.deck_id)}`);
            const parsed = parseDeckOverview(deckHtml, listing.deck_id, {
              publicBase: options.publicBase,
              resultLimit: options.publicDeckResultLimit,
            });
            if (!options.dryRun) {
              await upsertPublicDeck(pool, parsed.deck, listing);
              await replacePublicDeckChildren(pool, listing.deck_id, parsed);
              summary.publicDecksUpserted += 1;
            }
            for (const row of parsed.results) {
              if (row.decklist_id && decklistIds.size < options.publicDecklistLimit) {
                decklistIds.add(row.decklist_id);
              }
            }
          } catch (error) {
            summary.errors.push({ publicDeckId: listing.deck_id, message: error.message, statusCode: error.statusCode || null });
            console.warn(`Limitless public deck sync skipped ${listing.deck_id}: ${error.message}`);
          }
        }

        for (const decklistIdValue of decklistIds) {
          try {
            const decklistHtml = await publicClient.getHtml(`/decks/list/${encodeURIComponent(decklistIdValue)}`);
            const cards = parsePublicDecklistCards(decklistHtml, decklistIdValue, { publicBase: options.publicBase });
            summary.publicDecklistsFetched += 1;
            if (!options.dryRun) {
              await replacePublicDecklistCards(pool, decklistIdValue, cards);
            }
          } catch (error) {
            summary.errors.push({ publicDecklistId: decklistIdValue, message: error.message, statusCode: error.statusCode || null });
            console.warn(`Limitless public decklist sync skipped ${decklistIdValue}: ${error.message}`);
          }
        }
      } catch (error) {
        summary.errors.push({ publicSource: 'limitlesstcg.com', message: error.message, statusCode: error.statusCode || null });
        console.warn(`Limitless public sync skipped: ${error.message}`);
      }
    }

    await finishSyncRun(pool, runId, summary.errors.length ? 'partial' : 'success', summary);
    return summary;
  } catch (error) {
    await finishSyncRun(pool, runId, 'failed', summary, error);
    throw error;
  } finally {
    if (dependencies.pool == null && pool) {
      await pool.end().catch(() => {});
    }
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const loadedEnvFiles = loadDefaultFallbackEnvFiles(options.envFile);
  if (!options.dryRun && !databaseUrl()) {
    throw new Error('Missing MARKETPLACE_DATABASE_URL in the Oracle/peer4 job environment.');
  }
  console.log('Starting Limitless competitive sync', {
    mode: options.dryRun ? 'dry-run' : 'apply',
    envFilesLoaded: loadedEnvFiles.length,
    apiBase: options.apiBase,
    publicBase: options.publicBase,
    maxTournaments: options.maxTournaments,
    publicDeckLimit: options.publicDeckLimit,
    publicTournamentLimit: options.publicTournamentLimit,
    publicDecklistLimit: options.publicDecklistLimit,
    games: options.games,
    tournamentCount: options.tournamentIds.length,
    includeDetails: options.includeDetails,
    includeStandings: options.includeStandings,
    includePairings: options.includePairings,
    includeDecklists: options.includeDecklists,
    includePublic: options.includePublic,
  });
  const startedAt = Date.now();
  const result = await run(options);
  console.log('Finished Limitless competitive sync', {
    ok: result.errors.length === 0,
    durationMs: Date.now() - startedAt,
    result,
  });
}

if (require.main === module) {
  main().catch((error) => {
    console.error('Limitless competitive sync failed', {
      message: error.message,
      statusCode: error.statusCode || '',
    });
    process.exitCode = 1;
  });
}

module.exports = {
  DEFAULT_API_BASE,
  DEFAULT_ENV_FILE,
  DEFAULT_PUBLIC_BASE,
  LimitlessClient,
  LimitlessPublicClient,
  decklistId,
  loadDefaultFallbackEnvFiles,
  normalizePairing,
  normalizeStanding,
  normalizeTournament,
  parseDeckOverview,
  parseArgs,
  parsePublicDecklistCards,
  parsePublicDecks,
  parsePublicTournaments,
  parseTournamentStandings,
  run,
};
