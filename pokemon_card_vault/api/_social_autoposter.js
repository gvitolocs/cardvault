const crypto = require('crypto');

const { marketplaceQuery } = require('./_marketplace_db');
const { authorizeSearchDebugRequest } = require('./_search_debug_auth');

const DEFAULT_SITE_URL = 'https://pokoin.com';
const DEFAULT_SOCIAL_AGENT_ENDPOINT = 'http://130.162.242.213:8787/social-post';
const DEFAULT_HASHTAGS = ['#Pokoin', '#PokemonCards', '#TradingCards'];
const TELEGRAM_MESSAGE_LIMIT = 4096;
const TELEGRAM_CAPTION_LIMIT = 1024;
const X_POST_LIMIT = 280;
const SOCIAL_AGENT_TIMEOUT_MS = 6000;
const SOCIAL_IMAGE_MAX_BYTES = 5 * 1024 * 1024;

function cleanText(value, maxLength = 4000) {
  return String(value || '')
    .replace(/\r\n/g, '\n')
    .replace(/[ \t]+\n/g, '\n')
    .replace(/\n{4,}/g, '\n\n\n')
    .trim()
    .slice(0, maxLength);
}

function boolValue(value, fallback = false) {
  if (value === undefined || value === null || value === '') return fallback;
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  return ['1', 'true', 'yes', 'on'].includes(String(value).trim().toLowerCase());
}

function siteOrigin(env = process.env) {
  const configured = cleanText(env.PUBLIC_SITE_URL, 240) || DEFAULT_SITE_URL;
  try {
    const url = new URL(configured);
    return `${url.protocol}//${url.host}`.replace(/\/+$/, '');
  } catch (_) {
    return DEFAULT_SITE_URL;
  }
}

function absoluteUrl(value, env = process.env) {
  const clean = cleanText(value, 1000);
  if (!clean) return '';
  try {
    return new URL(clean).toString();
  } catch (_) {
    try {
      return new URL(clean.startsWith('/') ? clean : `/${clean}`, siteOrigin(env)).toString();
    } catch (error) {
      return '';
    }
  }
}

