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

function productTypeClause(productType, productSearchOnly, values) {
  const normalized = cleanText(productType, 60);
  if (normalized) {
    values.push(normalized);
    return ` and product_type = $${values.length}`;
  }
  if (productSearchOnly) {
    return " and item_kind = 'product'";
  }
  return '';
}

function searchClause(query, productSearchOnly, searchLanguage, values) {
  const terms = searchTerms(query);
  if (terms.length === 0) {
    return '';
  }
  const fields = productSearchOnly
    ? ['name', 'set_name', 'product_variant', 'trainer_name']
    : ['name', 'set_name', 'trainer_name', 'card_type', 'rarity', 'card_number', 'product_variant'];
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
          and translations.name = marketplace_search_candidates.name
          and translations.localized_name ilike ${placeholder}
      ))`;
  });
  return ` and ${clauses.join(' and ')}`;
}

async function rowsForCards({ query, limit, productType, productSearchOnly, searchLanguage }) {
  const values = [];
  let where = 'where coalesce(preview_image_url, cdn_image_url, image_url) is not null';
  where += productTypeClause(productType, productSearchOnly, values);
  where += searchClause(query, productSearchOnly, searchLanguage, values);
  values.push(cleanLimit(limit));

  const result = await marketplaceQuery(
    `
      select
        card_id, name, product_variant as version, image_url, cdn_image_url,
        preview_image_url, set_name, rarity, card_type, card_number, product_variant,
        false as is_holo, false as is_foil, item_kind, product_type,
        trainer_name, card_palette, emoji, imported_at
      from public.marketplace_search_candidates
      ${where}
      order by search_weight desc, imported_at desc nulls last, card_id desc
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
    const rows = await rowsForCards({
      query: url.searchParams.get('query'),
      limit: url.searchParams.get('limit'),
      productType: url.searchParams.get('productType'),
      productSearchOnly: url.searchParams.get('productSearchOnly') === '1',
      searchLanguage: url.searchParams.get('lang') || url.searchParams.get('language'),
    });
    res.setHeader('Cache-Control', 'public, max-age=20, s-maxage=120');
    return res.status(200).json(rows);
  } catch (error) {
    console.error('marketplace-cards failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Marketplace cards failed.',
    });
  }
};

module.exports.rowsForCards = rowsForCards;
