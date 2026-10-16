import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin_suggest/pokoin_suggest.dart' show ArtistQuery;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pokoin/rebuild/presentation/marketplace/component/espansioni.dart';
import 'package:pokoin/rebuild/presentation/marketplace/component/marketplace_discovery.dart';
import 'package:pokoin/rebuild/presentation/marketplace/component/top_sellers.dart';
import 'package:pokoin/rebuild/controller/marketplace_controller.dart';
import 'package:pokoin/rebuild/main_mobile_prototype.dart';
import 'package:pokoin/rebuild/service/marketplace_home_service.dart';
import 'package:pokoin/rebuild/cache/marketplace_home_cache.dart';
import 'package:pokoin/rebuild/provider/cache_file_provider.dart';
import 'package:pokoin/rebuild/model/marketplace_home.dart';
import 'package:pokoin/rebuild/model/marketplace_suggestions.dart';
import 'package:pokoin/rebuild/service/marketplace_suggestion_service.dart';

import 'marketplace_home_service_test.dart' as fixtures;
import 'fixtures/account_fixtures.dart';

class _MemoryCacheStorage extends CacheFileProvider {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String contents) async => value = contents;
}

class _NoSuggestions extends MarketplaceSuggestionService {
  @override
  Future<ArtistQuery?> resolveArtist(String query) async => null;
  @override
  Future<void> warmUp() async {}
  @override
  Future<List<LocalSuggestion>> suggest(String query) async => const [];
}

