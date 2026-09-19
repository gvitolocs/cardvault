'use strict';

const MECHANIC_ALIAS_BLOCKLIST = new Set(['ex', 'gx', 'v', 'vmax', 'vstar']);

function firstCodeToken(value) {
  return String(value || '')
    .replace(/\(.*?\)/g, ' ')
    .split(/[|;,/]/)[0]
    .trim()
    .replace(/\s+/g, '');
}

function splitAliases(value) {
  return String(value || '')
    .split(',')
    .map((part) => part.trim())
    .filter(Boolean);
}

function splitNicknames(value) {
  return String(value || '')
    .split(/\s*\/\s*/)
    .map((part) => part.replace(/\s+/g, ' ').trim())
    .filter(Boolean);
}

function isNicknameFamily(cardName) {
  return /\bfamily\b/i.test(String(cardName || ''));
}

function cleanNicknameNumber(value) {
  let number = String(value || '').trim();
  const family = /\bvarious(\s+prints)?\b|\band variants\b/i.test(number);
  number = number
    .replace(/\b(and\s+)?variants?\b/ig, ' ')
    .replace(/\bvarious(\s+prints)?\b/ig, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (family) {
    return '';
  }
  return number;
}

function isDataLine(line) {
  const text = String(line || '').trim();
  if (!text || text.startsWith('=')) {
    return false;
  }
  if (/^(IMPORTANT|Format:|Note:|NOTES |Collision|Do NOT|Recommended|English expansion|Japanese expansion|Mainland China|Official current|Useful nickname|END OF FILE)/i.test(text)) {
    return false;
  }
  if (/^https?:\/\//i.test(text)) {
    return false;
  }
  if (/^-$/.test(text) || text.startsWith('- ')) {
    return false;
  }
  return text.includes('|');
}

function aliasPriority(alias, { kind = 'extra' } = {}) {
  const compact = String(alias || '').replace(/[^a-zA-Z0-9]/g, '');
  if (kind === 'joke') {
    return 85;
  }
  if (kind === 'canonical') {
    return compact.length <= 2 ? 100 : 50;
  }
  return compact.length <= 2 ? 110 : 70;
}

function shouldKeepAlias(alias, expansionName) {
  const token = String(alias || '').trim();
  if (!token) {
    return false;
  }
  const compact = token.toLowerCase().replace(/[^a-z0-9]/g, '');
  if (MECHANIC_ALIAS_BLOCKLIST.has(compact)) {
    return false;
  }
  const expansionCompact = String(expansionName || '').toLowerCase().replace(/[^a-z0-9]/g, '');
  if (compact && compact === expansionCompact) {
    return false;
  }
  return true;
}

function addExpansionAlias(out, expansionName, alias, { kind = 'extra', code = '' } = {}) {
  const name = String(expansionName || '').trim();
  const token = String(alias || '').trim();
  if (!name || !shouldKeepAlias(token, name)) {
    return;
  }
  out.expansionAliases.push({
    expansionName: name,
    alias: token,
    code: String(code || '').trim(),
    kind,
    priority: aliasPriority(token, { kind }),
  });
}

function parseTcgSearchAliasFile(text) {
  const out = {
    expansionAliases: [],
    cardNicknames: [],
  };
  let section = '';
  for (const rawLine of String(text || '').split(/\r?\n/)) {
    const line = rawLine.trim();
    if (/^1\) ENGLISH/.test(line)) {
      section = 'en';
      continue;
    }
    if (/^2\) USEFUL ENGLISH PROMO/.test(line)) {
      section = 'promo';
      continue;
    }
    if (/^3\) COMMON SET-LEVEL/.test(line)) {
      section = 'joke';
      continue;
    }
    if (/^4\) JAPANESE/.test(line)) {
      section = 'jp';
      continue;
    }
    if (/^5\) MAINLAND/.test(line)) {
      section = 'cn';
      continue;
    }
    if (/^6\) COMMON INDIVIDUAL/.test(line)) {
      section = 'nick';
      continue;
    }
    if (/^[78]\) /.test(line)) {
      section = '';
      continue;
    }
    if (!section || !isDataLine(line)) {
      continue;
    }
    const cols = line.split('|').map((part) => part.trim());
    if (section === 'en' && cols.length >= 4) {
      const expansionName = cols[1];
      const code = firstCodeToken(cols[2]);
      addExpansionAlias(out, expansionName, code, { kind: 'canonical', code });
      for (const alias of splitAliases(cols[3])) {
        addExpansionAlias(out, expansionName, alias, { kind: 'extra', code });
      }
      continue;
    }
    if (section === 'promo' && cols.length >= 2) {
      const expansionName = cols[0];
      const code = firstCodeToken(cols[1]);
      addExpansionAlias(out, expansionName, code, { kind: 'canonical', code });
      addExpansionAlias(out, expansionName, expansionName, { kind: 'extra', code });
      continue;
    }
    if (section === 'joke' && cols.length >= 3) {
      addExpansionAlias(out, cols[0], cols[2], { kind: 'joke', code: firstCodeToken(cols[1]) });
      continue;
    }
    if ((section === 'jp' || section === 'cn') && cols.length >= 3) {
      const expansionName = cols[1];
      const code = firstCodeToken(cols[2]);
      const englishAliases = cols[3] ? splitAliases(cols[3]) : [];
      addExpansionAlias(out, expansionName, code, { kind: 'canonical', code });
      for (const alias of englishAliases) {
        addExpansionAlias(out, expansionName, alias, { kind: 'extra', code });
        addExpansionAlias(out, alias, code, { kind: 'canonical', code });
        addExpansionAlias(out, alias, expansionName, { kind: 'extra', code });
      }
      continue;
    }
    if (section === 'nick' && cols.length >= 3) {
      if (isNicknameFamily(cols[1])) {
        continue;
      }
      const number = cleanNicknameNumber(cols[3]);
      for (const nickname of splitNicknames(cols[0])) {
        out.cardNicknames.push({
          nickname,
          cardName: cols[1],
          expansionName: cols[2],
          cardNumber: number,
          notes: cols[4] || '',
        });
      }
    }
  }
  return out;
}

module.exports = {
  MECHANIC_ALIAS_BLOCKLIST,
  parseTcgSearchAliasFile,
  firstCodeToken,
  shouldKeepAlias,
  cleanNicknameNumber,
  isNicknameFamily,
};
