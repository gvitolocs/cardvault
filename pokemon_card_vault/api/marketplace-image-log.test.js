const assert = require('node:assert/strict');
const test = require('node:test');
const {
  imagePrefix,
  prefixKind,
  recordMarketplaceImage,
  listMarketplaceImages,
} = require('./_marketplace_image_log');

test('image prefix kind distinguishes public id from ct_id', () => {
  assert.equal(imagePrefix('/card-images/299054_terapagos-ex.jpg'), '299054');
  assert.equal(
    prefixKind('598108', '299054', '/card-images/299054_terapagos-ex.jpg'),
    'ct_id',
  );
  assert.equal(
    prefixKind('598108', '299054', '/card-images/598108_terapagos-ex.jpg'),
    'public_id',
  );
});

test('image ring records served and error events', () => {
  const served = recordMarketplaceImage({
    source: 'marketplace-home',
    status: 'served',
    cardId: '598108',
    ctId: '299054',
    url: '/card-images/previews/299054_terapagos-ex.jpg',
    name: 'Terapagos ex',
  });
  const failed = recordMarketplaceImage({
    source: 'client',
    status: 'error',
    cardId: '598108',
    ctId: '299054',
    url: '/card-images/598108_terapagos-ex.jpg',
    error: 'HTTP 404',
  });
  assert.equal(served.prefixKind, 'ct_id');
  assert.equal(failed.prefixKind, 'public_id');
  const rows = listMarketplaceImages(10);
  assert.ok(rows.some((row) => row.status === 'error' && row.prefixKind === 'public_id'));
});
