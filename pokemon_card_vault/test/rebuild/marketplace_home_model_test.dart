import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/rebuild/model/marketplace_home.dart';

void main() {
  test('keeps the thumbnail and full artwork URLs separate', () {
    final preview = MarketplaceCardPreview.fromJson({
      'id': '24',
      'name': 'Carta',
      'homepageImageUrl': '/card-images/24_homepage.webp',
      'tileImageUrl': '/card-images/24_homepage.webp',
      'heroImageUrl': '/card-images/24.jpg',
      'imageUrl': '/card-images/24.jpg',
    });
    expect(preview.imageUrl, '/card-images/24_homepage.webp');
    expect(preview.fullImageUrl, '/card-images/24.jpg');
    expect(
        MarketplaceCardPreview.fromJson({'imageUrl': '/card-images/48.jpg'})
            .fullImageUrl,
        '/card-images/48.jpg');
  });

  test('preview prefers the first populated image and preserves API values',
      () {
    final preview = MarketplaceCardPreview.fromJson({
      'id': 806390,
      'name': 'Carta',
      'set': 'Set',
      'homepageImageUrl': '',
      'previewImageUrl': '/card-images/806390.jpg',
      'lowestPricePkn': '97126',
    });
    expect(preview.id, '806390');
    expect(preview.pricePkn, 97126);
    expect(preview.imageUrl, '/card-images/806390.jpg');
  });
}