function slugPart(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function cleanNumericId(value) {
  const text = cleanText(value, 80);
  if (!/^[0-9]+$/.test(text)) return '';
  const id = Number(text);
  return Number.isSafeInteger(id) && id > 0 ? String(id) : '';
}

function canonicalCardPath(card = {}) {
  const cardId = cleanNumericId(card.cardId || card.card_id || card.id || card.blueprintId || card.blueprint_id);
  if (!cardId) return '';
  const slug = [
    card.rarity || 'Card',
    card.name || card.cardName || card.title,
    card.collectorNumber || card.collector_number || card.cardNumber || card.card_number,
    card.setName || card.set_name || card.expansionName || card.expansion_name,
  ].map(slugPart).filter(Boolean).join('-');
  return slug ? `/marketplace/en/cards/${Number(cardId) * 2}/${slug}` : '';
}

function publicCardUrl(card = {}, env = process.env) {
  return absoluteUrl(
    card.cardUrl ||
      card.card_url ||
      card.listingUrl ||
      card.listing_url ||
      canonicalCardPath(card),
    env,
  );
}

function publicImageUrl(card = {}, env = process.env) {
  const clean = cleanText(
    card.cdnImageUrl ||
      card.cdn_image_url ||
      card.imageUrl ||
      card.image_url ||
      card.previewImageUrl ||
      card.preview_image_url ||
      card.homepageImageUrl ||
      card.homepage_image_url,
    1000,
  );
  if (!clean) return '';
  try {
    const url = new URL(clean);
    if (url.hostname === 'cdn.pokoin.com') {
      return new URL(`/card-images${url.pathname}${url.search}`, siteOrigin(env)).toString();
    }
    return url.toString();
  } catch (_) {
    return absoluteUrl(clean, env);
  }
}

function hashtagsFromInput(value) {
  const values = Array.isArray(value)
    ? value
    : String(value || '').split(/[,\s]+/);
  const tags = values
    .map((item) => cleanText(item, 40))
    .filter(Boolean)
    .map((item) => (item.startsWith('#') ? item : `#${item.replace(/^#+/, '')}`))
    .filter((item) => /^#[A-Za-z0-9_]{2,39}$/.test(item));
  return [...new Set(tags.length ? tags : DEFAULT_HASHTAGS)];
}

function formatPkn(value) {
  const price = Number(value);
  if (!Number.isFinite(price) || price <= 0) return '';
  const rounded = Math.round(price);
  return `${rounded.toLocaleString('en-US')} PKN`;
}

function cardDisplayTitle(card = {}) {
  const name = cleanText(card.title || card.cardTitle || card.cardName || card.name, 180) || 'Pokemon card';
  const setName = cleanText(card.setName || card.set_name || card.expansionName || card.expansion_name, 120);
  const number = cleanText(
    card.collectorNumber || card.collector_number || card.cardNumber || card.card_number,
    80,
  );
  const suffix = [setName, number].filter(Boolean).join(' ');
  return suffix && !name.includes(suffix) ? `${name} (${suffix})` : name;
}

function truncateText(value, maxLength) {
  const clean = cleanText(value, Math.max(maxLength * 2, maxLength));
  if (clean.length <= maxLength) return clean;
  if (maxLength <= 3) return clean.slice(0, maxLength);
  return `${clean.slice(0, maxLength - 3).trimEnd()}...`;
}

function composeWithSuffix(main, suffix, maxLength) {
  const cleanMain = cleanText(main, Math.max(maxLength * 2, maxLength));
  const cleanSuffix = cleanText(suffix, Math.max(maxLength, 1000));
  if (!cleanSuffix) return truncateText(cleanMain, maxLength);
  const combined = `${cleanMain}\n\n${cleanSuffix}`.trim();
  if (combined.length <= maxLength) return combined;
  const availableMain = maxLength - cleanSuffix.length - 2;
  if (availableMain > 20) {
    return `${truncateText(cleanMain, availableMain)}\n\n${cleanSuffix}`.trim();
  }
  return truncateText(combined, maxLength);
}

function ensureTextIncludesUrl(text, url, maxLength) {
  const clean = cleanText(text, maxLength);
  const canonicalUrl = cleanText(url, 1000);
  if (!canonicalUrl || clean.includes(canonicalUrl)) {
    return truncateText(clean, maxLength);
  }
  return composeWithSuffix(clean, canonicalUrl, maxLength);
}

function buildPostContent(input = {}, options = {}) {
  const card = input.card || {};
  const cardUrl = absoluteUrl(input.cardUrl || publicCardUrl(card), options.env);
  const imageUrl = absoluteUrl(input.imageUrl || publicImageUrl(card), options.env);
  const hashtags = hashtagsFromInput(input.hashtags);
  const suppliedMessage = cleanText(input.message, TELEGRAM_MESSAGE_LIMIT);
  const title = cardDisplayTitle(card);
  const price = formatPkn(card.pricePkn || card.price_pkn || card.lowestAskPkn || card.lowest_ask_pkn);
  const hook = cleanText(input.hook, 120) ||
    (price ? 'Hot on Pokoin:' : 'New Pokoin marketplace signal:');
  const details = [
    price ? `Floor from ${price}` : '',
    card.rarity,
    card.artist || card.illustrator ? `Illustrated by ${card.artist || card.illustrator}` : '',
  ].filter(Boolean);
  const generated = [
    `${hook} ${title}`,
    details.join(' - '),
    'Explore, list, or buy with PKN on Pokoin.',
  ].filter(Boolean).join('\n');
  const baseMessage = suppliedMessage || generated;
  const suffix = [cardUrl, hashtags.join(' ')].filter(Boolean).join('\n');
  const telegramText = composeWithSuffix(baseMessage, suffix, TELEGRAM_MESSAGE_LIMIT);
  const xText = composeWithSuffix(baseMessage, suffix, X_POST_LIMIT);
  return {
    text: telegramText,
    telegramText,
    telegramCaption: truncateText(telegramText, TELEGRAM_CAPTION_LIMIT),
    xText,
    cardUrl,
    imageUrl,
    hashtags,
    card,
  };
}

function socialAgentEndpoint(env = process.env) {
  const configured = cleanText(
    env.ORACLE_SOCIAL_AGENT_URL ||
      env.SOCIAL_AGENT_ENDPOINT ||
      env.SOCIAL_AGENT_URL,
    500,
  );
  const endpoint = configured || DEFAULT_SOCIAL_AGENT_ENDPOINT;
  try {
    const url = new URL(endpoint);
    if (!url.pathname || url.pathname === '/') {
      url.pathname = '/social-post';
    }
    return url.toString().replace(/\/+$/, '');
  } catch (_) {
    return DEFAULT_SOCIAL_AGENT_ENDPOINT;
  }
}

function socialAgentToken(env = process.env) {
  return cleanText(
    env.SOCIAL_AGENT_TOKEN ||
      env.ORACLE_SOCIAL_AGENT_TOKEN ||
      env.POKOIN_SOCIAL_AGENT_TOKEN,
    2000,
  );
}

function socialAgentInstructions({ targets = ['telegram', 'x'], cardUrl = '' } = {}) {
  return [
    'You are the Pokoin social post agent, not the Pokontact support chatbot.',
    'Write promotional marketplace social copy for Pokoin Card Reserve and the PKN card marketplace.',
    'Voice: collector-friendly, confident, concise, playful but not support-chatty. Do not say "I can help" or ask follow-up questions.',
    'Grounding: use only the supplied card, price, listing, hot-score, and URL data. Do not invent prices, active listings, stock, sales, rarity, or popularity.',
    'If price/listing data is missing, talk about browsing or collecting the card without claiming it is available or cheap.',
    'Always include the canonical Pokoin URL exactly once in each post when a URL is supplied.',
    'X rules: max 280 characters, plain text, include the URL, no thread language, no unsupported claims.',
    'Telegram rules: may be richer than X, can use line breaks, include the URL, stay under 1024 characters when it may be used as a photo caption.',
    'Avoid financial-advice phrasing and avoid support chatbot phrasing.',
    `Requested targets: ${targets.join(', ')}.`,
    cardUrl ? `Canonical URL that must be included: ${cardUrl}` : '',
    'Return only JSON with string fields telegramText and xText, plus optional hashtags array.',
  ].filter(Boolean).join('\n');
}

function normalizeAgentContent(payload = {}, fallbackContent) {
  const telegramText = cleanText(
    payload.telegramText ||
      payload.telegram_text ||
      payload.telegram ||
      payload.text,
    TELEGRAM_MESSAGE_LIMIT,
  );
  const xText = cleanText(
    payload.xText ||
      payload.x_text ||
      payload.x ||
      payload.twitterText ||
      payload.twitter,
    X_POST_LIMIT,
  );
  if (!telegramText && !xText) {
    return null;
  }
  const telegramWithUrl = ensureTextIncludesUrl(
    telegramText || fallbackContent.telegramText || fallbackContent.text,
    fallbackContent.cardUrl,
    TELEGRAM_MESSAGE_LIMIT,
  );
  const xWithUrl = ensureTextIncludesUrl(
    xText || fallbackContent.xText,
    fallbackContent.cardUrl,
    X_POST_LIMIT,
  );
  const content = {
    ...fallbackContent,
    text: telegramWithUrl,
    telegramText: telegramWithUrl,
    xText: xWithUrl,
    agent: {
      ok: true,
      source: cleanText(payload.source, 80) || 'social-agent',
      provider: cleanText(payload.provider, 80),
      model: cleanText(payload.model, 120),
    },
  };
  content.telegramCaption = truncateText(content.telegramText, TELEGRAM_CAPTION_LIMIT);
  return content;
}

async function callSocialAgent(input = {}, options = {}) {
  const env = options.env || process.env;
  const token = socialAgentToken(env);
  if (!token) {
    return null;
  }
  const fallbackContent = input.fallbackContent || buildPostContent(input, options);
  const endpoint = socialAgentEndpoint(env);
  const fetchImpl = options.fetchImpl || fetch;
  const controller = new AbortController();
  const timeoutMs = Number(env.SOCIAL_AGENT_TIMEOUT_MS || SOCIAL_AGENT_TIMEOUT_MS);
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetchImpl(endpoint, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        instructions: socialAgentInstructions({
          targets: input.targets,
          cardUrl: fallbackContent.cardUrl,
        }),
        targets: input.targets || ['telegram', 'x'],
        card: fallbackContent.card || input.card || {},
        cardUrl: fallbackContent.cardUrl,
        imageUrl: fallbackContent.imageUrl,
        deterministic: {
          telegramText: fallbackContent.telegramText,
          xText: fallbackContent.xText,
          hashtags: fallbackContent.hashtags,
        },
        context: input.context || {},
      }),
      signal: controller.signal,
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(payload.error || `Social agent returned ${response.status}.`);
    }
    return normalizeAgentContent(payload, fallbackContent);
  } finally {
    clearTimeout(timeout);
  }
}

