import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/rebuild/presentation/shared/marketplace_image_url.dart';

void main() {
  test('card image route resolves directly to the identical CDN file', () {
    for (final source in [
      '/card-images/612454_tandemaus.jpg?v=2',
      'https://pokoin.com/card-images/612454_tandemaus.jpg?v=2',
    ]) {
      expect(marketplaceImageUri(source).toString(),
          'https://cdn.pokoin.com/612454_tandemaus.jpg?v=2');
    }
    expect(marketplaceImageUri('/card-images/nested/card%20one.jpg').toString(),
        'https://cdn.pokoin.com/nested/card%20one.jpg');
  });

  test('other origins and existing CDN paths stay unchanged', () {
    for (final source in [
      'https://cdn.pokoin.com/expansions/symbols/set.png',
      'https://example.com/card-images/card.jpg',
    ]) {
      expect(marketplaceImageUri(source).toString(), source);
    }
    expect(marketplaceImageUri('/assets/logo.png').toString(),
        'https://pokoin.com/assets/logo.png');
    expect(marketplaceImageUri(''), isNull);
    expect(marketplaceImageUri('file:///card.jpg'), isNull);
    expect(marketplaceImageUri('data:image/png;base64,abc'), isNull);
  });
}
