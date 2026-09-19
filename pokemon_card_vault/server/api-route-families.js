'use strict';

const FAMILIES = [
  { id: 'page-bff', title: 'React page BFFs' },
  { id: 'search', title: 'Search' },
  { id: 'card', title: 'Card identity' },
  { id: 'catalog', title: 'Catalog / sets' },
  { id: 'commerce', title: 'Listings / cart / orders' },
  { id: 'scan', title: 'Scan Connect' },
  { id: 'cardtrader', title: 'CardTrader' },
  { id: 'cardmarket', title: 'Cardmarket' },
  { id: 'auth', title: 'Auth' },
  { id: 'payments', title: 'PKN / Stripe' },
  { id: 'assistant', title: 'Assistant' },
  { id: 'social', title: 'Social' },
  { id: 'debug', title: 'Debug / ops' },
  { id: 'other', title: 'Other' },
];

function familyForPath(path) {
  const p = String(path || '');
  if (/\/api\/marketplace-(home|search|card|expansion)-page(?:\.js)?$/.test(p)
    || /\/api\/marketplace-portfolio(?:\.js)?$/.test(p)) {
    return 'page-bff';
  }
  if (/suggest|autocomplete|searchbar|search-candidates|extension-card-search|\/api\/marketplace-cards(?:\.js)?$/.test(p)) {
    return 'search';
  }
  if (/marketplace-card-(url|shortlink|seo|sales|last-median|cheapest|versions)|marketplace-version-set/.test(p)) {
    return 'card';
  }
  if (/\/api\/scan-(session|pair|phone|batch|stream)(?:\.js)?$/.test(p)) {
    return 'scan';
  }
  if (/cardtrader/.test(p) || /\/api\/ingest/.test(p)) {
    return 'cardtrader';
  }
  if (/cardmarket/.test(p)) {
    return 'cardmarket';
  }
  if (/listings|marketplace-cart|marketplace-orders|watchlist|marketplace-recents|marketplace-event/.test(p)) {
    return 'commerce';
  }
  if (/auth-login|user-current-page|cache-google/.test(p)) {
    return 'auth';
  }
  if (/stripe|create-pkn|crypto-pkn|earn-pkn|top-up|wpkn|bitcoin/.test(p)) {
    return 'payments';
  }
  if (/pokoin-assistant|trainingai/.test(p)) {
    return 'assistant';
  }
  if (/social/.test(p)) {
    return 'social';
  }
  if (/debug|flutter-debug|image-log/.test(p)) {
    return 'debug';
  }
  if (/expansion|artist|hot-blueprint|limitless|competitive/.test(p)) {
    return 'catalog';
  }
  return 'other';
}

function familyTitle(id) {
  return (FAMILIES.find((row) => row.id === id) || FAMILIES[FAMILIES.length - 1]).title;
}

function groupRoutes(routes) {
  const byId = new Map(FAMILIES.map((row) => [row.id, { ...row, routes: [] }]));
  for (const route of routes || []) {
    const id = route.family || familyForPath(route.path);
    const bucket = byId.get(id) || byId.get('other');
    bucket.routes.push({ ...route, family: id });
  }
  return FAMILIES.map((row) => byId.get(row.id)).filter((row) => row.routes.length);
}

module.exports = {
  FAMILIES,
  familyForPath,
  familyTitle,
  groupRoutes,
};
