import 'package:flutter/foundation.dart';

import '../models/pokemon_card.dart';

String cardDetailPath(PokemonCard card) {
  return safeCardDetailPath(card);
}

String rootCardDetailPath(PokemonCard card) {
  final canonical = _cleanCanonicalCardPath(card.canonicalPath);
  if (canonical.isNotEmpty) {
    return canonical;
  }
  return rootCardDetailPathFromParts(
    cardId: card.id,
    slug: cardDetailSlug(card),
  );
}

String rootCardDetailPathFromParts({
  required String cardId,
  required String slug,
}) {
  final cleanId = cardId.trim();
  final cleanSlug = normalizeCardDetailSlug(slug);
  if (!RegExp(r'^\d+$').hasMatch(cleanId) || cleanSlug.isEmpty) {
    return '';
  }
  return '/$cleanId/$cleanSlug';
}

String marketplaceCardDetailPath(PokemonCard card, {String language = 'en'}) {
  final canonical = _cleanCanonicalCardPath(card.canonicalPath);
  if (canonical.isNotEmpty) {
    return canonical;
  }
  return marketplaceCardDetailPathFromParts(
    cardId: card.id,
    slug: cardDetailSlug(card),
    language: language,
  );
}

String safeCardDetailPath(PokemonCard card, {String language = 'en'}) {
  final storedCanonical = _cleanCanonicalCardPath(card.canonicalPath);
  if (storedCanonical.isNotEmpty) {
    return storedCanonical;
  }
  final canonical = marketplaceCardDetailPath(card, language: language);
  if (canonical.isNotEmpty) {
    return canonical;
  }
  return '';
}

String safeCardDetailPathWithDatabaseCanonical(
  PokemonCard card, {
  String databaseCanonicalPath = '',
  String language = 'en',
}) {
  final databaseCanonical = _cleanCanonicalCardPath(databaseCanonicalPath);
  if (databaseCanonical.isNotEmpty) {
    return databaseCanonical;
  }
  return safeCardDetailPath(card, language: language);
}

String databaseCanonicalCardDetailPath(PokemonCard card) {
  return _cleanCanonicalCardPath(card.canonicalPath);
}

typedef MarketplaceCanonicalPathLookup = Future<String> Function({
  required String cardId,
  required String language,
});

Future<String> databaseBackedCardDetailPath(
  PokemonCard card, {
  String language = 'en',
  required MarketplaceCanonicalPathLookup canonicalPathLookup,
}) async {
  final storedCanonical = databaseCanonicalCardDetailPath(card);
  if (storedCanonical.isNotEmpty) {
    return storedCanonical;
  }
  final cardId = card.id.trim();
  if (!RegExp(r'^\d+$').hasMatch(cardId)) {
    return '';
  }
  final lookupCanonical = await canonicalPathLookup(
    cardId: cardId,
    language: language,
  );
  return _cleanCanonicalCardPath(lookupCanonical);
}

Future<String> resolveDatabaseBackedCardDetailPath(
  PokemonCard card, {
  String language = 'en',
  required MarketplaceCanonicalPathLookup canonicalPathLookup,
}) {
  return databaseBackedCardDetailPath(
    card,
    language: language,
    canonicalPathLookup: canonicalPathLookup,
  );
}

String marketplaceCardDetailPathFromParts({
  required String cardId,
  required String slug,
  String language = 'en',
}) {
  final cleanLanguage =
      _slugPart(language).isEmpty ? 'en' : _slugPart(language);
  final doubledId = doubledCardId(cardId);
  final cleanSlug = normalizeCardDetailSlug(slug);
  if (doubledId.isEmpty || cleanSlug.isEmpty) {
    return '';
  }
  return '/marketplace/$cleanLanguage/cards/$doubledId/$cleanSlug';
}

String marketplaceCardShortLinkRedirectPath(
  String id, {
  String language = 'en',
}) {
  final cleanId = id.trim();
  if (!isRootCardShortLink(cleanId)) {
    return '';
  }
  return '/$cleanId';
}

