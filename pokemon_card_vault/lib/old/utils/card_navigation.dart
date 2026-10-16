import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/pokemon_card.dart';
import '../services/card_service.dart';
import '../services/flutter_debug_log.dart';
import '../services/search_debug_trace.dart';
import 'card_url.dart';

Future<bool> navigateToCanonicalCardDetail(
  BuildContext context,
  PokemonCard card, {
  String language = 'en',
  Object? extra,
  String source = 'card_tile',
  CardService? cardService,
  bool replace = false,
}) async {
  final path = immediateCardDetailNavigationPath(card, language: language);
  if (!context.mounted) {
    return false;
  }
  if (path.isEmpty) {
    _recordCanonicalNavigationBlocked(card, source: source);
    return false;
  }
  CardDetailRouteGuard.instance.markExplicitNavigation(path);
  if (replace) {
    context.replace(path, extra: extra);
  } else {
    context.go(path, extra: extra);
  }
  return true;
}

String immediateCardDetailNavigationPath(PokemonCard card, {String language = 'en'}) {
  return safeCardDetailPath(card, language: language);
}

Future<String> canonicalCardDetailNavigationPath(
  PokemonCard card, {
  String language = 'en',
  CardService? cardService,
}) {
  return databaseBackedCardDetailPath(
    card,
    language: language,
    canonicalPathLookup: ({required cardId, required language}) async {
      final canonical =
          await (cardService ?? CardService()).getMarketplaceCardCanonicalUrl(
        cardId: cardId,
        language: language,
      );
      return canonical?.canonicalPath ?? '';
    },
  );
}

void _recordCanonicalNavigationBlocked(
  PokemonCard card, {
  required String source,
}) {
  final payload = {
    'cardId': card.id,
    'cardName': card.name,
    'source': source,
    'reason': 'missing_database_canonical_path',
  };
  SearchDebugTrace.instance.record(
    'card_detail_navigation.blocked',
    payload,
  );
  FlutterDebugLog.instance.record(
    'card_detail_navigation.blocked',
    category: 'navigation',
    payload: payload,
  );
}
