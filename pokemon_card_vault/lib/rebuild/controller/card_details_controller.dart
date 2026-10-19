import 'dart:async';
import 'package:flutter/foundation.dart';
import '../model/card_details_state.dart';
import '../service/card_service.dart';
export '../model/card_details_state.dart';

/// Carica una volta per apertura e filtra localmente, senza notificare la home.
class CardDetailsController {
  CardDetailsController({required this.cardId, required CardService service})
      : _service = service;
  final String cardId;
  final CardService _service;
  final info = ValueNotifier(const CardInfoState());
  final listings = ValueNotifier(const ListingsState());
  bool _started = false, _disposed = false;

  Future<void> load({bool includeListings = true}) async {
    if (_started || _disposed) return;
    _started = true;
    await Future.wait([
      _loadInfo(),
      if (includeListings) _loadListings(),
    ]);
  }

  Future<void> retryInfo() async {
    if (_disposed || info.value.loading || !info.value.hasError) return;
    info.value = const CardInfoState();
    await _loadInfo();
  }

  Future<void> retryListings() async {
    if (_disposed || listings.value.loading || !listings.value.hasError) return;
    listings.value = const ListingsState();
    await _loadListings();
  }

  Future<void> _loadInfo() async {
    try {
      final card = await _service.fetchCard(cardId);
      if (!_disposed) info.value = CardInfoState(card: card, loading: false);
    } catch (_) {
      if (!_disposed) {
        info.value = const CardInfoState(loading: false, hasError: true);
      }
    }
  }

  Future<void> _loadListings() async {
    try {
      final all = await _service.fetchListings(cardId);
      if (_disposed) return;
      listings.value = ListingsState(all: all, loading: false);
      _filter();
    } catch (_) {
      if (!_disposed) {
        listings.value = const ListingsState(loading: false, hasError: true);
      }
    }
  }

  void filter({String? condition, String? language, ListingSort? sort}) =>
      _filter(
          condition: condition,
          language: language,
          sort: sort,
          replaceFilters: true);

  void loadMoreListings(String originId) {
    if (_disposed) return;
    final state = listings.value;
    if (state.loading || state.hasError) return;
    final matching = state.groups.where((group) => group.origin.id == originId);
    if (matching.isEmpty || !matching.first.hasMore) return;
    final group = matching.first;
    listings.value = state.withGroups(limits: {
      ...state.groupLimits,
      originId: group.limit + group.nextCount,
    });
  }

  void toggleListingGroup(String originId) {
    if (_disposed) return;
    final state = listings.value;
    if (state.loading ||
        state.hasError ||
        !state.groups.any((group) => group.origin.id == originId)) {
      return;
    }
    final collapsed = {...state.collapsedGroups};
    if (!collapsed.add(originId)) collapsed.remove(originId);
    listings.value = state.withGroups(collapsed: collapsed);
  }

  void _filter(
      {String? condition,
      String? language,
      ListingSort? sort,
      bool replaceFilters = false}) {
    if (_disposed) return;
    final state = listings.value;
    final c = replaceFilters ? condition : state.condition;
    final l = replaceFilters ? language : state.language;
    final s = sort ?? state.sort;
    final visible = state.all
        .where((offer) =>
            (c == null || offer.condition == c) &&
            (l == null || offer.language == l))
        .toList()
      ..sort((a, b) {
        final price = s == ListingSort.lowestPrice
            ? a.pricePkn.compareTo(b.pricePkn)
            : b.pricePkn.compareTo(a.pricePkn);
        return price == 0 ? a.id.compareTo(b.id) : price;
      });
    listings.value = ListingsState(
        all: state.all,
        visible: List.unmodifiable(visible),
        loading: state.loading,
        hasError: state.hasError,
        condition: c,
        language: l,
        sort: s);
  }

  void dispose() {
    _disposed = true;
    info.dispose();
    listings.dispose();
  }
}
