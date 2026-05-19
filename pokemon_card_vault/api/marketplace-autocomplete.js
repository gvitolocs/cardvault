const {
  cleanLimit,
  cleanLanguage,
  cleanSearchTerm,
  rowsForSearchTerm,
} = require('./marketplace-search-candidates');

function compact(value) {
  return String(value || '').toLowerCase().replace(/[^a-z0-9]/g, '');
}

function searchTerms(value) {
  return normalizeVariationPhrases(value)
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .map((term) => term.trim())
    .filter((term) => term.length >= 2 || term === 'v');
}

function normalizeVariationPhrases(value) {
  return String(value || '')
    .replace(/\blv\s*\.?\s*x\b/gi, 'lvx')
    .replace(/\blevel\s+x\b/gi, 'lvx')
    .replace(/\bv\s*max\b/gi, 'vmax')
    .replace(/\bv\s*star\b/gi, 'vstar')
    .replace(/\bg\s*x\b/gi, 'gx')
    .replace(/\be\s*x\b/gi, 'ex');
}

function isVariationTerm(term) {
  return new Set([
    'ex',
    'v',
    'vmax',
    'vstar',
    'gx',
    'lvx',
    'lv',
    'mega',
    'break',
    'radiant',
    'shining',
    'shiny',
    'prime',
  ]).has(compact(term));
}

function rowHasVariation(row, term) {
  const normalizedTerm = compact(term);
  const text = [
    row.name,
    row.rarity,
    row.card_type,
    row.product_type,
    row.product_variant,
  ].join(' ').toLowerCase();
  const compactText = compact(text);
  if (normalizedTerm === 'lvx') {
    return /(^|[^a-z0-9])(lv\.?x|level x)([^a-z0-9]|$)/.test(text);
  }
  if (normalizedTerm === 'lv') {
    return /(^|[^a-z0-9])lv\.?([0-9]+|x)([^a-z0-9]|$)/.test(text);
  }
  if (normalizedTerm === 'v') {
    return /(^|[^a-z0-9])v([^a-z0-9]|$)/.test(text);
  }
  return new RegExp(`(^|[^a-z0-9])${normalizedTerm}([^a-z0-9]|$)`).test(text) ||
    compactText.includes(normalizedTerm);
}

function isRarityTerm(term) {
  return new Set([
    'sir',
    'ir',
    'ur',
    'sr',
    'rare',
    'ultra',
    'secret',
    'illustration',
    'holo',
    'shiny',
  ]).has(compact(term));
}

function rowHasRarity(row, term) {
  const normalizedTerm = compact(term);
  const text = [row.card_number, row.rarity].join(' ').toLowerCase();
  const normalizedText = text.replace(/[^a-z0-9]+/g, ' ').trim();
  if (normalizedTerm === 'sir') {
    return normalizedText.includes('special illustration rare');
  }
  if (normalizedTerm === 'ir') {
    return normalizedText.includes('illustration rare');
  }
  if (normalizedTerm === 'ur' || normalizedTerm === 'ultra') {
    return normalizedText.includes('ultra rare');
  }
  if (normalizedTerm === 'sr' || normalizedTerm === 'secret') {
    return normalizedText.includes('secret rare');
  }
  return normalizedText.includes(normalizedTerm);
}

const expansionAliases = new Map([
  ['col', ['calloflegends']],
  ['calllegends', ['calloflegends']],
  ['calloflegends', ['calloflegends']],
  ['151', ['151', 'pokemoncard151', 'collect151']],
  ['pokemon151', ['pokemoncard151']],
  ['pokemoncard151', ['pokemoncard151']],
  ['collect151', ['collect151']],
  ['cel', ['celebrations']],
  ['pal', ['paldeaevolved']],
  ['obf', ['obsidianflames']],
  ['obs', ['obsidianflames']],
  ['svi', ['scarletviolet']],
  ['sv', ['scarletviolet']],
]);

function expansionAliasTargets(term) {
  return expansionAliases.get(compact(term)) || [];
}

function isExpansionAliasTerm(term) {
  return expansionAliasTargets(term).length > 0;
}

function rowHasExpansionAlias(row, term) {
  const compactSet = compact(row.set_name || row.set || '');
  return expansionAliasTargets(term).some((target) =>
    compactSet === target || compactSet.startsWith(target) || target.startsWith(compactSet));
}

