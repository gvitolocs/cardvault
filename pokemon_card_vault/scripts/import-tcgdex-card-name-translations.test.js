const assert = require('node:assert/strict');
const test = require('node:test');

const {
  cardTranslationsForLanguage,
  compactText,
  expansionTranslationsForLanguage,
  localizedCardForRow,
  normalizeCollectorNumber,
  parseArgs,
  parseLanguages,
  upsertCardTranslationsSql,
  upsertExpansionTranslationsSql,
} = require('./import-tcgdex-card-name-translations');

test('TCGdex translation importer is dry-run by default', () => {
  const options = parseArgs([]);

  assert.equal(options.apply, false);
  assert.equal(options.importCards, true);
  assert.equal(options.importExpansions, true);
});

test('TCGdex translation importer parses scoped options', () => {
  const options = parseArgs([
    '--apply',
    '--language=it,fr',
    '--cards-only',
    '--limit=25',
    '--concurrency=100',
  ]);

  assert.equal(options.apply, true);
  assert.deepEqual(options.languages, ['it', 'fr']);
  assert.equal(options.importCards, true);
  assert.equal(options.importExpansions, false);
  assert.equal(options.limit, 25);
  assert.equal(options.concurrency, 8);
  assert.equal(options.limitlessFallback, true);
});

test('TCGdex translation importer can disable Limitless fallback', () => {
  const options = parseArgs(['--no-limitless-fallback']);

  assert.equal(options.limitlessFallback, false);
});

test('parseLanguages normalizes aliases and rejects unsupported languages', () => {
  assert.deepEqual(parseLanguages('jp,zh'), ['ja', 'zh-cn']);
  assert.throws(() => parseLanguages('ko'), /Unsupported language/);
});

test('normalizers fold accented multilingual names', () => {
  assert.equal(compactText('Pokémon Écarlate & Violet'), 'pokemonecarlateviolet');
  assert.equal(normalizeCollectorNumber('005/131'), '5');
  assert.equal(normalizeCollectorNumber('SVP 101'), 'svp101');
});

test('card mapping prefers stable TCGdex card IDs', () => {
  const rows = [{
    cardId: '316600',
    name: 'Leafeon ex',
    displayName: 'Leafeon ex',
    setName: 'Prismatic Evolutions',
    collectorNumber: '005/131',
    tcgdexSetId: 'sv8pt5',
    tcgdexCardId: 'sv8pt5-005',
  }];
  const localizedCards = [{
    id: 'sv8pt5-005',
    localId: '005',
    name: 'Phyllali-ex',
    set: { id: 'sv8pt5' },
  }];

  const match = localizedCardForRow(rows[0], {
    byId: new Map(localizedCards.map((card) => [card.id, { id: card.id, name: card.name, raw: card }])),
    bySetNumber: new Map(),
  });
  const { translations, counts } = cardTranslationsForLanguage(rows, localizedCards, 'fr');

  assert.equal(match.reason, 'tcgdex_card_id');
  assert.equal(translations.length, 1);
  assert.equal(translations[0].localizedName, 'Phyllali-ex');
  assert.equal(translations[0].source, 'tcgdex');
  assert.equal(counts.matched, 1);
});

test('card mapping can fall back to set id and collector number', () => {
  const { translations } = cardTranslationsForLanguage([
    {
      cardId: '25',
      name: 'Pikachu',
      displayName: 'Pikachu',
      setName: 'Scarlet & Violet',
      collectorNumber: '063/198',
      tcgdexSetId: 'sv1',
      tcgdexCardId: '',
    },
  ], [
    {
      id: 'sv1-063',
      localId: '063',
      name: 'Pikachu-DE',
      set: { id: 'sv1' },
    },
  ], 'de');

  assert.equal(translations.length, 1);
  assert.equal(translations[0].matchReason, 'tcgdex_set_id_collector');
});

test('TCGdex direct match wins over Limitless fallback support', () => {
  const { translations } = cardTranslationsForLanguage([
    {
      cardId: '25',
      name: 'Pikachu',
      displayName: 'Pikachu',
      setName: 'Scarlet & Violet',
      collectorNumber: '063/198',
      tcgdexSetId: 'sv1',
      tcgdexCardId: 'sv1-063',
      limitlessSetCode: 'SVI',
      limitlessCollectorNumber: '063',
      limitlessCardName: 'Different Pikachu',
      limitlessSourceCardId: 'limitless-pikachu',
      limitlessMatchConfidence: 1,
    },
  ], [
    {
      id: 'sv1-063',
      localId: '063',
      name: 'Pikachu-DE',
      set: { id: 'sv1' },
    },
    {
      id: 'sv2-063',
      localId: '063',
      name: 'Falscher Pikachu',
      set: { id: 'sv2' },
    },
  ], 'de', {
    englishCards: [{
      id: 'sv2-063',
      localId: '063',
      name: 'Different Pikachu',
      set: { id: 'sv2', name: 'Other Set' },
    }],
  });

  assert.equal(translations.length, 1);
  assert.equal(translations[0].matchReason, 'tcgdex_card_id');
  assert.equal(translations[0].source, 'tcgdex');
  assert.equal(translations[0].localizedName, 'Pikachu-DE');
});

