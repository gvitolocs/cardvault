const { marketplaceQuery } = require('./_marketplace_db');

function cleanText(value, maxLength = 180) {
  return String(value || '').trim().slice(0, maxLength);
}

function cleanLimit(value, fallback = 1000) {
  const limit = Number(value);
  if (!Number.isFinite(limit)) return fallback;
  return Math.min(Math.max(Math.trunc(limit), 1), 5000);
}

function normalizeCode(value) {
  return cleanText(value, 60).toLowerCase().replace(/[^a-z0-9]+/g, '');
}

async function expansionBlueprintRows({
  query = marketplaceQuery,
  expansionKey = '',
  setCode = '',
  name = '',
  includeBlueprints = false,
  limit = 1000,
} = {}) {
  const values = [includeBlueprints];
  let where = 'where 1=1';

  const normalizedExpansionKey = cleanText(expansionKey, 240);
  if (normalizedExpansionKey) {
    values.push(normalizedExpansionKey);
    where += ` and expansions.expansion_key = $${values.length}`;
  }

  const normalizedSetCode = normalizeCode(setCode);
  if (normalizedSetCode) {
    values.push(normalizedSetCode);
    where += ` and (
      regexp_replace(lower(expansions.pokoin_expansion_code), '[^a-z0-9]+', '', 'g') = $${values.length}
      or regexp_replace(lower(expansions.limitless_expansion_code), '[^a-z0-9]+', '', 'g') = $${values.length}
    )`;
  }

  const normalizedName = cleanText(name);
  if (normalizedName) {
    values.push(`%${normalizedName}%`);
    where += ` and (
      expansions.pokoin_expansion_name ilike $${values.length}
      or expansions.limitless_expansion_name ilike $${values.length}
    )`;
  }

  values.push(cleanLimit(limit));

  const result = await query(
    `
      select
        expansions.expansion_key,
        expansions.pokoin_expansion_name,
        expansions.pokoin_expansion_code,
        expansions.limitless_expansion_name,
        expansions.limitless_expansion_code,
        expansions.aliases,
        expansions.raw_metadata,
        expansions.source,
        expansions.source_url,
        expansions.source_updated_at,
        expansions.updated_at,
        count(mapping.blueprint_id)::integer as blueprint_count,
        case when $1::boolean then
          coalesce(jsonb_agg(
            jsonb_build_object(
              'blueprintId', mapping.blueprint_id::text,
              'cardId', mapping.card_id::text,
              'name', mapping.card_name,
              'collectorNumber', mapping.collector_number,
              'normalizedCollectorNumber', mapping.normalized_collector_number,
              'setCode', mapping.set_code,
              'limitlessCardKey', mapping.limitless_card_key,
              'limitlessCardName', mapping.limitless_card_name,
              'sourceCardId', mapping.source_card_id,
              'sourceUrl', mapping.source_url,
              'matchConfidence', mapping.match_confidence,
              'matchReason', mapping.match_reason
            )
            order by mapping.normalized_collector_number, mapping.card_name, mapping.blueprint_id
          ) filter (where mapping.blueprint_id is not null), '[]'::jsonb)
        else '[]'::jsonb end as blueprints
      from public.limitless_marketplace_expansions expansions
      left join public.limitless_marketplace_expansion_blueprints mapping
        on mapping.expansion_key = expansions.expansion_key
      ${where}
      group by expansions.expansion_key
      order by expansions.pokoin_expansion_name asc, expansions.limitless_expansion_name asc
      limit $${values.length}
    `,
    values,
  );

  return result.rows.map((row) => ({
    expansionKey: row.expansion_key,
    pokoinExpansionName: row.pokoin_expansion_name,
    pokoinExpansionCode: row.pokoin_expansion_code,
    limitlessExpansionName: row.limitless_expansion_name,
    limitlessExpansionCode: row.limitless_expansion_code,
    aliases: row.aliases || [],
    blueprintCount: Number(row.blueprint_count || 0),
    blueprints: row.blueprints || [],
    rawMetadata: row.raw_metadata || {},
    source: row.source,
    sourceUrl: row.source_url,
    sourceUpdatedAt: row.source_updated_at,
    updatedAt: row.updated_at,
  }));
}

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
    const expansions = await expansionBlueprintRows({
      expansionKey: url.searchParams.get('expansionKey'),
      setCode: url.searchParams.get('setCode') || url.searchParams.get('code'),
      name: url.searchParams.get('name') || url.searchParams.get('query'),
      includeBlueprints: url.searchParams.get('includeBlueprints') === '1',
      limit: url.searchParams.get('limit'),
    });
    res.setHeader('Cache-Control', 'public, max-age=60, s-maxage=300');
    return res.status(200).json({ expansions });
  } catch (error) {
    console.error('limitless-expansion-blueprints failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Limitless expansion blueprints failed.',
    });
  }
};

module.exports._test = {
  expansionBlueprintRows,
  normalizeCode,
};
