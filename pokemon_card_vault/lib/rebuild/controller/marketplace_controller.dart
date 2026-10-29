import 'package:flutter/foundation.dart';

import '../model/card.dart';
import '../model/demo_catalog.dart';
import '../model/marketplace_home.dart';
import '../model/cardex.dart';
import '../model/marketplace_discovery_state.dart';
import '../service/cart_service.dart';
import '../service/marketplace_home_service.dart';
import 'cart_controller.dart';
import 'marketplace_search_controller.dart';
import '../service/marketplace_search_service.dart';
import '../service/marketplace_suggestion_service.dart';
import 'card_details_controller.dart';
import '../service/card_service.dart';
import 'cardex_controller.dart';
import 'account_controller.dart';
import 'profile_controller.dart';
import 'scanner_controller.dart';
import 'scan_clipboard_controller.dart';
import '../provider/collection_provider.dart';
import '../provider/inventory_provider.dart';
import '../service/collection_service.dart';
import '../service/profile_service.dart';
import 'collection_artwork_controller.dart';
import '../service/collection_artwork_service.dart';

/// Coordina i service e lo stato del marketplace senza dipendere dalla UI.
/// Notifica separatamente catalogo, carrello e filtri/preferiti/navigazione.
class MarketplaceController extends ChangeNotifier {
  MarketplaceController({
    MarketplaceHomeService? homeService,
    CartService? cartService,
    CardService? cardService,
    MarketplaceSearchService? searchService,
    MarketplaceSuggestionService? suggestionService,
    CardexController? cardexController,
    AccountController? accountController,
    ProfileService? profileService,
  })  : _homeService = homeService,
        _ownsHomeService = homeService == null,
        _cardService = cardService,
        _ownsCardService = cardService == null,
        _injectedCardex = cardexController,
        account = accountController ?? AccountController(),
        _ownsAccount = accountController == null,
        _profileService = profileService,
        _ownsCardex = cardexController == null,
        _cartService = cartService,
        search = MarketplaceSearchController(
            service: searchService, suggestionService: suggestionService);

  MarketplaceHomeService? _homeService;
  final bool _ownsHomeService;
  final CartService? _cartService;
  late final CartController cart = CartController(
      service: _cartService, cards: _cardService ??= CardService());
  final CardexController? _injectedCardex;
  final AccountController account;
  final bool _ownsAccount;
  final ProfileService? _profileService;
  late final ProfileController profile =
      ProfileController(account: account, service: _profileService);
  late final CardexController cardex = _injectedCardex ??
      CardexController(
          artwork: CollectionArtworkController(
              service: CollectionArtworkService(
                  cards: _cardService ??= CardService())),
          collection: CollectionService(
              inventory: InventoryProvider(),
              provider: CollectionProvider(userIds: account.watchUserId)));
  final bool _ownsCardex;
  final MarketplaceSearchController search;
  final ScanClipboardController clipboard = ScanClipboardController();
  late final ScannerController scanner =
      ScannerController(storeDrafts: clipboard.storeScans);
  CardService? _cardService;
  final bool _ownsCardService;
  CardDetailsController createCardDetails(String id) => CardDetailsController(
      cardId: id, service: _cardService ??= CardService());
  final _discovery = ValueNotifier(const MarketplaceDiscoveryState());
  final _favorites = <String>{};
  Future<void>? _pendingDiscovery;
  bool _disposed = false;
  String _searchQuery = '';
  String? _expansion;
  int _selectedTab = 0;

  String get searchQuery => _searchQuery;
  String? get selectedExpansion => _expansion;
  int get selectedTab => _selectedTab;
  List<String> get expansions => demoExpansions;
  bool get isFiltered => _searchQuery.trim().isNotEmpty || _expansion != null;

  List<DemoCard> get visibleCards {
    final query = _searchQuery.trim().toLowerCase();
    return List.unmodifiable(demoCards.where((card) =>
        (_expansion == null || card.expansion == _expansion) &&
        '${card.name} ${card.expansion} ${card.number}'
            .toLowerCase()
            .contains(query)));
  }

  bool isFavorite(String cardId) => _favorites.contains(cardId);

  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    notifyListeners();
  }

  void selectExpansion(String? expansion) {
    if (_expansion == expansion) return;
    _expansion = expansion;
    notifyListeners();
  }

  void selectTab(int tab) {
    RangeError.checkValidIndex(tab, const [0, 1, 2, 3, 4]);
    if (_selectedTab == tab) return;
    _selectedTab = tab;
    if (tab == 2 || tab == 3) cardex.start(loadCatalog: tab == 3);
    if (tab == 4) profile.start();
    notifyListeners();
  }

  Future<void> openCardexExpansion(MarketplaceExpansion expansion) {
    selectTab(3);
    cardex.setFilter(CardexFilter.all);
    return cardex.selectExpansion(expansion);
  }

  void toggleFavorite(DemoCard card) {
    // Preferiti locali finché il prototipo rimane aperto.
    if (!_favorites.add(card.id)) _favorites.remove(card.id);
    notifyListeners();
  }

  ValueListenable<MarketplaceDiscoveryState> get discovery => _discovery;

  /// Il service viene creato solo quando si richiedono gli slider reali.
  /// Richieste concorrenti condividono il caricamento anche nel controller.
  Future<void> loadDiscovery({bool forceRefresh = false}) {
    if (_disposed) return Future.value();
    if (_pendingDiscovery != null) return _pendingDiscovery!;
    _discovery.value = MarketplaceDiscoveryState(
      data: _discovery.value.data,
      isLoading: true,
    );
    final service = _homeService ??= MarketplaceHomeService();
    _pendingDiscovery = _loadDiscovery(service, forceRefresh)
        .whenComplete(() => _pendingDiscovery = null);
    return _pendingDiscovery!;
  }

  Future<void> retryDiscovery() => loadDiscovery(forceRefresh: true);

  Future<void> _loadDiscovery(
      MarketplaceHomeService service, bool forceRefresh) async {
    try {
      final data = await service.load(
          forceRefresh: forceRefresh,
          onProgress: (data) {
            if (_disposed) return;
            _discovery.value = MarketplaceDiscoveryState(
                data: data,
                isLoading: data.expansionsLoading || data.topSellersLoading);
          });
      if (_disposed) return;
      if (identical(_discovery.value.data, data) &&
          !_discovery.value.isLoading) {
        return;
      }
      _discovery.value = MarketplaceDiscoveryState(data: data);
    } catch (_) {
      if (_disposed) return;
      _discovery.value = MarketplaceDiscoveryState(
        data: _discovery.value.data,
        hasError: true,
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    scanner.dispose();
    clipboard.dispose();
    if (_ownsHomeService) _homeService?.dispose();
    cart.dispose();
    if (_ownsCardService) _cardService?.dispose();
    search.dispose();
    if (_ownsCardex) cardex.dispose();
    profile.dispose();
    if (_ownsAccount) account.dispose();
    _discovery.dispose();
    super.dispose();
  }
}
