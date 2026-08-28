const VALID_SEARCH_ENGINES = new Set(['legacy', 'meili']);

function cleanSearchEngine(value) {
  const engine = String(value || 'legacy').trim().toLowerCase();
  return VALID_SEARCH_ENGINES.has(engine) ? engine : 'legacy';
}

function marketplaceSearchEngine() {
  return cleanSearchEngine(process.env.MARKETPLACE_SEARCH_ENGINE || process.env.SEARCH_ENGINE);
}

function marketplaceSearchShadowEnabled() {
  const value = String(
    process.env.MARKETPLACE_SEARCH_SHADOW ||
      process.env.SEARCH_SHADOW ||
      '0',
  ).trim().toLowerCase();
  return value === '1' || value === 'true' || value === 'yes';
}

function useMeiliSearch() {
  return marketplaceSearchEngine() === 'meili';
}

function useMeiliSearchForLanguage(searchLanguage) {
  const language = String(searchLanguage || '').trim().toLowerCase();
  return useMeiliSearch() && language === 'en';
}

module.exports = {
  cleanSearchEngine,
  marketplaceSearchEngine,
  marketplaceSearchShadowEnabled,
  useMeiliSearch,
  useMeiliSearchForLanguage,
};
