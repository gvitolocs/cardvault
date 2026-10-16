import '../model/marketplace_home.dart';

/// Regole pure di selezione dei due caroselli pubblici della home.
class MarketplaceHomeSelectionService {
  /// Ordine recuperato da recentHomeExpansions: indizi backend, data, catalogo.
  static List<MarketplaceExpansion> recentExpansions(
    List<MarketplaceExpansion> expansions, {
    Map<String, int> catalogOrder = const {},
    List<String> newArrivalSets = const [],
    int limit = 12,
  }) {
    final hints = <String, int>{};
    for (final name in newArrivalSets) {
      hints.putIfAbsent(name.trim().toLowerCase(), () => hints.length);
    }
    final order = {
      for (final entry in catalogOrder.entries)
        entry.key.trim().toLowerCase(): entry.value
    };
    final unique = <String, MarketplaceExpansion>{};
    for (final expansion in expansions) {
      final key = expansion.name.trim().toLowerCase();
      if (key.isNotEmpty &&
          expansion.slug.isNotEmpty &&
          expansion.cardCount > 0) {
        unique.putIfAbsent(key, () => expansion);
      }
    }
    final result = unique.values.toList()
      ..sort((a, b) {
        final aKey = a.name.trim().toLowerCase();
        final bKey = b.name.trim().toLowerCase();
        if (hints[aKey] != null || hints[bKey] != null) {
          final comparison = (hints[aKey] ?? hints.length)
              .compareTo(hints[bKey] ?? hints.length);
          if (comparison != 0) return comparison;
        }
        if (a.releaseDate != null || b.releaseDate != null) {
          if (a.releaseDate == null) return 1;
          if (b.releaseDate == null) return -1;
          final comparison = b.releaseDate!.compareTo(a.releaseDate!);
          if (comparison != 0) return comparison;
        }
        final comparison = (b.expansionId ?? order[bKey] ?? 0)
            .compareTo(a.expansionId ?? order[aKey] ?? 0);
        return comparison != 0 ? comparison : aKey.compareTo(bKey);
      });
    return result.take(limit < 0 ? 0 : limit).toList(growable: false);
  }

  /// Solo gli ID classificati dal backend: il prezzo non misura le vendite.
  static List<MarketplaceCardPreview> cardsForRankedIds(
      List<MarketplaceCardPreview> cards, List<String> rankedIds) {
    final wanted = rankedIds.toSet();
    final byId = {
      for (final card in cards)
        if (wanted.contains(card.id)) card.id: card
    };
    final seen = <String>{};
    return rankedIds
        .where(seen.add)
        .map((id) => byId[id])
        .whereType<MarketplaceCardPreview>()
        .take(12)
        .toList(growable: false);
  }
}
