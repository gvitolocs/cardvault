import 'dart:async';
import 'package:flutter/foundation.dart';
import '../model/cardex.dart';
import '../model/marketplace_home.dart';
import '../service/cardex_service.dart';
import '../service/collection_service.dart';
import '../model/expansion_era.dart';
import '../service/expansion_era_service.dart';
import '../service/card_ownership_service.dart';
import '../model/card_ownership.dart';
import '../constants/cardex_pagination_constants.dart';
import 'collection_artwork_controller.dart';

class CardexController extends ChangeNotifier {
  CardexController(
      {CardexService? catalog,
      CollectionService? collection,
      CollectionArtworkController? artwork})
      : _catalog = catalog ?? CardexService(),
        _ownsCatalog = catalog == null,
        _collection = collection ?? CollectionService(),
        artwork = artwork ?? CollectionArtworkController() {
    this.artwork.addListener(_artworkPreferenceChanged);
  }
  final CollectionArtworkController artwork;
  String _observedArtworkLanguage = 'IT';
  void _artworkPreferenceChanged() {
    if (_observedArtworkLanguage == artwork.language) return;
    _observedArtworkLanguage = artwork.language;
    _selectedLanguages.clear();
    _notify();
  }

  void setArtworkLanguage(String language) {
    _selectedLanguages.clear();
    artwork.selectLanguage(language);
    _notify();
  }

  String artworkLanguageFor(String cardId) =>
      _selectedLanguages[cardId] ?? artwork.language;

  CardOwnership detailsOwnershipFor(String cardId,
          {String? selectedLanguage}) =>
      _ownership.describe(collection, cardId,
          selectedLanguage: selectedLanguage ?? artworkLanguageFor(cardId));

  MarketplaceCardPreview artworkPreview(MarketplaceCardPreview preview) {
    final code = artworkLanguageFor(preview.id);
    final localized = code == 'EN'
        ? null
        : artwork.metadataFor(preview.id)?.languageImageUrls[code];
    if (localized == null) return preview;
    return MarketplaceCardPreview(
        id: preview.id,
        name: preview.name,
        expansion: preview.expansion,
        number: preview.number,
        imageUrl: localized,
        fullImageUrl: localized,
        imageLanguage: code,
        pricePkn: preview.pricePkn,
        canonicalPath: preview.canonicalPath);
  }

  final CardexService _catalog;
  final bool _ownsCatalog;
  final CollectionService _collection;
  StreamSubscription<CardCollection>? _subscription;
  bool _disposed = false, _started = false, _catalogStarted = false;
  int _generation = 0, _nextOffset = 0;
  List<MarketplaceExpansion> expansions = const [];
  List<MarketplaceCardPreview> cards = const [];
  MarketplaceExpansion? expansion;
  CardCollection collection = CardCollection(status: CollectionStatus.loading);
  CardexFilter filter = CardexFilter.all;
  bool loadingExpansions = false, expansionsError = false;
  bool loadingPage = false, pageError = false, hasMore = false;
  int total = 0;
  final _eras = ExpansionEraService();
  final _ownership = const CardOwnershipService();
  final _selectedLanguages = <String, String>{};
  CardOwnership ownershipFor(String cardId) =>
      _ownership.describe(collection, cardId,
          selectedLanguage: artworkLanguageFor(cardId));

  void selectOwnedLanguage(String cardId, String language) {
    if (_disposed || !ownershipKnown) return;
    final code = _ownership.normalizeLanguage(language);
    final view = ownershipFor(cardId);
    if (!view.languages.any((option) => option.code == code && option.owned) ||
        _selectedLanguages[cardId] == code) {
      return;
    }
    _selectedLanguages[cardId] = code;
    _notify();
  }

  List<ExpansionEraGroup> expansionGroups = const [];
  String expansionQuery = '';
  List<ExpansionEraGroup> get visibleExpansionGroups =>
      _eras.filter(expansionGroups, expansionQuery);

  void setExpansionQuery(String value) {
    if (_disposed || expansionQuery == value) return;
    expansionQuery = value;
    _notify();
  }

