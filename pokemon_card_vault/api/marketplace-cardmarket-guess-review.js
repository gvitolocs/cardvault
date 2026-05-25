const { marketplaceQuery } = require('./_marketplace_db');
const { authorizeSearchDebugRequest } = require('./_search_debug_auth');

function cleanLimit(value, fallback = 160, max = 500) {
  const limit = Number(value);
  if (!Number.isFinite(limit)) return fallback;
  return Math.min(Math.max(Math.trunc(limit), 1), max);
}

async function cardmarketGuessRows(limit) {
  const result = await marketplaceQuery(
    `
      with imported as (
        select
          parsing.blueprint_id,
          parsing.cardmarket_locale,
          parsing.card_name,
          parsing.cardmarket_name,
          parsing.expansion_name,
          parsing.cardmarket_expansion_slug,
          parsing.collector_number,
          parsing.normalized_collector_number,
          parsing.cardmarket_set_code,
          parsing.cardmarket_context_code,
          parsing.cardmarket_variant_marker,
          parsing.cardmarket_product_slug,
          parsing.cardmarket_url,
          parsing.verification_method,
          parsing.verification_source,
          parsing.notes,
          parsing.verified_at,
          versions.product_variant,
          coalesce(
            versions.preview_image_url,
            blueprints.preview_image_url,
            versions.cdn_image_url,
            blueprints.cdn_image_url,
            versions.image_url,
            blueprints.image_url
          ) as image_url,
          blueprints.card_market_ids,
          coalesce(cards.card_type, '') as card_type,
          rule.cardmarket_set_code as rule_set_code,
          rule.number_format_rule as rule_number_format_rule,
          rule.source as rule_source
        from public.marketplace_cm_product_parsing parsing
        join public.marketplace_card_versions versions
          on versions.card_id = parsing.blueprint_id
        left join public.cardtrader_pokemon_blueprints blueprints
          on blueprints.id = parsing.blueprint_id
        left join public.marketplace_cards cards
          on cards.card_id = parsing.blueprint_id
        left join public.marketplace_cm_expansion_rules rule
          on rule.expansion_name = parsing.expansion_name
          and rule.cardmarket_locale = parsing.cardmarket_locale
          and rule.applies_to_card_type = case
            when lower(coalesce(cards.card_type, '') || ' ' || coalesce(parsing.card_name, '')) ~ '(trainer|supporter|item|stadium|tool|ball|rod|blender|city)' then 'trainer'
            when lower(coalesce(cards.card_type, '') || ' ' || coalesce(parsing.card_name, '')) like '%energy%' then 'energy'
            else 'pokemon'
          end
        where parsing.match_status in ('verified', 'manual')
          and parsing.verification_source in (
            'cardmarket-tbody-paste',
            'debug-refinement-log',
            'chat',
            'user'
          )
        order by parsing.verified_at desc nulls last, parsing.updated_at desc
        limit $1
      )
      select
        *,
        case
          when cardmarket_set_code = '' then 'exact_only_name_or_special_slug'
          when rule_set_code is null then 'no_reusable_expansion_rule'
          when rule_set_code <> cardmarket_set_code then 'rule_code_differs'
          when cardmarket_variant_marker <> '' then 'variant_marker'
          else 'safe_verified'
        end as review_status
      from imported
    `,
    [limit],
  );
  return result.rows;
}

