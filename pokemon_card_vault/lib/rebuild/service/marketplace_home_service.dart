import 'package:http/http.dart' as http;

import '../cache/marketplace_home_cache.dart';
import '../model/marketplace_home.dart';
import '../provider/expansion_catalog_provider.dart';
import '../provider/marketplace_home_provider.dart';
import 'marketplace_home_selection_service.dart';

typedef ExpansionOrderLoader = Future<Map<String, int>> Function();
typedef MarketplaceHomeProgress = void Function(MarketplaceHomeData data);

/// Estratto da CardService e marketplace_home_discovery.dart.
/// Carica solo i due slider pubblici, senza inizializzare i servizi legacy.
class MarketplaceHomeService {
  MarketplaceHomeService({
    http.Client? client,
    Uri? apiBase,
    ExpansionOrderLoader? loadCatalogOrder,
    MarketplaceHomeCache? cache,
    this.timeout = const Duration(seconds: 8),
    this.cacheDuration = const Duration(minutes: 5),
  })  : _provider = MarketplaceHomeProvider(
            client: client, apiBase: apiBase, timeout: timeout),
        _loadCatalogOrder =
            loadCatalogOrder ?? ExpansionCatalogProvider().loadOrder,
        _diskCache = cache ?? MarketplaceHomeCache();

  final MarketplaceHomeProvider _provider;
  final ExpansionOrderLoader _loadCatalogOrder;
  final Duration timeout;
  final Duration cacheDuration;
  final MarketplaceHomeCache _diskCache;
  bool _restoredCache = false;
  Future<MarketplaceHomeData>? _inFlight;
  MarketplaceHomeData? _cached;
  DateTime? _cachedAt;
  MarketplaceHomeData? _latest;
  final _progressListeners = <MarketplaceHomeProgress>{};

  /// Richieste concorrenti condividono lo stesso caricamento; nessun GET in build.
  Future<MarketplaceHomeData> load(
      {bool forceRefresh = false, MarketplaceHomeProgress? onProgress}) {
    if (_inFlight != null) {
      if (onProgress != null) {
        _progressListeners.add(onProgress);
        if (_latest != null) onProgress(_latest!);
      }
      return _inFlight!;
    }
    if (!forceRefresh &&
        _cached != null &&
        DateTime.now().difference(_cachedAt!) < cacheDuration) {
      return Future.value(_cached);
    }
    if (onProgress != null) _progressListeners.add(onProgress);
    _inFlight = _load(forceRefresh: forceRefresh).whenComplete(() {
      _inFlight = null;
      _progressListeners.clear();
    });
    return _inFlight!;
  }

  Future<MarketplaceHomeData> _load({required bool forceRefresh}) async {
    if (!_restoredCache) await _restoreCache();
    final savedAt = _latest?.cachedAt;
    final now = DateTime.now();
    if (!forceRefresh &&
        savedAt != null &&
        !savedAt.isAfter(now) &&
        now.difference(savedAt) < cacheDuration) {
      // Un riavvio entro cinque minuti riusa anche la cache persistente.
      _cached = _latest;
      _cachedAt = savedAt;
      return _latest!;
    }
    final homeRequest = _provider.fetchHome();
    final expansionsRequest = _provider.fetchExpansions();
    final orderRequest = Future<Map<String, int>>.sync(_loadCatalogOrder)
        .catchError((_) => <String, int>{});
    var expansions = _latest?.expansions ?? <MarketplaceExpansion>[];
    var topSellers = _latest?.topSellers ?? <MarketplaceCardPreview>[];
    var newArrivalSets = <String>[];
    var order = <String, int>{};
    var expansionsLoading = true, topSellersLoading = true;
    var expansionsUnavailable = false, topSellersUnavailable = false;
    var expansionsFromCache =
        _latest != null && !_latest!.expansionsUnavailable;
    var topSellersFromCache =
        _latest != null && !_latest!.topSellersUnavailable;
    var refreshFailed = false;
    MarketplaceHomeData snapshot() => MarketplaceHomeData(
        expansions: expansionsFromCache
            ? expansions
            : MarketplaceHomeSelectionService.recentExpansions(expansions,
                catalogOrder: order, newArrivalSets: newArrivalSets),
        topSellers: topSellers,
        expansionsLoading: expansionsLoading,
        topSellersLoading: topSellersLoading,
        expansionsUnavailable: expansionsUnavailable,
        topSellersUnavailable: topSellersUnavailable,
        expansionsFromCache: expansionsFromCache,
        topSellersFromCache: topSellersFromCache,
        refreshFailed: refreshFailed);
    void publish() {
      _latest = snapshot();
      for (final listener in _progressListeners.toList()) {
        listener(_latest!);
      }
      // save serializza e gestisce gli errori; il disco non blocca UI o retry.
      _diskCache.save(_provider.apiBase.toString(), _latest!);
    }

    // Ogni sezione viene pubblicata appena pronta, senza aspettare l'altra.
    Future<void> loadHome() async {
      final home = await homeRequest;
      if (home == null && topSellersFromCache) {
        topSellersLoading = false;
        refreshFailed = true;
        publish();
        return;
      }
      topSellers = MarketplaceHomeSelectionService.cardsForRankedIds(
          home?.cards ?? const [], home?.bestSellerIds ?? const []);
      newArrivalSets = MarketplaceHomeSelectionService.cardsForRankedIds(
              home?.cards ?? const [], home?.newArrivalIds ?? const [])
          .map((card) => card.expansion)
          .toList(growable: false);
      topSellersLoading = false;
      topSellersUnavailable = home == null;
      topSellersFromCache = false;
      refreshFailed = refreshFailed || home == null;
      publish();
    }

    Future<void> loadExpansions() async {
      final payload = await expansionsRequest;
      order = await orderRequest;
      if (payload == null && expansionsFromCache) {
        expansionsLoading = false;
        refreshFailed = true;
        publish();
        return;
      }
      expansions = payload ?? <MarketplaceExpansion>[];
      expansionsLoading = false;
      expansionsUnavailable = payload == null;
      expansionsFromCache = false;
      refreshFailed = refreshFailed || payload == null;
      publish();
    }

    _latest = snapshot();
    if (_latest!.fromCache) {
      for (final listener in _progressListeners.toList()) {
        listener(_latest!);
      }
    }
    await Future.wait([loadHome(), loadExpansions()]);
    final data = _latest!;
    if (!data.expansionsUnavailable &&
        !data.topSellersUnavailable &&
        !data.refreshFailed &&
        !data.fromCache) {
      _cached = data;
      _cachedAt = DateTime.now();
    }
    return data;
  }

  Future<void> _restoreCache() async {
    _restoredCache = true;
    try {
      _latest ??= await _diskCache
          .read(_provider.apiBase.toString())
          .timeout(const Duration(milliseconds: 280));
    } catch (_) {
      // La rete resta disponibile anche se il disco è lento/non accessibile.
    }
  }

  void dispose() {
    _progressListeners.clear();
    _provider.dispose();
  }
}