  bool get ownershipKnown => collection.status == CollectionStatus.ready;
  bool collectionAlbum = true;
  // View intent must not change while private data is still loading or failed.
  bool get viewingCollection =>
      collectionAlbum && collection.status != CollectionStatus.guest;
  List<MarketplaceCardPreview> get visibleCards => viewingCollection
      ? collection.cards
      : !ownershipKnown
          ? cards
          : List.unmodifiable(cards.where((card) => switch (filter) {
                CardexFilter.all => true,
                CardexFilter.owned => collection.owns(card.id),
                CardexFilter.missing => !collection.owns(card.id),
              }));

  void start({bool loadCatalog = true}) {
    if (_disposed) return;
    unawaited(artwork.start());
    if (!_started) {
      _started = true;
      retryCollection();
    }
    if (loadCatalog && !_catalogStarted) {
      _catalogStarted = true;
      unawaited(loadExpansions());
    }
  }

  void retryCollection() {
    if (_disposed) return;
    unawaited(_subscription?.cancel());
    collection = CardCollection(status: CollectionStatus.loading);
    _selectedLanguages.clear();
    _notify();
    _subscription = _collection.watch().listen((value) {
      if (_disposed) return;
      collection = value;
      if (!ownershipKnown) {
        filter = CardexFilter.all;
        _selectedLanguages.clear();
      }
      _notify();
    }, onError: (Object error, StackTrace stack) {
      if (_disposed) return;
      collection = CardCollection(status: CollectionStatus.unavailable);
      _selectedLanguages.clear();
      _notify();
    });
  }

  Future<void> loadExpansions() async {
    if (loadingExpansions || _disposed) return;
    loadingExpansions = true;
    expansionsError = false;
    _notify();
    try {
      final result = await _catalog.loadExpansions();
      if (_disposed) return;
      expansions = result;
      expansionGroups = _eras.group(result);
      if (expansion == null && result.isNotEmpty) {
        unawaited(selectExpansion(result.first, showCatalog: false));
      }
    } catch (_) {
      if (!_disposed) expansionsError = true;
    } finally {
      if (!_disposed) {
        loadingExpansions = false;
        _notify();
      }
    }
  }

  Future<void> selectExpansion(MarketplaceExpansion value,
      {bool showCatalog = true}) async {
    if (_disposed) return;
    if (showCatalog) collectionAlbum = false;
    ++_generation;
    expansion = value;
    cards = const [];
    _nextOffset = 0;
    total = value.cardCount;
    hasMore = true;
    loadingPage = false;
    pageError = false;
    await loadMore();
  }

  Future<void> loadMore() async {
    if (_disposed || loadingPage || !hasMore || expansion == null) return;
    final request = _generation;
    final selected = expansion!;
    loadingPage = true;
    pageError = false;
    _notify();
    try {
      final page = await _catalog.loadPage(selected.slug, offset: _nextOffset);
      if (_disposed || request != _generation) return;
      final merged = _catalog.mergeCards(cards, page.cards);
      if (page.hasMore && merged.length == cards.length) {
        throw const FormatException('Catalog pagination made no progress');
      }
      cards = merged;
      _nextOffset = page.offset + page.cards.length;
      total = page.total;
      hasMore = page.hasMore;
    } catch (_) {
      if (!_disposed && request == _generation) pageError = true;
    } finally {
      if (!_disposed && request == _generation) {
        loadingPage = false;
        _notify();
      }
    }
  }

  /// Album coordinates refer to visible (possibly filtered) cards, not stock.
  /// Errors require explicit retry; no background retry loop or Guest fallback.
  void onAlbumPageVisible(int visibleEnd, int capacity) {
    if (_disposed ||
        viewingCollection ||
        pageError ||
        loadingPage ||
        !hasMore ||
        expansion == null ||
        capacity < 1) {
      return;
    }
    if (visibleCards.length - visibleEnd <=
        capacity * CardexPaginationConstants.prefetchRemainingSpreads) {
      unawaited(loadMore());
    }
  }

  void setFilter(CardexFilter value) {
    if (!ownershipKnown || filter == value) return;
    filter = value;
    _notify();
  }

  void showCollection() {
    if (!ownershipKnown || _disposed) return;
    collectionAlbum = true;
    filter = CardexFilter.all;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    artwork.removeListener(_artworkPreferenceChanged);
    artwork.dispose();
    unawaited(_subscription?.cancel());
    if (_ownsCatalog) _catalog.dispose();
    super.dispose();
  }
}
