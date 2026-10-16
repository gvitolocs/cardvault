import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pokoin_suggest/pokoin_suggest.dart';
import 'package:pokoin/rebuild/cache/marketplace_search_cache.dart';
import 'package:pokoin/rebuild/controller/marketplace_search_controller.dart';
import 'package:pokoin/rebuild/model/marketplace_search.dart';
import 'package:pokoin/rebuild/model/marketplace_artist_catalog.dart';
import 'package:pokoin/rebuild/provider/marketplace_artist_provider.dart';
import 'package:pokoin/rebuild/provider/marketplace_search_provider.dart';
import 'package:pokoin/rebuild/service/marketplace_search_service.dart';
import 'package:pokoin/rebuild/service/marketplace_suggestion_service.dart';
import 'package:pokoin/rebuild/presentation/marketplace/component/marketplace_search.dart';
import 'package:pokoin/rebuild/presentation/marketplace/atomics/suggestion_card_tile.dart';

const artist = ArtistQuery(
    slug: 'tomokazu-komiya',
    display: 'Tomokazu Komiya',
    remainingQuery: 'Pikachu');

Map<String, dynamic> artistPayload() => {
      'artist': {'slug': 'tomokazu-komiya', 'cardCount': 4},
      'cards': [
        for (final entry in [
          ('24', 'Pikachu', 'western'),
          ('48', 'Pikachu', 'japanese'),
          ('72', 'Pikachu', 'korean'),
          ('96', 'Mew', 'western')
        ])
          {
            'card_id': entry.$1,
            'name': entry.$2,
            'expansion_name': '151',
            'expansion_number': '025/165',
            'artist': 'Tomokazu Komiya',
            'nationality': entry.$3,
            'product_type': 'card',
            'homepage_image_url': '/card-images/${entry.$1}_homepage.webp'
          },
      ],
    };

class _ControlledArtistProvider extends MarketplaceArtistProvider {
  final pending = <Completer<MarketplaceArtistCatalog>>[];
  @override
  Future<MarketplaceArtistCatalog> fetch(String slug) {
    final reply = Completer<MarketplaceArtistCatalog>();
    pending.add(reply);
    return reply.future;
  }

  @override
  void cancelPending() {
    for (final reply in pending) {
      if (!reply.isCompleted) reply.completeError(StateError('Aborted'));
    }
  }
}