function poolSearchTerm(value) {
  return cleanSearchTerm(normalizeVariationPhrases(value));
}

function isPokemonIdentityRow(row) {
  if (String(row.item_kind || '') === 'product') {
    return false;
  }
  const type = String(row.card_type || '').toLowerCase();
  if (!type || type === 'card') {
    return false;
  }
  return !/\b(trainer|supporter|item|stadium|energy|accessory|product|sealed)\b/.test(type);
}

function isLikelyNameTokenTypo(nameWords, term) {
  const normalizedTerm = compact(term);
  if (normalizedTerm.length < 3) {
    return false;
  }
  return nameWords.some((word) => {
    const normalizedWord = compact(word);
    if (normalizedWord.length < 3) {
      return false;
    }
    if (normalizedWord.startsWith(normalizedTerm) || normalizedTerm.startsWith(normalizedWord)) {
      return true;
    }
    return boundedDistance(normalizedWord, normalizedTerm, normalizedTerm.length <= 4 ? 1 : 2) <=
      (normalizedTerm.length <= 4 ? 1 : 2);
  });
}

function cleanAutocompletePoolLimit(value) {
  const limit = cleanLimit(value ?? 1000);
  return Math.max(limit, 1000);
}

function boundedDistance(a, b, maxDistance) {
  if (Math.abs(a.length - b.length) > maxDistance) {
    return maxDistance + 1;
  }
  const matrix = Array.from({ length: a.length + 1 }, () =>
    Array(b.length + 1).fill(0),
  );
  for (let i = 0; i <= a.length; i += 1) matrix[i][0] = i;
  for (let j = 0; j <= b.length; j += 1) matrix[0][j] = j;
  for (let i = 1; i <= a.length; i += 1) {
    let rowMin = maxDistance + 1;
    for (let j = 1; j <= b.length; j += 1) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      let value = Math.min(
        matrix[i - 1][j] + 1,
        matrix[i][j - 1] + 1,
        matrix[i - 1][j - 1] + cost,
      );
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) {
        value = Math.min(value, matrix[i - 2][j - 2] + 1);
      }
      matrix[i][j] = value;
      rowMin = Math.min(rowMin, value);
    }
    if (rowMin > maxDistance) return maxDistance + 1;
  }
  return matrix[a.length][b.length];
}

