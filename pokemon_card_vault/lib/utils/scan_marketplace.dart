import '../models/pokemon_card.dart';
import 'card_url.dart';

/// Milo / YOLO identity is leftover `ct_id` (gallery manifest `identity: ct_id`).
/// Marketplace URLs use **our id** (`ct_id * 2`). Do not treat Milo `id` as a
/// TCGplayer product id. Catalog `card.id` is already public — do not × 2 it.
class CardScanHit {
  const CardScanHit({
    required this.tcgplayerId,
    required this.name,
    this.collectorNumber = '',
    this.setName = '',
    this.score = 0,
    this.cardtraderBlueprintId = '',
  });

  /// Only a real TCGplayer product id when the payload sends one. Milo `id` is not this.
  final String tcgplayerId;
  final String name;
  final String collectorNumber;
  final String setName;
  final double score;
  final String cardtraderBlueprintId;

  factory CardScanHit.fromJson(Map<String, dynamic> json) {
    final leftover =
        '${json['ct_id'] ?? json['ctId'] ?? json['blueprint_id'] ?? json['blueprintId'] ?? json['id'] ?? ''}'
            .trim();
    return CardScanHit(
      tcgplayerId:
          '${json['tcgplayerId'] ?? json['tcgplayer_id'] ?? ''}'.trim(),
      name: '${json['name'] ?? ''}'.trim(),
      collectorNumber:
          '${json['collector_number'] ?? json['collectorNumber'] ?? ''}'.trim(),
      setName: '${json['set'] ?? json['set_name'] ?? json['setName'] ?? ''}'
          .trim(),
      score: (json['score'] is num)
          ? (json['score'] as num).toDouble()
          : double.tryParse('${json['score'] ?? ''}') ?? 0,
      cardtraderBlueprintId: leftover,
    );
  }
}

String scanHitAutocompleteQuery({
  required String name,
  String collectorNumber = '',
}) {
  final cleanName = name.trim();
  if (cleanName.isEmpty) {
    return '';
  }
  final leading = _leadingCollectorToken(collectorNumber);
  return leading.isEmpty ? cleanName : '$cleanName $leading';
}

String scanHitMarketplacePath({
  required String name,
  String collectorNumber = '',
  String setName = '',
  String rarity = '',
  String cardtraderBlueprintId = '',
  PokemonCard? matchedCard,
}) {
  if (matchedCard != null) {
    final path = marketplaceCardDetailPath(matchedCard);
    if (path.isNotEmpty) {
      return path;
    }
  }
  final blueprint = cardtraderBlueprintId.trim();
  if (RegExp(r'^\d+$').hasMatch(blueprint)) {
    // CLIP/scan returns CardTrader ct_id. Our marketplace card.id is already
    // that × 2. Double only this raw ct_id — never a catalog card.id.
    final publicId = doubledCardId(blueprint);
    final generated = cardDetailPathFromParts(
      id: publicId.isEmpty ? blueprint : publicId,
      name: name,
      number: collectorNumber,
      setName: setName,
      rarity: rarity.trim().isEmpty ? 'Card' : rarity,
    );
    if (generated.isNotEmpty) {
      return generated;
    }
  }
  final query = scanHitAutocompleteQuery(
    name: name,
    collectorNumber: collectorNumber,
  );
  if (query.isEmpty) {
    return '/marketplace';
  }
  return Uri(
    path: '/marketplace/search',
    queryParameters: {'q': query},
  ).toString();
}

PokemonCard? pickMarketplaceCardForScanHit({
  required String name,
  String collectorNumber = '',
  String setName = '',
  required List<PokemonCard> candidates,
}) {
  final wantedName = _norm(name);
  if (wantedName.isEmpty || candidates.isEmpty) {
    return null;
  }
  final wantedNumber = _leadingCollectorToken(collectorNumber);
  final wantedSet = _norm(setName);
  PokemonCard? best;
  var bestScore = -1;
  for (final card in candidates) {
    if (_norm(card.name) != wantedName) {
      continue;
    }
    var score = 10;
    final cardNumber = _leadingCollectorToken(card.number);
    if (wantedNumber.isNotEmpty && cardNumber == wantedNumber) {
      score += 8;
    }
    if (wantedSet.isNotEmpty && _norm(card.set) == wantedSet) {
      score += 6;
    } else if (wantedSet.isNotEmpty &&
        _norm(card.set).contains(wantedSet)) {
      score += 2;
    }
    if (score > bestScore) {
      bestScore = score;
      best = card;
    }
  }
  return best;
}

String _leadingCollectorToken(String value) {
  final match = RegExp(r'\d+').firstMatch(value.trim());
  return match?.group(0) ?? '';
}

String _norm(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}
