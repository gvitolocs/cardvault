import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/rebuild/controller/marketplace_controller.dart';
import 'package:pokoin/rebuild/model/demo_catalog.dart';
import 'package:pokoin/rebuild/model/marketplace_home.dart';
import 'package:pokoin/rebuild/service/cart_service.dart';
import 'package:pokoin/rebuild/service/marketplace_home_service.dart';

final _home = MarketplaceHomeData(expansions: [], topSellers: []);

class _HomeService extends MarketplaceHomeService {
  final requests = <bool>[];
  final responses = <Completer<MarketplaceHomeData>>[];
  bool disposed = false;

  @override
  Future<MarketplaceHomeData> load(
      {bool forceRefresh = false, MarketplaceHomeProgress? onProgress}) {
    requests.add(forceRefresh);
    final response = Completer<MarketplaceHomeData>();
    responses.add(response);
    return response.future;
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  test(
      'combines case-insensitive search and expansion without losing favorites',
      () {
    final controller = MarketplaceController();
    addTearDown(controller.dispose);
    controller.setSearchQuery('  EX  ');
    controller.selectExpansion('151');
    expect(
        controller.visibleCards.map((card) => card.id), ['demo-2', 'demo-4']);
    controller.toggleFavorite(demoCards.first);
    controller.selectTab(2);
    controller.selectTab(0);
    expect(controller.isFavorite('demo-1'), isTrue);
    controller.setSearchQuery('205/165');
    expect(controller.visibleCards.single.id, 'demo-4');
    controller.setSearchQuery('');
    controller.selectExpansion(null);
    expect(controller.isFiltered, isFalse);
    expect(controller.visibleCards, hasLength(4));
    controller.toggleFavorite(demoCards.first);
    expect(controller.isFavorite('demo-1'), isFalse);
  });

  test('cart notifications remain separate from screen and discovery state',
      () {
    final cart = CartService();
    final controller = MarketplaceController(cartService: cart);
    addTearDown(cart.dispose);
    addTearDown(controller.dispose);
    var screenChanges = 0;
    var discoveryChanges = 0;
    var cartChanges = 0;
    controller.addListener(() => screenChanges++);
    controller.discovery.addListener(() => discoveryChanges++);
    controller.cart.addListener(() => cartChanges++);
    controller.cart.addCard(demoCards.first);
    controller.cart.addCard(demoCards.first);
    expect(controller.cart.itemCount, 2);
    expect(controller.cart.items.single.quantity, 2);
    expect(controller.cart.totalPrice, closeTo(49.8, 0.001));
    controller.cart.removeCard('demo-1');
    expect(controller.cart.itemCount, 0);
    expect(cartChanges, 3);
    expect(screenChanges, 0);
    expect(discoveryChanges, 0);
  });

  test('deduplicates pending loads and retains data during forced retry',
      () async {
    final service = _HomeService();
    final controller = MarketplaceController(homeService: service);
    addTearDown(service.dispose);
    addTearDown(controller.dispose);
    final first = controller.loadDiscovery();
    expect(controller.discovery.value.isLoading, isTrue);
    expect(controller.retryDiscovery(), same(first));
    service.responses.first.complete(_home);
    await first;
    expect(controller.discovery.value.data, same(_home));
    expect(controller.discovery.value.isLoading, isFalse);
    final retry = controller.retryDiscovery();
    expect(controller.discovery.value.data, same(_home));
    expect(controller.discovery.value.isLoading, isTrue);
    service.responses.last.complete(_home);
    await retry;
    expect(service.requests, [false, true]);
  });

  test('exposes failed loads and supports retry recovery', () async {
    final service = _HomeService();
    final controller = MarketplaceController(homeService: service);
    addTearDown(service.dispose);
    addTearDown(controller.dispose);
    final first = controller.loadDiscovery();
    service.responses.first.completeError(StateError('Unavailable'));
    await first;
    expect(controller.discovery.value.isLoading, isFalse);
    expect(controller.discovery.value.expansionsUnavailable, isTrue);
    expect(controller.discovery.value.topSellersUnavailable, isTrue);
    final retry = controller.retryDiscovery();
    service.responses.last.complete(_home);
    await retry;
    expect(controller.discovery.value.hasError, isFalse);
    expect(controller.discovery.value.data, same(_home));
  });

  for (final fails in [false, true]) {
    test('ignores late ${fails ? 'errors' : 'results'} after disposal',
        () async {
      final service = _HomeService();
      final cart = CartService();
      final controller =
          MarketplaceController(homeService: service, cartService: cart);
      addTearDown(service.dispose);
      addTearDown(cart.dispose);
      final pending = controller.loadDiscovery();
      controller.dispose();
      if (fails) {
        service.responses.first.completeError(StateError('Unavailable'));
      } else {
        service.responses.first.complete(_home);
      }
      await pending;
      expect(service.disposed, isFalse);
      cart.addCard(demoCards.first);
      expect(cart.itemCount, 1,
          reason: 'Injected services belong to the caller');
    });
  }
}