function scoreRow(row, query) {
  const name = String(row.name || '').toLowerCase();
  const set = String(row.set_name || '').toLowerCase();
  const number = String(row.card_number || row.version || row.card_id || '')
    .toLowerCase();
  const rarity = String(row.rarity || '').toLowerCase();
  const type = String(row.card_type || '').toLowerCase();
  const trainer = String(row.trainer_name || '').toLowerCase();
  const haystack = `${name} ${number} ${set} ${rarity} ${type} ${trainer}`;
  const compactQuery = compact(query);
  const compactName = compact(name);
  const compactNumber = compact(number);
  const terms = searchTerms(query);
  const nameWords = searchTerms(name);
  const hasNumberTerm = terms.some((term) => /^[0-9]+$/.test(term));
  const hasVariationTerm = terms.some(isVariationTerm);
  const hasRarityTerm = terms.some(isRarityTerm);
  const hasExpansionAliasTerm = terms.some(isExpansionAliasTerm);
  const hasTextTerm = terms.some((term) =>
    !/^[0-9]+$/.test(term) &&
    !isVariationTerm(term) &&
    !isRarityTerm(term) &&
    !isExpansionAliasTerm(term));
  const remoteScore = Number(row.search_rank || 0);
  const isProduct = String(row.item_kind || '') === 'product';
  const isPokemonIdentity = isPokemonIdentityRow(row);
  const productQuery = /\b(box|booster|pack|deck|display|collection|bundle|tin|blister|case|etb|dice|binder|premium|set)\b/i.test(query);
  let score = 0;

  if (number === query) score = Math.max(score, 980);
  if (compactNumber.startsWith(compactQuery) && compactQuery) {
    score = Math.max(score, 880);
  }
  if (name === query) score = Math.max(score, isPokemonIdentity ? 1420 : 1000);
  if (compactName === compactQuery) score = Math.max(score, isPokemonIdentity ? 1380 : 980);
  if (compactName.startsWith(compactQuery) && compactQuery) {
    score = Math.max(score, isPokemonIdentity ? 1180 : 820);
  }
  if (name.includes(query)) score = Math.max(score, 680);
  if (number.includes(query)) score = Math.max(score, 700);
  if (set.includes(query)) score = Math.max(score, 360);
  if (rarity.includes(query)) score = Math.max(score, 340);

  if (
    terms.length > 1 &&
    (hasNumberTerm || hasVariationTerm || hasExpansionAliasTerm) &&
    hasTextTerm
  ) {
    let intentScore = 0;
    let matchedName = false;
    let matchedNumber = false;
    let matchedVariation = false;
    let matchedExpansion = false;
    let matchedSet = false;
    for (const term of terms) {
      const compactTerm = compact(term);
      if (/^[0-9]+$/.test(term)) {
        const numberTokens = searchTerms(number);
        if (number === term || compactNumber === compactTerm || numberTokens.includes(term)) {
          intentScore += 1600;
          matchedNumber = true;
        } else if (number.startsWith(term) || compactNumber.startsWith(compactTerm)) {
          intentScore += 1300;
          matchedNumber = true;
        } else if (number.includes(term) || compactNumber.includes(compactTerm)) {
          intentScore += 900;
          matchedNumber = true;
        }
        continue;
      }
      if (isVariationTerm(term)) {
        if (rowHasVariation(row, term)) {
          intentScore += 1500;
          matchedVariation = true;
        }
        continue;
      }
      if (isExpansionAliasTerm(term)) {
        if (rowHasExpansionAlias(row, term)) {
          intentScore += 1550;
          matchedExpansion = true;
        }
        continue;
      }
      if (name === term || compactName === compactTerm) {
        intentScore += 1400;
        matchedName = true;
      } else if (name.startsWith(term) || compactName.startsWith(compactTerm)) {
        intentScore += 1150;
        matchedName = true;
      } else if (nameWords.some((word) => word.startsWith(term))) {
        intentScore += 980;
        matchedName = true;
      } else if (isLikelyNameTokenTypo(nameWords, term)) {
        intentScore += 920;
        matchedName = true;
      } else if (
        compactTerm.length >= 5 &&
        compactName.startsWith(compactTerm.slice(0, 2)) &&
        boundedDistance(compactName, compactTerm, 3) <= 3
      ) {
        intentScore += 760;
        matchedName = true;
      } else if (name.includes(term) || compactName.includes(compactTerm)) {
        intentScore += 720;
        matchedName = true;
      } else if (set.startsWith(term) || compact(set).startsWith(compactTerm)) {
        intentScore += 520;
        matchedSet = true;
      } else if (set.includes(term) || compact(set).includes(compactTerm)) {
        intentScore += 360;
        matchedSet = true;
      }
    }
    if (matchedName && matchedNumber) {
      score = Math.max(score, intentScore + 5200);
    } else if (matchedName && matchedVariation) {
      score = Math.max(score, intentScore + 4400);
    } else if (matchedName && matchedExpansion) {
      score = Math.max(score, intentScore + 4600);
    } else if (matchedName && matchedSet) {
      score = Math.max(score, intentScore + 700);
    } else if (matchedNumber || matchedVariation || matchedExpansion) {
      score = Math.min(score, 1);
    }
  }

  if (compactQuery.length >= 4 && compactName) {
    const prefix = compactName.slice(0, compactQuery.length);
    const distance = boundedDistance(prefix, compactQuery, 2);
    if (distance <= 1) score = Math.max(score, 760 - distance * 80);
    if (
      compactQuery.length >= 5 &&
      Math.abs(compactName.length - compactQuery.length) <= 2
    ) {
      const fullDistance = boundedDistance(compactName, compactQuery, 2);
      if (fullDistance <= 2) score = Math.max(score, 900 - fullDistance * 90);
    }
  }

  for (const term of terms) {
    const compactTerm = compact(term);
    if (!compactTerm) continue;
    if (nameWords.includes(term)) {
      score += isPokemonIdentity ? 1040 : 760;
    } else if (isLikelyNameTokenTypo(nameWords, term)) {
      score += isPokemonIdentity ? 920 : 620;
    } else if (compactName === compactTerm) {
      score += 900;
    } else if (compactName.startsWith(compactTerm)) {
      score += isPokemonIdentity ? 980 : 720;
    } else if (compactTerm.length >= 4) {
      const prefix = compactName.slice(0, compactTerm.length);
      const distance = boundedDistance(prefix, compactTerm, 2);
      if (distance <= 1) {
        score += 620 - distance * 80;
      }
    }
    if (compactNumber === compactTerm || compact(set) === compactTerm) {
      score += 520;
    } else if (
      compactNumber.startsWith(compactTerm) ||
      compact(set).startsWith(compactTerm)
    ) {
      score += 320;
    }
    if (rarity.includes(term)) {
      score += 180;
    }
  }

  if (terms.length > 1) {
    if (terms.every((term) => haystack.includes(term))) {
      score = Math.max(score, 620 + terms.length * 40);
    }
    const nameMatches = terms.filter((term) => {
      const compactTerm = compact(term);
      return compactTerm && (
        compactName.startsWith(compactTerm) ||
        isLikelyNameTokenTypo(nameWords, term) ||
        boundedDistance(compactName.slice(0, compactTerm.length), compactTerm, 2) <= 1
      );
    }).length;
    if (nameMatches > 0) {
      score += 420 * nameMatches;
    }
  }

  if (terms.length > 1 && hasRarityTerm && hasTextTerm) {
    let rarityScore = 420;
    let matchedName = false;
    let matchedRarity = false;
    for (const term of terms) {
      if (isRarityTerm(term)) {
        if (rowHasRarity(row, term)) {
          rarityScore += 420;
          matchedRarity = true;
        }
      } else if (name.startsWith(term)) {
        rarityScore += 260;
        matchedName = true;
      } else if (nameWords.some((word) => word.startsWith(term))) {
        rarityScore += 220;
        matchedName = true;
      } else if (name.includes(term)) {
        rarityScore += 160;
        matchedName = true;
      }
    }
    if (matchedName && matchedRarity) {
      score = Math.max(score, rarityScore);
    }
  }

  if (isProduct && !productQuery) {
    score -= 900;
  } else if (isProduct) {
    score -= 80;
  }
  if (!isPokemonIdentity && /^[a-z]{2,}$/.test(compactQuery) && compactQuery.length <= 5) {
    score -= 220;
  }
  const remoteMultiplier = isProduct && !productQuery ? 0.18 : 0.35;
  return Math.max(score, remoteScore * remoteMultiplier);
}