async function contentWithOptionalAgent(input = {}, options = {}) {
  const fallbackContent = input.fallbackContent || buildPostContent(input, options);
  if (!options.useAgent) {
    return {
      ...fallbackContent,
      agent: { ok: false, skipped: true, reason: 'agent_disabled' },
    };
  }
  try {
    const agentContent = await callSocialAgent({
      ...input,
      fallbackContent,
    }, options);
    if (agentContent) {
      return agentContent;
    }
    return {
      ...fallbackContent,
      agent: { ok: false, skipped: true, reason: 'SOCIAL_AGENT_TOKEN is not configured.' },
    };
  } catch (error) {
    return {
      ...fallbackContent,
      agent: {
        ok: false,
        fallback: true,
        error: error.name === 'AbortError' ? 'Social agent timed out.' : error.message,
      },
    };
  }
}

function cleanTargets(value) {
  const source = value === undefined || value === null || value === ''
    ? ['telegram', 'x']
    : Array.isArray(value)
      ? value
      : String(value).split(',');
  const targets = source
    .map((item) => String(item || '').trim().toLowerCase())
    .map((item) => (item === 'twitter' ? 'x' : item))
    .filter(Boolean);
  const uniqueTargets = [...new Set(targets)];
  const unsupported = uniqueTargets.filter((target) => !['telegram', 'x'].includes(target));
  if (unsupported.length) {
    const error = new Error(`Unsupported social target: ${unsupported.join(', ')}.`);
    error.statusCode = 400;
    throw error;
  }
  if (!uniqueTargets.length) {
    const error = new Error('At least one social target is required.');
    error.statusCode = 400;
    throw error;
  }
  return uniqueTargets;
}

function timingSafeEqualText(left, right) {
  const leftBuffer = Buffer.from(String(left || ''));
  const rightBuffer = Buffer.from(String(right || ''));
  if (!leftBuffer.length || leftBuffer.length !== rightBuffer.length) return false;
  return crypto.timingSafeEqual(leftBuffer, rightBuffer);
}

