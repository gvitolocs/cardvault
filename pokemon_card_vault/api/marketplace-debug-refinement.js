const { marketplaceQuery } = require('./_marketplace_db');
const { authorizeSearchDebugRequest } = require('./_search_debug_auth');
const cardmarketRedirect = require('./cardmarket-redirect');

function cleanLimit(value) {
  const limit = Number(value);
  if (!Number.isFinite(limit)) return 1000;
  return Math.min(Math.max(Math.trunc(limit), 1), 1000);
}

function cleanLocale(value) {
  const locale = String(value || 'en').trim().toLowerCase();
  return /^[a-z]{2}$/.test(locale) ? locale : 'en';
}

function cleanBlueprintId(value) {
  const id = Number(value);
  return Number.isSafeInteger(id) && id > 0 ? id : 0;
}

function cleanText(value, maxLength = 240) {
  return String(value || '').trim().slice(0, maxLength);
}

function cleanCardmarketUrl(value) {
  const text = cleanText(value, 600);
  let parsed;
  try {
    parsed = new URL(text);
  } catch {
    return '';
  }
  if (parsed.protocol !== 'https:') return '';
  if (parsed.hostname !== 'www.cardmarket.com' && parsed.hostname !== 'cardmarket.com') {
    return '';
  }
  if (!parsed.pathname.startsWith('/en/Pokemon/Products/Singles')) {
    return '';
  }
  parsed.hash = '';
  return parsed.toString();
}

function cleanStringArray(value) {
  if (!Array.isArray(value)) return [];
  return value
    .map((entry) => cleanText(entry, 80))
    .filter(Boolean)
    .slice(0, 12);
}

async function ensureRefinementLogTable() {
  await marketplaceQuery(`
    create table if not exists public.marketplace_cm_refinement_log (
      id bigserial primary key,
      blueprint_id bigint not null references public.cardtrader_pokemon_blueprints(id) on delete cascade,
      cardmarket_locale text not null default 'en',
      pasted_cardmarket_url text not null,
      candidate_cardmarket_url text not null default '',
      card_name text not null default '',
      expansion_name text not null default '',
      collector_number text not null default '',
      cardmarket_ids text[] not null default '{}',
      status text not null default 'pending' check (
        status in ('pending', 'implemented', 'rejected')
      ),
      debug_uid text not null default '',
      debug_email text not null default '',
      debug_username text not null default '',
      notes text not null default '',
      created_at timestamptz not null default now(),
      implemented_at timestamptz
    )
  `);
  await marketplaceQuery(`
    create index if not exists marketplace_cm_refinement_log_blueprint_idx
      on public.marketplace_cm_refinement_log (blueprint_id, status, created_at desc)
  `);
  await marketplaceQuery(`
    create index if not exists marketplace_cm_refinement_log_status_idx
      on public.marketplace_cm_refinement_log (status, created_at desc)
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

async function randomRows(limit, locale) {
  const verifiedLimit = Math.max(1, Math.floor(limit * 0.35));
  const candidateLimit = Math.max(1, limit - verifiedLimit);
  const result = await marketplaceQuery(
    `
      with base as (
        select
          versions.card_id,
          versions.name,
          versions.expansion_name,
          versions.expansion_number,
          versions.product_variant,
          versions.product_type,
          coalesce(
            versions.preview_image_url,
            blueprints.preview_image_url,
            versions.cdn_image_url,
            blueprints.cdn_image_url,
            versions.image_url,
            blueprints.image_url
          ) as image_url,
          blueprints.card_market_ids,
          coalesce(product_parsing.cardmarket_url, '') as stored_cardmarket_url,
          coalesce(product_parsing.match_status, '') as stored_match_status
        from public.marketplace_card_versions versions
        left join public.cardtrader_pokemon_blueprints blueprints
          on blueprints.id = versions.card_id
        left join lateral (
          select cardmarket_url, match_status, priority, verified_at, updated_at
          from (
            select
              link.cardmarket_url,
              link.confidence as match_status,
              0 as priority,
              link.verified_at,
              link.updated_at
            from public.marketplace_cm_verified_links link
            where link.blueprint_id = versions.card_id
              and link.cardmarket_locale = $3
              and link.confidence in ('verified', 'manual')
            union all
            select
              parsing.cardmarket_url,
              parsing.match_status,
              1 as priority,
              parsing.verified_at,
              parsing.updated_at
            from public.marketplace_cm_product_parsing parsing
            where parsing.blueprint_id = versions.card_id
              and parsing.cardmarket_locale = $3
              and parsing.match_status in ('verified', 'manual')
          ) stored
          order by priority, verified_at desc nulls last, updated_at desc
          limit 1
        ) product_parsing on true
        where versions.product_type = 'card'
          and versions.name is not null
          and versions.expansion_name is not null
          and versions.expansion_number is not null
      ), candidate_rows as (
        select *, 'candidate_review' as review_bucket
        from base
        where stored_cardmarket_url = ''
        order by random()
        limit $1
      ), verified_rows as (
        select *, 'verified_audit' as review_bucket
        from base
        where stored_cardmarket_url <> ''
        order by random()
        limit $2
      )
      select *
      from (
        select * from candidate_rows
        union all
        select * from verified_rows
      ) rows
      order by random()
    `,
    [candidateLimit, verifiedLimit, locale],
  );
  return result.rows;
}

async function saveRefinementLog(body, user, locale) {
  const blueprintId = cleanBlueprintId(body?.blueprintId);
  const pastedUrl = cleanCardmarketUrl(body?.cardmarketUrl);
  if (!blueprintId || !pastedUrl) {
    const error = new Error('Paste a valid Cardmarket singles URL for this blueprint.');
    error.statusCode = 400;
    throw error;
  }
  await ensureRefinementLogTable();
  const result = await marketplaceQuery(
    `
      insert into public.marketplace_cm_refinement_log (
        blueprint_id,
        cardmarket_locale,
        pasted_cardmarket_url,
        candidate_cardmarket_url,
        card_name,
        expansion_name,
        collector_number,
        cardmarket_ids,
        debug_uid,
        debug_email,
        debug_username,
        notes
      )
      values ($1, $2, $3, $4, $5, $6, $7, $8::text[], $9, $10, $11, $12)
      returning id, created_at
    `,
    [
      blueprintId,
      locale,
      pastedUrl,
      cleanText(body?.candidateCardmarketUrl, 600),
      cleanText(body?.cardName, 240),
      cleanText(body?.expansionName, 240),
      cleanText(body?.collectorNumber, 120),
      cleanStringArray(body?.cardMarketIds),
      cleanText(user.uid, 160),
      cleanText(user.email, 240),
      cleanText(user.username, 120),
      cleanText(body?.notes, 500),
    ],
  );
  await marketplaceQuery(
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
      values ($1, $2, $3, $4, $5, $6, $7, 'debug-refinement-log', 'manual', $8, now())
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
    `,
    [
      blueprintId,
      locale,
      pastedUrl,
      pastedUrl.split('/').filter(Boolean).pop() || '',
      cleanText(body?.cardName, 240),
      cleanText(body?.expansionName, 240),
      cleanText(body?.collectorNumber, 120),
      `Auto-promoted from refinement log ${result.rows[0]?.id || ''}.`,
    ],
  );
  return result.rows[0];
}

