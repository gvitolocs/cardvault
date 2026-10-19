import 'package:flutter/widgets.dart';

/// Carta reale: conserva ID e prezzi Pokoin restituiti dal backend.
class MarketplaceCard {
  const MarketplaceCard(
      {required this.id,
      required this.name,
      required this.expansion,
      required this.number,
      required this.imageUrl,
      this.pricePkn,
      this.rarity = '',
      this.artist = '',
      this.productType = '',
      this.canonicalPath = '',
      this.description = '',
      this.hp,
      this.types = const []});

  final String id, name, expansion, number, imageUrl;
  final String rarity, artist, productType, canonicalPath, description;
  final double? pricePkn;
  final int? hp;
  final List<String> types;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'set': expansion,
        'number': number,
        'imageUrl': imageUrl,
        'pricePkn': pricePkn,
        'rarity': rarity,
        'artist': artist,
        'productType': productType,
        'canonicalPath': canonicalPath,
        'description': description,
        'hp': hp,
        'types': types,
      };

  factory MarketplaceCard.fromJson(Map<String, dynamic> json) {
    String read(List<String> keys) {
      for (final key in keys) {
        final value = '${json[key] ?? ''}'.trim();
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    final price = num.tryParse(read(['pricePkn', 'price', 'lowestPricePkn']));
    final rawTypes = json['types'];
    return MarketplaceCard(
      id: read(['id', 'card_id']),
      name: read(['name']),
      expansion: read(['set', 'set_name', 'expansion_name']),
      number: read(['number', 'card_number', 'expansion_number']),
      imageUrl:
          read(['heroImageUrl', 'imageUrl', 'cdn_image_url', 'image_url']),
      pricePkn: price != null && price.isFinite && price > 0
          ? price.toDouble()
          : null,
      rarity: read(['rarityKind', 'rarity']),
      artist: read(['artist', 'illustrator']),
      productType: read(['productType', 'card_type']),
      canonicalPath: read(['canonicalPath', 'canonical_path']),
      description: read(['description']),
      hp: int.tryParse(read(['hp'])),
      types: List.unmodifiable(
          rawTypes is List ? rawTypes.map((e) => '$e') : <String>[]),
    );
  }
}

/// Modello locale delle carte usato dal prototipo del marketplace mobile.
class DemoCard {
  const DemoCard(this.id, this.name, this.expansion, this.number, this.price,
      this.color, this.icon);

  // Gli ID demo non sono ID del catalogo. Con i servizi usare l'ID canonico
  // Pokoin restituito da CardService, senza conversioni CardTrader nel client.
  final String id;
  final String name;
  final String expansion;
  final String number;
  final double price;
  final Color color;
  final IconData icon;
}
