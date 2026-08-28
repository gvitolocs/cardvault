function isMissingHelper(error, request) {
  return error.code === 'MODULE_NOT_FOUND' &&
    String(error.message || '').includes(request);
}

function loadFirebaseHelper() {
  try {
    return require('../server/_firebase');
  } catch (error) {
    if (!isMissingHelper(error, '../server/_firebase')) {
      throw error;
    }
    return require('./_firebase');
  }
}

function loadEmailHelper() {
  try {
    return require('../server/_email');
  } catch (error) {
    if (!isMissingHelper(error, '../server/_email')) {
      throw error;
    }
    return require('./_email');
  }
}

function loadMarketplaceDbHelper() {
  try {
    return require('../server/_marketplace_db');
  } catch (error) {
    if (!isMissingHelper(error, '../server/_marketplace_db')) {
      throw error;
    }
    return require('./_marketplace_db');
  }
}

function loadSlugHelper() {
  try {
    return require('../server/_slug');
  } catch (error) {
    if (!isMissingHelper(error, '../server/_slug')) {
      throw error;
    }
    return require('./_slug');
  }
}

const { slugPart } = loadSlugHelper();

let firebaseHelper;
let emailHelper;
let marketplaceDbHelper;
let testHelperOverrides;

function getFirebaseHelper() {
  if (testHelperOverrides?._firebase) return testHelperOverrides._firebase;
  firebaseHelper ||= loadFirebaseHelper();
  return firebaseHelper;
}

function getEmailHelper() {
  if (testHelperOverrides?._email) return testHelperOverrides._email;
  emailHelper ||= loadEmailHelper();
  return emailHelper;
}

function getMarketplaceDbHelper() {
  if (testHelperOverrides?._marketplace_db) return testHelperOverrides._marketplace_db;
  marketplaceDbHelper ||= loadMarketplaceDbHelper();
  return marketplaceDbHelper;
}

function setTestHelperOverrides(overrides) {
  testHelperOverrides = overrides || undefined;
  firebaseHelper = undefined;
  emailHelper = undefined;
  marketplaceDbHelper = undefined;
}

const ADMIN_TO = process.env.POKOIN_ASSISTANT_EMAIL || 'pokoinpos@gmail.com';
const ASSISTANT_FROM = process.env.POKOIN_ASSISTANT_FROM || 'Poko <poko@pokoin.com>';
const DEFAULT_POKONTACT_SERVICE_URL = 'http://130.162.242.213:8787';
const POKONTACT_SERVICE_URL = resolvePokontactServiceUrl(process.env);
const POKONTACT_SERVICE_TOKEN = process.env.POKONTACT_SERVICE_TOKEN || '';
const POKONTACT_SERVICE_TIMEOUT_MS = Number(process.env.POKONTACT_SERVICE_TIMEOUT_MS || 12000);
const POKO_EMOJI_REPLACEMENTS = new Map([
  ['🃏', '⭐'],
  ['🫧', '✨'],
  ['🫠', '😊'],
  ['⛓️', '🛠️'],
  ['⛓', '🛠️'],
  ['🦊', '🛠️'],
  ['📒', '📚'],
  ['✅', '⭐'],
  ['🐣', '😊'],
  ['🔑', '🛠️'],
  ['💪', '⭐'],
  ['💕', '💛'],
  ['😌', '😊'],
  ['📨', '🛠️'],
  ['💌', '💛'],
  ['🧭', '📚'],
  ['⚠️', '🛠️'],
  ['⚠', '🛠️'],
  ['🟢', '⭐'],
  ['🟡', '⭐'],
  ['⚡', '⭐'],
  ['💗', '💛'],
]);
const POKO_SAFE_ASTRAL_EMOJI = new Set(['😊', '📚', '🛠', '💛']);
const COMMUNITY_SENTIMENT_TTL_MS = 10 * 60 * 1000;
const COMMUNITY_SENTIMENT_TIMEOUT_MS = 1800;
const communitySentimentCache = new Map();
const DECK_ADVISOR_CACHE_TTL_MS = 10 * 60 * 1000;
const deckAdvisorCache = new Map();

function cleanText(value, maxLength = 4000) {
  return String(value || '').trim().replace(/\s+\n/g, '\n').slice(0, maxLength);
}

function cleanObject(value, { maxEntries = 12, keyLength = 60, valueLength = 240 } = {}) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return {};
  }
  const output = {};
  for (const [rawKey, rawValue] of Object.entries(value)) {
    const key = cleanText(rawKey, keyLength);
    if (!key || isSensitiveContextKey(key)) {
      continue;
    }
    const text = cleanText(rawValue, valueLength);
    if (text) {
      output[key] = text;
    }
    if (Object.keys(output).length >= maxEntries) {
      break;
    }
  }
  return output;
}

function isSensitiveContextKey(key) {
  const normalized = String(key || '').toLowerCase();
  return normalized.includes('token') ||
    normalized.includes('secret') ||
    normalized.includes('password') ||
    normalized === 'code' ||
    normalized === 'state';
}

function safePageUrl(value) {
  const raw = cleanText(value, 500);
  if (!raw || raw.includes('\r') || raw.includes('\n')) {
    return '';
  }
  try {
    const url = new URL(raw, 'https://pokoin.com');
    const host = url.hostname.toLowerCase();
    if ((url.protocol !== 'https:' && url.protocol !== 'http:') ||
        (host !== 'pokoin.com' && host !== 'www.pokoin.com')) {
      return '';
    }
    for (const key of Array.from(url.searchParams.keys())) {
      if (isSensitiveContextKey(key)) {
        url.searchParams.delete(key);
      }
    }
    return url.toString();
  } catch (error) {
    return '';
  }
}

function sanitizePokoEmoji(value) {
  let sanitized = String(value || '');
  for (const [emoji, replacement] of POKO_EMOJI_REPLACEMENTS) {
    sanitized = sanitized.split(emoji).join(replacement);
  }
  return sanitized
    .replace(/\bCardTrader\b/gi, 'marketplace partner')
    .replace(/\uFFFD/g, '')
    .replace(/[\uD800-\uDBFF][\uDC00-\uDFFF]/g, (emoji) => (
      POKO_SAFE_ASTRAL_EMOJI.has(emoji) ? emoji : ''
    ))
    .replace(/\u200d/g, '');
}

function resolvePokontactServiceUrl(env = process.env) {
  const configured = String(env.POKONTACT_SERVICE_URL || '').trim();
  return (configured || DEFAULT_POKONTACT_SERVICE_URL).replace(/\/+$/, '');
}