async function confirmCurrentUrl(body, user, locale) {
  const blueprintId = cleanBlueprintId(body?.blueprintId);
  const cardmarketUrl = cleanCardmarketUrl(body?.cardmarketUrl);
  if (!blueprintId || !cardmarketUrl) {
    const error = new Error('A valid current Cardmarket singles URL is required.');
    error.statusCode = 400;
    throw error;
  }
  await ensureRefinementLogTable();
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
      values ($1, $2, $3, $4, $5, $6, $7, 'debug-refinement-confirm-ok', 'verified', $8, now())
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
      returning blueprint_id, cardmarket_locale, cardmarket_url, verified_at
    `,
    [
      blueprintId,
      locale,
      cardmarketUrl,
      cardmarketUrl.split('/').filter(Boolean).pop() || '',
      cleanText(body?.cardName, 240),
      cleanText(body?.expansionName, 240),
      cleanText(body?.collectorNumber, 120),
      `Confirmed already OK by ${cleanText(user.email || user.username, 240)} from debug refinement.`,
    ],
  );
  return result.rows[0];
}

module.exports = async function handler(req, res) {
  if (req.method !== 'GET' && req.method !== 'POST') {
    res.setHeader('Allow', 'GET, POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const user = await authorizeSearchDebugRequest(req);
    const requestUrl = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
    const locale = cleanLocale(requestUrl.searchParams.get('locale'));
    if (req.method === 'POST') {
      if (req.body?.action === 'confirm_current_url') {
        const confirmed = await confirmCurrentUrl(req.body || {}, user, locale);
        res.setHeader('Cache-Control', 'no-store');
        return res.status(200).json({ ok: true, confirmed });
      }
      const saved = await saveRefinementLog(req.body || {}, user, locale);
      res.setHeader('Cache-Control', 'no-store');
      return res.status(201).json({ ok: true, log: saved });
    }
    const rows = await randomRows(cleanLimit(requestUrl.searchParams.get('limit')), locale);
    const payload = rows.map((row) => {
      const candidates = cardmarketRedirect.candidateUrls(row, locale);
      const directUrl = row.stored_cardmarket_url || candidates[0] || '';
      return {
        blueprintId: String(row.card_id || ''),
        name: row.name || '',
        expansionName: row.expansion_name || '',
        collectorNumber: row.expansion_number || '',
        productVariant: row.product_variant || '',
        imageUrl: row.image_url || '',
        cardMarketIds: Array.isArray(row.card_market_ids)
          ? row.card_market_ids.map(String)
          : [],
        cardmarketUrl: directUrl,
        cardmarketRedirectUrl: `/api/cardmarket-redirect?id=${encodeURIComponent(String(row.card_id || ''))}`,
        status: row.stored_cardmarket_url ? row.stored_match_status || 'stored' : 'candidate',
        reviewBucket: row.review_bucket || (row.stored_cardmarket_url ? 'verified_audit' : 'candidate_review'),
      };
    });

    res.setHeader('Cache-Control', 'no-store');
    return res.status(200).json({
      rows: payload,
      user,
      generatedAt: new Date().toISOString(),
    });
  } catch (error) {
    const status = error.statusCode || 500;
    return res.status(status).json({
      error: error.message || 'Marketplace debug refinement failed.',
    });
  }
};

module.exports.randomRows = randomRows;
module.exports.saveRefinementLog = saveRefinementLog;
module.exports.confirmCurrentUrl = confirmCurrentUrl;
module.exports.cleanCardmarketUrl = cleanCardmarketUrl;
