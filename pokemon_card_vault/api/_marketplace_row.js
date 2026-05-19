function hasCollectorNumber(value) {
  const text = String(value || '').trim().toLowerCase();
  return /(^|[^0-9])[0-9]{1,4}[a-z]?\/[0-9]{1,4}([^0-9]|$)/.test(text);
}

function normalizeMarketplaceRow(row) {
  const normalized = { ...row };
  const collectorNumber =
    normalized.card_number || normalized.expansion_number || normalized.version;
  if (hasCollectorNumber(collectorNumber)) {
    normalized.item_kind = 'single';
    normalized.product_type = 'card';
  }
  return normalized;
}

function normalizeMarketplaceRows(rows) {
  return rows.map((row) => normalizeMarketplaceRow(row));
}

module.exports = {
  hasCollectorNumber,
  normalizeMarketplaceRow,
  normalizeMarketplaceRows,
};
