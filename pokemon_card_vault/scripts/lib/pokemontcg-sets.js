'use strict';

const { normalizeExpansionName, pokemontcgSetIdForExpansion } = require('./pokemontcg-hires');

const SETS_URL = 'https://raw.githubusercontent.com/PokemonTCG/pokemon-tcg-data/master/sets/en.json';

/** Names in our marketplace that differ from pokemon-tcg-data. */
const EXTRA_ALIASES = {
  'base set': 'base1',
  'expedition': 'ecard1',
  'expedition base set': 'ecard1',
  '151': 'sv3pt5',
  'pokemon 151': 'sv3pt5',
  'mega evolution': 'me1',
  'phantasmal flames': 'me2',
  'scarlet violet': 'sv1',
  'scarlet and violet': 'sv1',
};

function indexPokemontcgSets(sets) {
  const byId = new Map();
  const byNorm = new Map();
  for (const set of sets || []) {
    if (!set || !set.id) {
      continue;
    }
    byId.set(String(set.id), set);
    const key = normalizeExpansionName(set.name);
    if (!key) {
      continue;
    }
    const bucket = byNorm.get(key) || [];
    bucket.push(set);
    byNorm.set(key, bucket);
  }
  return { byId, byNorm };
}

function matchPokemontcgSet(name, index) {
  if (!index) {
    const wizards = pokemontcgSetIdForExpansion(name);
    return wizards ? { setId: wizards, reason: 'wizards' } : { setId: null, reason: 'no-index' };
  }
  const wizards = pokemontcgSetIdForExpansion(name);
  if (wizards && index.byId.has(wizards)) {
    return { setId: wizards, reason: 'wizards', set: index.byId.get(wizards) };
  }
  let key = normalizeExpansionName(name);
  key = key.replace(/\s+(?:en|english|unlimited|jp|japanese)$/g, '').trim();
  const alias = EXTRA_ALIASES[key];
  if (alias && index.byId.has(alias)) {
    return { setId: alias, reason: 'alias', set: index.byId.get(alias) };
  }
  const exact = index.byNorm.get(key);
  if (exact && exact.length === 1) {
    return { setId: exact[0].id, reason: 'name', set: exact[0] };
  }
  const stripped = key.replace(/^pokemon\s+/, '');
  if (stripped !== key) {
    const again = index.byNorm.get(stripped);
    if (again && again.length === 1) {
      return { setId: again[0].id, reason: 'name-stripped', set: again[0] };
    }
  }
  return { setId: null, reason: exact && exact.length > 1 ? 'ambiguous' : 'unmapped' };
}

async function loadPokemontcgSets({ fetchImpl = fetch, cache } = {}) {
  if (cache && cache.sets) {
    return cache.sets;
  }
  const response = await fetchImpl(SETS_URL, {
    headers: { Accept: 'application/json', 'User-Agent': 'Pokoin pokemontcg set map' },
  });
  if (!response.ok) {
    throw new Error(`sets ${response.status}`);
  }
  const sets = await response.json();
  if (cache) {
    cache.sets = sets;
  }
  return sets;
}

module.exports = {
  SETS_URL,
  EXTRA_ALIASES,
  indexPokemontcgSets,
  matchPokemontcgSet,
  loadPokemontcgSets,
};