bool isRootCardShortLink(String value) {
  return RegExp(r'^\d+$').hasMatch(value.trim());
}

bool isLegacyRootCardDetailPathForCard({
  required String path,
  required PokemonCard card,
}) {
  final cleanCardId = card.id.trim();
  if (!RegExp(r'^\d+$').hasMatch(cleanCardId)) {
    return false;
  }
  final segments = path.split('/').where((part) => part.isNotEmpty).toList();
  if (segments.length != 2 || normalizeCardDetailSlug(segments[1]).isEmpty) {
    return false;
  }
  final routeId = segments.first.trim();
  return routeId == cleanCardId || routeId == doubledCardId(cleanCardId);
}

String marketplaceCardVersionsPathFromParts({
  required String cardId,
  required String slug,
  String language = 'en',
}) {
  final detailPath = marketplaceCardDetailPathFromParts(
    cardId: cardId,
    slug: slug,
    language: language,
  );
  return detailPath.isEmpty ? '' : '$detailPath/versions';
}

String marketplaceCardVersionsPath(PokemonCard card, {String language = 'en'}) {
  final canonical = _cleanCanonicalCardPath(card.canonicalPath);
  if (canonical.isNotEmpty) {
    return '$canonical/versions';
  }
  return marketplaceCardVersionsPathFromParts(
    cardId: card.id,
    slug: cardDetailSlug(card),
    language: language,
  );
}

String cardDetailSlug(PokemonCard card) {
  final storedSlug = _slugFromCanonicalCardPath(card.canonicalPath);
  if (storedSlug.isNotEmpty) {
    return storedSlug;
  }
  final parts = [
    card.rarity.trim().isEmpty ? 'Card' : card.rarity,
    card.name,
    card.number,
    card.set,
  ];
  return parts.map(_slugPart).where((part) => part.isNotEmpty).join('-');
}

String legacyCardDetailSlug(PokemonCard card) {
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
  String rarity = 'Card',
  String language = 'en',
}) {
  final parts = [
    rarity.trim().isEmpty ? 'Card' : rarity,
    name,
    number,
    setName
  ];
  final slug = parts.map(_slugPart).where((part) => part.isNotEmpty).join('-');
  return marketplaceCardDetailPathFromParts(
    cardId: id,
    slug: slug.isEmpty ? _slugPart(id) : slug,
    language: language,
  );
}

String safeCardDetailPathFromParts({
  required String id,
  required String name,
  required String number,
  required String setName,
  String rarity = 'Card',
  String language = 'en',
}) {
  final canonical = cardDetailPathFromParts(
    id: id,
    name: name,
    number: number,
    setName: setName,
    rarity: rarity,
    language: language,
  );
  if (canonical.isNotEmpty) {
    return canonical;
  }
  return '';
}

bool goToSafeCardDetail(
  void Function(String location, {Object? extra}) go,
  PokemonCard card, {
  String language = 'en',
  Object? extra,
}) {
  final path = safeCardDetailPath(card, language: language);
  if (path.isEmpty) {
    return false;
  }
  go(path, extra: extra);
  return true;
}

bool goToSafeCardDetailFromParts(
  void Function(String location, {Object? extra}) go, {
  required String id,
  required String name,
  required String number,
  required String setName,
  String rarity = 'Card',
  String language = 'en',
  Object? extra,
}) {
  final path = safeCardDetailPathFromParts(
    id: id,
    name: name,
    number: number,
    setName: setName,
    rarity: rarity,
    language: language,
  );
  if (path.isEmpty) {
    return false;
  }
  go(path, extra: extra);
  return true;
}

String _cleanCanonicalCardPath(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return '';
  }
  final uri = Uri.tryParse(text);
  final path = uri?.hasScheme == true ? uri!.path : text.split('?').first;
  if (!path.startsWith('/marketplace/') || !path.contains('/cards/')) {
    return '';
  }
  return path.split('#').first;
}

