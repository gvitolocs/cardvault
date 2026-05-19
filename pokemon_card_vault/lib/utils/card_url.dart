import '../models/pokemon_card.dart';

String cardDetailPath(PokemonCard card) {
  return marketplaceCardDetailPath(card);
}

String marketplaceCardDetailPath(PokemonCard card, {String language = 'en'}) {
  return marketplaceCardDetailPathFromSlug(
    cardDetailSlug(card),
    language: language,
  );
}

String marketplaceCardDetailPathFromSlug(
  String slug, {
  String language = 'en',
}) {
  final cleanLanguage =
      _slugPart(language).isEmpty ? 'en' : _slugPart(language);
  return '/marketplace/$cleanLanguage/cards/$slug';
}

String marketplaceCardVersionsPathFromSlug(
  String slug, {
  String language = 'en',
}) {
  return '${marketplaceCardDetailPathFromSlug(slug, language: language)}/versions';
}

String marketplaceCardVersionsPath(PokemonCard card, {String language = 'en'}) {
  return marketplaceCardVersionsPathFromSlug(
    cardDetailSlug(card),
    language: language,
  );
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

String cardDetailPathFromParts({
  required String id,
  required String name,
  required String number,
  required String setName,
  String language = 'en',
}) {
  final parts = [id, name, number, setName];
  return marketplaceCardDetailPathFromSlug(
    parts.map(_slugPart).where((part) => part.isNotEmpty).join('-'),
    language: language,
  );
}

String cardIdFromSlug(String slug) {
  final match = RegExp(r'^\d+').firstMatch(slug.trim());
  return match?.group(0) ?? slug.trim();
}

String collectionExpansionPath(String expansionName) {
  return '/collection/${collectionExpansionSlug(expansionName)}';
}

String collectionExpansionSlug(String expansionName) {
  return _slugPart(expansionName);
}

String _slugPart(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}