function configuredSocialSecret(env = process.env) {
  return cleanText(
    env.SOCIAL_AUTOPOST_SECRET ||
      env.SOCIAL_AUTOPST_SECRET ||
      env.POKOIN_SOCIAL_AUTOPOST_SECRET,
    500,
  );
}

function requestHeader(req, name) {
  return cleanText(req.headers?.[name.toLowerCase()] || req.headers?.[name], 1000);
}

function bearerToken(req) {
  const header = requestHeader(req, 'authorization');
  return header.toLowerCase().startsWith('bearer ') ? header.slice('Bearer '.length).trim() : '';
}

async function authorizeSocialRequest(req, env = process.env) {
  const secret = configuredSocialSecret(env);
  const cronSecret = cleanText(env.CRON_SECRET, 500);
  const suppliedSecret = requestHeader(req, 'x-pokoin-social-secret') ||
    requestHeader(req, 'x-social-autopost-secret') ||
    requestHeader(req, 'x-social-autopst-secret');
  const bearer = bearerToken(req);
  if (
    (secret && (timingSafeEqualText(suppliedSecret, secret) || timingSafeEqualText(bearer, secret))) ||
    (cronSecret && timingSafeEqualText(bearer, cronSecret))
  ) {
    return { type: cronSecret && timingSafeEqualText(bearer, cronSecret) ? 'cron_secret' : 'shared_secret' };
  }

  try {
    const user = await authorizeSearchDebugRequest(req);
    return { type: 'firebase_admin', uid: user.uid, email: user.email, username: user.username };
  } catch (error) {
    const authError = new Error('Social autoposter access denied.');
    authError.statusCode = error.statusCode === 403 ? 403 : 401;
    throw authError;
  }
}

function cleanWindow(value) {
  const normalized = String(value || '24h').trim().toLowerCase();
  return ['1h', '24h', '7d'].includes(normalized) ? normalized : '24h';
}

function scoreColumn(window) {
  switch (cleanWindow(window)) {
    case '1h':
      return 'hot_score_1h';
    case '7d':
      return 'hot_score_7d';
    default:
      return 'hot_score_24h';
  }
}

function cleanLimit(value, fallback = 12) {
  const limit = Number(value);
  if (!Number.isFinite(limit)) return fallback;
  return Math.min(Math.max(Math.trunc(limit), 1), 100);
}

function mapCardRow(row = {}) {
  const card = {
    cardId: String(row.card_id || row.blueprint_id || ''),
    blueprintId: String(row.blueprint_id || row.card_id || ''),
    name: row.name || row.card_name || '',
    setName: row.set_name || row.expansion_name || '',
    cardNumber: row.card_number || row.collector_number || row.expansion_number || '',
    rarity: row.rarity || '',
    cardType: row.card_type || '',
    productVariant: row.product_variant || '',
    itemKind: row.item_kind || 'single',
    productType: row.product_type || 'card',
    trainerName: row.trainer_name || '',
    artist: row.artist || row.illustrator || '',
    illustrator: row.illustrator || row.artist || '',
    imageUrl: row.image_url || '',
    cdnImageUrl: row.cdn_image_url || '',
    previewImageUrl: row.preview_image_url || '',
    homepageImageUrl: row.homepage_image_url || '',
    pricePkn: row.lowest_ask_pkn == null ? null : Number(row.lowest_ask_pkn),
    listingCount: Number(row.active_listing_count || 0),
    listedQuantity: Number(row.listed_quantity || 0),
    hotScore1h: Number(row.hot_score_1h || 0),
    hotScore24h: Number(row.hot_score_24h || 0),
    hotScore7d: Number(row.hot_score_7d || 0),
    lastEventAt: row.last_event_at || null,
  };
  return {
    ...card,
    cardUrl: publicCardUrl(card),
    imageUrl: publicImageUrl(card),
  };
}

async function fetchCardById(cardId, query = marketplaceQuery) {
  const cleanId = cleanNumericId(cardId);
  if (!cleanId) return null;
  const result = await query(
    `
      select
        c.card_id,
        c.name,
        c.set_name,
        c.card_number,
        c.rarity,
        c.card_type,
        c.product_variant,
        c.item_kind,
        c.product_type,
        c.trainer_name,
        c.image_url,
        c.cdn_image_url,
        c.preview_image_url,
        c.homepage_image_url,
        artist.artist,
        artist.illustrator,
        price.lowest_ask_pkn,
        price.active_listing_count,
        price.listed_quantity
      from public.marketplace_search_candidates c
      left join public.marketplace_blueprint_artists artist
        on artist.blueprint_id = c.card_id
      left join public.marketplace_blueprint_price_summary price
        on price.blueprint_id = c.card_id
      where c.card_id = $1::bigint
      limit 1
    `,
    [cleanId],
  );
  return result.rows[0] ? mapCardRow(result.rows[0]) : null;
}

