'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const csv = require('./_stock_csv');

describe('stock csv conditions / languages / finishes', () => {
  it('maps CM/PT conditions onto Pokoin', () => {
    assert.equal(csv.mapConditionFromCm('EX'), 'SP');
    assert.equal(csv.mapConditionFromCm('GD'), 'MP');
    assert.equal(csv.mapConditionFromCm('PO'), 'Poor');
    assert.equal(csv.mapConditionToCm('SP'), 'EX');
  });

  it('maps languages both ways', () => {
    assert.equal(csv.mapLanguageFromName('Italian'), 'IT');
    assert.equal(csv.mapLanguageToName('IT'), 'Italian');
  });

  it('maps ReverseHolo finish', () => {
    const f = csv.mapFinishFromPowerTools({ finishType: 'ReverseHolo', isReverseHolo: 'true' });
    assert.equal(f.foilState, 'reverse');
    assert.equal(f.reverse, true);
    const back = csv.mapFinishToPowerTools(f);
    assert.equal(back.finishType, 'ReverseHolo');
  });
});

describe('location ↔ stack/position', () => {
  it('formats and parses pokoin structured locations', () => {
    assert.equal(csv.formatListingLocation({ box: 'box1', stack: 3, stackSize: 1 }), 'box1·3');
    assert.equal(csv.formatListingLocation({ box: 'box1', stack: 2, position: 5, stackSize: 10 }), 'box1·2·5');
    assert.deepEqual(csv.parseLocation('box1·2·5'), { box: 'box1', stack: 2, position: 5 });
  });

  it('keeps bare PT box names intact (FUOCOBOMBA 006 - 16)', () => {
    const p = csv.parseLocation('FUOCOBOMBA 006 - 16');
    assert.equal(p.box, 'FUOCOBOMBA 006 - 16');
    assert.equal(p.stack, 1);
  });

  it('assigns sequential stacks when stackSize is 1', () => {
    const rows = csv.assignStackPositions([
      { location: 'FUOCOBOMBA 006 - 16' },
      { location: 'FUOCOBOMBA 006 - 16' },
      { location: 'other' },
    ], 1);
    assert.equal(rows[0].location, 'FUOCOBOMBA 006 - 16·1');
    assert.equal(rows[1].location, 'FUOCOBOMBA 006 - 16·2');
    assert.equal(rows[2].location, 'other·1');
  });

  it('fills positions then spills when stackSize > 1', () => {
    const rows = csv.assignStackPositions([
      { location: 'box1' },
      { location: 'box1' },
      { location: 'box1' },
    ], 2);
    assert.equal(rows[0].location, 'box1·1·1');
    assert.equal(rows[1].location, 'box1·1·2');
    assert.equal(rows[2].location, 'box1·2·1');
  });
});

describe('price', () => {
  it('converts EUR to PKN at 200×', () => {
    assert.equal(csv.priceToPkn('0.5', { priceMode: 'eur_to_pkn' }), 100);
    assert.equal(csv.priceToPkn('100', { priceMode: 'cents_eur_to_pkn' }), 200);
    assert.equal(csv.pknToEur(200), '1');
  });
});

describe('PowerTools sample round-trip', () => {
  const samplePath = [
    '/workspace/powertools-F006-16.csv',
    path.join(__dirname, 'fixtures/powertools-F006-16.csv'),
    '/home/nez/Desktop/F. 006 - 16.csv',
  ].find((p) => {
    try { return fs.existsSync(p); } catch { return false; }
  });

  it('detects and imports the attached PowerTools CSV', () => {
    assert.ok(samplePath, 'sample CSV missing');
    const text = fs.readFileSync(samplePath, 'utf8');
    const { format, results } = csv.importCsvText(text, { stackSize: 1, priceMode: 'eur_to_pkn' });
    assert.equal(format, 'powertools');
    assert.equal(results.length, 47);
    assert.ok(results.every((r) => r.ok));
    const first = results[0].row;
    assert.equal(first.cardmarketId, '805496');
    assert.equal(first.language, 'IT');
    assert.equal(first.foilState, 'reverse');
    assert.equal(first.location, 'FUOCOBOMBA 006 - 16·1');
    assert.equal(results[1].row.location, 'FUOCOBOMBA 006 - 16·2');
  });

  it('exports powertools headers exactly', () => {
    const out = csv.exportListingsCsv('powertools', [{
      cardName: 'Bug Catching Set',
      setName: 'Prismatic Evolutions',
      collectorNumber: '102/131',
      condition: 'NM',
      language: 'IT',
      foilState: 'reverse',
      reverse: true,
      pricePkn: 200,
      quantityAvailable: 1,
      location: 'FUOCOBOMBA 006 - 16·1',
      cardmarketId: '805496',
    }]);
    const { headers, records } = csv.parseCsv(out);
    assert.deepEqual(headers, [...csv.POWERTOOLS_HEADERS]);
    assert.equal(records[0].finishType, 'ReverseHolo');
    assert.equal(records[0].language, 'Italian');
    assert.equal(records[0].price, '1');
  });
});
