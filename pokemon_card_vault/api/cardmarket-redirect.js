const { marketplaceQuery } = require('./_marketplace_db');

const KNOWN_CARDMARKET_SET_CODES = new Map([
  ['Call of Legends', 'CL'],
  ['Chaos Rising', 'CRI'],
  ['CSVH4pC: Reward Pack', 'CSVH4Cp'],
  ['Skyridge', 'SK'],
  ['Start Deck 100', 'sI100'],
]);

const KNOWN_CARDMARKET_EXPANSION_SLUGS = new Map([
  [
    'CSVH4pC: Reward Pack',
    'Happy-Set-Decidueye-Melmetal-Koraidon-Miraidon',
  ],
]);

const KNOWN_NAME_ONLY_TRAINER_EXPANSIONS = new Set([
  'Night Unison',
  'Rising Fist',
]);

function cleanBlueprintId(value) {
  const id = String(value || '').trim();
  return /^\d{1,12}$/.test(id) ? id : '';
}

function slugPart(value) {
  return String(value || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/&/g, ' and ')
    .replace(/[^a-zA-Z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function cardNameSlug(name) {
  return slugPart(
    String(name || '')
      .replace(/\bShiny Rare\b/gi, '')
      .replace(/\bRare Holo\b/gi, '')
      .replace(/\bHolo\b/gi, '')
      .replace(/\s+/g, ' ')
      .trim(),
  );
}

function normalizedCollectorNumber(value) {
  const text = String(value || '').replace(/\|\|/g, '|').trim();
  const slashNumber = /([A-Z]*\d+[A-Z]?\s*\/\s*\d+)/i.exec(text);
  if (slashNumber) return slashNumber[1].replace(/\s+/g, '');
  const specialNumber = /\b([A-Z]{1,4}\s*\d+)\b/i.exec(text);
  if (specialNumber) return specialNumber[1].replace(/\s+/g, '');
  const stampNumber = /\bStamp Number\s+(\d+)\b/i.exec(text);
  if (stampNumber) return stampNumber[1];
  const plainNumber = /\b(?:No\.)?0*(\d{1,4})\b/i.exec(text);
  return plainNumber ? plainNumber[1] : text;
}

function unique(values) {
  return [...new Set(values.filter(Boolean))];
}

function maybeCardmarketSetCode(expansionName, cardtraderCode) {
  const known = KNOWN_CARDMARKET_SET_CODES.get(String(expansionName || '').trim());
  if (known) return known;
  return String(cardtraderCode || '').replace(/[^a-z0-9]/gi, '').toUpperCase();
}

function expansionSlug(expansionName) {
  const known = KNOWN_CARDMARKET_EXPANSION_SLUGS.get(String(expansionName || '').trim());
  return known || slugPart(expansionName);
}

function collectorCandidates(collectorNumber, setCode) {
  const raw = normalizedCollectorNumber(collectorNumber);
  if (!raw || !setCode) return [];
  const clean = raw.replace(/\s+/g, '').replace(/\/.*$/, '').toUpperCase();
  if (!/\d/.test(clean)) return [];
  const special = /^([A-Z]+)(\d+)$/.exec(clean);
  if (special) {
    const [, prefix, numeric] = special;
    const value = Number(numeric);
    const padded2 = Number.isFinite(value) ? String(value).padStart(2, '0') : numeric;
    const padded3 = Number.isFinite(value) ? String(value).padStart(3, '0') : numeric;
    return unique([
      `${setCode}${prefix}${padded2}`,
      `${setCode}${prefix}${numeric}`,
      `${setCode}${prefix}${padded3}`,
    ]);
  }
  const numeric = /^0*(\d+)[A-Z]?$/.exec(clean);
  if (numeric) {
    const value = Number(numeric[1]);
    const suffix = clean.replace(/^\d+/, '');
    const unpadded = `${setCode}${value}${suffix}`;
    const padded3 = `${setCode}${String(value).padStart(3, '0')}${suffix}`;
    const padded2 = `${setCode}${String(value).padStart(2, '0')}${suffix}`;
    return clean.startsWith('0')
      ? unique([padded3, unpadded, padded2])
      : unique([unpadded, padded3, padded2]);
  }
  return [`${setCode}${clean}`];
}

function likelyNameOnlyCardmarketSlug(row) {
  const expansionName = String(row.expansion_name || '').trim();
  const type = String(row.card_type || '').toLowerCase();
  if (/\b(trainer|supporter|item|stadium|tool|special energy|energy)\b/.test(type)) {
    return KNOWN_NAME_ONLY_TRAINER_EXPANSIONS.has(expansionName);
  }
  return false;
}

function candidateUrls(row, locale) {
  const setCode = maybeCardmarketSetCode(row.expansion_name, row.expansion_code);
  const expansion = expansionSlug(row.expansion_name);
  const name = cardNameSlug(row.name);
  const productCodes = collectorCandidates(row.expansion_number, setCode);
  const version = String(row.product_variant || '').trim();
  const versionMarkers =
    version && /^v\d+$/i.test(version) ? [version.toUpperCase(), ''] : [''];
  const nameOnlyCandidate =
    `https://www.cardmarket.com/${locale}/Pokemon/Products/Singles/${expansion}/${name}`;
  const candidates = likelyNameOnlyCardmarketSlug(row) ? [nameOnlyCandidate] : [];
  for (const productCode of productCodes) {
    for (const marker of versionMarkers) {
      const productSlug = [name, marker, productCode].filter(Boolean).join('-');
      candidates.push(
        `https://www.cardmarket.com/${locale}/Pokemon/Products/Singles/${expansion}/${productSlug}`,
      );
    }
  }
  candidates.push(nameOnlyCandidate);
  return unique(candidates);
}

async function rowForBlueprint(id) {
  const result = await marketplaceQuery(
    `
      with target as (
        select *
        from public.marketplace_card_versions
        where card_id = $1
        limit 1
      ), ranked as (
        select
          versions.card_id,
          versions.name,
          versions.expansion_name,
          versions.expansion_number,
          versions.expansion_number_int,
          versions.product_variant,
          case
            when count(*) over (partition by versions.expansion_name, versions.name) > 1
              then concat(
                'v',
                row_number() over (
                  partition by versions.expansion_name, versions.name
                  order by versions.expansion_number_int nulls last, versions.expansion_number, versions.card_id
                )
              )
            else ''
          end as inferred_product_variant,
          versions.product_type
        from public.marketplace_card_versions versions
        join target
          on target.expansion_name = versions.expansion_name
         and target.name = versions.name
        where versions.product_type = 'card'
      )
      select
        ranked.card_id,
        ranked.name,
        ranked.expansion_name,
        ranked.expansion_number,
        coalesce(nullif(ranked.product_variant, ''), ranked.inferred_product_variant) as product_variant,
        ranked.product_type,
        expansions.code as expansion_code,
        cards.card_type
      from ranked
      left join public.cardtrader_pokemon_expansions expansions
        on expansions.name = ranked.expansion_name
      left join public.marketplace_cards cards
        on cards.card_id = ranked.card_id
      where ranked.card_id = $1
      limit 1
    `,
    [id],
  );
  return result.rows[0] || null;
}

async function storedUrlForBlueprint(id, locale) {
  try {
    const result = await marketplaceQuery(
      `
        select cardmarket_url
        from public.marketplace_cm_product_parsing
        where blueprint_id = $1
          and cardmarket_locale = $2
          and match_status in ('verified', 'manual')
        order by verified_at desc nulls last, updated_at desc
        limit 1
      `,
      [id, locale],
    );
    return result.rows[0]?.cardmarket_url || '';
  } catch (error) {
    if (error.code === '42P01') {
      return '';
    }
    throw error;
  }
}

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const requestUrl = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
    const id = cleanBlueprintId(requestUrl.searchParams.get('id'));
    if (!id) {
      return res.status(400).json({ error: 'Missing or invalid blueprint id.' });
    }

    const requestedLocale = requestUrl.searchParams.get('locale') || '';
    const locale = /^[a-z]{2}$/.test(requestedLocale) ? requestedLocale : 'en';
    const storedUrl = await storedUrlForBlueprint(id, locale);
    let target = storedUrl;
    if (!target) {
      const row = await rowForBlueprint(id);
      if (!row) {
        return res.status(404).json({ error: 'Blueprint not found.' });
      }
      target = candidateUrls(row, locale)[0];
    }
    if (!target) {
      return res.status(404).json({ error: 'No Cardmarket URL candidate found.' });
    }

    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('X-Robots-Tag', 'noindex, nofollow');
    res.setHeader('Location', target);
    return res.status(302).end();
  } catch (error) {
    console.error('cardmarket-redirect failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Cardmarket redirect failed.',
    });
  }
};

module.exports.candidateUrls = candidateUrls;
module.exports.cleanBlueprintId = cleanBlueprintId;
