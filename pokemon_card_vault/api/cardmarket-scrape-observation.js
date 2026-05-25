const { marketplaceQuery } = require('./_marketplace_db');
const { verifyBearerToken } = require('./_firebase');

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Access-Control-Max-Age': '86400',
};

function setCorsHeaders(res) {
  for (const [key, value] of Object.entries(CORS_HEADERS)) {
    res.setHeader(key, value);
  }
}

function cleanText(value, maxLength = 240) {
  return String(value || '').trim().replace(/\s+/g, ' ').slice(0, maxLength);
}

function cleanLocale(value) {
  const locale = cleanText(value || 'en', 8).toLowerCase();
  return /^[a-z]{2}$/.test(locale) ? locale : 'en';
}

function cleanCardmarketUrl(value) {
  const text = cleanText(value, 800);
  let parsed;
  try {
    parsed = new URL(text);
  } catch {
    return null;
  }
  if (parsed.protocol !== 'https:') return null;
  if (parsed.hostname !== 'www.cardmarket.com' && parsed.hostname !== 'cardmarket.com') return null;
  if (!parsed.pathname.includes('/Pokemon/Products/Singles/')) return null;
  parsed.hash = '';
  return parsed;
}

function cardmarketPathParts(parsedUrl) {
  const parts = parsedUrl.pathname
    .split('/')
    .map((part) => decodeURIComponent(part))
    .filter(Boolean);
  const singlesIndex = parts.findIndex((part) => part.toLowerCase() === 'singles');
  return {
    locale: cleanLocale(parts[0]),
    expansionSlug: singlesIndex >= 0 ? cleanText(parts[singlesIndex + 1], 240) : '',
    productSlug: singlesIndex >= 0 ? cleanText(parts[singlesIndex + 2], 320) : '',
  };
}

function cleanJson(value, maxBytes = 16_000) {
  if (!value || typeof value !== 'object') return {};
  const text = JSON.stringify(value);
  if (Buffer.byteLength(text, 'utf8') <= maxBytes) return value;
  return {
    truncated: true,
    sample: text.slice(0, maxBytes),
  };
}

