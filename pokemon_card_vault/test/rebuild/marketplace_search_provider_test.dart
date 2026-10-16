import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pokoin/rebuild/model/marketplace_search.dart';
import 'package:pokoin/rebuild/provider/marketplace_search_provider.dart';
import 'package:pokoin/rebuild/service/marketplace_search_service.dart';

void main() {
  test('encodes query and filters, preserves canonical IDs and nullable totals',
      () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/marketplace-search-page');
      expect(request.url.queryParameters, {
        'query': 'Pikachu & 025/165',
        'offset': '24',
        'limit': '24',
        'includeFacets': '0',
        'search_language': 'en',
        'print_language': 'japanese',
        'productType': 'card',
      });
      return http.Response(
          jsonEncode({
            'cards': [
              {
                'id': '632778',
                'name': 'Pikachu',
                'set': '151',
                'number': '025/165',
                'price': 12.5,
                'tileImageUrl': '/card-images/pikachu.jpg'
              },
            ],
            'hasMore': true,
            'total': null
          }),
          200);
    });
    final provider = MarketplaceSearchProvider(
        client: client, apiBase: Uri.parse('https://example.test'));
    final service = MarketplaceSearchService(provider: provider);
    addTearDown(client.close);
    addTearDown(provider.dispose);
    addTearDown(service.dispose);
    final page = await service.search(const MarketplaceSearchRequest(
        query: '  Pikachu & 025/165  ',
        offset: 24,
        productType: 'card',
        printLanguage: 'japanese'));
    expect(page.cards.single.id, '632778');
    expect(page.cards.single.pricePkn, 12.5);
    expect(page.cards.single.imageUrl, '/card-images/pikachu.jpg');
    expect(page.total, isNull);
    expect(page.hasMore, isTrue);
    expect(() => page.cards.clear(), throwsUnsupportedError);
  });

  test('valid empty search is distinct from malformed or unavailable data',
      () async {
    for (final body in [
      {'cards': [], 'hasMore': false, 'total': 0},
      {'cards': [], 'total': 20},
      {
        'cards': [
          {'id': 'demo-1', 'name': 'Demo'}
        ],
        'hasMore': false
      },
      {'error': 'Unavailable'},
    ]) {
      final client =
          MockClient((_) async => http.Response(jsonEncode(body), 200));
      final provider = MarketplaceSearchProvider(client: client);
      try {
        final pending =
            provider.fetch(const MarketplaceSearchRequest(query: 'Pikachu'));
        if (body['total'] == 0) {
          final page = await pending;
          expect(page.cards, isEmpty);
          expect(page.total, 0);
        } else {
          await expectLater(pending, throwsFormatException);
        }
      } finally {
        provider.dispose();
        client.close();
      }
    }
  });

  test(
      'server errors do not become empty results or fallback GETs',
      () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('{}', 503);
    });
    final provider = MarketplaceSearchProvider(client: client);
    addTearDown(client.close);
    addTearDown(provider.dispose);
    await expectLater(
        provider.fetch(const MarketplaceSearchRequest(query: 'Pikachu')),
        throwsStateError);
    expect(calls, 1);
  });
}