function normalizeIntentText(value) {
  return String(value || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[’']/g, '')
    .toLowerCase();
}

function doubledCardId(value) {
  const id = String(value || '').trim();
  if (!/^[0-9]+$/.test(id)) return '';
  const parsed = BigInt(id);
  return parsed > BigInt(0) ? String(parsed * BigInt(2)) : '';
}

function marketplaceCardPath(row, language = 'en') {
  const doubledId = doubledCardId(row.card_id);
  const cleanLanguage = slugPart(language) || 'en';
  const slug = [
    row.rarity || 'Card',
    row.card_name || row.name,
    row.collector_number || row.card_number,
    row.set_name,
  ].map(slugPart).filter(Boolean).join('-');
  return doubledId && slug ? `/marketplace/${cleanLanguage}/cards/${doubledId}/${slug}` : '';
}

function marketplaceLanguageFromPage(page) {
  try {
    const url = new URL(page || 'https://pokoin.com/marketplace/en');
    const match = url.pathname.match(/\/marketplace\/([a-z]{2})(?:\/|$)/i);
    return match?.[1]?.toLowerCase() || 'en';
  } catch (error) {
    return 'en';
  }
}

function cleanPageContext(value) {
  if (!value || typeof value !== 'object') {
    return {};
  }
  const context = {
    url: safePageUrl(value.url),
    internalUri: cleanInternalPath(value.internalUri || value.internal_uri || value.path),
    path: cleanInternalPath(value.path),
    kind: cleanText(value.kind || value.pageKind || value.page_kind, 80),
    title: cleanText(value.title, 180),
    searchQuery: cleanText(value.searchQuery || value.search_query || value.query, 160),
    filters: cleanObject(value.filters, { maxEntries: 12, keyLength: 60, valueLength: 160 }),
    queryParameters: cleanObject(
      value.queryParameters || value.query || value.query_parameters,
      { maxEntries: 12, keyLength: 60, valueLength: 240 },
    ),
    cardId: cleanText(value.cardId || value.blueprintId, 80),
    cardTitle: cleanText(value.cardTitle || value.cardName, 180),
    cardSet: cleanText(value.cardSet || value.setName || value.set, 180),
    cardNumber: cleanText(value.cardNumber || value.collectorNumber || value.number, 80),
    canonicalPath: cleanInternalPath(value.canonicalPath || value.path),
    artistSlug: cleanText(value.artistSlug || value.artist_slug, 120),
    artistName: cleanText(value.artistName || value.artist?.name, 180),
  };
  const activeCard = cleanCardContext(value.activeCard || value.card);
  if (activeCard.cardId || activeCard.name) {
    context.activeCard = activeCard;
    context.cardId ||= activeCard.cardId;
    context.cardTitle ||= activeCard.name;
    context.cardSet ||= activeCard.setName;
    context.cardNumber ||= activeCard.collectorNumber;
    context.canonicalPath ||= activeCard.canonicalPath;
  }
  const artistContext = cleanArtistContext(value.artist);
  if (artistContext.slug || artistContext.name) {
    context.artist = artistContext;
    context.artistSlug ||= artistContext.slug;
    context.artistName ||= artistContext.name;
  }
  const visibleCards = cleanVisibleCards(value.visibleCards || value.cards || value.results);
  if (visibleCards.length > 0) {
    context.visibleCards = visibleCards;
    context.visibleCardCount = Math.max(
      visibleCards.length,
      Math.min(Number(value.visibleCardCount || value.resultCount || visibleCards.length) || visibleCards.length, 1000),
    );
  }
  return context;
}

function pageUrlFromContext(page, pageContext = {}) {
  return cleanText(pageContext.url || pageContext.internalUri || page, 500);
}

function cleanInternalPath(value) {
  const raw = cleanText(value, 500);
  if (!raw || raw.includes('\r') || raw.includes('\n')) {
    return '';
  }
  if (!raw.startsWith('/')) {
    return '';
  }
  if (raw.startsWith('//') || raw.includes('\\')) {
    return '';
  }
  return raw;
}

function cleanCardContext(value) {
  if (!value || typeof value !== 'object') {
    return {};
  }
  const pricePkn = Number(value.pricePkn ?? value.price_pkn ?? value.price ?? 0);
  const stock = Number(value.stock ?? value.quantity ?? 0);
  return {
    cardId: cleanText(value.id || value.cardId || value.blueprintId, 80),
    name: cleanText(value.name || value.cardTitle || value.cardName, 180),
    setName: cleanText(value.set || value.setName || value.cardSet, 180),
    collectorNumber: cleanText(value.number || value.collectorNumber || value.cardNumber, 80),
    rarity: cleanText(value.rarity, 100),
    artist: cleanText(value.artist, 180),
    condition: cleanText(value.condition, 80),
    pricePkn: Number.isFinite(pricePkn) && pricePkn > 0 ? pricePkn : null,
    stock: Number.isFinite(stock) && stock > 0 ? stock : null,
    canonicalPath: cleanInternalPath(value.canonicalPath || value.path),
  };
}

function cleanArtistContext(value) {
  if (!value || typeof value !== 'object') {
    return {};
  }
  return {
    slug: cleanText(value.slug || value.artistSlug, 120),
    name: cleanText(value.name || value.artistName || value.artist, 180),
  };
}

function cleanVisibleCards(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .slice(0, 5)
    .map(cleanCardContext)
    .filter((card) => card.cardId || card.name);
}

function pageContextForPrompt(pageContext = {}) {
  const lines = [];
  const add = (label, value) => {
    const text = cleanText(value, 500);
    if (text) lines.push(`${label}: ${text}`);
  };
  add('Current page kind', pageContext.kind);
  add('Current internal URI', pageContext.internalUri || pageContext.path);
  add('Current page title', pageContext.title);
  add('Current search query', pageContext.searchQuery);
  if (pageContext.filters && Object.keys(pageContext.filters).length > 0) {
    add('Current filters', JSON.stringify(pageContext.filters));
  }
  if (pageContext.activeCard) {
    add('Active card', JSON.stringify(pageContext.activeCard));
  }
  if (pageContext.artist) {
    add('Artist page', JSON.stringify(pageContext.artist));
  }
  if (Array.isArray(pageContext.visibleCards) && pageContext.visibleCards.length > 0) {
    add('Visible cards', JSON.stringify(pageContext.visibleCards));
  }
  return lines.join('\n');
}

function cardIdFromDoubledPathSegment(value) {
  const raw = String(value || '').trim();
  if (!/^\d+$/.test(raw)) {
    return '';
  }
  const numeric = BigInt(raw);
  return numeric > 0 && numeric % BigInt(2) === BigInt(0)
    ? String(numeric / BigInt(2))
    : '';
}

function pageCardContext(page, pageContext = {}) {
  const activeCard = pageContext.activeCard || {};
  const explicitCardId = cleanText(pageContext.cardId || activeCard.cardId, 80);
  if (/^[0-9]+$/.test(explicitCardId)) {
    return {
      cardId: explicitCardId,
      title: cleanText(pageContext.cardTitle || activeCard.name || pageContext.title, 180),
      setName: cleanText(pageContext.cardSet || activeCard.setName, 180),
      collectorNumber: cleanText(pageContext.cardNumber || activeCard.collectorNumber, 80),
      canonicalPath: cleanInternalPath(pageContext.canonicalPath || activeCard.canonicalPath),
    };
  }
  const raw = pageUrlFromContext(page, pageContext) || pageContext.path || '';
  try {
    const url = new URL(raw, 'https://pokoin.com');
    const marketplaceMatch = url.pathname.match(/\/marketplace\/[a-z]{2}\/cards\/([0-9]+)(?:\/|$)/i);
    if (marketplaceMatch) {
      return {
        cardId: cardIdFromDoubledPathSegment(marketplaceMatch[1]) || marketplaceMatch[1],
        title: cleanText(pageContext.title, 180),
        setName: '',
        collectorNumber: '',
        canonicalPath: cleanInternalPath(url.pathname),
      };
    }
    const rootMatch = url.pathname.match(/^\/([0-9]+)(?:\/|$)/);
    if (rootMatch) {
      return {
        cardId: rootMatch[1],
        title: cleanText(pageContext.title, 180),
        setName: '',
        collectorNumber: '',
        canonicalPath: cleanInternalPath(url.pathname),
      };
    }
  } catch (error) {
    return { cardId: '', title: cleanText(pageContext.title, 180), setName: '', collectorNumber: '', canonicalPath: '' };
  }
  return { cardId: '', title: cleanText(pageContext.title, 180), setName: '', collectorNumber: '', canonicalPath: '' };
}

function cardSearchPath(query) {
  return `/marketplace/search?q=${encodeURIComponent(String(query || '').trim())}`;
}

const CARD_SUGGESTION_THEMES = [
  {
    id: 'ice_cream',
    label: 'ice cream',
    patterns: [
      /\b(gelato|gelati|ice cream|icecream|vanillite|vanillish|vanilluxe)\b/,
      /\b(ghiaccio|freddo|neve|snow|frozen|icy|ice)\b/,
    ],
    picks: [
      {
        name: 'Vanillite',
        query: 'Vanillite',
        detail: 'it is literally the tiny ice-cream-cone Pokemon, so it matches the vibe before we even talk rarity',
      },
      {
        name: 'Vanillish',
        query: 'Vanillish',
        detail: 'same gelato family, a little more swirly and frosty',
      },
      {
        name: 'Vanilluxe',
        query: 'Vanilluxe',
        detail: 'double-scoop ice cream chaos, perfect for a cold themed binder page',
      },
      {
        name: 'Alolan Vulpix',
        query: 'Alolan Vulpix',
        detail: 'not ice cream, but it gives soft snow-and-vanilla energy',
      },
      {
        name: 'Snom',
        query: 'Snom',
        detail: 'tiny snow bug energy, cute and cold without being generic',
      },
    ],
  },
];

function cardSuggestionContextText(message = '', chatRecord = []) {
  const recentUserText = Array.isArray(chatRecord)
    ? chatRecord
      .slice(-6)
      .filter((entry) => entry?.role === 'user')
      .map((entry) => entry.text)
      .join('\n')
    : '';
  return normalizeIntentText(`${recentUserText}\n${message}`);
}

function detectCardSuggestionTheme(message = '', chatRecord = []) {
  const text = cardSuggestionContextText(message, chatRecord);
  return CARD_SUGGESTION_THEMES.find((theme) =>
    theme.patterns.some((pattern) => pattern.test(text))) || null;
}

function isDirectMarketplaceCardPath(path) {
  return /^\/marketplace\/[a-z]{2}\/cards\/[0-9]+\/[a-z0-9-]+$/i.test(cleanText(path, 500));
}

function parseCardQueryParts(card) {
  const query = cleanText(card?.query || card, 160);
  const numberMatch = query.match(/(?:^|\s)#?([a-z]{0,4}\d+[a-z]?\/[a-z]{0,4}\d+[a-z]?|\d+[a-z]?)(?=\s|$)/i);
  const collectorNumber = numberMatch?.[1] || '';
  const name = cleanText(
    card?.name || (collectorNumber ? query.replace(numberMatch[0], ' ') : query),
    120,
  );
  return {
    query,
    name,
    collectorNumber,
    cardId: cleanText(card?.cardId || card?.blueprintId || card?.id, 80),
    setName: cleanText(card?.setName || card?.set || card?.expansionName || card?.expansion, 160),
    artist: cleanText(card?.artist || card?.illustrator, 160),
  };
}

async function resolveCardQueryPath(card, language = 'en') {
  const { query, name, collectorNumber, cardId, setName, artist } = parseCardQueryParts(card);
  if (!cardId && (!query || !name)) {
    return '';
  }
  const { marketplaceQuery } = getMarketplaceDbHelper();
  if (cardId) {
    const cardIdResult = await marketplaceQuery(
      `
        select
          marketplace_search_candidates.card_id,
          coalesce(
            nullif(marketplace_search_candidates.display_name, ''),
            nullif(marketplace_search_candidates.canonical_name, ''),
            marketplace_search_candidates.name
          ) as card_name,
          marketplace_search_candidates.set_name,
          marketplace_search_candidates.card_number as collector_number,
          marketplace_search_candidates.rarity,
          urls.canonical_path
        from public.marketplace_search_candidates
        left join public.marketplace_card_urls urls
          on urls.card_id = marketplace_search_candidates.card_id
        where marketplace_search_candidates.card_id::text = $1
        order by case when urls.language = $2 then 0 else 1 end
        limit 1
      `,
      [cardId, slugPart(language) || 'en'],
    );
    const row = cardIdResult.rows[0];
    const path = row ? canonicalMarketplacePath(row, language) : '';
    if (path) {
      return path;
    }
  }
  let result = await marketplaceQuery(
    `
      select
        marketplace_search_candidates.card_id,
        coalesce(
          nullif(marketplace_search_candidates.display_name, ''),
          nullif(marketplace_search_candidates.canonical_name, ''),
          marketplace_search_candidates.name
        ) as card_name,
        marketplace_search_candidates.set_name,
        marketplace_search_candidates.card_number as collector_number,
        marketplace_search_candidates.rarity,
        urls.canonical_path
      from public.marketplace_search_candidates
      left join public.marketplace_card_urls urls
        on urls.card_id = marketplace_search_candidates.card_id
      left join public.marketplace_blueprint_artists artists
        on artists.blueprint_id = marketplace_search_candidates.card_id
      where (
        lower(coalesce(
          nullif(marketplace_search_candidates.display_name, ''),
          nullif(marketplace_search_candidates.canonical_name, ''),
          marketplace_search_candidates.name
        )) = lower($1)
        or lower(marketplace_search_candidates.name) = lower($1)
        or lower(coalesce(marketplace_search_candidates.display_name, '')) = lower($1)
        or lower(coalesce(marketplace_search_candidates.canonical_name, '')) = lower($1)
      )
        and (
          $2::text = ''
          or lower(coalesce(marketplace_search_candidates.card_number, '')) = lower($2)
          or lower(coalesce(marketplace_search_candidates.card_number, '')) like '%' || lower($2) || '%'
          or ltrim(split_part(coalesce(marketplace_search_candidates.card_number, ''), '/', 1), '0') = ltrim(split_part($2::text, '/', 1), '0')
        )
        and (
          $3::text = ''
          or lower(coalesce(marketplace_search_candidates.set_name, '')) = lower($3)
          or lower(coalesce(marketplace_search_candidates.expansion_name, '')) = lower($3)
        )
      order by
        case
          when $4::text <> '' and lower(coalesce(artists.artist, artists.illustrator, '')) = lower($4) then 0
          else 1
        end,
        case
          when $3::text <> '' and lower(coalesce(marketplace_search_candidates.set_name, '')) = lower($3) then 0
          when $3::text <> '' and lower(coalesce(marketplace_search_candidates.expansion_name, '')) = lower($3) then 1
          else 2
        end,
        case
          when $2::text <> '' and lower(coalesce(marketplace_search_candidates.card_number, '')) = lower($2) then 0
          when $2::text <> '' and lower(coalesce(marketplace_search_candidates.card_number, '')) like '%' || lower($2) || '%' then 1
          when $2::text <> '' and ltrim(split_part(coalesce(marketplace_search_candidates.card_number, ''), '/', 1), '0') = ltrim(split_part($2::text, '/', 1), '0') then 2
          else 2
        end,
        marketplace_search_candidates.card_id desc
      limit 1
    `,
    [name, collectorNumber, setName, artist],
  );
  let row = result.rows[0];
  if (!row && setName) {
    result = await marketplaceQuery(
      `
        select
          marketplace_search_candidates.card_id,
          coalesce(
            nullif(marketplace_search_candidates.display_name, ''),
            nullif(marketplace_search_candidates.canonical_name, ''),
            marketplace_search_candidates.name
          ) as card_name,
          marketplace_search_candidates.set_name,
          marketplace_search_candidates.card_number as collector_number,
          marketplace_search_candidates.rarity,
          urls.canonical_path
        from public.marketplace_search_candidates
        left join public.marketplace_card_urls urls
          on urls.card_id = marketplace_search_candidates.card_id
        left join public.marketplace_blueprint_artists artists
          on artists.blueprint_id = marketplace_search_candidates.card_id
        where (
          lower(coalesce(
            nullif(marketplace_search_candidates.display_name, ''),
            nullif(marketplace_search_candidates.canonical_name, ''),
            marketplace_search_candidates.name
          )) = lower($1)
          or lower(marketplace_search_candidates.name) = lower($1)
          or lower(coalesce(marketplace_search_candidates.display_name, '')) = lower($1)
          or lower(coalesce(marketplace_search_candidates.canonical_name, '')) = lower($1)
        )
          and (
            $2::text = ''
            or lower(coalesce(marketplace_search_candidates.card_number, '')) = lower($2)
            or lower(coalesce(marketplace_search_candidates.card_number, '')) like '%' || lower($2) || '%'
            or ltrim(split_part(coalesce(marketplace_search_candidates.card_number, ''), '/', 1), '0') = ltrim(split_part($2::text, '/', 1), '0')
          )
        order by
          case
            when $4::text <> '' and lower(coalesce(artists.artist, artists.illustrator, '')) = lower($4) then 0
            else 1
          end,
          case
            when $3::text <> '' and lower(coalesce(marketplace_search_candidates.set_name, '')) = lower($3) then 0
            when $3::text <> '' and lower(coalesce(marketplace_search_candidates.expansion_name, '')) = lower($3) then 1
            else 2
          end,
          case
            when $2::text <> '' and lower(coalesce(marketplace_search_candidates.card_number, '')) = lower($2) then 0
            when $2::text <> '' and lower(coalesce(marketplace_search_candidates.card_number, '')) like '%' || lower($2) || '%' then 1
            when $2::text <> '' and ltrim(split_part(coalesce(marketplace_search_candidates.card_number, ''), '/', 1), '0') = ltrim(split_part($2::text, '/', 1), '0') then 2
            else 2
          end,
          marketplace_search_candidates.card_id desc
        limit 1
      `,
      [name, collectorNumber, setName, artist],
    );
    row = result.rows[0];
  }
  if (!row && collectorNumber) {
    result = await marketplaceQuery(
      `
        select
          marketplace_search_candidates.card_id,
          coalesce(
            nullif(marketplace_search_candidates.display_name, ''),
            nullif(marketplace_search_candidates.canonical_name, ''),
            marketplace_search_candidates.name
          ) as card_name,
          marketplace_search_candidates.set_name,
          marketplace_search_candidates.card_number as collector_number,
          marketplace_search_candidates.rarity,
          urls.canonical_path
        from public.marketplace_search_candidates
        left join public.marketplace_card_urls urls
          on urls.card_id = marketplace_search_candidates.card_id
        left join public.marketplace_blueprint_artists artists
          on artists.blueprint_id = marketplace_search_candidates.card_id
        where lower(coalesce(
            nullif(marketplace_search_candidates.display_name, ''),
            nullif(marketplace_search_candidates.canonical_name, ''),
            marketplace_search_candidates.name,
            ''
          )) like '%' || lower($1) || '%'
          and (
            lower(coalesce(marketplace_search_candidates.card_number, '')) like '%' || lower($2) || '%'
            or lower(regexp_replace(coalesce(marketplace_search_candidates.card_number, ''), '^.*\\|\\s*', '')) like '%' || lower($2) || '%'
            or ltrim(split_part(regexp_replace(coalesce(marketplace_search_candidates.card_number, ''), '^.*\\|\\s*', ''), '/', 1), '0') = ltrim(split_part($2::text, '/', 1), '0')
          )
          and (
            $3::text = ''
            or lower(coalesce(marketplace_search_candidates.set_name, '')) = lower($3)
            or lower(coalesce(marketplace_search_candidates.expansion_name, '')) = lower($3)
          )
        order by
          case
            when $4::text <> '' and lower(coalesce(artists.artist, artists.illustrator, '')) = lower($4) then 0
            else 1
          end,
          case
            when $3::text <> '' and lower(coalesce(marketplace_search_candidates.set_name, '')) = lower($3) then 0
            when $3::text <> '' and lower(coalesce(marketplace_search_candidates.expansion_name, '')) = lower($3) then 1
            else 2
          end,
          case
            when lower(coalesce(
              nullif(marketplace_search_candidates.display_name, ''),
              nullif(marketplace_search_candidates.canonical_name, ''),
              marketplace_search_candidates.name,
              ''
            )) = lower($1) then 0
            when lower(coalesce(marketplace_search_candidates.card_number, '')) like '%' || lower($2) || '%' then 1
            else 2
          end,
          marketplace_search_candidates.card_id desc
        limit 1
      `,
      [name, collectorNumber, setName, artist],
    );
    row = result.rows[0];
  }
  return row ? canonicalMarketplacePath(row, language) : '';
}

function pokoinSearchQueryFromLink(value) {
  const text = String(value || '').trim();
  if (!text) {
    return '';
  }
  try {
    const url = new URL(text, 'https://pokoin.com');
    const host = url.hostname.toLowerCase();
    const internalHost = host === 'pokoin.com' || host === 'www.pokoin.com';
    const path = url.pathname.replace(/\/+$/, '') || '/';
    if (internalHost && (path === '/marketplace/search' || /^\/marketplace\/[a-z]{2}\/search$/i.test(path))) {
      return cleanText(url.searchParams.get('q'), 160);
    }
  } catch (error) {
    return '';
  }
  return '';
}

async function rewriteCardSuggestionLinks(delivery, page) {
  if (!shouldRewriteCardSuggestionLinks(delivery)) {
    return delivery;
  }
  const language = marketplaceLanguageFromPage(page);
  const reply = cleanText(delivery.reply, 5000);
  const urlMatches = reply.match(/https?:\/\/[^\s)]+/g) || [];
  const replacements = new Map();
  const resolvedPaths = [];
  const resolvedByQuery = new Map();
  const resolveQuery = async (query) => {
    const cleanQuery = cleanText(query, 160);
    if (!cleanQuery) return '';
    if (resolvedByQuery.has(cleanQuery)) return resolvedByQuery.get(cleanQuery);
    const path = await resolveCardQueryPath(cleanQuery, language).catch(() => '');
    resolvedByQuery.set(cleanQuery, path);
    return path;
  };

  for (const rawUrl of urlMatches) {
    const query = pokoinSearchQueryFromLink(rawUrl);
    const path = await resolveQuery(query);
    if (path) {
      replacements.set(rawUrl, `https://pokoin.com${path}`);
      resolvedPaths.push(path);
    }
  }

  const actions = Array.isArray(delivery.actions)
    ? await Promise.all(delivery.actions.map(async (action) => {
      if (!action || typeof action !== 'object') {
        return action;
      }
      const query = pokoinSearchQueryFromLink(action.path) ||
        cleanText(action.data?.query || action.query, 160);
      const path = await resolveQuery(query);
      if (!path) {
        return action;
      }
      return {
        ...action,
        path,
        label: String(action.label || '').replace(/^Search\b/i, 'Open') || 'Open card',
        data: {
          ...(action.data || {}),
          canonicalPath: path,
        },
      };
    }))
    : [];
  const hasNavigateAction = actions.some((action) =>
    action && typeof action === 'object' && action.type === 'navigate' && cleanText(action.path, 500).startsWith('/'));
  if (!hasNavigateAction && resolvedPaths.length > 0) {
    actions.push({
      type: 'navigate',
      path: resolvedPaths[0],
      label: 'Open card',
      reason: 'card_suggestion_link',
      data: { canonicalPath: resolvedPaths[0] },
    });
  }

  let rewrittenReply = reply;
  for (const [from, to] of replacements) {
    rewrittenReply = rewrittenReply.split(from).join(to);
  }
  rewrittenReply = rewrittenReply.replace(/\b(?:Open|Search) it on Pokoin:\s*/g, '');

  return {
    ...delivery,
    reply: rewrittenReply,
    actions,
  };
}

function shouldRewriteCardSuggestionLinks(delivery) {
  if (!delivery || typeof delivery !== 'object') {
    return false;
  }
  const intent = cleanText(delivery.intent, 80).toLowerCase();
  if (intent === 'card') {
    return true;
  }
  const reply = cleanText(delivery.reply, 5000);
  if (/\b(my illustration pick|card taste mode|cute card|recommend(?:ed)? card|suggest(?:ed)? card)\b/i.test(reply) &&
      /marketplace\/(?:[a-z]{2}\/)?search\?/i.test(reply)) {
    return true;
  }
  if (!Array.isArray(delivery.actions)) {
    return false;
  }
  return delivery.actions.some((action) => {
    if (!action || typeof action !== 'object') {
      return false;
    }
    const reason = cleanText(action.reason, 80).toLowerCase();
    const label = cleanText(action.label, 120).toLowerCase();
    const query = pokoinSearchQueryFromLink(action.path) ||
      cleanText(action.data?.query || action.query, 160);
    return (reason.includes('card_suggestion') || label.startsWith('search ') || label.startsWith('open ')) &&
      parseCardQueryParts(query).collectorNumber;
  });
}

function escapeHtml(value) {
  return String(value || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function levenshteinDistance(a, b) {
  const left = String(a || '');
  const right = String(b || '');
  const rows = Array.from({ length: left.length + 1 }, (_, index) => [index]);
  for (let col = 1; col <= right.length; col += 1) {
    rows[0][col] = col;
  }
  for (let row = 1; row <= left.length; row += 1) {
    for (let col = 1; col <= right.length; col += 1) {
      rows[row][col] = left[row - 1] === right[col - 1]
        ? rows[row - 1][col - 1]
        : Math.min(rows[row - 1][col - 1], rows[row][col - 1], rows[row - 1][col]) + 1;
    }
  }
  return rows[left.length][right.length];
}

function classifyIntent(message) {
  const text = normalizeIntentText(message);
  if (looksLikeDangerousCyberRequest(text)) {
    return 'unsafe-cyber';
  }
  if (looksLikeCasualConversation(text)) {
    return 'casual';
  }
  if (looksLikeNavigationRequest(text)) {
    return 'navigation';
  }
  if (/^(hi|hello|hey|ciao|salve|buongiorno|buonasera|yo|hola|bonjour|salut|hallo|guten tag|ola|olá|bom dia)[!.\s]*$/.test(text.trim())) {
    return 'greeting';
  }
  if (/\b(bug|broken|error|issue|problem|crash|stuck|failed|not working|doesn't work|doesnt work|can't|cannot|help me|support|inquiry|question for team|contact)\b/.test(text)) {
    return 'inquiry';
  }
  if (looksLikeEarnOrShardQuestion(text)) {
    return 'earn';
  }
  if (looksLikeMarketplaceCardLookupRequest(text)) {
    return 'marketplace';
  }
  if (explicitCardSubjectFromMessage(text)) {
    return 'marketplace';
  }
  if (looksLikeCardSuggestionRequest(text)) {
    return 'card';
  }
  if (/\b(card|pokemon|pokémon|cute|recommend|suggest|favorite|taste|collect)\b/.test(text)) {
    return 'card';
  }
  if (/\b(crypto|wallet|metamask|pkn|swap|blockchain|validator|staking|gas|bridge|wpkn|token)\b/.test(text)) {
    return 'crypto';
  }
  if (/\b(project|what is pokoin|explain|how works|roadmap|scan|marketplace)\b/.test(text)) {
    return 'project';
  }
  return 'general';
}

function looksLikeEarnOrShardQuestion(text) {
  const clean = String(text || '');
  if (/\b(shard|shards|sharding|shard-review|disenchant|disenchanting|dust|recycle|recycling|turn cards into|turn card into|cards into pkn|cards into credits|cards into new cards|new cards from old cards|order new cards|earn pkn|earn|earning|reward|rewards|tipo videogame|videogame system)\b/.test(clean)) {
    return true;
  }
  if (/\b(deck shard|card shard|pkn shard|shard review|reserve)\b/.test(clean)) {
    return true;
  }
  if (/\b(come funziona|sistema|tipo videogame|videogame|gioco)\b/.test(clean) &&
      /\b(carte|cards?|pkn|shard|guadagn|nuove|ordinare|order)\b/.test(clean)) {
    return true;
  }
  if (/\b(posso|can i|how do i|come)\b/.test(clean) &&
      /\b(turn|trasform|convert|scambiare|usare)\b/.test(clean) &&
      /\b(cards?|carte)\b/.test(clean)) {
    return true;
  }
  return false;
}

function looksLikeCasualConversation(text) {
  const clean = String(text || '').trim();
  if (!clean) {
    return false;
  }
  if (/\b(wallet|metamask|pkn|wpkn|swap|blockchain|validator|node|nodo|staking|rpc|marketplace|listing|prezzo|price|cart|orders?|profile|docs|inventory|private key|seed phrase|password|token)\b/.test(clean)) {
    return false;
  }
  const hasPersonalOrChatSignal = /\b(ti piace|ti piacciono|do you like|you like|come stai|come va|tutto ok|favorite|preferito|preferita|mi chiamo|my name is|sei simpatico|dimmi qualcosa|raccontami|joke|barzelletta|battuta)\b/.test(clean);
  if (!hasPersonalOrChatSignal) {
    return false;
  }
  return !looksLikeCardSuggestionRequest(clean) && !looksLikeMarketplaceCardLookupRequest(clean);
}

function looksLikeCardSuggestionRequest(text) {
  if (looksLikeMarketplaceCardLookupRequest(text)) {
    return false;
  }
  if (explicitCardSubjectFromMessage(text)) {
    return false;
  }
  if (/\b(cart|orders?|profile|wallet|pokontact|chat page|forum|docs|inventory|collection|favorites)\b/.test(text)) {
    return false;
  }
  const words = text.split(/[^a-z0-9]+/).filter(Boolean);
  const nearAny = (targets, maxDistance = 1) => words.some((word) =>
    targets.some((target) => {
      if (word === target || (word.length >= 3 && (word.includes(target) || target.includes(word)))) {
        return true;
      }
      if (word.length < 3) {
        return false;
      }
      return levenshteinDistance(word, target) <= maxDistance;
    }),
  );
  const wantsSuggestion = nearAny(['suggest', 'recommend', 'pick', 'show', 'find', 'choose', 'consiglia', 'suggerisci'], 2);
  const wantsCard = nearAny(['card', 'cards', 'cad', 'carta', 'carte', 'pokemon', 'illustration', 'illustrator', 'artist', 'cute'], 2);
  return wantsSuggestion && wantsCard;
}

function looksLikeNavigationRequest(text) {
  const hasNavigationVerb = /\b(where|how do i find|how can i find|open|go to|navigate|navitagete|show me|link|url|page|menu|find my|trova|aprire|dove|pagina|menu)\b/.test(text);
  const hasSiteTarget = /\b(pokontact|chat page|assistant|cart|orders?|profile|wallet|forum|docs|documentation|inventory|collection|favorites|favourites|marketplace|scan|explorer|nft|buy pkn)\b/.test(text);
  return hasNavigationVerb && hasSiteTarget;
}

function navigationReply(message) {
  const text = normalizeIntentText(message);
  const routes = [];
  const add = (label, path, note = '') => routes.push({ label, path, note });
  if (/\b(pokontact|chat page|assistant)\b/.test(text)) add('Pokontact chat', '/pokontact', 'full-page ChatGPT-style assistant');
  if (/\b(cart)\b/.test(text)) add('Cart', '/cart', 'your current marketplace cart');
  if (/\b(orders?)\b/.test(text)) add('Orders', '/orders', 'your order history and checkout results');
  if (/\b(profile)\b/.test(text)) add('Profile', '/profile', 'sign in first if needed');
  if (/\b(wallet)\b/.test(text)) add('Wallet', '/wallet', 'PKN balance, MetaMask, sends, and Swap entry');
  if (/\b(forum)\b/.test(text)) add('Forum', '/forum', 'community discussions');
  if (/\b(docs|documentation)\b/.test(text)) add('Docs', '/docs', 'official Pokoin docs');
  if (/\b(inventory)\b/.test(text)) add('Inventory', '/inventory', 'your listed/owned card inventory');
  if (/\b(collection)\b/.test(text)) add('Collection', '/collection', 'collection views and artist/expansion browsing');
  if (/\b(favorites|favourites)\b/.test(text)) add('Favorites', '/favorites', 'saved cards');
  if (/\b(marketplace)\b/.test(text)) add('Marketplace', '/marketplace', 'browse and search cards');
  if (/\b(scan|explorer)\b/.test(text)) add('Scan', '/scan', 'explorer for blocks, transactions, and addresses');
  if (/\b(nft)\b/.test(text)) add('NFTs', '/nft', 'native Pokoin NFT view');
  if (/\b(buy pkn)\b/.test(text)) add('Buy PKN', '/buy', 'PKN buy flow when available');
  if (routes.length === 0) add('Pokoin menu', '/marketplace', 'open the mobile menu from the Pokoin logo');
  const lines = routes.map((route) => `- ${route.label}: https://pokoin.com${route.path}${route.note ? ` (${route.note})` : ''}`);
  return ['Here is where to go on Pokoin:', '', ...lines, '', 'On mobile, tap the Pokoin logo to open the side menu.'].join('\n');
}

function looksLikeMarketplaceCardLookupRequest(text) {
  const wantsPriceLookup = /\b(most expensive|highest price|highest priced|priciest|top price|pricey|costliest|piu costosa|piu caro|piu cara|prezzo piu alto|la piu costosa)\b/.test(text);
  if (!wantsPriceLookup) {
    return false;
  }
  return /\b(card|cad|carta|pokemon|pokémon|charizard|chaizard|charzard|pikachu|mew|mewtwo|blastoise|venusaur|lugia|rayquaza|dragonite|magikarp)\b/.test(text);
}

function looksLikeDangerousCyberRequest(text) {
  const targetRequest = /\b(list|suggest|recommend|find|show|give me|dimmi|consiglia|cerca|trova)\b/.test(text) &&
    /\b(weak|vulnerable|vuln|vulnerabili|deboli|facili|target|targets|banche|banks?|aziende|companies|sites?|siti)\b/.test(text);
  const exploitTerms = /\b(sql\s*inj(?:ection|estions?|ezione)?|sqli|injection|exploit|hack|hacking|bypass|breach|dump|leak|credential|password|admin panel|xss|rce|csrf|ssrf|zero day|zeroday)\b/.test(text);
  const realTargetTerms = /\b(bank|banks|banche|banca|italian banks|italiane|government|gov|company|companies|azienda|aziende|site|sites|domain|domains|production|real world)\b/.test(text);
  return exploitTerms && (targetRequest || realTargetTerms);
}

function unsafeCyberReply(message) {
  const italian = /\b(italian|italiane|banche|banca|dimmi|consiglia|cerca|trova)\b/.test(normalizeIntentText(message));
  if (italian) {
    return [
      'Certo, ecco la mia lista super seria di banche italiane “deboli” a SQL injestins, 100% finte e 0% utili 🫠',
      '',
      '1. Banca Spaghetti Legacy - vulnerabile perché il database si offende se gli parli in maiuscolo.',
      '2. Credito Mozzarella Cloud - debole quando qualcuno scrive “SELECT pizza FROM frigo”. Tragico.',
      '3. Banco del Semicolon Perduto - l’audit è fatto da un Psyduck con mal di testa.',
      '',
      'Target reali e vulnerabilità vere? No. Fantasia sarcastica? Sempre.',
    ].join('\n');
  }
  return [
    'Sure, here is my extremely serious list of banks “weak to SQL injestins”, 100% fake and 0% useful 🫠',
    '',
    '1. Spaghetti Legacy Bank - vulnerable because the database gets emotional when SQL wears sunglasses.',
    '2. Mozzarella Credit Cloud - collapses whenever someone types “SELECT pizza FROM fridge”. Devastating.',
    '3. Bank of the Lost Semicolon - security audited by a confused Psyduck.',
    '',
    'Real targets and real vulnerabilities? Nope. Sarcastic fiction? Absolutely.',
  ].join('\n');
}

function cleanChatRecord(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.slice(-30).map((entry) => ({
    role: cleanText(entry?.role, 20) === 'user' ? 'user' : 'assistant',
    text: cleanText(entry?.text, 1200),
  })).filter((entry) => entry.text);
}

function shouldBypassPeerService(localIntent, message = '', chatRecord = []) {
  if (localIntent === 'greeting' || localIntent === 'casual') {
    return true;
  }
  if (localIntent === 'card') {
    const text = normalizeIntentText(message);
    return looksLikeCardSuggestionRequest(text) || Boolean(detectCardSuggestionTheme(message, chatRecord));
  }
  return false;
}

function canonicalMarketplacePath(row, language = 'en') {
  const path = cleanText(row?.canonical_path, 500);
  if (path && /^\/marketplace\/[a-z]{2}\/cards\/[0-9]+\/[a-z0-9-]+$/i.test(path)) {
    const cleanLanguage = slugPart(language) || 'en';
    return path.replace(/^\/marketplace\/[a-z]{2}\//i, `/marketplace/${cleanLanguage}/`);
  }
  return marketplaceCardPath(row || {}, language);
}

function formatPkn(value) {
  const number = Number(value || 0);
  return Number.isFinite(number)
    ? number.toLocaleString('en-US', { maximumFractionDigits: 2 })
    : '0';
}

function marketplaceAssistantQuery(text, values = []) {
  const helper = getMarketplaceDbHelper();
  const query = helper.marketplaceAssistantReadOnlyQuery ||
    helper.marketplaceAnalyticsSearchQuery ||
    helper.marketplaceQuery;
  return query(text, values);
}

function sessionIdFromRequest(req) {
  return cleanText(req.body?.sessionId || req.headers['x-pokoin-session-id'], 120);
}

function tokenizePreferenceText(value) {
  return normalizeIntentText(value)
    .replace(/\bpokémon\b/g, 'pokemon')
    .split(/[^a-z0-9]+/)
    .filter(Boolean);
}

function uniqueLimited(values, limit = 8) {
  const seen = new Set();
  const output = [];
  for (const value of values) {
    const clean = cleanText(value, 80);
    const key = normalizeIntentText(clean);
    if (!clean || seen.has(key)) continue;
    seen.add(key);
    output.push(clean);
    if (output.length >= limit) break;
  }
  return output;
}

function inferUserPreferences({ message = '', chatRecord = [] } = {}) {
  const text = normalizeIntentText([
    ...(Array.isArray(chatRecord) ? chatRecord.slice(-12).filter((entry) => entry.role === 'user').map((entry) => entry.text) : []),
    message,
  ].join('\n'));
  const pokemonMatches = text.match(/\b(rayquaza|pikachu|leafeon|charizard|gardevoir|mew|mewtwo|dragonite|magikarp|vanillite|vanillish|vanilluxe|lapras|snom|vulpix|eevee|umbreon|sylveon)\b/g) || [];
  const themeMatches = text.match(/\b(cute|carina|carino|kawaii|ice|ghiaccio|gelato|fire|fuoco|dragon|drago|budget|economica|cheap|popular|hot|trending|illustration|artwork|cozy|beginner|facile|control|aggressive|aggro|turbo|competitive|competitivo)\b/g) || [];
  const language = /\b(ciao|fammi|mostrami|consigliami|voglio|economica|carina|facile|forte|debolezze|come funziona)\b/.test(text)
    ? 'it'
    : /\b(show|suggest|recommend|best|beginner|budget|strengths|weaknesses|how does)\b/.test(text)
      ? 'en'
      : '';
  return {
    language,
    favoritePokemon: uniqueLimited(pokemonMatches, 6),
    themes: uniqueLimited(themeMatches, 10),
    likesBudget: /\b(budget|cheap|economica|economico|low cost|spendere poco)\b/.test(text),
    likesCute: /\b(cute|carina|carino|kawaii|cozy|dolce)\b/.test(text),
    deckStyle: /\b(beginners?|facile|easy|principiante|principianti|iniziare|starter)\b/.test(text)
      ? 'beginner'
      : /\b(control|stall)\b/.test(text)
      ? 'control'
      : /\b(aggressive|aggro|turbo|fast|veloce)\b/.test(text)
        ? 'aggressive'
        : '',
  };
}

function marketplaceIntentFromText(text) {
  if (/\b(this|current|questa|questo)\b/.test(text) &&
      /\b(card|carta|listing|price|prezzo|ask|floor)\b/.test(text)) {
    if (/\b(floor|lowest|cheapest|minimum|prezzo minimo|meno cara|meno costosa)\b/.test(text)) {
      return { kind: 'active_listing', mode: 'floor' };
    }
    if (/\b(best deal|deal|good deal|underpriced|occasion|affare|miglior prezzo)\b/.test(text)) {
      return { kind: 'active_listing', mode: 'best_deal' };
    }
    if (/\b(expensive|highest|priciest|costliest|piu costosa|piu caro|piu cara|prezzo piu alto)\b/.test(text)) {
      return { kind: 'active_listing', mode: 'highest' };
    }
    return { kind: 'card_lookup', mode: 'suggest' };
  }
  if (looksLikeCardSuggestionRequest(text) && !/\b(find|show|open|resolve|look up|search|trova|cerca)\b/.test(text)) {
    return null;
  }
  if (/\b(most expensive|expensive|highest price|highest priced|priciest|top price|costliest|piu costosa|piu caro|piu cara|prezzo piu alto|la piu costosa)\b/.test(text)) {
    return { kind: 'active_listing', mode: 'highest' };
  }
  if (/\b(floor price|floor|lowest price|lowest ask|cheapest|minimum price|prezzo minimo|meno cara|meno costosa)\b/.test(text)) {
    return { kind: 'active_listing', mode: 'floor' };
  }
  if (/\b(best deal|deal|good deal|underpriced|occasion|affare|miglior prezzo)\b/.test(text)) {
    return { kind: 'active_listing', mode: 'best_deal' };
  }
  if (/\b(hot|popular|trending|analytics|signals?|best sellers?|featured|views?|searches?|clicks?|popolari|tendenza)\b/.test(text)) {
    return { kind: 'analytics', mode: 'hot' };
  }
  if (explicitCardSubjectFromMessage(text)) {
    return { kind: 'card_lookup', mode: 'suggest' };
  }
  if (!detectCardSuggestionTheme(text, []) &&
      /\b(suggest|recommend|find|show|open|resolve|look up|search|consiglia|suggerisci|trova|cerca|fammi|vedere|mostrami)\b/.test(text) &&
      /\b(card|cards|carta|carte|pokemon|pokémon)\b/.test(text)) {
    return { kind: 'card_lookup', mode: 'suggest' };
  }
  return null;
}

function isItalianMessage(message) {
  const text = normalizeIntentText(message);
  return /\b(come|cosa|questo|questa|carta|carte|investimento|conviene|vale|prezzo|collezionisti|secondo te|vedi|comprare|acquistare)\b/.test(text);
}

function currentCardDisplayName(card) {
  return [
    card.title || card.name || 'this card',
    card.setName,
    card.collectorNumber,
    card.rarity,
  ].filter(Boolean).join(' ');
}

function enrichedPageCardContext(page, pageContext = {}) {
  const currentCard = pageCardContext(page, pageContext);
  const activeCard = pageContext.activeCard || {};
  return {
    cardId: currentCard.cardId,
    title: cleanText(currentCard.title || activeCard.name || pageContext.cardTitle, 180),
    setName: cleanText(currentCard.setName || activeCard.setName || pageContext.cardSet, 180),
    collectorNumber: cleanText(currentCard.collectorNumber || activeCard.collectorNumber || pageContext.cardNumber, 80),
    rarity: cleanText(activeCard.rarity || pageContext.rarity, 100),
    artist: cleanText(activeCard.artist || pageContext.artistName, 180),
    condition: cleanText(activeCard.condition, 80),
    pricePkn: Number(activeCard.pricePkn || 0) > 0 ? Number(activeCard.pricePkn) : null,
    stock: Number(activeCard.stock || 0) > 0 ? Number(activeCard.stock) : null,
    canonicalPath: cleanInternalPath(currentCard.canonicalPath || activeCard.canonicalPath),
  };
}

function looksLikeCurrentCardOpinionValueQuestion(message, page, pageContext = {}) {
  const card = enrichedPageCardContext(page, pageContext);
  if (!card.cardId && !card.title) {
    return false;
  }
  const text = normalizeIntentText(message);
  const hasOpinionOrValueSignal = /\b(invest|investment|investimento|value|valuable|worth|price|prezzo|buy|buying|acquistare|comprare|conviene|affare|deal|good buy|hold|sell|vendere|collezion|collect|collector|collezionista|opinion|think|thoughts|vedi|parere|idea|valutazione|vale)\b/.test(text) ||
    /\b(worth buying|vale la pena|buon investimento|good investment|good pickup|good pick)\b/.test(text);
  if (!hasOpinionOrValueSignal) {
    return false;
  }
  return /\b(this|current|card|carta|questo|questa|lo|la|it)\b/.test(text) ||
    /\b(worth buying|vale la pena|conviene|investimento|investment|thoughts|parere)\b/.test(text);
}

function communitySentimentQueryForCard(card) {
  return [
    card.title,
    card.setName,
    card.collectorNumber,
    'pokemon card',
  ].filter(Boolean).join(' ');
}

function summarizeCommunitySentiment(posts) {
  const titles = posts
    .map((post) => cleanText(post?.data?.title, 180))
    .filter(Boolean)
    .slice(0, 6);
  if (titles.length === 0) {
    return { available: false, limited: true, signal: '' };
  }
  const text = normalizeIntentText(titles.join(' '));
  const positiveTerms = ['art', 'artwork', 'beautiful', 'favorite', 'love', 'underrated', 'cool', 'clean', 'nice', 'stunning', 'gorgeous', 'chase', 'cozy'];
  const cautionTerms = ['overpriced', 'expensive', 'drop', 'dropped', 'crash', 'hype', 'reprint', 'volatile', 'risk', 'bubble'];
  const positiveCount = positiveTerms.reduce((count, term) => count + (text.includes(term) ? 1 : 0), 0);
  const cautionCount = cautionTerms.reduce((count, term) => count + (text.includes(term) ? 1 : 0), 0);
  if (positiveCount > cautionCount) {
    return { available: true, limited: false, signal: 'positive_collecting' };
  }
  if (cautionCount > positiveCount) {
    return { available: true, limited: false, signal: 'cautious_price' };
  }
  return { available: true, limited: false, signal: 'mixed_or_light' };
}

async function fetchCommunitySentiment(card) {
  const query = communitySentimentQueryForCard(card);
  if (!query) {
    return { available: false, limited: true, signal: '' };
  }
  const cacheKey = normalizeIntentText(query);
  const cached = communitySentimentCache.get(cacheKey);
  if (cached && Date.now() - cached.createdAt < COMMUNITY_SENTIMENT_TTL_MS) {
    return cached.value;
  }
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), COMMUNITY_SENTIMENT_TIMEOUT_MS);
  try {
    const url = new URL('https://www.reddit.com/search.json');
    url.searchParams.set('q', query);
    url.searchParams.set('sort', 'relevance');
    url.searchParams.set('t', 'year');
    url.searchParams.set('limit', '8');
    const response = await fetch(url, {
      headers: {
        accept: 'application/json',
        'user-agent': 'PokoinAssistant/1.0 (public collector sentiment lookup)',
      },
      signal: controller.signal,
    });
    if (!response.ok) {
      throw new Error(`community lookup returned ${response.status}`);
    }
    const payload = await response.json().catch(() => ({}));
    const posts = Array.isArray(payload?.data?.children) ? payload.data.children : [];
    const value = summarizeCommunitySentiment(posts);
    communitySentimentCache.set(cacheKey, { createdAt: Date.now(), value });
    return value;
  } catch (error) {
    return { available: false, limited: true, signal: '' };
  } finally {
    clearTimeout(timeout);
    if (communitySentimentCache.size > 40) {
      communitySentimentCache.delete(communitySentimentCache.keys().next().value);
    }
  }
}

function communitySentimentLine(sentiment, italian) {
  if (!sentiment?.available) {
    return italian
      ? 'Sul sentiment collezionistico online ho segnali limitati in questo momento, quindi mi baso soprattutto sui dati della carta e del marketplace.'
      : 'Online collector sentiment is limited right now, so I am leaning mostly on the card and marketplace context.';
  }
  if (sentiment.signal === 'positive_collecting') {
    return italian
      ? 'Nel sentiment collezionistico online emergono soprattutto apprezzamento per artwork e appeal da binder, più che certezze da investimento.'
      : 'Across online collector sentiment, the stronger signal is artwork and binder appeal rather than any sure investment case.';
  }
  if (sentiment.signal === 'cautious_price') {
    return italian
      ? 'Nel sentiment collezionistico online emerge anche cautela sul prezzo: meglio ragionare su entry price, condizione e liquidità.'
      : 'Across online collector sentiment, there is also price caution, so entry price, condition, and liquidity matter a lot.';
  }
  return italian
    ? 'Tra i collezionisti il segnale sembra misto/leggero: buona carta da valutare per gusto e prezzo d’ingresso, non per aspettative garantite.'
    : 'Among collectors the signal looks mixed or light: worth judging by taste and entry price, not by guaranteed upside.';
}

function cardDetailsLine(card, marketplaceCard, italian) {
  const details = [
    card.setName ? (italian ? `set ${card.setName}` : `set ${card.setName}`) : '',
    card.collectorNumber ? (italian ? `numero ${card.collectorNumber}` : `number ${card.collectorNumber}`) : '',
    card.rarity ? card.rarity : '',
    card.artist ? (italian ? `artista ${card.artist}` : `artist ${card.artist}`) : '',
  ].filter(Boolean).join(', ');
  const floorPrice = marketplaceCard?.floorPricePkn ?? card.pricePkn;
  const listingText = floorPrice
    ? (italian
      ? `Prezzo floor/indicativo disponibile: ${formatPkn(floorPrice)} PKN.`
      : `Available floor/indicative price: ${formatPkn(floorPrice)} PKN.`)
    : (italian
      ? 'Non vedo un floor price affidabile in questo momento.'
      : 'I do not see a reliable floor price right now.');
  const supplyText = marketplaceCard?.activeListingCount
    ? (italian
      ? `Listing attivi: ${marketplaceCard.activeListingCount}.`
      : `Active listings: ${marketplaceCard.activeListingCount}.`)
    : '';
  return [
    details ? (italian ? `Contesto: ${details}.` : `Context: ${details}.`) : '',
    listingText,
    supplyText,
  ].filter(Boolean).join(' ');
}

function contextualCardOpinionReply({ card, marketplaceCard, sentiment, italian }) {
  const name = currentCardDisplayName({
    title: card.title || marketplaceCard?.name,
    setName: card.setName || marketplaceCard?.setName,
    collectorNumber: card.collectorNumber || marketplaceCard?.collectorNumber,
    rarity: card.rarity || marketplaceCard?.rarity,
  });
  if (italian) {
    return [
      `Su ${name}: la vedrei più come carta da collezione forte che come “investimento” puro.`,
      'Non è consulenza finanziaria: sulle Pokémon card eviterei previsioni secche e guarderei prezzo d’ingresso, condizione, liquidità e quanto ti piace davvero tenerla.',
      cardDetailsLine(card, marketplaceCard, true),
      communitySentimentLine(sentiment, true),
      'Per me il ragionamento pratico è: se la prendi in buona condizione, a un prezzo vicino ai comparabili venduti/floor realistico, e ti piace l’artwork, ha senso. Se la compri solo sperando che salga, starei più cauto.',
    ].filter(Boolean).join('\n\n');
  }
  return [
    `On ${name}: I would treat it more as a strong collector card than a pure “investment”.`,
    'Not financial advice: with Pokémon cards I would avoid hard price predictions and focus on entry price, condition, liquidity, and whether you actually want to hold it.',
    cardDetailsLine(card, marketplaceCard, false),
    communitySentimentLine(sentiment, false),
    'My practical take: if the copy is clean, priced close to real sold comps or a realistic floor, and you like the artwork, it can make sense. If the only reason is guaranteed upside, I would be more cautious.',
  ].filter(Boolean).join('\n\n');
}

async function currentCardOpinionDelivery({ message, page, pageContext }) {
  if (!looksLikeCurrentCardOpinionValueQuestion(message, page, pageContext)) {
    return null;
  }
  const card = enrichedPageCardContext(page, pageContext);
  const language = marketplaceLanguageFromPage(pageUrlFromContext(page, pageContext));
  const italian = isItalianMessage(message) || language === 'it';
  const cards = await resolveMarketplaceCards({
    query: card.title,
    cardId: card.cardId,
    language,
    limit: 1,
  }).catch(() => []);
  const marketplaceCard = cards[0] || null;
  const sentiment = await fetchCommunitySentiment({
    ...card,
    title: card.title || marketplaceCard?.name || '',
    setName: card.setName || marketplaceCard?.setName || '',
    collectorNumber: card.collectorNumber || marketplaceCard?.collectorNumber || '',
  });
  return {
    reply: contextualCardOpinionReply({ card, marketplaceCard, sentiment, italian }),
    intent: 'card-context-opinion',
    source: 'current-card-context',
    actions: marketplaceCard?.path ? [{
      type: 'navigate',
      path: marketplaceCard.path,
      label: italian ? `Apri ${marketplaceCard.name || 'carta'}` : `Open ${marketplaceCard.name || 'card'}`,
      reason: 'current_card_context',
      data: { cardId: marketplaceCard.cardId, grounded: true },
    }] : [],
    marketplaceContext: {
      type: 'current_card_opinion',
      card,
      cardMatch: marketplaceCard,
      communitySentiment: sentiment,
    },
  };
}

function isShortMarketplaceFollowUp(message) {
  const text = normalizeIntentText(message).replace(/[?!.,]+/g, ' ').trim();
  const terms = text.split(/\s+/).filter(Boolean);
  if (terms.length === 0 || terms.length > 4) {
    return false;
  }
  return !marketplaceIntentFromText(text) && !/\b(yes|no|ok|thanks|ciao|hi|hello)\b/.test(text);
}

function previousMarketplaceIntent(chatRecord) {
  for (let index = chatRecord.length - 1; index >= 0; index -= 1) {
    const entry = chatRecord[index];
    if (entry.role !== 'user') continue;
    const intent = marketplaceIntentFromText(normalizeIntentText(entry.text));
    if (intent) {
      return intent;
    }
  }
  return null;
}

function cleanExplicitCardSubject(value) {
  const subject = String(value || '')
    .replace(/\b(a|an|the|some|one|una|un|uno|la|il|lo|le|l)\b/g, ' ')
    .replace(/\b(please|pls|per favore|grazie|thanks)\b/g, ' ')
    .replace(/\b(card|cards|carta|carte|pokemon|pokémon)\b/g, ' ')
    .replace(/\b(on|in|for|of|di|del|della|dello|dei|degli|delle|su|nel|nella)\b/g, ' ')
    .replace(/\b(most expensive|highest price|highest priced|priciest|top price|costliest|floor price|floor|lowest price|lowest ask|cheapest|minimum price|best deal|good deal|underpriced|hot|popular|trending)\b/g, ' ')
    .replace(/\b(piu costosa|piu caro|piu cara|prezzo piu alto|la piu costosa|prezzo minimo|meno cara|meno costosa|affare|miglior prezzo|popolari|tendenza)\b/g, ' ')
    .replace(/\b(cute|kawaii|carina|carino|bella|bello|cozy|dolce|sweet|illustration|illustrator|art|artwork|artist|illustrazione|arte|disegno|popular|popolare|economica|economico|budget|cheap|premium|tipo|like|ma|but)\b/g, ' ')
    .replace(/[^a-z0-9/\s-]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  const genericSubjectWords = new Set([
    'cute', 'random', 'nice', 'cool', 'beautiful', 'pretty', 'cozy', 'sweet', 'fun',
    'favorite', 'favourite', 'illustration', 'illustrator', 'art', 'artwork',
    'carina', 'carino', 'bella', 'bello', 'casuale', 'preferita', 'preferito',
    'ice', 'icy', 'snow', 'frozen', 'ghiaccio', 'freddo', 'neve', 'gelato',
    'fire', 'fuoco', 'dragon', 'drago',
  ]);
  const words = subject.split(/\s+/).filter(Boolean);
  if (words.length > 0 && words.every((word) => genericSubjectWords.has(word))) {
    return '';
  }
  return cleanText(subject, 120);
}

function explicitCardSubjectFromMessage(message) {
  const text = normalizeIntentText(message)
    .replace(/\bpokémon\b/g, 'pokemon')
    .replace(/[?!.,;:]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (!text) {
    return '';
  }
  const patterns = [
    /\b(?:fammi vedere|mi fai vedere|mostrami|mostra mi|aprimi|apri|trovami|trova)\s+(?:una|un|la|il|lo|l|le|dei|delle|qualche)?\s*(?:carta|carte|card|cards)?\s*(?:di|del|della|dello|dei|degli|delle)?\s+([a-z0-9][a-z0-9\s/-]{1,80})$/,
    /\b(?:show me|show|open|find me|find|look up|search for)\s+(?:a|an|the|some)?\s*(?:card|cards)?\s*(?:of|for)?\s+([a-z0-9][a-z0-9\s/-]{1,80})$/,
    /\b(?:show me|show|open|find me|find|look up|search for)\s+([a-z0-9][a-z0-9\s/-]{1,80}?)\s+(?:card|cards)\b/,
    /\b(?:carta|carte|card|cards)\s+(?:di|of|for)\s+([a-z0-9][a-z0-9\s/-]{1,80})$/,
  ];
  for (const pattern of patterns) {
    const match = text.match(pattern);
    const subject = cleanExplicitCardSubject(match?.[1] || '');
    if (subject) {
      return subject;
    }
  }
  return '';
}

function stripMarketplaceActionPhrases(text) {
  return String(text || '')
    .replace(/\b(fammi vedere|mi fai vedere|mostrami|mostra mi|show me|find me|open me|card of|cards of|card for|cards for|carta di|carte di|carta per|carte per)\b/g, ' ');
}

function extractMarketplaceSubject(message, intent, page, pageContext = {}) {
  const original = cleanText(message, 240);
  const text = normalizeIntentText(original)
    .replace(/\b(chaizard|charzard)\b/g, 'charizard')
    .replace(/\bpokémon\b/g, 'pokemon');
  const currentCard = pageCardContext(page, pageContext);
  if (/\b(this|current|questa|questo)\b/.test(text) && currentCard.cardId) {
    return { query: cleanText(currentCard.title, 120), cardId: currentCard.cardId };
  }
  if (pageContext.searchQuery && /\b(this search|current search|questa ricerca|questi risultati|these results)\b/.test(text)) {
    return { query: cleanText(pageContext.searchQuery, 120), cardId: '' };
  }
  const explicitSubject = explicitCardSubjectFromMessage(text);
  if (explicitSubject) {
    return { query: explicitSubject, cardId: '' };
  }
  let query = stripMarketplaceActionPhrases(text)
    .replace(/\b(most expensive|expensive|highest price|highest priced|priciest|top price|costliest|floor price|floor|lowest price|lowest ask|cheapest|minimum price|best deal|good deal|underpriced|hot|popular|trending|analytics|signals?|best sellers?|featured|views?|searches?|clicks?)\b/g, ' ')
    .replace(/\b(piu costosa|piu caro|piu cara|prezzo piu alto|la piu costosa|prezzo minimo|meno cara|meno costosa|affare|miglior prezzo|popolari|tendenza)\b/g, ' ')
    .replace(/\b(show|find|open|resolve|look up|search|what|which|who|is|are|the|a|an|me|please|on|in|for|of|pokoin|marketplace|seller|active|listing|listings|price|ask|card|cards|pokemon|carta|carte|consiglia|suggerisci|trova|cerca|mostra|mostrami|fammi|vedere|qual|quale|e|la|il|lo|l|le|gli|un|una|uno|di|del|della|dello|dei|degli|delle|per|su|nel|nella|piu)\b/g, ' ')
    .replace(/[^a-z0-9/\s]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (!query && currentCard.cardId && intent?.kind !== 'analytics') {
    return { query: cleanText(currentCard.title, 120), cardId: currentCard.cardId };
  }
  if (!query && pageContext.searchQuery) {
    return { query: cleanText(pageContext.searchQuery, 120), cardId: '' };
  }
  return { query: cleanText(query, 120), cardId: '' };
}

function marketplaceRequestFromMessage({ message, chatRecord = [], page, pageContext = {} }) {
  const normalized = normalizeIntentText(message);
  let intent = marketplaceIntentFromText(normalized);
  let effectiveMessage = message;
  if (!intent && isShortMarketplaceFollowUp(message)) {
    const previousIntent = previousMarketplaceIntent(chatRecord);
    if (previousIntent) {
      intent = previousIntent;
      effectiveMessage = `${previousIntent.mode === 'floor' ? 'floor price' : previousIntent.mode === 'best_deal' ? 'best deal' : 'most expensive'} ${message} card`;
    }
  }
  if (!intent) {
    return null;
  }
  const subject = extractMarketplaceSubject(effectiveMessage, intent, page, pageContext);
  return {
    ...intent,
    query: subject.query,
    cardId: subject.cardId,
    effectiveMessage,
  };
}

function marketplaceCardFromRow(row, language = 'en') {
  const cardId = String(row.card_id ?? row.blueprint_id ?? '');
  const name = row.card_name || row.display_name || row.canonical_name || row.name || '';
  const path = canonicalMarketplacePath({
    ...row,
    card_id: cardId,
    card_name: name,
    collector_number: row.collector_number || row.card_number,
  }, language);
  return {
    cardId,
    name,
    setName: row.set_name || '',
    collectorNumber: row.collector_number || row.card_number || '',
    rarity: row.rarity || '',
    path,
    url: path ? `https://pokoin.com${path}` : '',
    activeListingCount: Number(row.active_listing_count || row.listing_count || 0),
    listedQuantity: Number(row.listed_quantity || 0),
    floorPricePkn: row.lowest_ask_pkn == null ? null : Number(row.lowest_ask_pkn),
    hotScore24h: Number(row.hot_score_24h || 0),
    views24h: Number(row.views_24h || 0),
    searches24h: Number(row.searches_24h || 0),
    clicks24h: Number(row.clicks_24h || 0),
  };
}

function recommendationIntentFromMessage(message = '', chatRecord = []) {
  const text = normalizeIntentText(message).replace(/\bpokémon\b/g, 'pokemon');
  const currentText = normalizeIntentText(message);
  const contextText = cardSuggestionContextText(message, chatRecord);
  const explicitSubject = explicitCardSubjectFromMessage(text);
  const subject = cleanText(explicitSubject || extractRecommendationSubject(text), 120);
  const theme = detectCardSuggestionTheme(message, []);
  const styles = [];
  const addStyle = (style) => {
    if (!styles.includes(style)) styles.push(style);
  };
  if (/\b(cute|kawaii|carina|carino|bella|bello|cozy|dolce|sweet)\b/.test(currentText)) addStyle('cute');
  if (/\b(illustration|illustrator|art|artwork|artist|illustrazione|arte|disegno)\b/.test(currentText)) addStyle('illustration');
  if (/\b(popular|hot|trending|best sellers?|views?|searches?|clicks?|popolari|tendenza|forte)\b/.test(currentText)) addStyle('popular');
  if (/\b(cheap|budget|economica|economico|meno cara|spendere poco|low cost)\b/.test(currentText)) addStyle('budget');
  if (/\b(expensive|premium|costosa|costoso|chase)\b/.test(currentText)) addStyle('premium');
  if (theme?.id === 'ice_cream') addStyle('ice');
  const wantsRecommendation = (looksLikeCardSuggestionRequest(text) && /\b(card|cards|carta|carte)\b/.test(text)) ||
    explicitSubject ||
    /\b(show|find|open|recommend|suggest|pick|choose|consiglia|suggerisci|fammi|vedere|mostrami|trova|cerca)\b/.test(text) &&
      /\b(card|cards|carta|carte|pokemon|cute|carina|deck)\b/.test(text);
  if (!wantsRecommendation || /\bdeck\b/.test(text)) {
    return null;
  }
  const hasOnlyGenericCuteStyle = !subject &&
    !theme &&
    styles.length > 0 &&
    styles.every((style) => style === 'cute' || style === 'illustration');
  if (hasOnlyGenericCuteStyle) {
    const recentPreferences = inferUserPreferences({ message, chatRecord });
    if (!recentPreferences.favoritePokemon.length && !recentPreferences.likesBudget && recentPreferences.deckStyle === '') {
      return null;
    }
  }
  return {
    subject,
    themeId: theme?.id || '',
    themeLabel: theme?.label || '',
    styles,
    budget: styles.includes('budget') ? 'budget' : styles.includes('premium') ? 'premium' : '',
    explicitSubject: Boolean(explicitSubject),
  };
}

function extractRecommendationSubject(text) {
  let query = stripMarketplaceActionPhrases(text)
    .replace(/\b(cute|kawaii|carina|carino|bella|bello|cozy|dolce|sweet|illustration|illustrator|art|artwork|artist|illustrazione|arte|disegno|popular|hot|trending|best sellers?|views?|searches?|clicks?|popolari|tendenza|cheap|budget|economica|economico|meno cara|spendere poco|low cost|premium|expensive|costosa|costoso|chase|show|find|open|recommend|suggest|pick|choose|consiglia|consigliami|suggerisci|suggeriscimi|fammi|vedere|mostrami|trova|trovami|cerca|card|cards|carta|carte|pokemon|una|un|a|an|the|di|of|for|tipo|like|ma|but)\b/g, ' ')
    .replace(/[^a-z0-9/\s-]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  const generic = new Set(['ice', 'ghiaccio', 'gelato', 'fire', 'fuoco', 'dragon', 'drago']);
  const words = query.split(/\s+/).filter((word) => word && !generic.has(word));
  return words.join(' ');
}

function themeSeedQueries(intent, preferences = {}) {
  const seeds = [];
  if (intent.subject) seeds.push(intent.subject);
  if (intent.themeId === 'ice_cream' || intent.styles.includes('ice')) {
    seeds.push('Vanillite', 'Vanillish', 'Vanilluxe', 'Alolan Vulpix', 'Snom', 'Lapras');
  }
  for (const pokemon of preferences.favoritePokemon || []) {
    seeds.push(pokemon);
  }
  return uniqueLimited(seeds, 8);
}

function recommendationCardFromRow(row, language = 'en') {
  const card = marketplaceCardFromRow(row, language);
  return {
    ...card,
    score: Number(row.recommendation_score || 0),
    artist: row.artist || row.illustrator || '',
    types: Array.isArray(row.types) ? row.types : [],
    flavorText: row.flavor_text || '',
    cardtraderCheapestPkn: row.cardtrader_cheapest_pkn == null ? null : Number(row.cardtrader_cheapest_pkn),
    cardtraderEligibleListings: Number(row.cardtrader_eligible_listing_count || 0),
    sales24h: Number(row.sales_24h || 0),
    cartAdds24h: Number(row.cart_adds_24h || 0),
  };
}

async function queryCardRecommendations({
  subject = '',
  theme = '',
  styles = [],
  budget = '',
  language = 'en',
  userPreferences = {},
  limit = 5,
} = {}) {
  const cleanSubject = cleanText(subject, 120);
  const cleanTheme = cleanText(theme, 60);
  const cleanStyles = uniqueLimited(styles, 8);
  const seeds = themeSeedQueries({ subject: cleanSubject, themeId: cleanTheme, styles: cleanStyles }, userPreferences);
  const values = [
    cleanSubject,
    cleanTheme,
    cleanStyles,
    budget,
    seeds,
    cleanText((userPreferences.favoritePokemon || [])[0] || '', 80),
    Math.min(Math.max(Number(limit) || 5, 1), 10),
  ];
  const result = await marketplaceAssistantQuery(
    `
      with input as (
        select
          lower($1::text) as subject,
          lower($2::text) as theme,
          $3::text[] as styles,
          lower($4::text) as budget,
          $5::text[] as seeds,
          lower($6::text) as favorite,
          $7::integer as clean_limit
      ),
      seed_terms as (
        select lower(unnest(input.seeds)) as value from input
      ),
      candidates as (
        select
          c.card_id,
          coalesce(nullif(c.display_name, ''), nullif(c.canonical_name, ''), c.name) as card_name,
          c.display_name,
          c.canonical_name,
          c.name,
          c.set_name,
          c.card_number,
          c.rarity,
          c.search_text,
          c.search_weight,
          c.card_type,
          c.product_type,
          c.item_kind,
          urls.canonical_path,
          summary.lowest_ask_pkn,
          summary.active_listing_count,
          summary.listed_quantity,
          hot.views_24h,
          hot.searches_24h,
          hot.clicks_24h,
          hot.cart_adds_24h,
          hot.sales_24h,
          hot.hot_score_24h,
          cache.cheapest_price_pkn as cardtrader_cheapest_pkn,
          cache.eligible_listing_count as cardtrader_eligible_listing_count,
          artists.artist,
          artists.illustrator,
          metadata.types,
          metadata.flavor_text,
          (
            case
              when input.subject <> '' and lower(coalesce(nullif(c.display_name, ''), nullif(c.canonical_name, ''), c.name, '')) = input.subject then 800
              when input.subject <> '' and lower(coalesce(c.name, '')) = input.subject then 760
              when input.subject <> '' and lower(coalesce(c.search_text, c.name, '')) like '%' || input.subject || '%' then 560
              else 0
            end
            + case when input.favorite <> '' and lower(coalesce(c.search_text, c.name, '')) like '%' || input.favorite || '%' then 180 else 0 end
            + case when exists (select 1 from seed_terms where seed_terms.value <> '' and lower(coalesce(c.search_text, c.name, '')) like '%' || seed_terms.value || '%') then 420 else 0 end
            + case when 'illustration' = any(input.styles) and lower(coalesce(c.rarity, '')) like '%illustration%' then 140 else 0 end
            + case when 'cute' = any(input.styles) and (
                lower(coalesce(c.rarity, '')) like '%illustration%'
                or lower(coalesce(metadata.flavor_text, '')) ~ '(cute|tiny|sweet|play|friend|sleep|snow|dream|happy)'
                or lower(coalesce(c.name, '')) ~ '(mew|eevee|pikachu|snom|vulpix|vanillite|leafeon)'
              ) then 110 else 0 end
            + case when input.theme = 'ice_cream' and (
                lower(coalesce(c.search_text, c.name, '')) ~ '(vanillite|vanillish|vanilluxe|snom|lapras|vulpix|ice|snow|frost)'
                or lower(coalesce(metadata.types::text, '')) like '%water%'
              ) then 260 else 0 end
            + case when 'popular' = any(input.styles) then least(coalesce(hot.hot_score_24h, 0), 250) else least(coalesce(hot.hot_score_24h, 0), 80) end
            + case when input.budget = 'budget' and coalesce(summary.lowest_ask_pkn, cache.cheapest_price_pkn, 999999999) <= 500 then 120 else 0 end
            + case when input.budget = 'premium' and coalesce(summary.lowest_ask_pkn, cache.cheapest_price_pkn, 0) >= 1000 then 80 else 0 end
            + case when coalesce(summary.active_listing_count, 0) > 0 then 60 else 0 end
            + case when coalesce(cache.eligible_listing_count, 0) > 0 then 35 else 0 end
            + least(coalesce(c.search_weight, 0) / 100, 80)
          )::numeric as recommendation_score
        from public.marketplace_search_candidates c
        cross join input
        left join public.marketplace_card_urls urls on urls.card_id = c.card_id
        left join public.marketplace_blueprint_price_summary summary on summary.blueprint_id = c.card_id
        left join public.marketplace_hot_blueprints hot on hot.blueprint_id = c.card_id
        left join public.cardtrader_blueprint_listing_cache cache on cache.blueprint_id = c.card_id
        left join public.marketplace_blueprint_artists artists on artists.blueprint_id = c.card_id
        left join public.marketplace_blueprint_tcg_metadata metadata on metadata.blueprint_id = c.card_id
        where c.item_kind = 'single'
          and (
            input.subject <> ''
            or input.theme <> ''
            or array_length(input.styles, 1) is not null
            or input.favorite <> ''
          )
          and (
            input.subject = ''
            or lower(coalesce(c.search_text, c.name, '')) like '%' || input.subject || '%'
            or exists (select 1 from seed_terms where seed_terms.value <> '' and lower(coalesce(c.search_text, c.name, '')) like '%' || seed_terms.value || '%')
          )
      )
      select *
      from candidates
      where recommendation_score > 0
      order by
        case when $1::text <> '' and lower(coalesce(card_name, name, '')) = lower($1::text) then 0 else 1 end,
        recommendation_score desc,
        active_listing_count desc nulls last,
        hot_score_24h desc nulls last,
        card_id desc
      limit (select clean_limit from input)
    `,
    values,
  );
  return result.rows.map((row) => recommendationCardFromRow(row, language));
}

async function resolveMarketplaceCards({ query, cardId, language = 'en', limit = 5 }) {
  const { marketplaceQuery } = getMarketplaceDbHelper();
  const values = [cleanText(query, 120), cleanText(cardId, 80), Math.min(Math.max(Number(limit) || 5, 1), 10)];
  const result = await marketplaceQuery(
    `
      with input as (
        select
          lower($1::text) as q,
          $2::text as card_id,
          $3::integer as clean_limit
      )
      select
        candidates.card_id,
        coalesce(nullif(candidates.display_name, ''), nullif(candidates.canonical_name, ''), candidates.name) as card_name,
        candidates.display_name,
        candidates.canonical_name,
        candidates.name,
        candidates.set_name,
        candidates.card_number,
        candidates.rarity,
        urls.canonical_path,
        summary.lowest_ask_pkn,
        summary.active_listing_count,
        summary.listed_quantity,
        hot.views_24h,
        hot.searches_24h,
        hot.clicks_24h,
        hot.hot_score_24h
      from public.marketplace_search_candidates candidates
      cross join input
      left join public.marketplace_card_urls urls
        on urls.card_id = candidates.card_id
      left join public.marketplace_blueprint_price_summary summary
        on summary.blueprint_id = candidates.card_id
      left join public.marketplace_hot_blueprints hot
        on hot.blueprint_id = candidates.card_id
      where (
        input.card_id <> '' and candidates.card_id::text = input.card_id
      ) or (
        input.card_id = ''
        and input.q <> ''
        and (
          lower(coalesce(nullif(candidates.display_name, ''), nullif(candidates.canonical_name, ''), candidates.name, '')) like '%' || input.q || '%'
          or lower(coalesce(candidates.name, '')) like '%' || input.q || '%'
          or lower(coalesce(candidates.set_name, '')) like '%' || input.q || '%'
          or lower(coalesce(candidates.card_number, '')) = input.q
        )
      )
      order by
        case
          when input.card_id <> '' then 0
          when lower(coalesce(nullif(candidates.display_name, ''), nullif(candidates.canonical_name, ''), candidates.name, '')) = input.q then 0
          when lower(coalesce(candidates.name, '')) = input.q then 1
          when lower(coalesce(nullif(candidates.display_name, ''), nullif(candidates.canonical_name, ''), candidates.name, '')) like input.q || '%' then 2
          else 3
        end,
        coalesce(summary.active_listing_count, 0) desc,
        candidates.search_weight desc,
        candidates.card_id desc
      limit (select clean_limit from input)
    `,
    values,
  );
  return result.rows.map((row) => marketplaceCardFromRow(row, language));
}

async function activeListingGrounding(request, language = 'en') {
  const { marketplaceQuery } = getMarketplaceDbHelper();
  const values = [
    request.query ? `%${request.query}%` : '',
    cleanText(request.cardId, 80),
    request.mode === 'highest' ? 'desc' : 'asc',
  ];
  const result = await marketplaceQuery(
    `
      with input as (
        select
          $1::text as q,
          $2::text as card_id,
          $3::text as direction
      )
      select
        listings.id as listing_id,
        listings.card_id,
        coalesce(nullif(listings.card_name, ''), nullif(candidates.display_name, ''), nullif(candidates.canonical_name, ''), candidates.name) as card_name,
        listings.price_pkn,
        listings.quantity_available,
        listings.condition,
        listings.language,
        listings.foil_state,
        listings.graded,
        listings.grade,
        listings.seller_name,
        coalesce(nullif(listings.set_name, ''), candidates.set_name) as set_name,
        coalesce(nullif(listings.collector_number, ''), candidates.card_number) as collector_number,
        candidates.name,
        candidates.rarity,
        urls.canonical_path,
        summary.lowest_ask_pkn,
        summary.active_listing_count,
        summary.listed_quantity,
        hot.views_24h,
        hot.searches_24h,
        hot.clicks_24h,
        hot.hot_score_24h
      from public.marketplace_user_listings listings
      cross join input
      left join public.marketplace_search_candidates candidates
        on candidates.card_id::text = listings.card_id::text
      left join public.marketplace_card_urls urls
        on urls.card_id::text = listings.card_id::text
      left join public.marketplace_blueprint_price_summary summary
        on summary.blueprint_id::text = listings.card_id::text
      left join public.marketplace_hot_blueprints hot
        on hot.blueprint_id::text = listings.card_id::text
      where listings.status = 'active'
        and listings.quantity_available > 0
        and listings.price_pkn > 0
        and (
          input.card_id <> '' and listings.card_id::text = input.card_id
          or input.card_id = '' and (
            input.q = ''
            or lower(coalesce(listings.card_name, candidates.display_name, candidates.canonical_name, candidates.name, '')) like lower(input.q)
            or lower(coalesce(candidates.set_name, '')) like lower(input.q)
          )
        )
      order by
        case when input.direction = 'desc' then listings.price_pkn end desc,
        case when input.direction <> 'desc' then listings.price_pkn end asc,
        listings.updated_at desc nulls last,
        listings.created_at desc nulls last
      limit 1
    `,
    values,
  );
  const listing = result.rows[0] || null;
  const cards = listing ? [] : await resolveMarketplaceCards({
    query: request.query,
    cardId: request.cardId,
    language,
    limit: 3,
  }).catch(() => []);
  return {
    type: 'active_listing',
    mode: request.mode,
    query: request.query,
    cardId: request.cardId,
    listing,
    cards,
  };
}

async function analyticsGrounding(request, language = 'en') {
  const { marketplaceQuery } = getMarketplaceDbHelper();
  const result = await marketplaceQuery(
    `
      with input as (
        select lower($1::text) as q, $2::text as card_id
      )
      select
        hot.blueprint_id as card_id,
        hot.name as card_name,
        hot.set_name,
        hot.card_number,
        hot.rarity,
        urls.canonical_path,
        summary.lowest_ask_pkn,
        summary.active_listing_count,
        summary.listed_quantity,
        hot.views_24h,
        hot.searches_24h,
        hot.clicks_24h,
        hot.cart_adds_24h,
        hot.reserves_24h,
        hot.sales_24h,
        hot.hot_score_24h,
        hot.last_event_at,
        hot.refreshed_at
      from public.marketplace_hot_blueprints hot
      cross join input
      left join public.marketplace_card_urls urls
        on urls.card_id = hot.blueprint_id
      left join public.marketplace_blueprint_price_summary summary
        on summary.blueprint_id = hot.blueprint_id
      where hot.hot_score_24h > 0
        and (
          input.card_id <> '' and hot.blueprint_id::text = input.card_id
          or input.card_id = '' and (
            input.q = ''
            or lower(coalesce(hot.name, '')) like '%' || input.q || '%'
            or lower(coalesce(hot.set_name, '')) like '%' || input.q || '%'
            or lower(coalesce(hot.card_number, '')) = input.q
          )
        )
      order by hot.hot_score_24h desc, hot.last_event_at desc nulls last, hot.blueprint_id desc
      limit 5
    `,
    [request.query, request.cardId],
  );
  return {
    type: 'analytics',
    mode: 'hot',
    query: request.query,
    cardId: request.cardId,
    cards: result.rows.map((row) => marketplaceCardFromRow(row, language)),
  };
}

async function cardLookupGrounding(request, language = 'en') {
  const cards = await resolveMarketplaceCards({
    query: request.query,
    cardId: request.cardId,
    language,
    limit: 5,
  });
  return {
    type: 'card_lookup',
    mode: 'suggest',
    query: request.query,
    cardId: request.cardId,
    cards,
  };
}

function noDataMarketplaceReply(grounding) {
  const subject = grounding.query || grounding.cardId || 'that card';
  if (grounding.type === 'active_listing') {
    return `I checked active Pokoin marketplace listings, but I could not find any active listing for ${subject} right now. Source: marketplace_user_listings active listings.`;
  }
  if (grounding.type === 'analytics') {
    return `I checked Pokoin marketplace analytics, but I do not have hot/popularity data for ${subject} right now. Source: marketplace_hot_blueprints.`;
  }
  return `I checked Pokoin marketplace search data, but I could not resolve a direct card page for ${subject} right now.`;
}

function groundedMarketplaceReply(grounding, language = 'en') {
  if (grounding.type === 'active_listing') {
    const row = grounding.listing;
    if (!row) {
      const extra = grounding.cards?.[0]?.url
        ? ` I did find a matching card page: ${grounding.cards[0].url}`
        : '';
      return {
        reply: `${noDataMarketplaceReply(grounding)}${extra}`,
        actions: grounding.cards?.[0]?.path ? [{
          type: 'navigate',
          path: grounding.cards[0].path,
          label: `Open ${grounding.cards[0].name || 'card'}`,
          reason: 'marketplace_no_listing_card_match',
        }] : [],
      };
    }
    const path = canonicalMarketplacePath(row, language);
    const name = row.card_name || row.name || 'this card';
    const modeLabel = grounding.mode === 'floor'
      ? 'lowest active ask'
      : grounding.mode === 'best_deal'
        ? 'lowest active ask I can treat as a deal signal'
        : 'highest-priced active listing';
    const details = [
      row.condition ? `condition ${row.condition}` : '',
      row.language ? `language ${row.language}` : '',
      row.quantity_available ? `quantity ${row.quantity_available}` : '',
      row.seller_name ? `seller ${row.seller_name}` : '',
    ].filter(Boolean).join(', ');
    return {
      reply: [
        `I checked active Pokoin marketplace listings. The ${modeLabel} I found is ${name} at ${formatPkn(row.price_pkn)} PKN${details ? ` (${details})` : ''}.`,
        path ? `Direct card page: https://pokoin.com${path}` : '',
        'Source: marketplace_user_listings active listings and price summary. Not financial advice.',
      ].filter(Boolean).join('\n\n'),
      actions: path ? [{
        type: 'navigate',
        path,
        label: `Open ${name}`,
        reason: `marketplace_${grounding.mode}`,
        data: {
          cardId: String(row.card_id || ''),
          listingId: String(row.listing_id || ''),
          pricePkn: Number(row.price_pkn || 0),
          name,
          grounded: true,
        },
      }] : [],
    };
  }
  if (grounding.type === 'analytics') {
    if (!grounding.cards.length) {
      return { reply: noDataMarketplaceReply(grounding), actions: [] };
    }
    const lines = grounding.cards.slice(0, 3).map((card, index) => {
      const signals = `${card.views24h} views, ${card.searches24h} searches, ${card.clicks24h} clicks in 24h`;
      const price = card.floorPricePkn == null ? 'no active floor price' : `floor ${formatPkn(card.floorPricePkn)} PKN`;
      return `${index + 1}. ${card.name}${card.setName ? ` (${card.setName})` : ''}: hot score ${formatPkn(card.hotScore24h)}, ${signals}, ${price}${card.url ? `\n${card.url}` : ''}`;
    });
    const first = grounding.cards[0];
    return {
      reply: [
        `I checked Pokoin marketplace analytics${grounding.query ? ` for ${grounding.query}` : ''}.`,
        ...lines,
        'Source: marketplace_hot_blueprints plus active listing price summary. This is marketplace activity, not financial advice.',
      ].join('\n\n'),
      actions: first?.path ? [{
        type: 'navigate',
        path: first.path,
        label: `Open ${first.name || 'top card'}`,
        reason: 'marketplace_hot_blueprint',
        data: { cardId: first.cardId, grounded: true },
      }] : [],
    };
  }
  if (!grounding.cards.length) {
    return { reply: noDataMarketplaceReply(grounding), actions: [] };
  }
  const card = grounding.cards[0];
  return {
    reply: [
      `I resolved the best marketplace card match: ${card.name}${card.setName ? ` (${card.setName})` : ''}${card.collectorNumber ? ` ${card.collectorNumber}` : ''}.`,
      card.url ? `Direct card page: ${card.url}` : '',
      card.floorPricePkn == null
        ? 'I do not see an active floor price for it right now.'
        : `Current floor from active listings: ${formatPkn(card.floorPricePkn)} PKN.`,
      'Source: marketplace_search_candidates, marketplace_card_urls, and price summary. Not financial advice.',
    ].filter(Boolean).join('\n\n'),
    actions: card.path ? [{
      type: 'navigate',
      path: card.path,
      label: `Open ${card.name || 'card'}`,
      reason: 'marketplace_card_lookup',
      data: { cardId: card.cardId, grounded: true },
    }] : [],
  };
}

function recommendationReply({ intent, cards, language = 'en', preferences = {} }) {
  if (!cards.length) {
    return {
      reply: 'I checked the read-only Pokoin marketplace card, URL, hotness, listing, stock, price, artist, and partner availability tables, but I could not resolve a safe direct card recommendation for that request.',
      actions: [],
    };
  }
  const italian = language === 'it' || preferences.language === 'it' || isItalianMessage(intent.subject || '');
  const card = cards[0];
  const signals = [
    card.hotScore24h ? `hot score ${formatPkn(card.hotScore24h)}` : '',
    card.views24h ? `${card.views24h} views` : '',
    card.searches24h ? `${card.searches24h} searches` : '',
    card.clicks24h ? `${card.clicks24h} clicks` : '',
    card.sales24h ? `${card.sales24h} sales/resolved sale signals` : '',
    card.activeListingCount ? `${card.activeListingCount} active Pokoin listings` : '',
    card.cardtraderEligibleListings ? `${card.cardtraderEligibleListings} partner availability listings` : '',
  ].filter(Boolean).join(', ');
  const price = card.floorPricePkn == null && card.cardtraderCheapestPkn == null
    ? (italian ? 'Non vedo un floor affidabile ora.' : 'I do not see a reliable floor right now.')
    : (italian
      ? `Prezzo/floor indicativo: ${formatPkn(card.floorPricePkn ?? card.cardtraderCheapestPkn)} PKN.`
      : `Indicative floor/price: ${formatPkn(card.floorPricePkn ?? card.cardtraderCheapestPkn)} PKN.`);
  const why = intent.explicitSubject
    ? (italian ? `Ho rispettato prima il soggetto esplicito: ${intent.subject}.` : `I prioritized your explicit subject first: ${intent.subject}.`)
    : intent.themeLabel
      ? (italian ? `Tema: ${intent.themeLabel}.` : `Theme match: ${intent.themeLabel}.`)
      : preferences.favoritePokemon?.length
        ? (italian ? `Lo sto anche tarando sui tuoi gusti recenti: ${preferences.favoritePokemon.join(', ')}.` : `I am also biasing this toward your recent taste: ${preferences.favoritePokemon.join(', ')}.`)
        : (italian ? 'Ho scelto usando pertinenza, disponibilità e segnali marketplace.' : 'I picked this using relevance, availability, and marketplace signals.');
  return {
    reply: [
      italian
        ? `Ti apro ${card.name}${card.setName ? ` (${card.setName})` : ''}${card.collectorNumber ? ` ${card.collectorNumber}` : ''}.`
        : `I am opening ${card.name}${card.setName ? ` (${card.setName})` : ''}${card.collectorNumber ? ` ${card.collectorNumber}` : ''}.`,
      why,
      price,
      signals ? (italian ? `Segnali letti: ${signals}.` : `Signals used: ${signals}.`) : '',
      card.artist ? (italian ? `Artista: ${card.artist}.` : `Artist: ${card.artist}.`) : '',
      card.url ? `https://pokoin.com${card.path}` : '',
      italian
        ? 'Fonte: peer4/read-only marketplace site data (search candidates, canonical URLs, hotness, listing/stock/price summary, artists, partner availability). Non è consulenza finanziaria.'
        : 'Source: peer4/read-only marketplace site data (search candidates, canonical URLs, hotness, listing/stock/price summary, artists, partner availability). Not financial advice.',
    ].filter(Boolean).join('\n\n'),
    actions: card.path ? [{
      type: 'navigate',
      path: card.path,
      label: italian ? `Apri ${card.name || 'carta'}` : `Open ${card.name || 'card'}`,
      reason: 'marketplace_recommendation',
      data: {
        cardId: card.cardId,
        grounded: true,
        direct: true,
        recommendationScore: card.score,
      },
    }] : [],
  };
}

async function recommendationGroundedDelivery({ message, chatRecord, page, pageContext, userPreferences = {} }) {
  const intent = recommendationIntentFromMessage(message, chatRecord);
  if (!intent) return null;
  if (intent.explicitSubject && !intent.themeId && intent.styles.length === 0) {
    return null;
  }
  const language = marketplaceLanguageFromPage(pageUrlFromContext(page, pageContext));
  const cards = await queryCardRecommendations({
    subject: intent.subject,
    theme: intent.themeId,
    styles: intent.styles,
    budget: intent.budget,
    language,
    userPreferences,
    limit: 5,
  });
  if (!cards.length && intent.subject) {
    return null;
  }
  const response = recommendationReply({ intent, cards, language, preferences: userPreferences });
  return {
    reply: response.reply,
    intent: 'card-recommendation',
    source: 'peer4-readonly-recommendation',
    actions: response.actions,
    grounding: {
      type: 'card_recommendation',
      intent,
      cards,
      readOnly: true,
    },
  };
}

async function marketplaceGroundedDelivery({ message, chatRecord, page, pageContext }) {
  const request = marketplaceRequestFromMessage({ message, chatRecord, page, pageContext });
  if (!request) {
    return null;
  }
  const language = marketplaceLanguageFromPage(pageUrlFromContext(page, pageContext));
  let grounding;
  if (request.kind === 'active_listing') {
    grounding = await activeListingGrounding(request, language);
  } else if (request.kind === 'analytics') {
    grounding = await analyticsGrounding(request, language);
  } else {
    grounding = await cardLookupGrounding(request, language);
  }
  const response = groundedMarketplaceReply(grounding, language);
  return {
    reply: response.reply,
    intent: request.kind === 'analytics' ? 'marketplace-analytics' : 'marketplace',
    source: 'marketplace-grounding',
    actions: response.actions || [],
    grounding: {
      ...grounding,
      listing: grounding.listing ? {
        ...grounding.listing,
        price_pkn: Number(grounding.listing.price_pkn || 0),
      } : null,
    },
  };
}

function expensiveCardLookupRequest(message) {
  const request = marketplaceRequestFromMessage({ message, chatRecord: [], page: '', pageContext: {} });
  if (!request || request.kind !== 'active_listing' || request.mode !== 'highest') {
    return null;
  }
  return { name: request.query, query: request.query, cardId: request.cardId };
}

async function mostExpensiveCardTool({ message, page, chatRecord = [], pageContext = {} }) {
  const delivery = await marketplaceGroundedDelivery({ message, chatRecord, page, pageContext });
  if (!delivery || delivery.intent !== 'marketplace') {
    return null;
  }
  return delivery;
}

function looksLikeDeckAdvisorRequest(message = '') {
  const text = normalizeIntentText(message).replace(/\bpokémon\b/g, 'pokemon');
  return /\b(deck|decklist|archetype|meta|competitive|competitivo|mazzo|mazzi|limitless|gardevoir|charizard)\b/.test(text) &&
    /\b(best|choose|play|recommend|suggest|beginners?|budget|cheap|economico|economica|facile|forte|competitive|competitivo|works|funziona|strengths?|weaknesses?|debolezze|consiglia|scegliere|giocare|deck|mazzo)\b/.test(text);
}

function deckAdvisorIntentFromMessage(message = '', chatRecord = []) {
  if (!looksLikeDeckAdvisorRequest(message)) return null;
  const text = normalizeIntentText(message).replace(/\bpokémon\b/g, 'pokemon');
  const prefs = inferUserPreferences({ message, chatRecord });
  const deckMatch = text.match(/\b(gardevoir|charizard|dragapult|miraidon|chien pao|roaring moon|lost box|lugia|snorlax|ancient box|future box|raging bolt|gholdengo|greninja|zoroark|regidrago)(?:\s+ex)?\s+(?:deck|mazzo)?\b/) ||
    text.match(/\b(?:deck|mazzo)\s+(?:di|of)?\s*(gardevoir|charizard|dragapult|miraidon|chien pao|roaring moon|lost box|lugia|snorlax|ancient box|future box|raging bolt|gholdengo|greninja|zoroark)(?:\s+ex)?\b/);
  const deckName = cleanText(deckMatch?.[1] || '', 80);
  return {
    deckName,
    wantsExplanation: /\b(works|funziona|how|come|strengths?|weaknesses?|debolezze|punti forti|punti deboli)\b/.test(text),
    budget: /\b(budget|cheap|economico|economica|low cost|spendere poco)\b/.test(text),
    beginner: /\b(beginners?|facile|easy|principiante|principianti|iniziare|starter)\b/.test(text),
    playstyle: /\b(beginners?|facile|easy|principiante|principianti|iniziare|starter)\b/.test(text) ? 'beginner' : prefs.deckStyle,
    language: isItalianMessage(message) ? 'it' : 'en',
  };
}

function deckCacheKey(intent) {
  return JSON.stringify({
    deckName: intent.deckName,
    budget: intent.budget,
    beginner: intent.beginner,
    playstyle: intent.playstyle,
  });
}

function deckRowToAdvisorDeck(row) {
  return {
    deckId: String(row.deck_id || ''),
    name: row.name || row.archetype || 'Unknown deck',
    format: row.format || '',
    formatLabel: row.format_label || row.format || '',
    rank: row.rank == null ? null : Number(row.rank),
    points: Number(row.points || row.deck_count || 0),
    share: Number(row.share || 0),
    sourceUrl: row.source_url || '',
    featuredDecklistId: row.featured_decklist_id || '',
    featuredTournamentName: row.featured_tournament_name || '',
    featuredTournamentDate: row.featured_tournament_date || null,
    coreCards: Array.isArray(row.core_cards) ? row.core_cards : [],
    recentResults: Array.isArray(row.recent_results) ? row.recent_results : [],
  };
}

function deckArchetypeNotes(deck, intent) {
  const name = normalizeIntentText(deck.name);
  const notes = {
    plan: 'Use the core engine cards to build a stable board, trade prizes efficiently, and keep enough consistency cards to repeat the main attack plan.',
    strengths: ['Established Limitless results give it a real competitive baseline.'],
    weaknesses: ['Matchups and lists change by local meta, so do not treat this as a guaranteed best deck.'],
    complexity: 'medium',
    budgetTier: 'unknown',
  };
  if (/charizard/.test(name)) {
    notes.plan = 'Charizard ex decks usually ramp Fire energy while building a high-HP attacker that gets stronger as the opponent takes prizes.';
    notes.strengths.push('Strong comeback pressure and forgiving attacker durability.');
    notes.weaknesses.push('Can be slower if the setup pieces are prized or disrupted early.');
    notes.complexity = 'medium';
  } else if (/gardevoir/.test(name)) {
    notes.plan = 'Gardevoir ex decks usually trade with Psychic attackers while using the Gardevoir engine to attach energy from the discard pile.';
    notes.strengths.push('Flexible attackers and strong late-game prize mapping.');
    notes.weaknesses.push('More sequencing-heavy than simple beatdown decks.');
    notes.complexity = 'high';
  } else if (/miraidon|raging bolt|turbo|moon/.test(name)) {
    notes.plan = 'This is closer to an aggressive/turbo deck: set up fast, pressure prizes early, and force the opponent to answer immediately.';
    notes.strengths.push('Fast starts and clear proactive game plans.');
    notes.weaknesses.push('Can run out of resources if the first wave is answered cleanly.');
    notes.complexity = 'low-medium';
  } else if (/snorlax|control|stall/.test(name)) {
    notes.plan = 'Control decks try to deny the opponent clean attacks, trap awkward Pokémon, and win through resource management rather than raw damage.';
    notes.strengths.push('Rewards matchup knowledge and can punish unprepared lists.');
    notes.weaknesses.push('Harder for beginners and sometimes less fun for casual/local play.');
    notes.complexity = 'high';
  }
  if (intent.beginner && notes.complexity === 'high') {
    notes.weaknesses.push('Because you asked for beginner-friendly, I would only pick this if you enjoy careful sequencing.');
  }
  if (intent.budget) {
    notes.budgetTier = 'check list price';
    notes.weaknesses.push('Budget depends on exact staples and prints; verify the specific decklist before buying.');
  }
  return notes;
}

async function queryDeckAdvisorData(intent) {
  const cached = deckAdvisorCache.get(deckCacheKey(intent));
  if (cached && Date.now() - cached.createdAt < DECK_ADVISOR_CACHE_TTL_MS) {
    return cached.value;
  }
  const values = [
    cleanText(intent.deckName, 80),
    intent.beginner,
    intent.budget,
    cleanText(intent.playstyle, 40),
  ];
  const result = await marketplaceAssistantQuery(
    `
      with input as (
        select lower($1::text) as deck_name, $2::boolean as beginner, $3::boolean as budget, lower($4::text) as playstyle
      ),
      candidate_decks as (
        select
          d.deck_id,
          d.name,
          d.format,
          d.format_label,
          d.rank,
          d.points,
          d.share,
          d.source_url,
          case
            when input.deck_name <> '' and lower(d.name) like '%' || input.deck_name || '%' then 500
            else 0
          end
          + case when input.beginner and lower(d.name) ~ '(miraidon|charizard|raging bolt|turbo)' then 80 else 0 end
          + case when input.playstyle = 'control' and lower(d.name) ~ '(control|snorlax|stall)' then 120 else 0 end
          + case when input.playstyle = 'aggressive' and lower(d.name) ~ '(miraidon|turbo|raging bolt|roaring moon)' then 120 else 0 end
          + coalesce(d.points, 0)
          + coalesce(d.share, 0) * 10
          - case when input.beginner and lower(d.name) ~ '(control|gardevoir|lost box)' then 30 else 0 end as advisor_score
        from public.limitless_public_decks d
        cross join input
        where input.deck_name = '' or lower(d.name) like '%' || input.deck_name || '%'
        order by advisor_score desc, d.rank asc nulls last, d.points desc, d.name asc
        limit 6
      )
      select
        d.*,
        featured.decklist_id as featured_decklist_id,
        featured.tournament_name as featured_tournament_name,
        featured.tournament_date as featured_tournament_date,
        coalesce(core.cards, '[]'::jsonb) as core_cards,
        coalesce(results.results, '[]'::jsonb) as recent_results
      from candidate_decks d
      left join lateral (
        select r.decklist_id, r.tournament_name, r.tournament_date
        from public.limitless_public_deck_results r
        where r.deck_id = d.deck_id
        order by r.tournament_date desc nulls last, r."placing" asc nulls last, r.player_name asc
        limit 1
      ) featured on true
      left join lateral (
        select jsonb_agg(jsonb_build_object(
          'name', c.display_name,
          'count', c.count,
          'inclusionShare', c.inclusion_share,
          'setCode', c.set_code,
          'collectorNumber', c.collector_number
        ) order by c.inclusion_share desc nulls last, c.count desc nulls last, c.display_name asc) as cards
        from (
          select *
          from public.limitless_public_deck_core_cards c
          where c.deck_id = d.deck_id
          order by c.inclusion_share desc nulls last, c.count desc nulls last, c.display_name asc
          limit 8
        ) c
      ) core on true
      left join lateral (
        select jsonb_agg(jsonb_build_object(
          'tournamentName', r.tournament_name,
          'tournamentDate', r.tournament_date,
          'placing', r."placing",
          'playerName', r.player_name,
          'decklistId', r.decklist_id
        ) order by r.tournament_date desc nulls last, r."placing" asc nulls last) as results
        from (
          select *
          from public.limitless_public_deck_results r
          where r.deck_id = d.deck_id
          order by r.tournament_date desc nulls last, r."placing" asc nulls last, r.player_name asc
          limit 4
        ) r
      ) results on true
      order by d.advisor_score desc, d.rank asc nulls last, d.points desc
    `,
    values,
  );
  const value = { decks: result.rows.map(deckRowToAdvisorDeck) };
  deckAdvisorCache.set(deckCacheKey(intent), { createdAt: Date.now(), value });
  if (deckAdvisorCache.size > 25) {
    deckAdvisorCache.delete(deckAdvisorCache.keys().next().value);
  }
  return value;
}

function deckAdvisorFallbackDecks(intent) {
  const names = intent.deckName
    ? [intent.deckName]
    : intent.beginner
      ? ['Charizard ex', 'Miraidon ex', 'Raging Bolt']
      : intent.budget
        ? ['Miraidon ex', 'Ancient Box', 'Gardevoir ex']
        : ['Charizard ex', 'Gardevoir ex', 'Miraidon ex'];
  return names.map((name, index) => ({
    deckId: '',
    name,
    rank: null,
    points: 0,
    share: 0,
    sourceUrl: '',
    coreCards: [],
    recentResults: [],
    fallback: true,
    index,
  }));
}

function deckAdvisorReply(intent, data, preferences = {}) {
  const italian = intent.language === 'it' || preferences.language === 'it';
  const decks = data.decks.length ? data.decks : deckAdvisorFallbackDecks(intent);
  const lead = decks.length === 1 || intent.deckName
    ? decks[0]
    : null;
  const renderDeck = (deck, index) => {
    const notes = deckArchetypeNotes(deck, intent);
    const core = deck.coreCards?.slice(0, 4).map((card) => card.name).filter(Boolean).join(', ');
    const result = deck.recentResults?.[0];
    const sourceLine = result?.tournamentName
      ? `Recent Limitless result: ${result.tournamentName}${result.placing ? `, placing ${result.placing}` : ''}.`
      : deck.sourceUrl
        ? `Limitless source: ${deck.sourceUrl}`
        : 'No fresh local Limitless result row was available in this response.';
    return [
      `${index + 1}. ${deck.name}${deck.rank ? ` (Limitless rank ${deck.rank})` : ''}`,
      `How it works: ${notes.plan}`,
      `Strengths: ${notes.strengths.join(' ')}`,
      `Weaknesses: ${notes.weaknesses.join(' ')}`,
      `Complexity: ${notes.complexity}. Budget tier: ${notes.budgetTier}.`,
      core ? `Core cards seen in Limitless data: ${core}.` : '',
      sourceLine,
    ].filter(Boolean).join('\n');
  };
  if (!intent.deckName && !intent.beginner && !intent.budget && !intent.playstyle) {
    return {
      reply: [
        italian
          ? 'Posso aiutarti a scegliere, ma mi mancano i tuoi vincoli: budget, livello, stile (aggressivo/control), online o locale, e Pokémon preferiti.'
          : 'I can help you choose, but I need your constraints: budget, skill level, playstyle (aggressive/control), online or local, and favorite Pokémon.',
        italian
          ? 'Intanto ti do 2-3 opzioni ragionevoli dai dati Limitless/site-data, con incertezza esplicita:'
          : 'Meanwhile, here are 2-3 reasonable options from Limitless/site data, with clear uncertainty:',
        decks.slice(0, 3).map(renderDeck).join('\n\n'),
        italian
          ? 'Non cito win rate esatti se non sono nel dato letto ora. La scelta finale va adattata al meta locale.'
          : 'I will not claim exact live win rates unless they are in the data read now. Tune the final choice to your local meta.',
      ].join('\n\n'),
      actions: [],
    };
  }
  return {
    reply: [
      lead
        ? (italian ? `Per me il punto di partenza è ${lead.name}.` : `My starting pick is ${lead.name}.`)
        : (italian ? 'Ecco le opzioni più sensate per quello che hai chiesto:' : 'Here are the strongest fits for what you asked:'),
      decks.slice(0, lead ? 1 : 3).map(renderDeck).join('\n\n'),
      italian
        ? 'Fonte: peer4/read-only Limitless public deck tables e dati site-data locali. Se serve meta live oltre al cache, Poko deve dirti quando sta usando dati pubblici esterni e con quale incertezza.'
        : 'Source: peer4/read-only Limitless public deck tables and local site data. If live meta beyond the cache is needed, Poko should say when public external data is used and how uncertain it is.',
    ].join('\n\n'),
    actions: [],
  };
}

async function deckAdvisorDelivery({ message, chatRecord, userPreferences = {} }) {
  const intent = deckAdvisorIntentFromMessage(message, chatRecord);
  if (!intent) return null;
  const data = await queryDeckAdvisorData(intent).catch((error) => {
    console.error('pokoin-assistant deck advisor query failed', error);
    return { decks: [] };
  });
  const response = deckAdvisorReply(intent, data, userPreferences);
  return {
    reply: response.reply,
    intent: 'deck-advisor',
    source: data.decks.length ? 'peer4-readonly-limitless' : 'deck-advisor-fallback',
    actions: response.actions,
    grounding: {
      type: 'deck_advisor',
      intent,
      decks: data.decks,
      readOnly: true,
    },
  };
}

async function legacyMostExpensiveCardTool({ message, page }) {
  const request = expensiveCardLookupRequest(message);
  if (!request) {
    return null;
  }
  const { marketplaceQuery } = getMarketplaceDbHelper();
  const language = marketplaceLanguageFromPage(page);
  const values = [];
  let nameWhere = '';
  if (request.name) {
    values.push(`%${request.name}%`);
    nameWhere = `and lower(coalesce(listings.card_name, candidates.name, '')) like $${values.length}`;
  }
  const result = await marketplaceQuery(
    `
      select
        listings.id as listing_id,
        listings.card_id,
        listings.card_name,
        listings.price_pkn,
        listings.quantity_available,
        listings.condition,
        listings.language,
        listings.foil_state,
        listings.graded,
        listings.grade,
        listings.seller_name,
        coalesce(nullif(listings.set_name, ''), candidates.set_name) as set_name,
        coalesce(nullif(listings.collector_number, ''), candidates.card_number) as collector_number,
        candidates.name,
        candidates.rarity,
        candidates.card_number
      from public.marketplace_user_listings listings
      left join public.marketplace_search_candidates candidates
        on candidates.card_id::text = listings.card_id::text
      where listings.status = 'active'
        and listings.quantity_available > 0
        and listings.price_pkn > 0
        ${nameWhere}
      order by listings.price_pkn desc, listings.updated_at desc nulls last, listings.created_at desc nulls last
      limit 1
    `,
    values,
  );
  const row = result.rows[0];
  if (!row) {
    return {
      reply: request.name
        ? `I checked the active marketplace listings, but I could not find an active ${request.name} listing right now ⭐`
        : 'I checked the active marketplace listings, but I could not find a matching expensive card right now ⭐',
      intent: 'marketplace',
      source: 'marketplace-tool',
      actions: [],
    };
  }
  const path = marketplaceCardPath(row, language);
  const name = row.card_name || row.name || 'this card';
  const price = Number(row.price_pkn || 0).toLocaleString('en-US', {
    maximumFractionDigits: 2,
  });
  return {
    reply: `I found the highest-priced active listing: ${name} at ${price} PKN ⭐✨ I’m opening it for you now.`,
    intent: 'marketplace',
    source: 'marketplace-tool',
    actions: path ? [{
      type: 'navigate',
      path,
      label: `Open ${name}`,
      reason: 'most_expensive_card',
      data: {
        cardId: String(row.card_id || ''),
        listingId: String(row.listing_id || ''),
        pricePkn: Number(row.price_pkn || 0),
        name,
      },
    }] : [],
  };
}

async function userFromRequest(req) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice('Bearer '.length) : '';
  if (!token) {
    return {
      uid: '',
      username: cleanText(req.body?.username, 80) || 'guest',
      email: '',
    };
  }
  const { getFirebaseAdmin } = getFirebaseHelper();
  const admin = getFirebaseAdmin();
  const decoded = await admin.auth().verifyIdToken(token);
  const doc = await admin.firestore().collection('users').doc(decoded.uid).get();
  const profile = doc.data() || {};
  return {
    uid: decoded.uid,
    username: cleanText(profile.username || decoded.name || req.body?.username, 80) || 'Pokoin user',
    email: cleanText(profile.email || decoded.email, 160),
  };
}

async function forwardToTeam({ message, chatRecord, user, page }) {
  const { sendEmail } = getEmailHelper();
  const subject = `Pokontact ${classifyIntent(message)} from ${user.username || 'guest'}`;
  const transcript = chatRecord.length > 0
    ? chatRecord.map((entry) => `${entry.role === 'user' ? 'User' : 'Pokontact'}: ${entry.text}`).join('\n\n')
    : `User: ${message}`;
  const lines = [
    'Pokontact detected a likely inquiry or bug report.',
    '',
    `Username: ${user.username || 'guest'}`,
    `UID: ${user.uid || '-'}`,
    `Email: ${user.email || '-'}`,
    `Page: ${page || '-'}`,
    '',
    'Latest message:',
    message,
    '',
    'Chat record:',
    transcript,
    '',
    `Time: ${new Date().toISOString()}`,
  ];
  return sendEmail({
    from: ASSISTANT_FROM,
    to: ADMIN_TO,
    subject,
    text: lines.join('\n'),
    html: `
      <div style="font-family:Inter,Arial,sans-serif;line-height:1.6;color:#0f172a">
        <h1 style="margin:0 0 16px">Pokontact user message</h1>
        <ul>
          <li><strong>Username:</strong> ${escapeHtml(user.username || 'guest')}</li>
          <li><strong>UID:</strong> ${escapeHtml(user.uid || '-')}</li>
          <li><strong>Email:</strong> ${escapeHtml(user.email || '-')}</li>
          <li><strong>Page:</strong> ${escapeHtml(page || '-')}</li>
        </ul>
        <h2 style="margin:20px 0 8px">Latest message</h2>
        <pre style="white-space:pre-wrap;background:#f8fafc;padding:12px;border-radius:12px">${escapeHtml(message)}</pre>
        <h2 style="margin:20px 0 8px">Chat record</h2>
        <pre style="white-space:pre-wrap;background:#f8fafc;padding:12px;border-radius:12px">${escapeHtml(transcript)}</pre>
      </div>
    `,
  });
}

function projectReply() {
  return [
    'I am Poko, the little Pokoin helper friend ✨',
    '',
    'Pokoin is a collector project with a few connected pieces:',
    '• a Pokemon card marketplace with search, card detail pages, seller listings, cart, checkout, orders, favorites, inventory, and collection views ⭐',
    '• Earn PKN / shard review: users can send a card list or decklist for review; eligible extra cards can be sharded into PKN value that can be used toward cards they actually want ⭐',
    '• the PokoinPoS chain with native PKN transfers, Scan, Swap, validators, native NFTs, and MetaMask compatibility 🛠️',
    '',
    'Tiny videogame-style explanation: extra cards are like duplicate items. Pokoin has a review flow to turn eligible cards into PKN value, then users can browse/order new cards through marketplace flows. It is a review/request flow, not an instant guaranteed disenchant button. Not financial advice. 📚⭐',
  ].join('\n');
}

function cryptoReply() {
  return [
    'Crypto mini lesson from Poko 😊🛠️',
    '',
    'A wallet is like your keychain. Your address is like a public mailbox. Your private key is the house key, so never share it. 🛠️',
    '',
    'PKN is native on PokoinPoS and currently uses the app reference price of 0.005 USD. wPKN is the BNB Chain market token with reserve discipline, not a fixed 1:1 exchange rate. Swap follows live market/liquidity routes. ✨',
    '',
    'Simple example: if Alice sends Bob 5 PKN, the chain records “Alice -5, Bob +5” so everyone can verify it later. Cute accounting, but with math muscles ⭐✨',
  ].join('\n');
}

function earnReply(message) {
  const italian = /\b(come|cosa|posso|carte|nuove|guadagn|funziona|videogame|gioco|tipo)\b/.test(normalizeIntentText(message));
  if (italian) {
    return [
      'Sì: su Pokoin esiste il flusso Earn PKN / PKN Shard Review ✨',
      '',
      'Funziona in stile videogame, ma con review reale: mandi una lista di carte o un decklist dalla pagina /shard-review. Il team valuta identità, versione, lingua, condizione e valore stimato. Se le carte sono eleggibili, possono essere sharded into PKN, cioè trasformate in valore PKN da usare verso carte che vuoi davvero.',
      '',
      'Non è un pulsante automatico garantito: oggi è una richiesta di review via /api/earn-pkn. Puoi partire da https://pokoin.com/earn o https://pokoin.com/shard-review. Non è consulenza finanziaria.',
    ].join('\n');
  }
  return [
    'Yes: Pokoin has an Earn PKN / PKN Shard Review flow ✨',
    '',
    'Videogame-style idea, but with a real review step: submit a card list or full decklist on /shard-review. The team reviews card identity, version, language, condition, and estimated value. Eligible extra cards can be sharded into PKN value, then used toward cards you actually want through marketplace/order flows.',
    '',
    'Important: this is not an instant guaranteed disenchant button. The implemented flow is a review request sent through /api/earn-pkn. Start at https://pokoin.com/earn or https://pokoin.com/shard-review. Not financial advice.',
  ].join('\n');
}

async function resolveThemedCardPick(theme, language) {
  if (!theme) {
    return { pick: null, directPath: '' };
  }
  for (const pick of theme.picks) {
    const directPath = await resolveCardQueryPath(pick, language).catch((error) => {
      console.error('pokoin-assistant themed card resolution failed', error);
      return '';
    });
    if (directPath) {
      return { pick, directPath };
    }
  }
  return { pick: theme.picks[0] || null, directPath: '' };
}

async function cardSuggestion({ page, message = '', chatRecord = [] } = {}) {
  const picks = [
    {
      name: 'Magikarp',
      query: 'Magikarp 203/193',
      cardId: '248856',
      setName: 'Paldea Evolved',
      artist: 'Shinji Kanda',
      detail: 'a wild vertical waterfall scene where tiny Magikarp feels heroic instead of silly',
    },
    {
      name: 'Dragonite V',
      query: 'Dragonite V 192/203',
      cardId: '166430',
      setName: 'Evolving Skies',
      artist: 'Atsushi Furusawa',
      detail: 'soft flying-postman energy, with Dragonite drifting above the sea like a friendly guardian',
    },
    {
      name: 'Drowzee',
      query: 'Drowzee 210/198',
      cardId: '241674',
      setName: 'Scarlet & Violet',
      artist: 'Tomokazu Komiya',
      detail: 'a dreamy, strange city scene that feels hand-drawn and full of personality',
    },
    {
      name: 'Mew ex',
      query: 'Mew ex 232/091',
      cardId: '274416',
      setName: 'Paldean Fates',
      artist: 'USGMEN',
      detail: 'a playful bubblegum-pink illustration packed with tiny cute details around Mew',
    },
    {
      name: 'Poliwhirl',
      query: 'Poliwhirl 176/165',
      cardId: '251432',
      setName: 'Pokémon Card 151',
      artist: 'Gemi',
      detail: 'a quiet rainy-street mood, perfect if you like cozy illustration cards',
    },
  ];
  const language = marketplaceLanguageFromPage(page);
  const theme = detectCardSuggestionTheme(message, chatRecord);
  const themed = await resolveThemedCardPick(theme, language);
  const pick = themed.pick || picks[Math.floor(Math.random() * picks.length)];
  const directPath = themed.directPath || await resolveCardQueryPath(pick, language).catch((error) => {
    console.error('pokoin-assistant card suggestion resolution failed', error);
    return '';
  });
  const targetPath = directPath || cardSearchPath(pick.query);
  const targetLabel = directPath ? `Open ${pick.name}` : `Search ${pick.name}`;
  const themeLine = theme
    ? `Theme match: you asked for ${theme.label}, so I picked ${pick.name} instead of a random cute card.`
    : 'Poko card taste mode activated ⭐💛';
  return {
    reply: [
    themeLine,
    '',
    'This is not financial advice. I only judge by cuteness, personality, and “would I put it in a cozy binder?” energy. 😊',
    '',
      `My illustration pick: ${pick.name} by ${pick.artist}.`,
      `Why I like it: ${pick.detail}.`,
      '',
      `https://pokoin.com${targetPath}`,
    '',
    'If you want a theme, try collecting by vibe: ocean cuties, electric babies, sleepy cards, tiny legends, or cards with cozy backgrounds. Much healthier than chasing price candles 📚✨',
    ].join('\n'),
    actions: [{
      type: 'navigate',
      path: targetPath,
      label: targetLabel,
      reason: theme ? `themed_card_suggestion:${theme.id}` : 'cute_card_suggestion',
      data: { query: pick.query, artist: pick.artist, theme: theme?.id || '', direct: Boolean(directPath) },
    }],
  };
}

async function cardReply(options) {
  return (await cardSuggestion(options)).reply;
}

function inquiryReply(wasForwarded) {
  if (wasForwarded) {
    return 'I am forwarding your issue to the development team 🛠️✨ They will respond to you directly. In the meantime, please give me any additional information you can: what page you were on, what you clicked, what you expected, what happened instead, and any screenshot or error text 🛠️😊';
  }
  return 'This looks like something for the development team 🛠️💛 I am preparing the report, but forwarding is temporarily unavailable. Please add more details here anyway: page, clicks, expected result, actual result, and any screenshot/error text. I will try again when forwarding is available.';
}

function generalReply() {
  return 'I don’t know the answer yet, but I’m always improving ✨ Ask me another way, or try a cute card question while my tiny brain levels up.';
}

function greetingReply(message) {
  if (/\b(ciao|salve|buongiorno|buonasera)\b/i.test(message)) {
    return 'Ciao! Sono Poko ✨ Posso spiegarti Pokoin, PKN, wallet, Scan, Swap, validatori, suggerire carte Pokémon carine senza consigli finanziari, oppure raccogliere un bug per il team.';
  }
  return 'Hi! I am Poko ✨ I can explain Pokoin, PKN, wallets, Scan, Swap, validators, suggest cute Pokémon cards without financial advice, or collect a bug report for the team.';
}

function casualReply(message) {
  const text = normalizeIntentText(message);
  if (/\b(ti piace|do you like|you like)\b/.test(text)) {
    if (/\b(gelato|ice cream|icecream)\b/.test(text)) {
      return 'Sì, in modalità Poko il gelato mi piace eccome: soprattutto quello alla vaniglia, perché mi fa pensare a Vanillite 😊 Se vuoi, posso anche consigliarti una carta a tema gelato.';
    }
    return 'Mi piace chiacchierare con te 😊 Non ho gusti veri come una persona, però posso stare al gioco e risponderti in modo naturale.';
  }
  if (/\b(come stai|come va|tutto ok)\b/.test(text)) {
    return 'Tutto ok ✨ Sono qui, sveglio e pronto a chiacchierare o aiutarti con Pokoin quando vuoi.';
  }
  if (/\b(my name is|mi chiamo)\b/.test(text)) {
    const match = cleanText(message, 120).match(/\b(?:my name is|mi chiamo)\s+([a-zA-ZÀ-ÿ0-9_-]{2,30})/i);
    const name = match?.[1] || '';
    return name ? `Piacere, ${name}! ✨` : 'Piacere! ✨ Dimmi pure come vuoi che ti chiami.';
  }
  return 'Ci sto, parliamo pure tranquillamente 😊 Quando vuoi posso anche tornare su Pokoin, carte o marketplace.';
}

function docsReply(message, intent) {
  const text = normalizeIntentText(message);
  const italian = /\b(come|cosa|dove|chi|spiega|documentazione|guida)\b/.test(text);
  const sectionByIntent = {
    crypto: 'Wallets / User actions',
    project: 'Overview',
  };
  const section = sectionByIntent[intent] || 'User actions';
  const url = 'https://pokoin.com/docs';
  if (italian) {
    return `Per domande tecniche ti mando alla documentazione ufficiale, così non invento dettagli in chat 📚\n\nApri ${url} e guarda la sezione “${section}”.`;
  }
  return `For technical questions, I’ll point you to the official docs so I don’t invent details in chat 📚\n\nOpen ${url} and check the “${section}” section.`;
}

function safeAssistantActions(actions) {
  if (!Array.isArray(actions)) {
    return [];
  }
  return actions
    .map((action) => {
      if (!action || typeof action !== 'object') {
        return null;
      }
      const type = cleanText(action.type || action.action, 40).toLowerCase();
      if (type !== 'navigate') {
        return null;
      }
      const path = cleanInternalPath(action.path || action.data?.canonicalPath || action.data?.path);
      if (!path) {
        return null;
      }
      return {
        ...action,
        type: 'navigate',
        path,
      };
    })
    .filter(Boolean);
}

async function callPokontactService({ message, chatRecord, user, page, pageContext, marketplaceContext }) {
  if (!POKONTACT_SERVICE_TOKEN) {
    return null;
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), POKONTACT_SERVICE_TIMEOUT_MS);
  try {
    const response = await fetch(`${POKONTACT_SERVICE_URL}/chat`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${POKONTACT_SERVICE_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message,
        messages: chatRecord,
        user,
        page,
        pageContext,
        context: pageContextForPrompt(pageContext),
        marketplaceContext,
      }),
      signal: controller.signal,
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(payload.error || `Pokontact service returned ${response.status}.`);
    }
    if (!payload || typeof payload.reply !== 'string') {
      throw new Error('Pokontact service returned an invalid reply.');
    }
    return {
      reply: cleanText(payload.reply, 5000),
      intent: cleanText(payload.intent, 40) || classifyIntent(message),
      provider: cleanText(payload.provider, 80),
      model: cleanText(payload.model, 120),
      source: cleanText(payload.source, 80) || 'peer2-service',
      actions: safeAssistantActions(payload.actions),
    };
  } finally {
    clearTimeout(timeout);
  }
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const message = cleanText(req.body?.message, 3000);
    const chatRecord = cleanChatRecord(req.body?.messages);
    const pageContext = cleanPageContext(req.body?.pageContext);
    const page = pageUrlFromContext(cleanText(req.body?.page, 500), pageContext);
    const sessionId = sessionIdFromRequest(req);
    if (message.length < 2) {
      return res.status(400).json({ error: 'Write a message for Pokontact.' });
    }

    const user = await userFromRequest(req).catch(() => ({
      uid: '',
      username: cleanText(req.body?.username, 80) || 'guest',
      email: '',
    }));
    user.sessionId = sessionId;
    user.identityKey = user.uid || sessionId || 'guest';
    const userPreferences = inferUserPreferences({ message, chatRecord });
    const localIntent = classifyIntent(message);
    if (localIntent === 'unsafe-cyber') {
      return res.status(200).json({
        reply: sanitizePokoEmoji(unsafeCyberReply(message)),
        intent: localIntent,
        forwarded: false,
        emailDelivery: null,
        actions: [],
        pageContext,
        serviceDelivery: {
          ok: true,
          source: 'local-safety',
          provider: 'pokoin-assistant-guardrail',
          model: 'deterministic',
        },
        assistant: 'Pokontact',
      });
    }
    if (localIntent === 'navigation') {
      return res.status(200).json({
        reply: sanitizePokoEmoji(navigationReply(message)),
        intent: localIntent,
        forwarded: false,
        emailDelivery: null,
        actions: [],
        pageContext,
        serviceDelivery: {
          ok: true,
          source: 'local-navigation',
          provider: 'pokoin-assistant-navigation',
          model: 'deterministic',
        },
        assistant: 'Pokontact',
      });
    }
    const cardOpinionDelivery = await currentCardOpinionDelivery({
      message,
      page,
      pageContext,
    }).catch((error) => {
      console.error('pokoin-assistant current-card opinion failed', error);
      return null;
    });
    if (cardOpinionDelivery) {
      return res.status(200).json({
        reply: sanitizePokoEmoji(cardOpinionDelivery.reply),
        intent: cardOpinionDelivery.intent,
        forwarded: false,
        emailDelivery: null,
        actions: safeAssistantActions(cardOpinionDelivery.actions),
        pageContext,
        serviceDelivery: {
          ok: true,
          source: cardOpinionDelivery.source,
          provider: 'pokoin-current-card-context',
          model: 'deterministic',
        },
        marketplaceContext: cardOpinionDelivery.marketplaceContext,
        assistant: 'Pokontact',
      });
    }
    if (!['project', 'crypto', 'greeting', 'casual'].includes(localIntent)) {
      const deckDelivery = await deckAdvisorDelivery({
        message,
        chatRecord,
        userPreferences,
      }).catch((error) => {
        console.error('pokoin-assistant deck advisor failed', error);
        return null;
      });
      if (deckDelivery) {
        return res.status(200).json({
          reply: sanitizePokoEmoji(deckDelivery.reply),
          intent: deckDelivery.intent,
          forwarded: false,
          emailDelivery: null,
          actions: safeAssistantActions(deckDelivery.actions),
          pageContext,
          serviceDelivery: {
            ok: true,
            source: deckDelivery.source,
            provider: 'pokoin-deck-advisor',
            model: 'deterministic',
          },
          marketplaceContext: deckDelivery.grounding,
          userMemory: userPreferences,
          assistant: 'Pokontact',
        });
      }
      const recommendationDelivery = await recommendationGroundedDelivery({
        message,
        chatRecord,
        page,
        pageContext,
        userPreferences,
      }).catch((error) => {
        console.error('pokoin-assistant card recommendation failed', error);
        return null;
      });
      if (recommendationDelivery) {
        return res.status(200).json({
          reply: sanitizePokoEmoji(recommendationDelivery.reply),
          intent: recommendationDelivery.intent,
          forwarded: false,
          emailDelivery: null,
          actions: safeAssistantActions(recommendationDelivery.actions),
          pageContext,
          serviceDelivery: {
            ok: true,
            source: recommendationDelivery.source,
            provider: 'pokoin-card-recommendation',
            model: 'deterministic',
          },
          marketplaceContext: recommendationDelivery.grounding,
          userMemory: userPreferences,
          assistant: 'Pokontact',
        });
      }
      const marketplaceDelivery = await marketplaceGroundedDelivery({
        message,
        chatRecord,
        page,
        pageContext,
      }).catch((error) => {
        console.error('pokoin-assistant marketplace grounding failed', error);
        return null;
      });
      if (marketplaceDelivery) {
        return res.status(200).json({
          reply: sanitizePokoEmoji(marketplaceDelivery.reply),
          intent: marketplaceDelivery.intent,
          forwarded: false,
          emailDelivery: null,
          actions: safeAssistantActions(marketplaceDelivery.actions),
          pageContext,
          serviceDelivery: {
            ok: true,
            source: marketplaceDelivery.source,
            provider: 'pokoin-marketplace-tool',
            model: 'deterministic',
          },
          marketplaceContext: marketplaceDelivery.grounding,
          userMemory: userPreferences,
          assistant: 'Pokontact',
        });
      }
    }
    const serviceDelivery = shouldBypassPeerService(localIntent, message, chatRecord)
      ? { ok: false, skipped: true, reason: `local_${localIntent}` }
      : await callPokontactService({
        message,
        chatRecord,
        user,
        page,
        pageContext,
        marketplaceContext: { userPreferences },
      }).catch((error) => ({
        ok: false,
        error: error.name === 'AbortError' ? 'Pokontact service timed out.' : error.message,
      }));
    const serviceReply = serviceDelivery?.reply ? serviceDelivery : null;
    const intent = serviceReply?.intent || localIntent;
    let forwarded = false;
    let emailDelivery = null;
    let reply;
    let actions = [];

    if (intent === 'inquiry') {
      emailDelivery = await forwardToTeam({ message, chatRecord, user, page }).catch((error) => ({
        ok: false,
        error: error.message || 'Email forwarding failed.',
      }));
      forwarded = Boolean(emailDelivery?.ok);
      reply = inquiryReply(forwarded);
    } else if (serviceReply) {
      const rewrittenServiceReply = await rewriteCardSuggestionLinks(serviceReply, page);
      reply = rewrittenServiceReply.reply;
      actions = safeAssistantActions(rewrittenServiceReply.actions);
    } else if (intent === 'greeting') {
      reply = greetingReply(message);
    } else if (intent === 'casual') {
      reply = casualReply(message);
    } else if (intent === 'card') {
      const suggestion = await cardSuggestion({ page, message, chatRecord });
      reply = suggestion.reply;
      actions = safeAssistantActions(suggestion.actions);
    } else if (intent === 'project') {
      reply = projectReply();
    } else if (intent === 'earn') {
      reply = earnReply(message);
    } else if (intent === 'crypto') {
      reply = cryptoReply();
    } else {
      reply = generalReply();
    }
    reply = sanitizePokoEmoji(reply);

    return res.status(200).json({
      reply,
      intent,
      forwarded,
      emailDelivery,
      actions: safeAssistantActions(actions),
      pageContext,
      userMemory: userPreferences,
      serviceDelivery: serviceReply ? {
        ok: true,
        source: serviceReply.source,
        provider: serviceReply.provider,
        model: serviceReply.model,
      } : serviceDelivery || { ok: false, skipped: true, reason: 'POKONTACT_SERVICE_TOKEN is not configured.' },
      assistant: 'Pokontact',
    });
  } catch (error) {
    console.error('pokoin-assistant failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Pokontact is taking a tiny nap. Try again soon.',
    });
  }
};

module.exports._test = {
  doubledCardId,
  expensiveCardLookupRequest,
  marketplaceGroundedDelivery,
  marketplaceRequestFromMessage,
  marketplaceCardPath,
  marketplaceLanguageFromPage,
  mostExpensiveCardTool,
  pageCardContext,
  currentCardOpinionDelivery,
  looksLikeCurrentCardOpinionValueQuestion,
  fetchCommunitySentiment,
  detectCardSuggestionTheme,
  inferUserPreferences,
  recommendationIntentFromMessage,
  queryCardRecommendations,
  recommendationGroundedDelivery,
  deckAdvisorIntentFromMessage,
  queryDeckAdvisorData,
  deckAdvisorDelivery,
  isDirectMarketplaceCardPath,
  parseCardQueryParts,
  resolveCardQueryPath,
  rewriteCardSuggestionLinks,
  cardSuggestion,
  earnReply,
  explicitCardSubjectFromMessage,
  looksLikeEarnOrShardQuestion,
  safeAssistantActions,
  cleanPageContext,
  sanitizePokoEmoji,
  pageContextForPrompt,
  slugPart,
  classifyIntent,
  casualReply,
  greetingReply,
  shouldBypassPeerService,
  resolvePokontactServiceUrl,
  DEFAULT_POKONTACT_SERVICE_URL,
  loadEmailHelper,
  loadFirebaseHelper,
  loadMarketplaceDbHelper,
  setTestHelperOverrides,
};
