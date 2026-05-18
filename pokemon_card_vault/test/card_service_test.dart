import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/services/card_service.dart';

void main() {
  test('CardTrader blueprint mapping removes generic Pokemon badge fallback',
      () {
    final service = CardService();

    final card = service.cardFromBlueprintForTest({
      'id': 281194,
      'name': 'Gengar ex',
      'cdn_image_url': 'https://cdn.pokoin.com/cards/gengar.png',
      'preview_image_url': 'https://cdn.pokoin.com/previews/gengar.webp',
      'blueprint': {
        'name': 'Gengar ex',
        'category_name': 'Pokemon',
        'editable_properties': [
          {'name': 'number', 'value': '193/162'},
        ],
      },
      'expansion': {'name': 'Temporal Forces'},
    });

    expect(card.name, 'Gengar ex');
    expect(card.set, 'Temporal Forces');
    expect(card.number, '193/162');
    expect(card.rarity, 'Card');
    expect(card.type, 'Trading card');
    expect(card.stock, 0);
    expect(card.tags, isNot(contains('Pokemon')));
    expect(card.imageUrl, '/card-images/cards/gengar.png');
    expect(card.previewImageUrl, '/card-images/previews/gengar.webp');
  });

  test('CardTrader blueprint mapping leaves external image URLs unchanged', () {
    final service = CardService();

    final card = service.cardFromBlueprintForTest({
      'id': 42,
      'name': 'External card',
      'image_url': 'https://images.pokemontcg.io/base1/4_hires.png',
      'blueprint': <String, dynamic>{},
      'expansion': <String, dynamic>{},
    });

    expect(card.imageUrl, 'https://images.pokemontcg.io/base1/4_hires.png');
    expect(
      card.previewImageUrl,
      'https://images.pokemontcg.io/base1/4_hires.png',
    );
  });

  test('CardTrader blueprint mapping reads image URL from blueprint fallback',
      () {
    final service = CardService();

    final card = service.cardFromBlueprintForTest({
      'id': 43,
      'name': 'Blueprint image card',
      'blueprint': {
        'image_url': 'https://cdn.pokoin.com/blueprint/card.png',
      },
      'expansion': <String, dynamic>{},
    });

    expect(card.imageUrl, '/card-images/blueprint/card.png');
    expect(card.previewImageUrl, '/card-images/blueprint/card.png');
  });
}