test('TCGdex miss can use high-confidence Limitless bridge to localized TCGdex card', () => {
  const { translations, counts } = cardTranslationsForLanguage([
    {
      cardId: '99',
      name: 'Rare Candy',
      displayName: 'Rare Candy',
      setName: 'HeartGold & SoulSilver',
      collectorNumber: '82/123',
      tcgdexSetId: '',
      tcgdexCardId: '',
      limitlessSetCode: 'HS',
      limitlessCollectorNumber: '82',
      limitlessCardName: 'Rare Candy',
      limitlessSourceCardId: 'rare-candy-hs-82',
      limitlessExpansionName: 'HeartGold & SoulSilver',
      limitlessMatchConfidence: 1,
    },
  ], [
    {
      id: 'hgss1-082',
      localId: '082',
      name: 'Super Bonbon',
      set: { id: 'hgss1' },
    },
  ], 'fr', {
    englishCards: [{
      id: 'hgss1-082',
      localId: '082',
      name: 'Rare Candy',
      set: { id: 'hgss1', name: 'HeartGold & SoulSilver' },
    }],
  });

  assert.equal(translations.length, 1);
  assert.equal(translations[0].localizedName, 'Super Bonbon');
  assert.equal(translations[0].source, 'tcgdex+limitless');
  assert.equal(translations[0].matchReason, 'limitless_set_name_collector_name');
  assert.equal(counts.bySource['tcgdex+limitless'], 1);
});

test('low-confidence Limitless card fallback is skipped', () => {
  const { translations, counts } = cardTranslationsForLanguage([
    {
      cardId: '99',
      name: 'Rare Candy',
      displayName: 'Rare Candy',
      setName: 'HeartGold & SoulSilver',
      collectorNumber: '82/123',
      tcgdexSetId: '',
      tcgdexCardId: '',
      limitlessSetCode: 'HS',
      limitlessCollectorNumber: '82',
      limitlessCardName: 'Rare Candy',
      limitlessSourceCardId: 'rare-candy-hs-82',
      limitlessExpansionName: 'HeartGold & SoulSilver',
      limitlessMatchConfidence: 0.8,
    },
  ], [
    {
      id: 'hgss1-082',
      localId: '082',
      name: 'Super Bonbon',
      set: { id: 'hgss1' },
    },
  ], 'fr', {
    englishCards: [{
      id: 'hgss1-082',
      localId: '082',
      name: 'Rare Candy',
      set: { id: 'hgss1', name: 'HeartGold & SoulSilver' },
    }],
  });

  assert.equal(translations.length, 0);
  assert.equal(counts.skipped, 1);
});

test('expansion mapping imports localized aliases', () => {
  const { translations, counts } = expansionTranslationsForLanguage([
    {
      name: 'Scarlet & Violet',
      code: 'SVI',
      tcgdexSetId: 'sv1',
    },
  ], [
    {
      id: 'sv1',
      name: 'Écarlate et Violet',
    },
  ], 'fr');

  assert.equal(counts.matched, 1);
  assert.equal(translations[0].expansionName, 'Scarlet & Violet');
  assert.equal(translations[0].localizedName, 'Écarlate et Violet');
  assert.equal(translations[0].matchReason, 'tcgdex_set_id');
  assert.equal(translations[0].source, 'tcgdex');
});

test('expansion mapping can use Limitless alias fallback to TCGdex set', () => {
  const { translations, counts } = expansionTranslationsForLanguage([
    {
      name: 'HeartGold & SoulSilver',
      code: 'HS',
      tcgdexSetId: '',
      limitlessExpansionName: 'HeartGold & SoulSilver',
      limitlessExpansionCode: 'HS',
      limitlessAliases: ['HGSS'],
    },
  ], [
    {
      id: 'hgss1',
      name: 'HeartGold & SoulSilver-DE',
    },
  ], 'de', {
    englishSets: [{
      id: 'hgss1',
      name: 'HeartGold & SoulSilver',
    }],
  });

  assert.equal(counts.matched, 1);
  assert.equal(translations[0].localizedName, 'HeartGold & SoulSilver-DE');
  assert.equal(translations[0].source, 'tcgdex+limitless');
  assert.equal(translations[0].matchReason, 'limitless_expansion_name');
});

test('upsert SQL targets only multilingual translation tables', () => {
  assert.match(upsertCardTranslationsSql(1), /public\.marketplace_card_name_translations/);
  assert.match(upsertExpansionTranslationsSql(1), /public\.marketplace_expansion_name_translations/);
  assert.match(upsertCardTranslationsSql(1), /source <> 'tcgdex'[\s\S]*excluded\.source = 'tcgdex'/);
  assert.match(upsertExpansionTranslationsSql(1), /source <> 'tcgdex'[\s\S]*excluded\.source = 'tcgdex'/);
  assert.doesNotMatch(upsertCardTranslationsSql(1), /marketplace_user_listings|marketplace_blueprint_price/);
  assert.doesNotMatch(upsertExpansionTranslationsSql(1), /marketplace_user_listings|marketplace_blueprint_price/);
});