function cleanNumber(value) {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function cleanBlueprintId(value) {
  const id = Number(value);
  return Number.isSafeInteger(id) && id > 0 ? id : null;
}

async function optionalUser(req) {
  if (!req.headers.authorization) return {};
  try {
    const decoded = await verifyBearerToken(req);
    return {
      uid: cleanText(decoded.uid, 160),
      email: cleanText(decoded.email, 240),
    };
  } catch {
    return {};
  }
}

async function ensureObservationTable() {
  await marketplaceQuery(`
    create table if not exists public.marketplace_cm_scrape_observations (
      id uuid primary key default gen_random_uuid(),
      cardmarket_url text not null,
      cardmarket_locale text not null default 'en',
      cardmarket_expansion_slug text not null default '',
      cardmarket_product_slug text not null default '',
      page_title text not null default '',
      scraped_name text not null default '',
      scraped_expansion text not null default '',
      collector_number text not null default '',
      collector_prefix text not null default '',
      numeric_collector_number text not null default '',
      raw_title text not null default '',
      structured_payload jsonb not null default '{}'::jsonb,
      page_context jsonb not null default '{}'::jsonb,
      matched_blueprint_id bigint references public.cardtrader_pokemon_blueprints(id) on delete set null,
      match_confidence numeric,
      match_payload jsonb not null default '{}'::jsonb,
      source text not null default 'pokemon-card-extension',
      extension_version text not null default '',
      user_agent text not null default '',
      debug_uid text not null default '',
      debug_email text not null default '',
      status text not null default 'observed' check (
        status in ('observed', 'matched', 'verified', 'rejected')
      ),
      notes text not null default '',
      observed_at timestamptz not null default now(),
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    )
  `);
  await marketplaceQuery(`
    create unique index if not exists marketplace_cm_scrape_observations_url_idx
      on public.marketplace_cm_scrape_observations (cardmarket_url)
  `);
  await marketplaceQuery(`
    create index if not exists marketplace_cm_scrape_observations_status_idx
      on public.marketplace_cm_scrape_observations (status, observed_at desc)
  `);
  await marketplaceQuery(`
    create table if not exists public.marketplace_cm_verified_links (
      blueprint_id bigint not null references public.cardtrader_pokemon_blueprints(id) on delete cascade,
      cardmarket_locale text not null default 'en',
      cardmarket_url text not null,
      cardmarket_product_slug text not null default '',
      card_name text not null default '',
      expansion_name text not null default '',
      collector_number text not null default '',
      source text not null default '',
      confidence text not null default 'verified' check (
        confidence in ('verified', 'manual')
      ),
      notes text not null default '',
      verified_at timestamptz not null default now(),
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      primary key (blueprint_id, cardmarket_locale)
    )
  `);
  await marketplaceQuery(`
    create unique index if not exists marketplace_cm_verified_links_url_idx
      on public.marketplace_cm_verified_links (cardmarket_url)
  `);
}

function observationFromBody(body = {}, req, user) {
  const parsedUrl = cleanCardmarketUrl(body.cardmarketUrl || body.url || body.pageUrl);
  if (!parsedUrl) {
    const error = new Error('A valid Cardmarket singles URL is required.');
    error.statusCode = 400;
    throw error;
  }
  const pathParts = cardmarketPathParts(parsedUrl);
  const structured = body.structuredCard || body.structured || {};
  const context = body.cardmarketContext || body.context || {};
  const match = body.match || body.bestMatch || {};
  const matchedBlueprintId = cleanBlueprintId(
    body.blueprintId || body.matchedBlueprintId || match.cardId || match.blueprintId,
  );
  const confidence = cleanNumber(body.matchConfidence || match.relevanceScore || match.score);
  const promoteVerifiedLink =
    body.promoteVerifiedLink === true ||
    body.promoteVerifiedLink === '1' ||
    body.promoteVerifiedLink === 'true';
  const status = matchedBlueprintId ? 'matched' : 'observed';

  return {
    url: parsedUrl.toString(),
    locale: cleanLocale(body.locale || pathParts.locale),
    expansionSlug: cleanText(body.cardmarketExpansionSlug || pathParts.expansionSlug, 240),
    productSlug: cleanText(body.cardmarketProductSlug || pathParts.productSlug, 320),
    pageTitle: cleanText(body.title || body.pageTitle, 400),
    scrapedName: cleanText(structured.name || body.name || body.cardName, 240),
    scrapedExpansion: cleanText(structured.expansion || context.expansion || body.expansionName, 240),
    collectorNumber: cleanText(
      structured.collectorNumber || structured.printedCollectorNumber || body.collectorNumber,
      80,
    ),
    collectorPrefix: cleanText(structured.collectorNumberPrefix || body.collectorPrefix, 40),
    numericCollectorNumber: cleanText(structured.numericCollectorNumber || body.numericCollectorNumber, 40),
    rawTitle: cleanText(structured.rawTitle || body.rawTitle || body.title, 500),
    structuredPayload: cleanJson(structured),
    pageContext: cleanJson({
      ...context,
      debug: body.debug,
      hostname: body.hostname,
    }),
    matchedBlueprintId,
    matchConfidence: confidence,
    matchPayload: cleanJson(match),
    source: cleanText(body.source || 'pokemon-card-extension', 80),
    extensionVersion: cleanText(body.extensionVersion || body.version, 40),
    userAgent: cleanText(req.headers['user-agent'], 500),
    debugUid: user.uid || '',
    debugEmail: user.email || '',
    status,
    promoteVerifiedLink,
    notes: cleanText(body.notes, 500),
  };
}

async function saveObservation(observation) {
  await ensureObservationTable();
  const result = await marketplaceQuery(
    `
      insert into public.marketplace_cm_scrape_observations (
        cardmarket_url,
        cardmarket_locale,
        cardmarket_expansion_slug,
        cardmarket_product_slug,
        page_title,
        scraped_name,
        scraped_expansion,
        collector_number,
        collector_prefix,
        numeric_collector_number,
        raw_title,
        structured_payload,
        page_context,
        matched_blueprint_id,
        match_confidence,
        match_payload,
        source,
        extension_version,
        user_agent,
        debug_uid,
        debug_email,
        status,
        notes
      )
      values (
        $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
        $11, $12::jsonb, $13::jsonb, $14, $15, $16::jsonb,
        $17, $18, $19, $20, $21, $22, $23
      )
      on conflict (cardmarket_url)
      do update set
        cardmarket_locale = excluded.cardmarket_locale,
        cardmarket_expansion_slug = excluded.cardmarket_expansion_slug,
        cardmarket_product_slug = excluded.cardmarket_product_slug,
        page_title = excluded.page_title,
        scraped_name = excluded.scraped_name,
        scraped_expansion = excluded.scraped_expansion,
        collector_number = excluded.collector_number,
        collector_prefix = excluded.collector_prefix,
        numeric_collector_number = excluded.numeric_collector_number,
        raw_title = excluded.raw_title,
        structured_payload = excluded.structured_payload,
        page_context = excluded.page_context,
        matched_blueprint_id = excluded.matched_blueprint_id,
        match_confidence = excluded.match_confidence,
        match_payload = excluded.match_payload,
        source = excluded.source,
        extension_version = excluded.extension_version,
        user_agent = excluded.user_agent,
        debug_uid = excluded.debug_uid,
        debug_email = excluded.debug_email,
        status = case
          when public.marketplace_cm_scrape_observations.status = 'verified'
            then public.marketplace_cm_scrape_observations.status
          else excluded.status
        end,
        notes = excluded.notes,
        observed_at = now(),
        updated_at = now()
      returning id, status, observed_at
    `,
    [
      observation.url,
      observation.locale,
      observation.expansionSlug,
      observation.productSlug,
      observation.pageTitle,
      observation.scrapedName,
      observation.scrapedExpansion,
      observation.collectorNumber,
      observation.collectorPrefix,
      observation.numericCollectorNumber,
      observation.rawTitle,
      JSON.stringify(observation.structuredPayload),
      JSON.stringify(observation.pageContext),
      observation.matchedBlueprintId,
      observation.matchConfidence,
      JSON.stringify(observation.matchPayload),
      observation.source,
      observation.extensionVersion,
      observation.userAgent,
      observation.debugUid,
      observation.debugEmail,
      observation.status,
      observation.notes,
    ],
  );
  return result.rows[0];
}

async function promoteVerifiedLink(observation, savedObservation) {
  if (!observation.promoteVerifiedLink || !observation.matchedBlueprintId) {
    return null;
  }
  const result = await marketplaceQuery(
    `
      insert into public.marketplace_cm_verified_links (
        blueprint_id,
        cardmarket_locale,
        cardmarket_url,
        cardmarket_product_slug,
        card_name,
        expansion_name,
        collector_number,
        source,
        confidence,
        notes,
        verified_at
      )
      values ($1, $2, $3, $4, $5, $6, $7, 'cardmarket-scrape-observation', 'verified', $8, now())
      on conflict (blueprint_id, cardmarket_locale)
      do update set
        cardmarket_url = excluded.cardmarket_url,
        cardmarket_product_slug = excluded.cardmarket_product_slug,
        card_name = excluded.card_name,
        expansion_name = excluded.expansion_name,
        collector_number = excluded.collector_number,
        source = excluded.source,
        confidence = excluded.confidence,
        notes = excluded.notes,
        verified_at = excluded.verified_at,
        updated_at = now()
      returning blueprint_id, cardmarket_locale, cardmarket_url
    `,
    [
      observation.matchedBlueprintId,
      observation.locale,
      observation.url,
      observation.productSlug,
      observation.scrapedName,
      observation.scrapedExpansion,
      observation.collectorNumber,
      `Promoted from scrape observation ${savedObservation.id}.`,
    ],
  );
  await marketplaceQuery(
    `
      update public.marketplace_cm_scrape_observations
      set status = 'verified',
          notes = concat_ws(E'\n', nullif(notes, ''), 'Promoted to verified links.'),
          updated_at = now()
      where id = $1
    `,
    [savedObservation.id],
  );
  return result.rows[0] || null;
}

module.exports = async function handler(req, res) {
  setCorsHeaders(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST, OPTIONS');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const user = await optionalUser(req);
    const observation = observationFromBody(req.body || {}, req, user);
    const saved = await saveObservation(observation);
    const verifiedLink = await promoteVerifiedLink(observation, saved);
    res.setHeader('Cache-Control', 'no-store');
    return res.status(201).json({ ok: true, observation: saved, verifiedLink });
  } catch (error) {
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Cardmarket scrape observation failed.',
    });
  }
};

module.exports.observationFromBody = observationFromBody;
module.exports.saveObservation = saveObservation;
module.exports.promoteVerifiedLink = promoteVerifiedLink;