String _slugFromCanonicalCardPath(String value) {
  final path = _cleanCanonicalCardPath(value);
  if (path.isEmpty) {
    return '';
  }
  final parts = path.split('/').where((part) => part.isNotEmpty).toList();
  final cardsIndex = parts.indexOf('cards');
  if (cardsIndex < 0 || cardsIndex + 2 >= parts.length) {
    return '';
  }
  return normalizeCardDetailSlug(parts.sublist(cardsIndex + 2).join('-'));
}

String? browserInitialLocationForRouter(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return null;
  }
  final path = uri.path.isEmpty ? '/' : uri.path;
  final query = uri.hasQuery ? '?${uri.query}' : '';
  final fragment = uri.hasFragment ? '#${uri.fragment}' : '';
  return '$path$query$fragment';
}

bool isMarketplaceCardDetailRoutePath(String path) {
  final segments = path.split('/').where((part) => part.isNotEmpty).toList();
  if (segments.length != 5) {
    return false;
  }
  return segments[0] == 'marketplace' &&
      RegExp(r'^[a-z]{2}(?:-[a-z]{2})?$').hasMatch(segments[1]) &&
      segments[2] == 'cards' &&
      RegExp(r'^\d+$').hasMatch(segments[3]) &&
      normalizeCardDetailSlug(segments[4]).isNotEmpty;
}

bool isMarketplaceArtistRoutePath(String path) {
  final segments = path.split('/').where((part) => part.isNotEmpty).toList();
  if (segments.length < 4 || segments.length > 5) {
    return false;
  }
  const artistSubpages = {
    'illustration',
    'full-arts',
    'normal-cards',
    'profile',
  };
  final isArtistLeaf = segments.length == 4;
  final isArtistSubpage = segments.length == 5 &&
      artistSubpages.contains(segments[4]);
  return segments[0] == 'marketplace' &&
      RegExp(r'^[a-z]{2}(?:-[a-z]{2})?$').hasMatch(segments[1]) &&
      segments[2] == 'artists' &&
      normalizeCardDetailSlug(segments[3]).isNotEmpty &&
      (isArtistLeaf || isArtistSubpage);
}

bool isProtectedCardDetailDriftTargetPath(String path) {
  return path == '/' ||
      path == '/marketplace' ||
      isMarketplaceArtistRoutePath(path);
}

bool shouldRepairCardDetailRootDrift({
  required String previousPath,
  required String nextPath,
  required String lastCardDetailRoute,
  bool cardDetailMounted = false,
  bool hasExplicitNavigationIntent = false,
  String browserPath = '',
}) {
  if (!isProtectedCardDetailDriftTargetPath(nextPath)) {
    return false;
  }
  final lastPath = _pathFromLocation(lastCardDetailRoute);
  if (!isMarketplaceCardDetailRoutePath(lastPath)) {
    return false;
  }
  if (hasExplicitNavigationIntent) {
    return false;
  }
  return cardDetailMounted || isMarketplaceCardDetailRoutePath(previousPath);
}

String cardDetailCanonicalReplacementLocation({
  required String canonicalPath,
  required Uri currentUri,
}) {
  final cleanPath = canonicalPath.trim();
  if (cleanPath.isEmpty) {
    return '';
  }
  return Uri(
    path: cleanPath,
    fragment: currentUri.hasFragment ? currentUri.fragment : null,
  ).toString();
}

String _pathFromLocation(String location) {
  final text = location.trim();
  if (text.isEmpty) {
    return '';
  }
  return Uri.tryParse(text)?.path ?? text;
}

class CardDetailRouteGuard {
  CardDetailRouteGuard._();

  static final CardDetailRouteGuard instance = CardDetailRouteGuard._();

  int _mountedCardDetailCount = 0;
  String _lastCardDetailRoute = '';
  _ExplicitNavigationIntent? _explicitIntent;