void main() {
  testWidgets('manual startup sends no GET until discovery is requested',
      (tester) async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response('{}', 503);
    });
    addTearDown(client.close);
    final service = MarketplaceHomeService(
        client: client,
        cache: MarketplaceHomeCache(storage: _MemoryCacheStorage()),
        loadCatalogOrder: () async => {});
    await tester.pumpWidget(MobileMarketplacePrototypeApp(
        homeService: service,
        autoLoadDiscovery: false,
        accountService: guestAccountService()));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    expect(requests, 0);
    final load = find.text('Carica espansioni e più vendute');
    expect(load, findsOneWidget);
    await tester.ensureVisible(load);
    await tester.tap(load);
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(find.text('Riprova'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'saved rails remain visible through offline startup and show retry',
      (tester) async {
    final cache = MarketplaceHomeCache(storage: _MemoryCacheStorage());
    await cache.save(
        'https://api.pokoin.com',
        MarketplaceHomeData(expansions: const [
          MarketplaceExpansion(
              name: 'Espansione salvata', slug: 'saved', cardCount: 100)
        ], topSellers: const [
          MarketplaceCardPreview(
              id: '24', name: 'Carta salvata', expansion: 'Set')
        ]));
    final home = Completer<http.Response>();
    final sets = Completer<http.Response>();
    final client = MockClient((request) =>
        request.url.path.contains('expansion') ? sets.future : home.future);
    addTearDown(client.close);
    final service = MarketplaceHomeService(
        client: client, cache: cache, loadCatalogOrder: () async => {});
    final controller = MarketplaceController(homeService: service);
    addTearDown(controller.dispose);
    final pending = controller.loadDiscovery(forceRefresh: true);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: ValueListenableBuilder(
                    valueListenable: controller.discovery,
                    builder: (context, state, _) => MarketplaceDiscovery(
                        state: state,
                        onRetry: controller.retryDiscovery,
                        onExpansionSelected: (_) {},
                        onCardSelected: (_) {}))))));
    await tester.pump();
    expect(find.text('Espansione salvata'), findsOneWidget);
    expect(find.text('Carta salvata'), findsOneWidget);
    expect(find.text('Contenuti salvati · aggiornamento in corso'),
        findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    home.complete(http.Response('{}', 503));
    sets.complete(http.Response('{}', 503));
    await pending;
    await tester.pumpAndSettle();
    expect(find.text('Carta salvata'), findsOneWidget);
    expect(find.text('Contenuti salvati · aggiornamento non riuscito'),
        findsOneWidget);
    expect(find.text('Riprova'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final homeFirst in [false, true]) {
    testWidgets(
        'shows the ready rail while ${homeFirst ? 'expansions' : 'home'} waits',
        (tester) async {
      final home = Completer<http.Response>();
      final expansions = Completer<http.Response>();
      final client = MockClient((request) =>
          request.url.path.contains('expansion')
              ? expansions.future
              : home.future);
      addTearDown(client.close);
      final service = MarketplaceHomeService(
          client: client,
          cache: MarketplaceHomeCache(storage: _MemoryCacheStorage()),
          loadCatalogOrder: () async => {});
      final controller = MarketplaceController(homeService: service);
      addTearDown(controller.dispose);
      final pending = controller.loadDiscovery();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
        child: ValueListenableBuilder(
            valueListenable: controller.discovery,
            builder: (context, state, _) => MarketplaceDiscovery(
                state: state,
                onRetry: controller.retryDiscovery,
                onExpansionSelected: (_) {},
                onCardSelected: (_) {})),
      ))));
      if (homeFirst) {
        home.complete(fixtures.jsonResponse(fixtures.homePayload));
      } else {
        expansions.complete(fixtures.jsonResponse(fixtures.expansionsPayload));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      final sets = tester.widget<Espansioni>(find.byType(Espansioni));
      final sellers = tester.widget<TopSellers>(find.byType(TopSellers));
      expect(sets.isLoading, homeFirst);
      expect(sellers.isLoading, !homeFirst);
      expect(homeFirst ? sellers.cards.length : sets.expansions.length, 2);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      if (homeFirst) {
        expansions.complete(fixtures.jsonResponse(fixtures.expansionsPayload));
      } else {
        home.complete(fixtures.jsonResponse(fixtures.homePayload));
      }
      await pending;
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('real discovery survives filters and navigation without new GETs',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return fixtures.jsonResponse(request.url.path.contains('expansion')
          ? fixtures.expansionsPayload
          : fixtures.homePayload);
    });
    addTearDown(client.close);
    final service = MarketplaceHomeService(
        client: client,
        cache: MarketplaceHomeCache(storage: _MemoryCacheStorage()),
        loadCatalogOrder: () async => {});
    final suggestions = _NoSuggestions();
    addTearDown(suggestions.dispose);
    await tester.pumpWidget(MobileMarketplacePrototypeApp(
        homeService: service,
        suggestionService: suggestions,
        accountService: guestAccountService()));
    await tester.pumpAndSettle();
    expect(find.byType(Espansioni), findsOneWidget);
    expect(find.byType(TopSellers), findsOneWidget);
    expect(tester.widget<TopSellers>(find.byType(TopSellers)).cards.first.id,
        '24');
    expect(requests, 2);
    await tester.ensureVisible(find.text('Set nuovo').first);
    await tester.tap(find.text('Set nuovo').first);
    await tester.pumpAndSettle();
    expect(find.text('120 carte nel catalogo'), findsOneWidget);
    await tester.tap(find.text('Chiudi'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Pikachu');
    await tester.pumpAndSettle();
    expect(find.byType(Espansioni), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.byType(Espansioni), findsOneWidget);
    expect(requests, 2);
    await tester.tap(find.text('Profilo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wallet'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Market'));
    await tester.pumpAndSettle();
    expect(find.byType(Espansioni), findsOneWidget);
    expect(requests, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('section retry recovers without hiding the successful section',
      (tester) async {
    var fail = true;
    final client = MockClient((request) async {
      if (!request.url.path.contains('expansion')) {
        return fixtures.jsonResponse(fixtures.homePayload);
      }
      return fail
          ? http.Response('{}', 503)
          : fixtures.jsonResponse(fixtures.expansionsPayload);
    });
    addTearDown(client.close);
    final service = MarketplaceHomeService(
        client: client,
        cache: MarketplaceHomeCache(storage: _MemoryCacheStorage()),
        loadCatalogOrder: () async => {});
    final controller = MarketplaceController(homeService: service);
    addTearDown(controller.dispose);
    controller.loadDiscovery();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
      child: ValueListenableBuilder(
        valueListenable: controller.discovery,
        builder: (context, state, _) => MarketplaceDiscovery(
          state: state,
          onRetry: controller.retryDiscovery,
          onExpansionSelected: (_) {},
          onCardSelected: (_) {},
        ),
      ),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Riprova'), findsOneWidget);
    expect(find.text('Carta economica'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('Riprova'), findsNothing);
    expect(find.text('Set nuovo').first, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile sliders remain lazy and fit enlarged text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final home = {
      'cards': List.generate(
          12,
          (index) => {
                'id': '$index',
                'name': 'Carta $index con un nome molto lungo',
                'set': 'Espansione lunga',
                'price': 1
              }),
      'sections': {'bestSellerIds': List.generate(12, (index) => '$index')},
    };
    final client = MockClient((request) async => fixtures.jsonResponse(
        request.url.path.contains('expansion')
            ? fixtures.expansionsPayload
            : home));
    addTearDown(client.close);
    final service = MarketplaceHomeService(
        client: client,
        cache: MarketplaceHomeCache(storage: _MemoryCacheStorage()),
        loadCatalogOrder: () async => {});
    final controller = MarketplaceController(homeService: service);
    addTearDown(controller.dispose);
    controller.loadDiscovery();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
      child: Padding(
          padding: const EdgeInsets.all(20),
          child: ValueListenableBuilder(
            valueListenable: controller.discovery,
            builder: (context, state, _) => MarketplaceDiscovery(
              state: state,
              onRetry: controller.retryDiscovery,
              onExpansionSelected: (_) {},
              onCardSelected: (_) {},
            ),
          )),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Carta 11 con un nome molto lungo'), findsNothing);
    await tester.ensureVisible(find.text('Articoli più venduti'));
    await tester.pumpAndSettle();
    final sellersList = find.descendant(
        of: find.byType(TopSellers), matching: find.byType(ListView));
    await tester.drag(sellersList, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
