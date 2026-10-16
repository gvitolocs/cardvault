import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pokoin/rebuild/provider/marketplace_home_provider.dart';

import 'marketplace_home_service_test.dart' as fixtures;

class _TrackingClient extends MockClient {
  _TrackingClient() : super((_) async => http.Response(jsonEncode({}), 200));
  bool wasClosed = false;

  @override
  void close() {
    wasClosed = true;
    super.close();
  }
}

void main() {
  test('home provider filters previews but preserves backend ranking metadata',
      () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return fixtures.jsonResponse({
        ...fixtures.homePayload,
        'sections': {
          'bestSellerIds': [' 48 ', '', 24, 'missing', '48'],
          'newArrivalIds': ['24'],
        },
      });
    });
    final provider = MarketplaceHomeProvider(
        client: client, apiBase: Uri.parse('https://example.test'));
    addTearDown(provider.dispose);
    addTearDown(client.close);

    final payload = (await provider.fetchHome())!;
    expect(requests,
        [Uri.parse('https://example.test/api/marketplace-home-page?limit=48')]);
    expect(payload.cards.map((card) => card.id), ['24', '48']);
    expect(payload.cards.first.name, 'Carta economica');
    expect(payload.cards.first.pricePkn, 12.5);
    expect(payload.bestSellerIds, ['48', '24', 'missing', '48']);
    expect(payload.newArrivalIds, ['24']);
    expect(() => payload.bestSellerIds.clear(), throwsUnsupportedError);
  });

  test('expansion provider leaves selection to the service', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/marketplace-expansion-page');
      expect(request.url.queryParameters['limit'], '1000');
      return fixtures.jsonResponse(fixtures.expansionsPayload);
    });
    final provider = MarketplaceHomeProvider(client: client);
    addTearDown(provider.dispose);
    addTearDown(client.close);

    final expansions = (await provider.fetchExpansions())!;
    expect(expansions.map((set) => set.slug),
        ['storico', 'nuovo', 'duplicato', 'vuoto']);
    expect(expansions.last.cardCount, 0);
  });

  test(
      'missing sections trigger compatibility fallback, valid empty data does not',
      () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return fixtures.jsonResponse(
          calls == 1 ? {'cards': []} : {'cards': [], 'sections': {}});
    });
    final provider = MarketplaceHomeProvider(client: client);
    addTearDown(provider.dispose);
    addTearDown(client.close);

    final payload = (await provider.fetchHome())!;
    expect(payload.cards, isEmpty);
    expect(payload.bestSellerIds, isEmpty);
    expect(payload.newArrivalIds, isEmpty);
    expect(calls, 2);
    expect(await provider.fetchHome(), isNotNull);
    expect(calls, 3);
  });

  test('disposing a provider keeps an injected client usable', () async {
    final client = _TrackingClient();
    addTearDown(client.close);
    final provider = MarketplaceHomeProvider(client: client);
    provider.dispose();
    expect(client.wasClosed, isFalse);
    expect(
        (await client.get(Uri.parse('https://example.test'))).statusCode, 200);
  });
}