async function selectHotCard(options = {}) {
  const query = options.query || marketplaceQuery;
  const window = cleanWindow(options.window);
  const orderBy = scoreColumn(window);
  const limit = cleanLimit(options.limit);
  const result = await query(
    `
      with hot as (
        select *
        from public.marketplace_hot_blueprints
        where ${orderBy} > 0
        order by ${orderBy} desc, last_event_at desc nulls last, blueprint_id desc
        limit $1
      )
      select
        hot.blueprint_id,
        hot.name,
        hot.set_name,
        hot.card_number,
        hot.rarity,
        hot.card_type,
        hot.item_kind,
        hot.product_type,
        hot.hot_score_1h,
        hot.hot_score_24h,
        hot.hot_score_7d,
        hot.last_event_at,
        c.product_variant,
        c.trainer_name,
        c.image_url,
        c.cdn_image_url,
        c.preview_image_url,
        c.homepage_image_url,
        artist.artist,
        artist.illustrator,
        price.lowest_ask_pkn,
        price.active_listing_count,
        price.listed_quantity
      from hot
      left join public.marketplace_search_candidates c
        on c.card_id = hot.blueprint_id
      left join public.marketplace_blueprint_artists artist
        on artist.blueprint_id = hot.blueprint_id
      left join public.marketplace_blueprint_price_summary price
        on price.blueprint_id = hot.blueprint_id
      order by hot.${orderBy} desc, hot.last_event_at desc nulls last, hot.blueprint_id desc
      limit 1
    `,
    [limit],
  );
  return result.rows[0] ? mapCardRow(result.rows[0]) : null;
}

function cardFromBody(body = {}) {
  const source = body.card && typeof body.card === 'object' ? body.card : body;
  const card = {
    cardId: source.cardId || source.card_id || body.cardId || body.blueprintId,
    blueprintId: source.blueprintId || source.blueprint_id || body.blueprintId || body.cardId,
    title: source.title || source.cardTitle || body.cardTitle,
    name: source.name || source.cardName || body.cardName,
    setName: source.setName || source.set_name || body.setName,
    cardNumber: source.cardNumber || source.card_number || source.collectorNumber || body.cardNumber || body.collectorNumber,
    rarity: source.rarity || body.rarity,
    artist: source.artist || source.illustrator || body.artist,
    imageUrl: source.imageUrl || source.image_url || body.imageUrl,
    cdnImageUrl: source.cdnImageUrl || source.cdn_image_url,
    previewImageUrl: source.previewImageUrl || source.preview_image_url,
    pricePkn: source.pricePkn || source.price_pkn || body.pricePkn,
    cardUrl: source.cardUrl || source.card_url || body.cardUrl || body.card_url || body.url,
    listingUrl: source.listingUrl || source.listing_url || body.listingUrl,
  };
  return Object.fromEntries(Object.entries(card).filter(([, value]) => value !== undefined && value !== null && value !== ''));
}

async function resolveManualPostInput(body = {}, options = {}) {
  const suppliedCard = cardFromBody(body);
  const query = options.query || marketplaceQuery;
  const fetchedCard = suppliedCard.cardId || suppliedCard.blueprintId
    ? await fetchCardById(suppliedCard.cardId || suppliedCard.blueprintId, query).catch(() => null)
    : null;
  const card = {
    ...(fetchedCard || {}),
    ...suppliedCard,
  };
  const content = await contentWithOptionalAgent({
    message: body.message || body.text,
    hook: body.hook,
    hashtags: body.hashtags,
    card,
    cardUrl: body.cardUrl || body.listingUrl || card.cardUrl,
    imageUrl: body.imageUrl || card.imageUrl,
    targets: options.targets,
    context: { source: 'manual' },
  }, {
    ...options,
    useAgent: options.useAgent,
  });
  if (!content.text) {
    const error = new Error('A post message or card payload is required.');
    error.statusCode = 400;
    throw error;
  }
  return content;
}

async function telegramApiRequest(method, payload, options = {}) {
  const token = cleanText(options.env?.TELEGRAM_BOT_TOKEN || process.env.TELEGRAM_BOT_TOKEN, 500);
  if (!token) {
    const error = new Error('TELEGRAM_BOT_TOKEN is not configured.');
    error.statusCode = 500;
    throw error;
  }
  const fetchImpl = options.fetchImpl || fetch;
  const response = await fetchImpl(`https://api.telegram.org/bot${token}/${method}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  const responseBody = await response.json().catch(() => ({}));
  if (!response.ok || responseBody.ok === false) {
    const error = new Error(responseBody.description || `Telegram ${method} failed.`);
    error.statusCode = response.status || 502;
    throw error;
  }
  return responseBody;
}

async function telegramApiFormRequest(method, form, options = {}) {
  const token = cleanText(options.env?.TELEGRAM_BOT_TOKEN || process.env.TELEGRAM_BOT_TOKEN, 500);
  if (!token) {
    const error = new Error('TELEGRAM_BOT_TOKEN is not configured.');
    error.statusCode = 500;
    throw error;
  }
  const fetchImpl = options.fetchImpl || fetch;
  const response = await fetchImpl(`https://api.telegram.org/bot${token}/${method}`, {
    method: 'POST',
    body: form,
  });
  const responseBody = await response.json().catch(() => ({}));
  if (!response.ok || responseBody.ok === false) {
    const error = new Error(responseBody.description || `Telegram ${method} failed.`);
    error.statusCode = response.status || 502;
    throw error;
  }
  return responseBody;
}

