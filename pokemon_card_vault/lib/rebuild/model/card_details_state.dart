import 'card.dart';
import 'listing.dart';

class CardInfoState {
  const CardInfoState({this.card, this.loading = true, this.hasError = false});
  final MarketplaceCard? card;
  final bool loading, hasError;
}

enum ListingSort { lowestPrice, highestPrice }

class ListingsState {
  const ListingsState(
      {this.all = const [],
      this.visible = const [],
      this.loading = true,
      this.hasError = false,
      this.condition,
      this.language,
      this.groupLimits = const {},
      this.collapsedGroups = const {},
      this.sort = ListingSort.lowestPrice});
  final List<MarketplaceListing> all, visible;
  final bool loading, hasError;
  final String? condition, language;
  final ListingSort sort;
  static const groupPageSize = 4;
  final Map<String, int> groupLimits;
  final Set<String> collapsedGroups;

  /// Proiezione dei risultati filtrati: conserva l'ordine di prezzo scelto.
  List<ListingGroup> get groups {
    final buckets = <String, List<MarketplaceListing>>{};
    for (final offer in visible) {
      buckets.putIfAbsent(offer.origin.id, () => []).add(offer);
    }
    return List.unmodifiable([
      for (final entry in buckets.entries)
        ListingGroup(
            origin: entry.value.first.origin,
            offers: List.unmodifiable(entry.value),
            limit: groupLimits[entry.key] ?? groupPageSize,
            expanded: !collapsedGroups.contains(entry.key)),
    ]);
  }

  ListingsState withGroups(
          {Map<String, int>? limits, Set<String>? collapsed}) =>
      ListingsState(
        all: all,
        visible: visible,
        loading: loading,
        hasError: hasError,
        condition: condition,
        language: language,
        sort: sort,
        groupLimits: Map.unmodifiable(limits ?? groupLimits),
        collapsedGroups: Set.unmodifiable(collapsed ?? collapsedGroups),
      );

  MarketplaceListing? get bestOffer {
    MarketplaceListing? best;
    for (final offer in visible) {
      if (best == null ||
          offer.pricePkn < best.pricePkn ||
          (offer.pricePkn == best.pricePkn &&
              offer.id.compareTo(best.id) < 0)) {
        best = offer;
      }
    }
    return best;
  }
}

class ListingGroup {
  const ListingGroup(
      {required this.origin,
      required this.offers,
      required this.limit,
      required this.expanded});
  final ListingOrigin origin;
  final List<MarketplaceListing> offers;
  final int limit;
  final bool expanded;
  List<MarketplaceListing> get shown => List.unmodifiable(offers.take(limit));
  bool get hasMore => limit < offers.length;
  int get nextCount =>
      (offers.length - limit).clamp(0, ListingsState.groupPageSize);
  double get lowestPrice =>
      offers.map((offer) => offer.pricePkn).reduce((a, b) => a < b ? a : b);
}
