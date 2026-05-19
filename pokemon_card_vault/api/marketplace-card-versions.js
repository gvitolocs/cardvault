const { marketplaceQuery } = require('./_marketplace_db');

function cleanLimit(value, fallback = 240) {
  const limit = Number(value);
  if (!Number.isFinite(limit)) {
    return fallback;
  }
  return Math.min(Math.max(Math.trunc(limit), 1), 1000);
}

function cleanText(value, maxLength = 120) {
  return String(value || '').trim().slice(0, maxLength);
}

function searchTerms(value) {
  return cleanText(value)
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .map((term) => term.trim())
    .filter((term) => term.length >= 2 || /^[0-9]+$/.test(term));
}

function cleanLanguage(value) {
  const language = String(value || 'en').trim().toLowerCase();
  if (/^[a-z]{2}(?:-[a-z]{2})?$/.test(language)) {
    return language;
  }
  return 'en';
}

function normalizedCollectorNumberSql(column) {
  return `coalesce(
    substring(${column} from '([A-Za-z]*[0-9]+[A-Za-z]?\\s*/\\s*[0-9]+)'),
    substring(${column} from '([A-Za-z]{1,4}\\s*[0-9]+)'),
    ${column}
  )`;
}

function normalCollectorSql(column) {
  const normalized = normalizedCollectorNumberSql(column);
  return `case
    when ${normalized} ~ '^\\s*[0-9]+[A-Za-z]?\\s*(/[0-9]+)?\\s*$'
    then 0
    else 1
  end`;
}

function searchClause(query, productType, searchLanguage, values) {
  const terms = searchTerms(query);
  if (terms.length === 0) {
    return '';
  }
  const fields = productType
    ? ['versions.name', 'versions.expansion_name', 'versions.product_variant', 'versions.trainer_name']
    : [
        'versions.name',
        'versions.expansion_name',
        'versions.trainer_name',
        'versions.expansion_number',
      ];
  const clauses = terms.map((term) => {
    values.push(`%${term}%`);
    const placeholder = `$${values.length}`;
    values.push(cleanLanguage(searchLanguage));
    const languagePlaceholder = `$${values.length}`;
    return `(${fields.map((field) => `${field} ilike ${placeholder}`).join(' or ')}
      or exists (
        select 1
        from public.marketplace_card_name_translations translations
        where translations.language = ${languagePlaceholder}
          and translations.name = versions.name
          and translations.localized_name ilike ${placeholder}
      ))`;
  });
  return ` and ${clauses.join(' and ')}`;
}

async function rowsForVersions({
  query,
  expansionName,
  cardId,
  sameAsCardId,
  limit,
  productType,
  searchLanguage,
}) {
  const values = [];
  let where =
    'where coalesce(versions.preview_image_url, versions.cdn_image_url, versions.image_url) is not null';

  const normalizedCardId = Number(cardId);
  if (Number.isSafeInteger(normalizedCardId) && normalizedCardId > 0) {
    values.push(normalizedCardId);
    where += ` and versions.card_id = $${values.length}`;
  }

  const normalizedSameAsCardId = Number(sameAsCardId);
  if (Number.isSafeInteger(normalizedSameAsCardId) && normalizedSameAsCardId > 0) {
    values.push(normalizedSameAsCardId);
    where += ` and exists (
      select 1
      from public.marketplace_card_versions target
      where target.card_id = $${values.length}
        and target.name = versions.name
        and target.expansion_name = versions.expansion_name
    )`;
  }

  const normalizedExpansion = cleanText(expansionName);
  if (normalizedExpansion) {
    values.push(normalizedExpansion);
    where += ` and versions.expansion_name = $${values.length}`;
  }

  const normalizedProductType = cleanText(productType, 60);
  if (normalizedProductType) {
    values.push(normalizedProductType);
    where += ` and versions.product_type = $${values.length}`;
  }

  where += searchClause(query, normalizedProductType, searchLanguage, values);
  values.push(cleanLimit(limit));

  const result = await marketplaceQuery(
    `
      select
        versions.card_id,
        versions.name,
        versions.expansion_name,
        versions.expansion_number,
        versions.expansion_number_int,
        versions.product_variant,
        versions.blueprint_id,
        versions.image_url,
        versions.cdn_image_url,
        versions.preview_image_url,
        versions.product_type,
        versions.trainer_name,
        versions.card_palette,
        versions.emoji,
        versions.projected_at,
        expansions.symbol_image_url as expansion_symbol_url
      from public.marketplace_card_versions versions
      left join public.cardtrader_pokemon_expansions expansions
        on expansions.name = versions.expansion_name
      ${where}
      order by
        versions.expansion_name asc,
        ${normalCollectorSql('versions.expansion_number')} asc,
        versions.expansion_number_int asc nulls last,
        ${normalizedCollectorNumberSql('versions.expansion_number')} asc,
        versions.blueprint_id asc nulls last,
        versions.card_id asc
      limit $${values.length}
    `,
    values,
  );
  return result.rows;
}

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
    const rows = await rowsForVersions({
      query: url.searchParams.get('query'),
      expansionName: url.searchParams.get('expansionName'),
      cardId: url.searchParams.get('cardId'),
      sameAsCardId: url.searchParams.get('sameAsCardId'),
      limit: url.searchParams.get('limit'),
      productType: url.searchParams.get('productType'),
      searchLanguage: url.searchParams.get('lang') || url.searchParams.get('language'),
    });
    res.setHeader('Cache-Control', 'public, max-age=20, s-maxage=120');
    return res.status(200).json(rows);
  } catch (error) {
    console.error('marketplace-card-versions failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Marketplace card versions failed.',
    });
  }
};

module.exports.rowsForVersions = rowsForVersions;