function extensionFromContentType(contentType) {
  const normalized = cleanText(contentType, 120).split(';')[0].trim().toLowerCase();
  if (normalized === 'image/png') return 'png';
  if (normalized === 'image/webp') return 'webp';
  if (normalized === 'image/gif') return 'gif';
  return 'jpg';
}

async function downloadSocialImage(imageUrl, options = {}) {
  const url = absoluteUrl(imageUrl, options.env);
  if (!url) {
    const error = new Error('No public image URL is available for social media upload.');
    error.statusCode = 400;
    throw error;
  }
  const fetchImpl = options.fetchImpl || fetch;
  const response = await fetchImpl(url, {
    headers: {
      Accept: 'image/avif,image/webp,image/png,image/jpeg,image/*,*/*;q=0.8',
      'User-Agent': 'PokoinSocialBot/1.0 (+https://pokoin.com)',
    },
  });
  if (!response.ok) {
    const error = new Error(`Failed to fetch social image: ${response.status}.`);
    error.statusCode = response.status || 502;
    throw error;
  }
  const contentType = cleanText(response.headers?.get?.('content-type'), 120) || 'image/jpeg';
  const bytes = Buffer.from(await response.arrayBuffer());
  const maxBytes = Number(options.env?.SOCIAL_IMAGE_MAX_BYTES || process.env.SOCIAL_IMAGE_MAX_BYTES || SOCIAL_IMAGE_MAX_BYTES);
  if (bytes.length > maxBytes) {
    const error = new Error(`Social image is too large (${bytes.length} bytes).`);
    error.statusCode = 413;
    throw error;
  }
  if (!contentType.toLowerCase().startsWith('image/')) {
    const error = new Error(`Social image response is not an image (${contentType}).`);
    error.statusCode = 415;
    throw error;
  }
  return {
    bytes,
    contentType,
    filename: `pokoin-card.${extensionFromContentType(contentType)}`,
    url,
  };
}

function appendImageBlob(form, fieldName, image) {
  if (typeof Blob === 'undefined') {
    const error = new Error('Blob is not available in this Node runtime.');
    error.statusCode = 500;
    throw error;
  }
  form.append(fieldName, new Blob([image.bytes], { type: image.contentType }), image.filename);
}

async function postToTelegram(content, options = {}) {
  const env = options.env || process.env;
  const chatId = cleanText(env.TELEGRAM_CHANNEL_ID, 200);
  if (!chatId && !options.dryRun) {
    const error = new Error('TELEGRAM_CHANNEL_ID is not configured.');
    error.statusCode = 500;
    throw error;
  }
  const usePhoto = Boolean(content.imageUrl) && options.sendPhoto !== false;
  const method = usePhoto ? 'sendPhoto' : 'sendMessage';
  const payload = usePhoto
    ? {
        chat_id: chatId,
        photo: content.imageUrl,
        caption: content.telegramCaption,
        disable_notification: options.silent === true,
      }
    : {
        chat_id: chatId,
        text: truncateText(content.telegramText || content.text, TELEGRAM_MESSAGE_LIMIT),
        disable_notification: options.silent === true,
      };
  if (options.dryRun) {
    return { ok: true, dryRun: true, platform: 'telegram', method, payload: { ...payload, chat_id: chatId ? '[configured]' : '' } };
  }
  if (usePhoto) {
    const image = await downloadSocialImage(content.imageUrl, options);
    const form = new FormData();
    form.append('chat_id', chatId);
    form.append('caption', content.telegramCaption);
    form.append('disable_notification', options.silent === true ? 'true' : 'false');
    appendImageBlob(form, 'photo', image);
    const sentPhoto = await telegramApiFormRequest('sendPhoto', form, options);
    return {
      ok: true,
      platform: 'telegram',
      method: 'sendPhoto',
      messageId: sentPhoto.result?.message_id,
      uploadedImage: true,
    };
  }
  const sent = await telegramApiRequest(method, payload, options);
  return {
    ok: true,
    platform: 'telegram',
    method,
    messageId: sent.result?.message_id,
  };
}

