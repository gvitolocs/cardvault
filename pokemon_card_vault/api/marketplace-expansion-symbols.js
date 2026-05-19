const { marketplaceQuery } = require('./_marketplace_db');
const { getFirebaseAdmin, verifyBearerToken } = require('./_firebase');

function cleanLimit(value, fallback = 300) {
  const limit = Number(value);
  if (!Number.isFinite(limit)) {
    return fallback;
  }
  return Math.min(Math.max(Math.trunc(limit), 1), 1000);
}

function cleanText(value, maxLength = 240) {
  return String(value || '').trim().slice(0, maxLength);
}

function slugify(value) {
  return String(value || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 140);
}

function defaultSymbolUrl(name) {
  const slug = slugify(name);
  return slug ? `https://cdn.pokoin.com/expansions/symbols/${slug}.png` : '';
}

function isValidHttpUrl(value) {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' || url.protocol === 'http:';
  } catch (_) {
    return false;
  }
}

async function requireAdmin(req) {
  const decoded = await verifyBearerToken(req);
  const email = String(decoded.email || '').trim().toLowerCase();
  const allowlist = [
    process.env.MARKETPLACE_ADMIN_EMAILS || '',
    process.env.ADMIN_SIGNUP_EMAIL || '',
  ]
    .join(',')
    .split(',')
    .map((value) => value.trim().toLowerCase())
    .filter(Boolean);
  if (allowlist.includes(email)) {
    return decoded;
  }

  const admin = getFirebaseAdmin();
  const userDoc = await admin.firestore().collection('users').doc(decoded.uid).get();
  const profile = userDoc.data() || {};
  const role = String(profile.role || '').trim().toLowerCase();
  if (profile.admin === true || profile.isAdmin === true || role === 'admin') {
    return decoded;
  }

  const error = new Error('Admin access required.');
  error.statusCode = 403;
  throw error;
}

async function listExpansionSymbols({ query, missingOnly, limit }) {
  const values = [];
  let where = 'where expansion_name is not null and expansion_name <> \'\''; 
  const normalizedQuery = cleanText(query);
  if (normalizedQuery) {
    values.push(`%${normalizedQuery}%`);
    where += ` and versions.expansion_name ilike $${values.length}`;
  }

  const missingFilter = String(missingOnly || '').trim() === '1';
  if (missingFilter) {
    where += ' and coalesce(expansions.symbol_image_url, \'\') = \'\'';
  }

  values.push(cleanLimit(limit));
  const result = await marketplaceQuery(
    `
      select
        versions.expansion_name as name,
        min(expansions.expansion_id) as expansion_id,
        min(expansions.code) as code,
        min(expansions.source_asset_code) as source_asset_code,
        min(expansions.symbol_image_url) as symbol_image_url,
        min(expansions.symbol_object_key) as symbol_object_key,
        count(*)::integer as card_count
      from public.marketplace_card_versions versions
      left join public.cardtrader_pokemon_expansions expansions
        on expansions.name = versions.expansion_name
      ${where}
      group by versions.expansion_name
      order by versions.expansion_name asc
      limit $${values.length}
    `,
    values,
  );

  return result.rows.map((row) => ({
    name: row.name || '',
    expansionId: row.expansion_id == null ? null : Number(row.expansion_id),
    code: row.code || '',
    sourceAssetCode: row.source_asset_code || '',
    symbolImageUrl: row.symbol_image_url || '',
    symbolObjectKey: row.symbol_object_key || '',
    defaultSymbolUrl: defaultSymbolUrl(row.name),
    cardCount: Number(row.card_count || 0),
  }));
}

async function updateExpansionSymbol({ name, symbolImageUrl, sourceAssetCode }) {
  const expansionName = cleanText(name);
  const symbolUrl = cleanText(symbolImageUrl, 500);
  const sourceCode = cleanText(sourceAssetCode, 120);
  if (!expansionName) {
    const error = new Error('Expansion name is required.');
    error.statusCode = 400;
    throw error;
  }
  if (symbolUrl && !isValidHttpUrl(symbolUrl)) {
    const error = new Error('Logo URL must be a valid http(s) URL.');
    error.statusCode = 400;
    throw error;
  }

  const versionResult = await marketplaceQuery(
    `
      select min(expansion_name) as name
      from public.marketplace_card_versions
      where expansion_name = $1
    `,
    [expansionName],
  );
  if (!versionResult.rows[0]?.name) {
    const error = new Error('Expansion was not found in marketplace versions.');
    error.statusCode = 404;
    throw error;
  }

  const idResult = await marketplaceQuery(
    `
      select expansion_id
      from public.cardtrader_pokemon_expansions
      where name = $1
      limit 1
    `,
    [expansionName],
  );
  const existingId = Number(idResult.rows[0]?.expansion_id);
  const expansionId = Number.isSafeInteger(existingId) && existingId > 0
    ? existingId
    : Math.abs(hashString(expansionName)) + 2_000_000_000;

  const objectKey = symbolUrl.includes('/expansions/symbols/')
    ? symbolUrl.split('/expansions/symbols/')[1]
    : null;
  const result = await marketplaceQuery(
    `
      insert into public.cardtrader_pokemon_expansions (
        expansion_id,
        game_id,
        name,
        source_asset_code,
        symbol_image_url,
        symbol_object_key,
        symbol_imported_at
      )
      values ($1, 5, $2, nullif($3, ''), nullif($4, ''), $5, now())
      on conflict (expansion_id) do update set
        name = excluded.name,
        source_asset_code = excluded.source_asset_code,
        symbol_image_url = excluded.symbol_image_url,
        symbol_object_key = excluded.symbol_object_key,
        symbol_imported_at = now()
      returning expansion_id, name, source_asset_code, symbol_image_url, symbol_object_key
    `,
    [expansionId, expansionName, sourceCode, symbolUrl, objectKey],
  );

  const row = result.rows[0] || {};
  return {
    name: row.name || expansionName,
    expansionId: Number(row.expansion_id || expansionId),
    sourceAssetCode: row.source_asset_code || '',
    symbolImageUrl: row.symbol_image_url || '',
    symbolObjectKey: row.symbol_object_key || '',
    defaultSymbolUrl: defaultSymbolUrl(expansionName),
  };
}

function hashString(value) {
  let hash = 0;
  for (const char of String(value || '')) {
    hash = (hash * 31 + char.charCodeAt(0)) | 0;
  }
  return hash;
}

module.exports = async function handler(req, res) {
  try {
    await requireAdmin(req);
    if (req.method === 'GET') {
      const url = new URL(req.url, `https://${req.headers.host || 'pokoin.com'}`);
      const rows = await listExpansionSymbols({
        query: url.searchParams.get('query'),
        missingOnly: url.searchParams.get('missingOnly'),
        limit: url.searchParams.get('limit'),
      });
      res.setHeader('Cache-Control', 'private, no-store');
      return res.status(200).json({ expansions: rows });
    }
    if (req.method === 'POST') {
      const updated = await updateExpansionSymbol(req.body || {});
      return res.status(200).json({ expansion: updated });
    }
    res.setHeader('Allow', 'GET, POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  } catch (error) {
    console.error('marketplace-expansion-symbols failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Expansion symbol update failed.',
    });
  }
};
