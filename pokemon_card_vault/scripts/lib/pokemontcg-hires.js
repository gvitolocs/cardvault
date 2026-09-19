'use strict';

/**
 * Pokémon TCG API CDN (images.pokemontcg.io) as a higher-definition source
 * for Wizards-era English scans. Catalog output is JPEG (D00000E) — q100,
 * 4:4:4, mozjpeg. Never write PNG to R2.
 *
 * URL: https://images.pokemontcg.io/{setId}/{number}_hires.png
 */

const { pngToMaxJpeg } = require('./png-to-jpeg');

const POKEMONTCG_HIRES = 'https://images.pokemontcg.io';
const CATALOG_JPEG_QUALITY = 100;
const BETTER_AREA_RATIO = 1.2;

/** CardTrader English expansion name → pokemon-tcg-data set id.
 * Listed Base Set is unlimited TCGPlayer, not pokemontcg.io `base1`
 * (those hires are 1st Edition / shadowless). See
 * `import-base-set-unlimited-tcgplayer.js`. */
const WIZARDS_EXPANSION_TO_SET = {
  jungle: 'base2',
  fossil: 'base3',
  'base set 2': 'base4',
  'team rocket': 'base5',
  'gym heroes': 'gym1',
  'gym challenge': 'gym2',
  'neo genesis': 'neo1',
  'neo discovery': 'neo2',
  'neo revelation': 'neo3',
  'neo destiny': 'neo4',
  'southern islands': 'si1',
  'legendary collection': 'base6',
  'expedition base set': 'ecard1',
  expedition: 'ecard1',
  aquapolis: 'ecard2',
  skyridge: 'ecard3',
  'wizards black star promos': 'basep',
  'best of game': 'bp',
};

function normalizeExpansionName(name) {
  return String(name || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/['’]/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function pokemontcgSetIdForExpansion(name) {
  let key = normalizeExpansionName(name);
  key = key.replace(/\s+(?:en|english|unlimited|1st edition|first edition)$/g, '').trim();
  if (!key || /shadowless/.test(key) || /pokemon jungle/.test(key) || /mystery of the fossils/.test(key)) {
    return null;
  }
  if (key === 'base set' || key === 'base') {
    return null;
  }
  return WIZARDS_EXPANSION_TO_SET[key] || null;
}

function collectorNumberFromVersion(version) {
  const s = String(version || '').trim();
  if (!s) {
    return null;
  }
  const frac = [...s.matchAll(/\b([Hh]?\d{1,3}[a-zA-Z]?)\s*\/\s*\d{1,3}\b/g)];
  if (frac.length) {
    return normalizeCollectorNumber(frac[frac.length - 1][1]);
  }
  const promo = s.match(/^\s*0*(\d{1,3})\s*(?:\||$)/);
  if (promo) {
    return promo[1];
  }
  return null;
}

function normalizeCollectorNumber(raw) {
  const s = String(raw || '').trim();
  const hidden = s.match(/^h(\d{1,3}[a-zA-Z]?)$/i);
  if (hidden) {
    return `H${hidden[1]}`;
  }
  const padded = s.match(/^0+(\d{1,3}[a-zA-Z]?)$/);
  if (padded) {
    return padded[1];
  }
  return s;
}

function hiresPngUrl(setId, number) {
  if (!setId || number == null || number === '') {
    return null;
  }
  return `${POKEMONTCG_HIRES}/${setId}/${encodeURIComponent(String(number))}_hires.png`;
}

function pngDimensionsFromPrefix(buf) {
  if (!Buffer.isBuffer(buf) || buf.length < 24) {
    return null;
  }
  if (buf[0] !== 0x89 || buf[1] !== 0x50 || buf.toString('ascii', 12, 16) !== 'IHDR') {
    return null;
  }
  return {
    width: buf.readUInt32BE(16),
    height: buf.readUInt32BE(20),
  };
}

function isBetterDefinition(api, ours) {
  if (!api || !api.width || !api.height) {
    return false;
  }
  if (!ours || !ours.width || !ours.height) {
    return true;
  }
  const apiArea = api.width * api.height;
  const ourArea = ours.width * ours.height;
  return apiArea >= Math.round(ourArea * BETTER_AREA_RATIO) && api.width >= ours.width;
}

function resolvePokemontcgHires(card = {}) {
  const setId =
    card.setId ||
    pokemontcgSetIdForExpansion(
      card.set || card.set_name || card.expansion_name || card.expansionName,
    );
  const number = collectorNumberFromVersion(
    card.number || card.card_number || card.version || card.rarity,
  );
  return {
    setId,
    number,
    url: hiresPngUrl(setId, number),
  };
}

function absoluteCdnUrl(value) {
  const text = String(value || '').trim();
  if (!text) {
    return '';
  }
  if (text.startsWith('http://') || text.startsWith('https://')) {
    return text;
  }
  if (text.startsWith('/card-images/')) {
    return `https://cdn.pokoin.com/${text.slice('/card-images/'.length)}`;
  }
  if (text.startsWith('/')) {
    return `https://cdn.pokoin.com${text}`;
  }
  return `https://cdn.pokoin.com/${text.replace(/^\/+/, '')}`;
}

async function catalogJpegFromPokemontcgPng(png, { sharp, sanitizeCardImage, filename } = {}) {
  if (!sharp) {
    throw new Error('sharp is required');
  }
  if (typeof sanitizeCardImage === 'function') {
    const result = await sanitizeCardImage(png, {
      sharp,
      format: 'jpg',
      jpegQuality: CATALOG_JPEG_QUALITY,
      filename,
    });
    if (!result.skipped) {
      return {
        body: result.body,
        width: result.width,
        height: result.height,
        format: 'jpg',
        sanitized: true,
        pad: result.pad || 0,
      };
    }
  }
  const encoded = await pngToMaxJpeg(png, {
    sharp,
    matte: { r: 11, g: 11, b: 15 },
    punchPartialAlpha: true,
  });
  return {
    body: encoded.body,
    width: encoded.width,
    height: encoded.height,
    format: 'jpg',
    sanitized: false,
    pad: 0,
  };
}

module.exports = {
  POKEMONTCG_HIRES,
  CATALOG_JPEG_QUALITY,
  BETTER_AREA_RATIO,
  WIZARDS_EXPANSION_TO_SET,
  normalizeExpansionName,
  pokemontcgSetIdForExpansion,
  collectorNumberFromVersion,
  normalizeCollectorNumber,
  hiresPngUrl,
  pngDimensionsFromPrefix,
  isBetterDefinition,
  resolvePokemontcgHires,
  absoluteCdnUrl,
  catalogJpegFromPokemontcgPng,
};
