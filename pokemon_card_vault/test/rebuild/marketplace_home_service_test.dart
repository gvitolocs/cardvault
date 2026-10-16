import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pokoin/rebuild/model/marketplace_home.dart';
import 'package:pokoin/rebuild/service/marketplace_home_service.dart';

const homePayload = {
  'cards': [
    {'id': '24', 'name': 'Carta economica', 'set': 'Set nuovo', 'price': 12.5},
    {'id': '48', 'name': 'Carta costosa', 'set': 'Set storico', 'price': 999},
    {'id': '96', 'name': 'Fuori classifica', 'set': 'Altro', 'price': 3000},
  ],
  'sections': {
    'bestSellerIds': ['24', 'missing', '24', '48'],
    'newArrivalIds': ['24'],
  },
};
const expansionsPayload = {
  'expansions': [
    {'name': 'Set storico', 'slug': 'storico', 'cardCount': 70},
    {'name': 'Set nuovo', 'slug': 'nuovo', 'cardCount': 120},
    {'name': ' set nuovo ', 'slug': 'duplicato', 'cardCount': 20},
    {'name': 'Vuoto', 'slug': 'vuoto', 'cardCount': 0},
  ],
};

http.Response jsonResponse(Object payload) =>
    http.Response(jsonEncode(payload), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  for (final status in [401, 403, 429, 503, 530]) {
    test('HTTP $status stops home fallback on the same host', () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        return request.url.path.contains('expansion')
            ? jsonResponse(expansionsPayload)
            : http.Response('{}', status);
      });
      addTearDown(client.close);
      final service = MarketplaceHomeService(
          client: client, loadCatalogOrder: () async => {});
      final result = await service.load();
      expect(paths.where((path) => path.contains('home')),
          ['/api/marketplace-home-page']);
      expect(result.topSellersUnavailable, isTrue);
      expect(result.expansions, hasLength(2));
    });
  }
  for (final homeFirst in [false, true]) {
    test(
        '${homeFirst ? 'top sellers' : 'expansions'} publish before slower rail',
        () async {
      final home = Completer<http.Response>();
      final expansions = Completer<http.Response>();
      final client = MockClient((request) =>
          request.url.path.contains('expansion')
              ? expansions.future
              : home.future);
      addTearDown(client.close);
      final service = MarketplaceHomeService(
          client: client, loadCatalogOrder: () async => {});
      final first = Completer<MarketplaceHomeData>();
      final progress = <MarketplaceHomeData>[];
      final pending = service.load(onProgress: (data) {
        progress.add(data);
        if (!first.isCompleted) first.complete(data);
      });
      if (homeFirst) {
        home.complete(jsonResponse(homePayload));
      } else {
        expansions.complete(jsonResponse(expansionsPayload));
      }
      final partial = await first.future;
      expect(partial.expansionsLoading, homeFirst);
      expect(partial.topSellersLoading, !homeFirst);
      expect(
          homeFirst ? partial.topSellers.length : partial.expansions.length, 2);
      expect(homeFirst ? expansions.isCompleted : home.isCompleted, isFalse);
      final joined = <MarketplaceHomeData>[];
      expect(service.load(onProgress: joined.add), same(pending));
      expect(joined.single, same(partial));
      if (homeFirst) {
        expansions.complete(jsonResponse(expansionsPayload));
      } else {
        home.complete(jsonResponse(homePayload));
      }
      final data = await pending;
      expect(data.expansionsLoading, isFalse);
      expect(data.topSellersLoading, isFalse);
      expect(data.expansions.first.name, 'Set nuovo');
      expect(progress.last, same(data));
      expect(joined.last, same(data));
      final afterCompletion = <MarketplaceHomeData>[];
      await service.load(onProgress: afterCompletion.add);
      expect(afterCompletion, isEmpty);
    });
  }

  test('home timeout does not spend a second timeout on legacy fallback',
      () async {
    final paths = <String>[];
    final blockedHome = Completer<http.Response>();
    final client = MockClient((request) {
      paths.add(request.url.path);
      return request.url.path.contains('expansion')
          ? Future.value(jsonResponse(expansionsPayload))
          : blockedHome.future;
    });
    addTearDown(client.close);
    final service = MarketplaceHomeService(
        client: client,
        timeout: const Duration(milliseconds: 40),
        loadCatalogOrder: () async => {});
    final progress = <MarketplaceHomeData>[];
    final result = await service.load(onProgress: progress.add);
    expect(paths,
        ['/api/marketplace-home-page', '/api/marketplace-expansion-page']);
    expect(progress.first.expansions, hasLength(2));
    expect(progress.first.topSellersLoading, isTrue);
    expect(result.topSellersUnavailable, isTrue);
    expect(result.expansionsUnavailable, isFalse);
    blockedHome.complete(jsonResponse(homePayload));
  });

  test('loads only discovery endpoints, preserving ranking and canonical units',
      () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      return jsonResponse(request.url.path.contains('expansion')
          ? expansionsPayload
          : homePayload);
    });
    addTearDown(client.close);
    final service = MarketplaceHomeService(
        client: client,
        loadCatalogOrder: () async => {'Set storico': 999, 'Set nuovo': 1});
    final data = await service.load();
    expect(paths,
        ['/api/marketplace-home-page', '/api/marketplace-expansion-page']);
    expect(data.topSellers.map((card) => card.id), ['24', '48']);
    expect(data.topSellers.first.pricePkn, 12.5);
    expect(
        data.expansions.map((set) => set.name), ['Set nuovo', 'Set storico']);
    expect(data.expansionsUnavailable, isFalse);
    expect(data.topSellersUnavailable, isFalse);
    expect(() => data.topSellers.clear(), throwsUnsupportedError);
  });

  test('deduplicates in-flight requests and caches successful responses',
      () async {
    final home = Completer<http.Response>();
    var calls = 0;
    final client = MockClient((request) {
      calls++;
      return request.url.path.contains('expansion')
          ? Future.value(jsonResponse(expansionsPayload))
          : home.future;
    });
    addTearDown(client.close);
    final service = MarketplaceHomeService(
        client: client, loadCatalogOrder: () async => {});
    final first = service.load();
    final second = service.load();
    expect(identical(first, second), isTrue);
    home.complete(jsonResponse(homePayload));
    final data = await first;
    expect(calls, 2);
    expect(identical(await service.load(), data), isTrue);
    expect(calls, 2);
    await service.load(forceRefresh: true);
    expect(calls, 4);
  });

  test('legacy home fallback handles malformed preferred responses', () async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path.endsWith('home-page')) {
        return http.Response('<html>', 200);
      }
      return jsonResponse(request.url.path.contains('expansion')
          ? expansionsPayload
          : homePayload);
    });
    addTearDown(client.close);
    final service = MarketplaceHomeService(
        client: client, loadCatalogOrder: () async => {});
    final data = await service.load();
    expect(paths.where((path) => path.contains('home')),
        ['/api/marketplace-home-page', '/api/marketplace-home']);
    expect(data.topSellers.map((card) => card.id), ['24', '48']);
  });

  test('expansion failure keeps working top sellers and remains retryable',
      () async {
    var failing = true;
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (!request.url.path.contains('expansion')) {
        return jsonResponse(homePayload);
      }
      return failing
          ? http.Response('{}', 503)
          : jsonResponse(expansionsPayload);
    });
    addTearDown(client.close);
    final service = MarketplaceHomeService(
        client: client, loadCatalogOrder: () async => {});
    final data = await service.load();
    expect(data.expansionsUnavailable, isTrue);
    expect(data.topSellersUnavailable, isFalse);
    expect(data.topSellers, hasLength(2));
    failing = false;
    expect((await service.load()).expansions, hasLength(2));
    expect(calls, 4);
  });

  test('home failure never fabricates a best-seller ranking', () async {
    final client = MockClient((request) async =>
        request.url.path.contains('expansion')
            ? jsonResponse(expansionsPayload)
            : http.Response('{}', 503));
    addTearDown(client.close);
    final service = MarketplaceHomeService(
        client: client,
        loadCatalogOrder: () => throw StateError('Missing registry'));
    final data = await service.load();
    expect(data.topSellers, isEmpty);
    expect(data.topSellersUnavailable, isTrue);
    expect(data.expansions, hasLength(2));
    expect(data.expansionsUnavailable, isFalse);
  });

  test('empty backend ranking remains empty even with expensive cards',
      () async {
    final client = MockClient(
        (request) async => jsonResponse(request.url.path.contains('expansion')
            ? expansionsPayload
            : {
                ...homePayload,
                'sections': {'bestSellerIds': [], 'newArrivalIds': []}
              }));
    addTearDown(client.close);
    final service = MarketplaceHomeService(
        client: client, loadCatalogOrder: () async => {});
    final data = await service.load();
    expect(data.topSellers, isEmpty);
    expect(data.topSellersUnavailable, isFalse);
  });
}