async function missingExpansionRows(limit) {
  const result = await marketplaceQuery(
    `
      with card_rows as (
        select
          versions.expansion_name,
          case
            when lower(coalesce(cards.card_type, '') || ' ' || coalesce(versions.name, '')) ~ '(trainer|supporter|item|stadium|tool|ball|rod|blender|city)' then 'trainer'
            when lower(coalesce(cards.card_type, '') || ' ' || coalesce(versions.name, '')) like '%energy%' then 'energy'
            else 'pokemon'
          end as applies_to_card_type,
          versions.card_id,
          versions.name,
          versions.expansion_number,
          coalesce(
            versions.preview_image_url,
            blueprints.preview_image_url,
            versions.cdn_image_url,
            blueprints.cdn_image_url,
            versions.image_url,
            blueprints.image_url
          ) as image_url
        from public.marketplace_card_versions versions
        left join public.marketplace_cards cards
          on cards.card_id = versions.card_id
        left join public.cardtrader_pokemon_blueprints blueprints
          on blueprints.id = versions.card_id
        where versions.product_type = 'card'
          and versions.expansion_name is not null
      ), grouped as (
        select
          card_rows.expansion_name,
          card_rows.applies_to_card_type,
          count(*)::int as card_count,
          count(link.blueprint_id)::int as verified_count,
          (array_agg(card_rows.card_id order by random()))[1] as sample_blueprint_id,
          (array_agg(card_rows.name order by random()))[1] as sample_name,
          (array_agg(card_rows.expansion_number order by random()))[1] as sample_collector_number,
          (array_agg(card_rows.image_url order by random()))[1] as sample_image_url
        from card_rows
        left join public.marketplace_cm_expansion_rules rule
          on rule.expansion_name = card_rows.expansion_name
          and rule.cardmarket_locale = 'en'
          and rule.applies_to_card_type = card_rows.applies_to_card_type
        left join public.marketplace_cm_verified_links link
          on link.blueprint_id = card_rows.card_id
          and link.cardmarket_locale = 'en'
        where rule.expansion_name is null
        group by card_rows.expansion_name, card_rows.applies_to_card_type
      )
      select *
      from grouped
      order by verified_count desc, card_count desc, expansion_name
      limit $1
    `,
    [limit],
  );
  return result.rows;
}

function rowToJson(row) {
  return {
    blueprintId: `${row.blueprint_id ?? ''}`,
    locale: row.cardmarket_locale || 'en',
    name: row.card_name || '',
    cardmarketName: row.cardmarket_name || '',
    expansionName: row.expansion_name || '',
    cardmarketExpansionSlug: row.cardmarket_expansion_slug || '',
    collectorNumber: row.collector_number || '',
    normalizedCollectorNumber: row.normalized_collector_number || '',
    productVariant: row.product_variant || '',
    imageUrl: row.image_url || '',
    cardMarketIds: Array.isArray(row.card_market_ids)
      ? row.card_market_ids
      : row.card_market_ids || [],
    cardmarketUrl: row.cardmarket_url || '',
    cardmarketProductSlug: row.cardmarket_product_slug || '',
    cardmarketSetCode: row.cardmarket_set_code || '',
    cardmarketContextCode: row.cardmarket_context_code || '',
    cardmarketVariantMarker: row.cardmarket_variant_marker || '',
    verificationMethod: row.verification_method || '',
    verificationSource: row.verification_source || '',
    notes: row.notes || '',
    verifiedAt: row.verified_at || '',
    reviewStatus: row.review_status || '',
    ruleSetCode: row.rule_set_code || '',
    ruleNumberFormatRule: row.rule_number_format_rule || '',
    ruleSource: row.rule_source || '',
  };
}

function missingRowToJson(row) {
  return {
    expansionName: row.expansion_name || '',
    appliesToCardType: row.applies_to_card_type || '',
    cardCount: Number(row.card_count || 0),
    verifiedCount: Number(row.verified_count || 0),
    sampleBlueprintId: `${row.sample_blueprint_id || ''}`,
    sampleName: row.sample_name || '',
    sampleCollectorNumber: row.sample_collector_number || '',
    sampleImageUrl: row.sample_image_url || '',
  };
}

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    await authorizeSearchDebugRequest(req);
    const requestUrl = new URL(
      req.url,
      `https://${req.headers.host || 'pokoin.com'}`,
    );
    const limit = cleanLimit(requestUrl.searchParams.get('limit'));
    const missingLimit = cleanLimit(
      requestUrl.searchParams.get('missingLimit'),
      120,
      300,
    );
    const [guesses, missingExpansions] = await Promise.all([
      cardmarketGuessRows(limit),
      missingExpansionRows(missingLimit),
    ]);
    return res.status(200).json({
      generatedAt: new Date().toISOString(),
      guesses: guesses.map(rowToJson),
      riskyGuesses: guesses
        .filter((row) => row.review_status !== 'safe_verified')
        .map(rowToJson),
      missingExpansions: missingExpansions.map(missingRowToJson),
    });
  } catch (error) {
    console.error('marketplace-cardmarket-guess-review failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Failed to load Cardmarket guess review.',
    });
  }
};