async function uploadXMedia(content, options = {}) {
  if (!content.imageUrl || options.sendPhoto === false || options.attachMedia === false) {
    return null;
  }
  const env = options.env || process.env;
  const oauth1 = options.oauth1 || xOAuth1Credentials(env);
  if (oauth1) {
    return uploadXMediaOAuth1(content, {
      ...options,
      oauth1,
    });
  }
  const token = cleanText(
    env.X_OAUTH2_ACCESS_TOKEN ||
      env.X_ACCESS_TOKEN ||
      env.X_USER_ACCESS_TOKEN ||
      env.X_BEARER_TOKEN,
    2000,
  );
  if (!token) return null;
  const image = await downloadSocialImage(content.imageUrl, options);
  const fetchImpl = options.fetchImpl || fetch;
  const endpoint = cleanText(env.X_MEDIA_UPLOAD_URL, 500) || 'https://api.x.com/2/media/upload';
  const authHeaders = { Authorization: `Bearer ${token}` };
  const initForm = new FormData();
  initForm.append('command', 'INIT');
  initForm.append('media_type', image.contentType.split(';')[0].trim());
  initForm.append('media_category', 'tweet_image');
  initForm.append('total_bytes', String(image.bytes.length));
  const initResponse = await fetchImpl(endpoint, {
    method: 'POST',
    headers: authHeaders,
    body: initForm,
  });
  const initPayload = await initResponse.json().catch(() => ({}));
  if (!initResponse.ok) {
    const error = new Error(initPayload.detail || initPayload.title || initPayload.message || `X media INIT failed (${initResponse.status}).`);
    error.statusCode = initResponse.status || 502;
    throw error;
  }
  const mediaId = cleanText(initPayload.data?.id || initPayload.media_id_string || initPayload.media_id, 120);
  if (!mediaId) {
    const error = new Error('X media INIT did not return a media id.');
    error.statusCode = 502;
    throw error;
  }

  const appendForm = new FormData();
  appendForm.append('command', 'APPEND');
  appendForm.append('media_id', mediaId);
  appendForm.append('segment_index', '0');
  appendImageBlob(appendForm, 'media', image);
  const appendResponse = await fetchImpl(endpoint, {
    method: 'POST',
    headers: authHeaders,
    body: appendForm,
  });
  if (!appendResponse.ok) {
    const appendPayload = await appendResponse.json().catch(() => ({}));
    const error = new Error(appendPayload.detail || appendPayload.title || appendPayload.message || `X media APPEND failed (${appendResponse.status}).`);
    error.statusCode = appendResponse.status || 502;
    throw error;
  }

  const finalizeForm = new FormData();
  finalizeForm.append('command', 'FINALIZE');
  finalizeForm.append('media_id', mediaId);
  const finalizeResponse = await fetchImpl(endpoint, {
    method: 'POST',
    headers: authHeaders,
    body: finalizeForm,
  });
  const finalizePayload = await finalizeResponse.json().catch(() => ({}));
  if (!finalizeResponse.ok) {
    const error = new Error(finalizePayload.detail || finalizePayload.title || finalizePayload.message || `X media FINALIZE failed (${finalizeResponse.status}).`);
    error.statusCode = finalizeResponse.status || 502;
    throw error;
  }
  return mediaId;
}

