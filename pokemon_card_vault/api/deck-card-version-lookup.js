const { marketplaceQuery } = require('./_marketplace_db');
const { withCardEmojiFields } = require('./_marketplace_card_emoji');
const { projectedRaritySql } = require('./_marketplace_card_rarity');
const {
  projectedExpansionNumberSql,
  projectedExpansionNumberIntSql,
} = require('./marketplace-card-versions');

function cors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

function cleanText(value, maxLength = 160) {
  return String(value || '').trim().slice(0, maxLength);
}

function cleanLimit(value, fallback = 24) {
  const limit = Number(value);
  if (!Number.isFinite(limit)) return fallback;
  return Math.min(Math.max(Math.trunc(limit), 1), 100);
}

function compactText(value) {
  return cleanText(value, 240)
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[’']/g, '')
    .replace(/[^a-z0-9]+/g, '');
}

function normalizeCollectorNumber(value) {
  let text = cleanText(value, 80).toLowerCase();
  const match = text.match(/[a-z]*0*([0-9]+[a-z]?)(?=\s*(?:\/|$)|[^a-z0-9])/);
  if (match) return match[1];
  return text.replace(/[^a-z0-9]+/g, '');
}

function normalizeSetCode(value) {
  return cleanText(value, 40).toLowerCase().replace(/[^a-z0-9]+/g, '');
}

function readBody(req) {
  if (req.method !== 'POST') return {};
  return req.body && typeof req.body === 'object' ? req.body : {};
}

function requestInput(req) {
  const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
  const body = readBody(req);
  const get = (key) => body[key] ?? url.searchParams.get(key);
  return {
    name: cleanText(get('name')),
    setCode: cleanText(get('setCode') ?? get('set_code')),
    collectorNumber: cleanText(get('collectorNumber') ?? get('collector_number')),
    limitlessExpansionName: cleanText(get('limitlessExpansionName') ?? get('limitless_expansion_name')),
    limitlessExpansionCode: cleanText(get('limitlessExpansionCode') ?? get('limitless_expansion_code')),
    language: cleanText(get('language') ?? get('lang'), 12) || 'en',
    limit: cleanLimit(get('limit')),
  };
}

function rankDeckVersionRows(rows, input) {
  const targetName = compactText(input.name);
  const targetSetCode = normalizeSetCode(input.setCode || input.limitlessExpansionCode);
  const targetNumber = normalizeCollectorNumber(input.collectorNumber);
  const targetExpansion = compactText(input.limitlessExpansionName);

  return rows.map((row) => {
    const rowName = compactText(row.name || row.canonical_name || row.display_name);
    const rowNumber = normalizeCollectorNumber(row.expansion_number || row.card_number);
    const rowSetCode = normalizeSetCode(
      row.expansion_code ||
        row.limitless_expansion_code ||
        row.cardtrader_expansion_code ||
        row.set_code,
    );
    const rowExpansion = compactText(row.expansion_name);
    let score = 0;

    if (rowName === targetName) score += 10_000;
    else if (rowName.includes(targetName) || targetName.includes(rowName)) score += 1_200;

    if (targetNumber && rowNumber === targetNumber) score += 4_000;
    if (targetSetCode && rowSetCode === targetSetCode) score += 3_500;
    if (targetExpansion && rowExpansion === targetExpansion) score += 2_500;

    if (rowName === targetName && targetNumber && rowNumber === targetNumber) score += 1_500;
    if (targetSetCode && rowSetCode === targetSetCode && targetNumber && rowNumber === targetNumber) score += 1_500;
    if (row.product_type === 'card') score += 100;
    if ((targetSetCode && rowSetCode !== targetSetCode) || (targetNumber && rowNumber !== targetNumber)) {
      score -= 2_000;
    }

    return {
      ...row,
      match_score: score,
      match: {
        name: rowName === targetName ? 'exact' : rowName.includes(targetName) ? 'contains' : '',
        setCode: targetSetCode && rowSetCode === targetSetCode ? 'exact' : '',
        collectorNumber: targetNumber && rowNumber === targetNumber ? 'exact' : '',
      },
    };
  }).sort((a, b) => {
    const score = Number(b.match_score || 0) - Number(a.match_score || 0);
    if (score !== 0) return score;
    const expansion = String(a.expansion_name || '').localeCompare(String(b.expansion_name || ''));
    if (expansion !== 0) return expansion;
    return String(a.expansion_number || '').localeCompare(String(b.expansion_number || ''), undefined, {
      numeric: true,
      sensitivity: 'base',
    });
  });
}

async function deckVersionRows({ input, dbQuery = marketplaceQuery }) {
  if (!input.name && !input.collectorNumber) return [];

  const values = [];
  const expansionNumberSql = projectedExpansionNumberSql();
  const expansionNumberIntSql = projectedExpansionNumberIntSql(expansionNumberSql);
  const raritySql = projectedRaritySql({
    rarityColumn: 'candidates.rarity',
    collectorNumberSql: expansionNumberSql,
  });
  const compactName = compactText(input.name);
  const targetNumber = normalizeCollectorNumber(input.collectorNumber);

  let where = `
    where coalesce(versions.preview_image_url, versions.cdn_image_url, versions.image_url) is not null
      and versions.product_type = 'card'
  `;

  if (compactName) {
    values.push(compactName);
    where += `
      and (
        regexp_replace(lower(coalesce(nullif(versions.canonical_name, ''), versions.name)), '[^a-z0-9]+', '', 'g') = $${values.length}
        or regexp_replace(lower(versions.name), '[^a-z0-9]+', '', 'g') like '%' || $${values.length} || '%'
        or $${values.length} like '%' || regexp_replace(lower(versions.name), '[^a-z0-9]+', '', 'g') || '%'
      )
    `;
  } else if (targetNumber) {
    values.push(targetNumber);
    where += `
      and regexp_replace(
        lower(coalesce(substring(${expansionNumberSql} from '[A-Za-z]*0*([0-9]+[A-Za-z]?)'), ${expansionNumberSql})),
        '[^a-z0-9]+',
        '',
        'g'
      ) = $${values.length}
    `;
  }

  values.push(Math.max(input.limit * 6, 80));

  const result = await dbQuery(
    `
      select
        versions.card_id,
        versions.name,
        versions.display_name,
        versions.canonical_name,
        versions.expansion_name,
        ${expansionNumberSql} as expansion_number,
        ${expansionNumberIntSql} as expansion_number_int,
        versions.product_variant,
        versions.blueprint_id,
        versions.image_url,
        versions.cdn_image_url,
        versions.preview_image_url,
        versions.homepage_image_url,
        versions.product_type,
        versions.trainer_name,
        versions.card_palette,
        versions.emoji,
        artist.artist,
        artist.illustrator,
        ${raritySql} as rarity,
        candidates.card_type,
        urls.canonical_path,
        versions.projected_at,
        expansions.code as expansion_code,
        expansions.symbol_image_url as expansion_symbol_url,
        expansions.logo_image_url as expansion_logo_url,
        coalesce(price_summary.listed_quantity, 0) as listed_quantity,
        price_summary.lowest_ask_pkn as lowest_price_pkn
      from public.marketplace_card_versions versions
      left join public.marketplace_search_candidates candidates
        on candidates.card_id = versions.card_id
      left join public.marketplace_blueprint_price_summary price_summary
        on price_summary.blueprint_id = versions.card_id
      left join public.cardtrader_pokemon_blueprints blueprints
        on blueprints.id = versions.card_id
      left join public.marketplace_blueprint_tcg_metadata tcg_metadata
        on tcg_metadata.blueprint_id = versions.card_id
      left join lateral (
        select collector_number
        from public.marketplace_cm_verified_links link
        where link.blueprint_id = versions.card_id
          and nullif(link.collector_number, '') is not null
        order by
          case link.confidence when 'verified' then 0 when 'manual' then 1 else 2 end,
          link.verified_at desc nulls last,
          link.updated_at desc nulls last
        limit 1
      ) verified_links on true
      left join lateral (
        select collector_number
        from public.marketplace_cm_product_parsing parsing
        where parsing.blueprint_id = versions.card_id
          and nullif(parsing.collector_number, '') is not null
        order by parsing.verified_at desc nulls last, parsing.updated_at desc nulls last
        limit 1
      ) product_parsing on true
      left join lateral (
        select e.*
        from public.cardtrader_pokemon_expansions e
        where e.name = versions.expansion_name
          or (blueprints.expansion_id is not null and e.expansion_id = blueprints.expansion_id)
        order by case when e.name = versions.expansion_name then 0 else 1 end
        limit 1
      ) expansions on true
      left join public.marketplace_blueprint_artists artist
        on artist.blueprint_id = versions.blueprint_id
      left join public.marketplace_card_urls urls
        on urls.card_id = versions.card_id
        and urls.language = 'en'
      ${where}
      order by versions.projected_at desc nulls last, versions.card_id desc
      limit $${values.length}
    `,
    values,
  );

  return rankDeckVersionRows(result.rows.map(withCardEmojiFields), input).slice(0, input.limit);
}

module.exports = async function handler(req, res) {
  cors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'GET' && req.method !== 'POST') {
    res.setHeader('Allow', 'GET,POST,OPTIONS');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const input = requestInput(req);
    const matches = await deckVersionRows({ input });
    res.setHeader('Cache-Control', 'public, max-age=20, s-maxage=120');
    return res.status(200).json({
      ok: true,
      source: 'oracle_structured_deck_lookup',
      input,
      matches,
    });
  } catch (error) {
    console.error('deck-card-version-lookup failed', error);
    return res.status(error.statusCode || 500).json({
      ok: false,
      error: error.message || 'Deck card version lookup failed.',
    });
  }
};

module.exports._test = {
  compactText,
  normalizeCollectorNumber,
  normalizeSetCode,
  rankDeckVersionRows,
  deckVersionRows,
};