  bool get hasMountedCardDetail => _mountedCardDetailCount > 0;
  String get lastCardDetailRoute => _lastCardDetailRoute;

  void cardDetailMounted({String route = ''}) {
    _mountedCardDetailCount += 1;
    updateCardDetailRoute(route);
  }

  void cardDetailDisposed() {
    if (_mountedCardDetailCount > 0) {
      _mountedCardDetailCount -= 1;
    }
  }

  void updateCardDetailRoute(String route) {
    final text = route.trim();
    if (text.isEmpty) {
      return;
    }
    final path = _pathFromLocation(text);
    if (isMarketplaceCardDetailRoutePath(path)) {
      _lastCardDetailRoute = text;
    }
  }

  void markExplicitNavigation(
    String location, {
    Duration ttl = const Duration(seconds: 3),
  }) {
    final path = _pathFromLocation(location);
    if (path.isEmpty) {
      return;
    }
    _explicitIntent = _ExplicitNavigationIntent(
      path: path,
      expiresAt: DateTime.now().add(ttl),
    );
  }

  bool consumeExplicitNavigation(String location) {
    final intent = _explicitIntent;
    if (intent == null) {
      return false;
    }
    if (DateTime.now().isAfter(intent.expiresAt)) {
      _explicitIntent = null;
      return false;
    }
    final path = _pathFromLocation(location);
    if (path != intent.path) {
      return false;
    }
    _explicitIntent = null;
    return true;
  }

  @visibleForTesting
  void resetForTest() {
    _mountedCardDetailCount = 0;
    _lastCardDetailRoute = '';
    _explicitIntent = null;
  }
}

class _ExplicitNavigationIntent {
  const _ExplicitNavigationIntent({
    required this.path,
    required this.expiresAt,
  });

  final String path;
  final DateTime expiresAt;
}

String numericCardIdFromSlug(String slug) {
  final match = RegExp(r'^\d+').firstMatch(slug.trim());
  return match?.group(0) ?? '';
}

String cardIdFromSlug(String slug) {
  final match = RegExp(r'^\d+').firstMatch(slug.trim());
  return match?.group(0) ?? slug.trim();
}

String doubledCardId(String id) {
  final cleanId = id.trim();
  if (!RegExp(r'^\d+$').hasMatch(cleanId)) {
    return '';
  }
  final value = BigInt.tryParse(cleanId);
  if (value == null || value <= BigInt.zero) {
    return '';
  }
  return (value * BigInt.from(2)).toString();
}

String cardIdFromDoubledId(String doubledId) {
  final cleanId = doubledId.trim();
  if (!RegExp(r'^\d+$').hasMatch(cleanId)) {
    return '';
  }
  final value = BigInt.tryParse(cleanId);
  if (value == null || value <= BigInt.zero || !value.isEven) {
    return '';
  }
  return (value ~/ BigInt.from(2)).toString();
}

MarketplaceCardRouteParts parseMarketplaceCardRoute({
  required String firstSegment,
  String? slugSegment,
}) {
  final first = firstSegment.trim();
  final slug =
      slugSegment == null ? null : normalizeCardDetailSlug(slugSegment);
  if (slug != null && slug.isNotEmpty) {
    final decodedId = cardIdFromDoubledId(first);
    if (decodedId.isNotEmpty) {
      return MarketplaceCardRouteParts(
        cardId: decodedId,
        cardSlug: slug,
        isCanonicalShape: true,
      );
    }
    return MarketplaceCardRouteParts(
      cardId: cardIdFromSlug(first),
      cardSlug: slug,
      isCanonicalShape: false,
    );
  }
  if (isRootCardShortLink(first)) {
    return MarketplaceCardRouteParts(
      cardId: first,
      cardSlug: null,
      isCanonicalShape: false,
    );
  }
  return MarketplaceCardRouteParts(
    cardId: cardIdFromSlug(first),
    cardSlug: first,
    isCanonicalShape: false,
  );
}