void main() {
  test('a new query cannot join an aborted artist download', () async {
    final provider = _ControlledArtistProvider();
    final service = MarketplaceSearchService(artistProvider: provider);
    addTearDown(provider.dispose);
    addTearDown(service.dispose);
    const request =
        MarketplaceSearchRequest(query: 'Pikachu Komi', artist: artist);
    final old = service.search(request);
    final oldCheck = expectLater(old, throwsStateError);
    service.cancelPending();
    final fresh = service.search(request);
    expect(provider.pending, hasLength(2));
    provider.pending.last.complete(MarketplaceArtistCatalog(const []));
    expect((await fresh).cards, isEmpty);
    await oldCheck;
  });
  testWidgets('bundled worker routes Pikachu Komi to real artist versions',
      (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.path, '/api/marketplace-artist-cards');
      final data = artistPayload();
      for (final row in data['cards'] as List) {
        row['homepage_image_url'] = '';
      }
      return http.Response(jsonEncode(data), 200);
    });
    final provider = MarketplaceArtistProvider(client: client);
    final service = MarketplaceSearchService(artistProvider: provider);
    final local = MarketplaceSuggestionService();
    final controller =
        MarketplaceSearchController(service: service, suggestionService: local);
    addTearDown(client.close);
    addTearDown(provider.dispose);
    addTearDown(service.dispose);
    addTearDown(local.dispose);
    addTearDown(controller.dispose);
    String? opened;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MarketplaceSearch(
                controller: controller,
                discovery: const SizedBox.shrink(),
                onOpen: (card) => opened = card.id))));
    await tester.enterText(find.byType(TextField), 'Pikachu Komi');
    await tester.pump(const Duration(milliseconds: 300));
    for (var i = 0; i < 150 && controller.state.isLoading; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(controller.state.hasError, isFalse);
    expect(controller.state.cards.map((card) => card.id), ['24', '48', '72']);
    expect(calls, 1);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SuggestionCardTile).first);
    await tester.pumpAndSettle();
    expect(opened, '24');
    expect(calls, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test('artist API is intersected with name and print filters and reused',
      () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.path, '/api/marketplace-artist-cards');
      expect(request.url.queryParameters['artistSlug'], artist.slug);
      return http.Response(jsonEncode(artistPayload()), 200);
    });
    final provider = MarketplaceArtistProvider(client: client);
    final service = MarketplaceSearchService(artistProvider: provider);
    addTearDown(client.close);
    addTearDown(provider.dispose);
    addTearDown(service.dispose);
    final page = await service.search(const MarketplaceSearchRequest(
        query: 'Pikachu Komi', artist: artist, limit: 1));
    expect(page.cards.single.id, '24');
    expect(page.cards.single.number, '025/165');
    expect(page.total, 3);
    expect(page.hasMore, isTrue);
    final next = await service.search(const MarketplaceSearchRequest(
        query: 'Pikachu Komi', artist: artist, limit: 1, offset: 1));
    expect(next.cards.single.id, '48');
    final jp = await service.search(const MarketplaceSearchRequest(
        query: 'Pikachu Komi',
        artist: artist,
        printLanguage: 'japanese',
        productType: 'card'));
    expect(jp.cards.map((card) => card.id), ['48', '72']);
    expect(jp.total, 2);
    final boxes = await service.search(const MarketplaceSearchRequest(
        query: 'Pikachu Komi', artist: artist, productType: 'booster_box'));
    expect(boxes.cards, isEmpty);
    expect(boxes.total, 0);
    expect(calls, 1);
  });

  test(
      'incomplete artist catalogs fail instead of returning a false empty page',
      () async {
    final payload = artistPayload();
    payload['artist']['cardCount'] = 6000;
    final client =
        MockClient((_) async => http.Response(jsonEncode(payload), 200));
    final provider = MarketplaceArtistProvider(client: client);
    final service = MarketplaceSearchService(artistProvider: provider);
    addTearDown(client.close);
    addTearDown(provider.dispose);
    addTearDown(service.dispose);
    await expectLater(
        service.search(const MarketplaceSearchRequest(
            query: 'Pikachu Komi', artist: artist)),
        throwsFormatException);
    expect(
        service.cached(const MarketplaceSearchRequest(query: 'Pikachu Komi')),
        isNull);
  });

  testWidgets(
      'repeated queries reuse fresh pages immediately; submit refreshes',
      (tester) async {
    var calls = 0;
    var clock = DateTime(2026, 10, 15);
    final cache = MarketplaceSearchCache(now: () => clock);
    final client = MockClient((_) async {
      calls++;
      return http.Response(
          jsonEncode({
            'cards': [
              {'id': '24', 'name': 'Pikachu', 'set': '151'}
            ],
            'hasMore': false,
            'total': 1
          }),
          200);
    });
    final provider = MarketplaceSearchProvider(client: client);
    final service = MarketplaceSearchService(provider: provider, cache: cache);
    final controller = MarketplaceSearchController(service: service);
    addTearDown(client.close);
    addTearDown(provider.dispose);
    addTearDown(service.dispose);
    addTearDown(controller.dispose);
    controller.setQuery('Pikachu');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(controller.state.cards.single.id, '24');
    expect(calls, 1);
    controller.setQuery('');
    controller.setQuery('Pikachu');
    expect(controller.state.cards.single.id, '24');
    expect(controller.state.isLoading, isFalse);
    expect(calls, 1);
    await controller.submit();
    expect(calls, 2, reason: 'An explicit submit/retry always refreshes');
    expect(
        service.cached(const MarketplaceSearchRequest(
            query: 'Pikachu', printLanguage: 'japanese')),
        isNull);
    clock = clock.add(const Duration(seconds: 31));
    controller.setQuery('');
    controller.setQuery('Pikachu');
    expect(controller.state.cards, isEmpty);
    expect(controller.state.isLoading, isTrue);
    controller.setQuery('');
  });
}