function dedupeRows(rows) {
  const seen = new Set();
  const result = [];
  for (const row of rows) {
    const id = String(row.card_id || row.id || '');
    if (!id || seen.has(id)) continue;
    seen.add(id);
    result.push(row);
  }
  return result;
}

function rankAutocompleteRows(rows, query, limit) {
  return dedupeRows(rows)
    .map((row) => ({ row, score: scoreRow(row, normalizeVariationPhrases(query).toLowerCase()) }))
    .filter((entry) => entry.score > 0)
    .sort((a, b) => {
      if (b.score !== a.score) return b.score - a.score;
      return String(a.row.name || '').localeCompare(String(b.row.name || ''));
    })
    .slice(0, limit)
    .map((entry) => entry.row);
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const searchTerm = cleanSearchTerm(
      req.body?.search_term ?? req.body?.searchTerm ?? req.body?.query,
    );
    const resultLimit = cleanLimit(req.body?.result_limit ?? req.body?.limit);
    const poolLimit = cleanAutocompletePoolLimit(req.body?.pool_limit);
    const searchLanguage = cleanLanguage(req.body?.search_language ?? req.body?.language);
    if (!searchTerm) {
      return res.status(200).json([]);
    }

    const started = Date.now();
    const rows = await rowsForSearchTerm(poolSearchTerm(searchTerm), poolLimit, 0, searchLanguage);
    const ranked = rankAutocompleteRows(rows, searchTerm, resultLimit);
    res.setHeader('Cache-Control', 'public, max-age=5, s-maxage=30');
    res.setHeader('Server-Timing', `autocomplete;dur=${Date.now() - started}`);
    return res.status(200).json(ranked);
  } catch (error) {
    console.error('marketplace-autocomplete failed', error);
    return res.status(error.statusCode || 500).json({
      error: error.message || 'Marketplace autocomplete failed.',
    });
  }
};

module.exports.poolSearchTerm = poolSearchTerm;
module.exports.cleanAutocompletePoolLimit = cleanAutocompletePoolLimit;
module.exports.rankAutocompleteRows = rankAutocompleteRows;
module.exports.scoreRow = scoreRow;
