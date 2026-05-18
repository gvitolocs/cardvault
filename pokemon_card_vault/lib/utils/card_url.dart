import '../models/pokemon_card.dart';

String cardDetailPath(PokemonCard card) {
  return '/${cardDetailSlug(card)}';
}

String cardDetailSlug(PokemonCard card) {
  final parts = [
    card.id,
    card.name,
    card.number,
    card.set,
  ];
  return parts.map(_slugPart).where((part) => part.isNotEmpty).join('-');
}

String cardIdFromSlug(String slug) {
  final match = RegExp(r'^\d+').firstMatch(slug.trim());
  return match?.group(0) ?? slug.trim();
}

String _slugPart(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}