function oauthPercentEncode(value) {
  return encodeURIComponent(String(value))
    .replace(/[!'()*]/g, (char) => `%${char.charCodeAt(0).toString(16).toUpperCase()}`);
}

function xOAuth1Credentials(env = process.env) {
  const consumerKey = cleanText(env.X_API_KEY || env.X_CONSUMER_KEY || env.TWITTER_API_KEY, 500);
  const consumerSecret = cleanText(
    env.X_API_SECRET ||
      env.X_API_KEY_SECRET ||
      env.X_CONSUMER_SECRET ||
      env.TWITTER_API_SECRET ||
      env.TWITTER_API_KEY_SECRET,
    1000,
  );
  const accessToken = cleanText(
    env.X_OAUTH1_ACCESS_TOKEN ||
      env.X_ACCESS_TOKEN ||
      env.TWITTER_ACCESS_TOKEN,
    1000,
  );
  const accessTokenSecret = cleanText(
    env.X_OAUTH1_ACCESS_TOKEN_SECRET ||
      env.X_ACCESS_TOKEN_SECRET ||
      env.TWITTER_ACCESS_TOKEN_SECRET,
    1000,
  );
  if (!consumerKey || !consumerSecret || !accessToken || !accessTokenSecret) {
    return null;
  }
  return {
    consumerKey,
    consumerSecret,
    accessToken,
    accessTokenSecret,
  };
}

function createOAuth1Header({ method, url, credentials, extraParams = {}, nonce, timestamp }) {
  const oauthParams = {
    oauth_consumer_key: credentials.consumerKey,
    oauth_nonce: nonce || crypto.randomBytes(16).toString('hex'),
    oauth_signature_method: 'HMAC-SHA1',
    oauth_timestamp: timestamp || Math.floor(Date.now() / 1000).toString(),
    oauth_token: credentials.accessToken,
    oauth_version: '1.0',
  };
  const signatureParams = {
    ...extraParams,
    ...oauthParams,
  };
  const normalizedParams = Object.keys(signatureParams)
    .sort()
    .map((key) => `${oauthPercentEncode(key)}=${oauthPercentEncode(signatureParams[key])}`)
    .join('&');
  const parsedUrl = new URL(url);
  const baseUrl = `${parsedUrl.protocol}//${parsedUrl.host}${parsedUrl.pathname}`;
  const signatureBase = [
    method.toUpperCase(),
    oauthPercentEncode(baseUrl),
    oauthPercentEncode(normalizedParams),
  ].join('&');
  const signingKey = `${oauthPercentEncode(credentials.consumerSecret)}&${oauthPercentEncode(credentials.accessTokenSecret)}`;
  const signature = crypto
    .createHmac('sha1', signingKey)
    .update(signatureBase)
    .digest('base64');
  const headerParams = {
    ...oauthParams,
    oauth_signature: signature,
  };
  return `OAuth ${Object.keys(headerParams)
    .sort()
    .map((key) => `${oauthPercentEncode(key)}="${oauthPercentEncode(headerParams[key])}"`)
    .join(', ')}`;
}

async function uploadXMediaOAuth1(content, options = {}) {
  const env = options.env || process.env;
  const credentials = options.oauth1 || xOAuth1Credentials(env);
  if (!credentials) return null;
  const image = await downloadSocialImage(content.imageUrl, options);
  const fetchImpl = options.fetchImpl || fetch;
  const endpoint = cleanText(env.X_OAUTH1_MEDIA_UPLOAD_URL, 500) || 'https://upload.twitter.com/1.1/media/upload.json';
  const form = new FormData();
  appendImageBlob(form, 'media', image);
  const response = await fetchImpl(endpoint, {
    method: 'POST',
    headers: {
      Authorization: createOAuth1Header({
        method: 'POST',
        url: endpoint,
        credentials,
      }),
    },
    body: form,
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(payload.errors?.[0]?.message || payload.error || `X OAuth 1.0a media upload failed (${response.status}).`);
    error.statusCode = response.status || 502;
    throw error;
  }
  const mediaId = cleanText(payload.media_id_string || payload.media_id || payload.data?.id, 120);
  if (!mediaId) {
    const error = new Error('X OAuth 1.0a media upload did not return a media id.');
    error.statusCode = 502;
    throw error;
  }
  return mediaId;
}

async function postToX(content, options = {}) {
  const env = options.env || process.env;
  const oauth1 = xOAuth1Credentials(env);
  const token = cleanText(
    env.X_OAUTH2_ACCESS_TOKEN ||
      env.X_ACCESS_TOKEN ||
      env.X_USER_ACCESS_TOKEN ||
      env.X_BEARER_TOKEN,
    2000,
  );
  if (!token && !oauth1 && !options.dryRun) {
    const error = new Error('X user credentials are not configured.');
    error.statusCode = 500;
    throw error;
  }
  const payload = { text: truncateText(content.xText || content.text, X_POST_LIMIT) };
  if (content.imageUrl && options.sendPhoto !== false && options.attachMedia !== false) {
    payload.media = { media_ids: ['[uploaded]'] };
  }
  if (options.dryRun) {
    return { ok: true, dryRun: true, platform: 'x', endpoint: '/2/tweets', payload };
  }
  const fetchImpl = options.fetchImpl || fetch;
  const endpoint = cleanText(env.X_CREATE_POST_URL, 500) || 'https://api.x.com/2/tweets';
  const mediaId = await uploadXMedia(content, {
    ...options,
    oauth1,
  });
  if (mediaId) {
    payload.media = { media_ids: [mediaId] };
  } else {
    delete payload.media;
  }
  const response = await fetchImpl(endpoint, {
    method: 'POST',
    headers: {
      Authorization: oauth1
        ? createOAuth1Header({
            method: 'POST',
            url: endpoint,
            credentials: oauth1,
          })
        : `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });
  const responseBody = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(responseBody.detail || responseBody.title || responseBody.message || 'X post creation failed.');
    error.statusCode = response.status || 502;
    throw error;
  }
  return {
    ok: true,
    platform: 'x',
    postId: responseBody.data?.id,
    text: responseBody.data?.text,
    mediaId,
  };
}

async function postToTargets(targets, content, options = {}) {
  const results = {};
  for (const target of targets) {
    try {
      results[target] = target === 'telegram'
        ? await postToTelegram(content, options)
        : await postToX(content, options);
    } catch (error) {
      results[target] = {
        ok: false,
        error: error.message || `${target} post failed.`,
        statusCode: error.statusCode || 500,
      };
    }
  }
  return {
    ok: Object.values(results).every((result) => result.ok),
    results,
  };
}

module.exports = {
  DEFAULT_SOCIAL_AGENT_ENDPOINT,
  TELEGRAM_CAPTION_LIMIT,
  TELEGRAM_MESSAGE_LIMIT,
  X_POST_LIMIT,
  absoluteUrl,
  authorizeSocialRequest,
  boolValue,
  buildPostContent,
  callSocialAgent,
  cardDisplayTitle,
  cardFromBody,
  cleanLimit,
  cleanTargets,
  cleanText,
  cleanWindow,
  composeWithSuffix,
  createOAuth1Header,
  downloadSocialImage,
  ensureTextIncludesUrl,
  configuredSocialSecret,
  contentWithOptionalAgent,
  fetchCardById,
  formatPkn,
  normalizeAgentContent,
  postToTargets,
  postToTelegram,
  postToX,
  uploadXMedia,
  uploadXMediaOAuth1,
  publicCardUrl,
  publicImageUrl,
  resolveManualPostInput,
  selectHotCard,
  siteOrigin,
  socialAgentEndpoint,
  socialAgentInstructions,
  socialAgentToken,
  truncateText,
  xOAuth1Credentials,
};