class MarketplaceCardRouteParts {
  const MarketplaceCardRouteParts({
    required this.cardId,
    required this.cardSlug,
    required this.isCanonicalShape,
  });

  final String cardId;
  final String? cardSlug;
  final bool isCanonicalShape;
}

bool cardDetailSlugHasNumericId(String slug) {
  return RegExp(r'^\d+(?:-|$)').hasMatch(slug.trim());
}

String normalizeCardDetailSlug(String slug) {
  return _slugPart(slug);
}

bool cardDetailSlugsMatch(String left, String right) {
  final normalizedLeft = _normalizeCardDetailSlugForMatch(left);
  final normalizedRight = _normalizeCardDetailSlugForMatch(right);
  if (normalizedLeft.isEmpty || normalizedRight.isEmpty) {
    return false;
  }
  if (normalizedLeft == normalizedRight) {
    return true;
  }
  const classifierPrefixes = {
    'card',
    'fixed',
    'common',
    'uncommon',
    'rare',
    'holo',
    'ultra',
    'secret',
    'promo',
    'product',
    'trading',
  };
  return _stripLeadingClassifier(normalizedLeft, classifierPrefixes) ==
      _stripLeadingClassifier(normalizedRight, classifierPrefixes);
}

String collectionExpansionPath(String expansionName) {
  return '/collection/${collectionExpansionSlug(expansionName)}';
}

String collectionExpansionSlug(String expansionName) {
  return _slugPart(expansionName);
}

String marketplaceArtistPath(String artistName, {String language = 'en'}) {
  final slug = artistSlug(artistName);
  final cleanLanguage =
      _slugPart(language).isEmpty ? 'en' : _slugPart(language);
  return slug.isEmpty
      ? '/marketplace/$cleanLanguage/artists'
      : '/marketplace/$cleanLanguage/artists/$slug';
}

String collectionArtistPath(String artistName) {
  final slug = artistSlug(artistName);
  return slug.isEmpty ? '/collection' : '/collection/artists/$slug';
}

String artistSlug(String artistName) {
  return _slugPart(artistName);
}

String _slugPart(String value) {
  return value
      .replaceAll('é', 'e')
      .replaceAll('É', 'E')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}

String _normalizeCardDetailSlugForMatch(String slug) {
  final parts = _slugParts(slug);
  if (parts.isEmpty) {
    return '';
  }
  return _normalizeCollectorNumberSlugParts(parts).join('-');
}

List<String> _slugParts(String value) {
  final normalized = _slugPart(value);
  if (normalized.isEmpty) {
    return const [];
  }
  return normalized.split('-').where((part) => part.isNotEmpty).toList();
}

List<String> _normalizeCollectorNumberSlugParts(List<String> parts) {
  final normalized = [...parts];
  for (var index = 0; index < normalized.length - 1; index += 1) {
    if (_isCollectorNumberSlugToken(normalized[index]) &&
        _isCollectorNumberSlugToken(normalized[index + 1])) {
      normalized[index] = _normalizeCollectorNumberSlugToken(normalized[index]);
      normalized[index + 1] =
          _normalizeCollectorNumberSlugToken(normalized[index + 1]);
      index += 1;
    }
  }
  return normalized;
}

bool _isCollectorNumberSlugToken(String value) {
  return RegExp(r'^[0-9]+[a-z]?$').hasMatch(value);
}

String _normalizeCollectorNumberSlugToken(String value) {
  return value.replaceFirst(RegExp(r'^0+(?=[0-9])'), '');
}

String _stripLeadingClassifier(String slug, Set<String> classifierPrefixes) {
  final parts = slug.split('-').where((part) => part.isNotEmpty).toList();
  while (parts.isNotEmpty && classifierPrefixes.contains(parts.first)) {
    parts.removeAt(0);
  }
  return parts.join('-');
}
