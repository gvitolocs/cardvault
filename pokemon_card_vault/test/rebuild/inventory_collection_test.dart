import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pokoin/rebuild/controller/cardex_controller.dart';
import 'package:pokoin/rebuild/model/cardex.dart';
import 'package:pokoin/rebuild/model/inventory_listing.dart';
import 'package:pokoin/rebuild/presentation/cardex/cardex_screen.dart';
import 'package:pokoin/rebuild/presentation/portfolio/portfolio_screen.dart';
import 'package:pokoin/rebuild/provider/collection_provider.dart';
import 'package:pokoin/rebuild/provider/inventory_provider.dart';
import 'package:pokoin/rebuild/service/collection_service.dart';
import 'package:pokoin/rebuild/service/inventory_reconciliation_service.dart';
import 'package:pokoin/rebuild/presentation/cardex/atomics/album_card.dart';

Finder albumCardNamed(String name) => find.byWidgetPredicate(
    (widget) => widget is AlbumCard && widget.card.name == name);

Map<String, dynamic> listing(String id,
        {String uid = 'alice',
        String? cardId,
        int quantity = 1,
        String status = 'active',
        String source = '',
        String language = 'IT',
        String name = 'Carta'}) =>
    {
      'id': id, 'sellerUid': uid, 'cardId': cardId ?? id,
      'quantityAvailable': quantity, 'status': status, 'language': language,
      'sourceListingId': source, 'cardName': name,
      'setName': 'Plasma Freeze Promos', 'collectorNumber': '11/116',
      // Price is intentionally zero: ownership must not use purchase availability.
      'pricePkn': 0,
    };

OwnedCard holding(String id,
        {String cardId = 'a',
        int quantity = 1,
        String link = '',
        String source = '',
        String language = 'EN'}) =>
    OwnedCard.fromJson({
      'id': id,
      'cardId': cardId,
      'quantity': quantity,
      'listingId': link,
      'sourceListingId': source,
      'language': language
    });

http.Response reply(Object data, [int status = 200]) =>
    http.Response(jsonEncode(data), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

CollectionService service(http.Client client, Stream<String?> Function() users,
        {int pageSize = 1000}) =>
    CollectionService(
        provider: CollectionProvider(
            client: client, idToken: (uid) async => uid, userIds: users),
        inventory: InventoryProvider(
            client: client, idToken: (uid) async => uid, pageSize: pageSize));

void main() {
  test('owner inventory reads all 2731 rows with bearer and offset pagination',
      () async {
    final offsets = <int>[];
    final rows = List.generate(2731, (i) => listing('$i'));
    final client = MockClient((request) async {
      expect(request.url.host, 'api.pokoin.com');
      expect(request.url.path, '/api/marketplace-listings');
      expect(request.headers['Authorization'], 'Bearer token');
      expect(request.url.queryParameters['sellerUid'], 'alice');
      expect(request.url.queryParameters['nativeOnly'], '1');
      expect(request.url.queryParameters['limit'], '1000');
      expect(request.url.queryParameters.containsKey('status'), isFalse);
      final offset = int.parse(request.url.queryParameters['offset']!);
      offsets.add(offset);
      return reply({'listings': rows.skip(offset).take(1000).toList()});
    });
    addTearDown(client.close);
    final result =
        await InventoryProvider(client: client, idToken: (_) async => 'token')
            .fetchItems('alice');
    expect(offsets, [0, 1000, 2000]);
    expect(result.length, 2731);
    expect(result.last.item.card.id, '2730');
  });

  test(
      'an exact page multiple requires an empty terminal page without metadata',
      () async {
    final offsets = <int>[];
    final client = MockClient((request) async {
      final offset = int.parse(request.url.queryParameters['offset']!);
      offsets.add(offset);
      return reply({
        'listings': offset == 0 ? [listing('a'), listing('b')] : []
      });
    });
    addTearDown(client.close);
    expect(
        (await InventoryProvider(
                client: client,
                pageSize: 2,
                idToken: (_) async => 'token').fetchItems('alice'))
            .length,
        2);
    expect(offsets, [0, 2]);
  });

  test('short pages follow hasMore rather than assuming a server limit',
      () async {
    final offsets = <String>[];
    final client = MockClient((request) async {
      final offset = request.url.queryParameters['offset']!;
      offsets.add(offset);
      return reply({
        'listings': [listing(offset)],
        'hasMore': offset == '0',
        'total': 2
      });
    });
    addTearDown(client.close);
    expect(
        (await InventoryProvider(client: client, idToken: (_) async => 'token')
                .fetchItems('alice'))
            .length,
        2);
    expect(offsets, ['0', '1']);
  });

  test('ignored offsets, duplicate rows and contradictory totals fail closed',
      () async {
    for (final payload in [
      {
        'listings': [listing('a'), listing('b')]
      }, // repeated next page
      {
        'listings': [listing('a'), listing('a')],
        'hasMore': false
      },
      {
        'listings': [listing('a')],
        'hasMore': false,
        'total': 2
      },
      {'listings': [], 'hasMore': true},
      {
        'listings': [listing('a')],
        'hasMore': true,
        'total': 1
      },
      {'listings': [], 'total': 3},
    ]) {
      final client = MockClient((_) async => reply(payload));
      await expectLater(
          InventoryProvider(
              client: client,
              pageSize: 2,
              idToken: (_) async => 'token').fetchItems('alice'),
          throwsFormatException);
      client.close();
    }
  });

  test(
      'HTTP errors, wrong owner and malformed private listings are not empty success',
      () async {
    for (final response in [
      reply({}, 401),
      reply({}, 503),
      reply({}),
      reply({'uid': 'bob', 'listings': []}),
      reply({
        'listings': [listing('a', uid: 'bob')]
      }),
      reply({
        'listings': [
          {...listing('a'), 'cardId': ''}
        ]
      }),
      reply({
        'listings': [
          {...listing('a'), 'quantityAvailable': 'oops'}
        ]
      }),
      reply({
        'listings': [
          {...listing('a'), 'id': ''}
        ]
      }),
    ]) {
      final client = MockClient((_) async => response);
      await expectLater(
          InventoryProvider(client: client, idToken: (_) async => 'token')
              .fetchItems('alice'),
          throwsA(anything));
      client.close();
    }
  });

  test('missing token and guest never request private inventory', () async {
    final client =
        MockClient((_) async => throw StateError('must not request'));
    addTearDown(client.close);
    final provider =
        InventoryProvider(client: client, idToken: (_) async => null);
    await expectLater(provider.fetchItems(''), throwsStateError);
    await expectLater(provider.fetchItems('alice'), throwsStateError);
  });

  test(
      'private holdings validate advertised counts rather than accepting truncation',
      () async {
    for (final counts in [
      {'itemCount': 2},
      {'cardsOwned': 1731}
    ]) {
      final client = MockClient((_) async => reply({
            'uid': 'alice',
            'items': [
              {'uid': 'alice', 'cardId': '1', 'quantity': 1}
            ],
            ...counts
          }));
      await expectLater(
          CollectionProvider(client: client, idToken: (_) async => 'token')
              .fetchItems('alice'),
          throwsFormatException);
      client.close();
    }
  });

  const reconciler = InventoryReconciliationService();
  test(
      'website-shaped 14 Listed plus one Held Audino keep 15 copies and Leafeon',
      () {
    final names = [
      'Antique Old Amber',
      'Audino',
      'Big Air Balloon',
      'Bill’s Transfer',
      'Bronzong',
      'Buddy-Buddy Poffin',
      'Cycling Road',
      'Dratini',
      'Erika’s Invitation',
      'Flamigo',
      'Misdreavus',
      'Pikachu',
      'Solrock',
      'Leafeon'
    ];
    final result = CardCollection(
        status: CollectionStatus.ready,
        items: reconciler.reconcile([
          holding('held-en', cardId: 'Audino', language: 'EN'),
        ], [
          for (final name in names)
            InventoryListing.fromJson(
                listing('sale-$name', cardId: name, name: name)),
        ]));
    expect(result.cards.length, 14);
    expect(result.copies, 15);
    expect(result.quantityFor('Audino'), 2);
    expect(result.quantityFor('Leafeon'), 1);
  });

  test(
      'numeric stock accepts integral doubles but rejects invalid unit quantities',
      () async {
    for (final quantity in [2.0, -1, 0.5, 'NaN']) {
      final client = MockClient((_) async => reply({
            'listings': [
              {...listing('a'), 'quantityAvailable': quantity}
            ]
          }));
      final future =
          InventoryProvider(client: client, idToken: (_) async => 'token')
              .fetchItems('alice');
      if (quantity == 2.0) {
        expect((await future).single.item.quantity, 2);
      } else {
        await expectLater(future, throwsFormatException);
      }
      client.close();
    }
  });

  test('a later failed page never yields a partial success', () async {
    final client = MockClient(
        (request) async => request.url.queryParameters['offset'] == '0'
            ? reply({
                'listings': [listing('one')],
                'hasMore': true
              })
            : reply({}, 503));
    addTearDown(client.close);
    await expectLater(
        InventoryProvider(
            client: client,
            pageSize: 1,
            idToken: (_) async => 'token').fetchItems('alice'),
        throwsStateError);
  });

  test(
      'listings primary: dedupe only explicit links, preserve independent same-print copies',
      () {
    final rows = reconciler.reconcile([
      holding('scan:a', quantity: 9, link: 'sale-a'),
      holding('scan:b', cardId: 'b', quantity: 7),
      holding('independent-en', language: 'EN'),
      holding('independent-it', language: 'IT'),
      holding('wrong-card', cardId: 'z', link: 'sale-a'),
      holding('held', cardId: 'held'),
      holding('nft', cardId: 'nft'),
    ], [
      InventoryListing.fromJson(listing('sale-a', cardId: 'a', quantity: 2)),
      InventoryListing.fromJson(
          listing('sale-b', cardId: 'b', source: 'scan:b', quantity: 3)),
      InventoryListing.fromJson(
          listing('paused', cardId: 'p', status: 'paused')),
      InventoryListing.fromJson(listing('sold', status: 'sold', quantity: 4)),
      InventoryListing.fromJson(
          listing('inactive', status: 'inactive', quantity: 5)),
      InventoryListing.fromJson(listing('zero', quantity: 0)),
    ]);
    final collection =
        CardCollection(status: CollectionStatus.ready, items: rows);
    expect(collection.quantityFor('a'), 4); // 2 Listed + EN + IT, not 9 stale
    expect(collection.quantityFor('b'), 3);
    expect(collection.quantityFor('p'), 1);
    expect(collection.owns('sold'), isFalse);
    expect(collection.owns('inactive'), isFalse);
    expect(collection.owns('zero'), isFalse);
    expect(collection.owns('z'), isTrue);
    expect(collection.owns('held'), isTrue);
    expect(collection.owns('nft'), isTrue);
    expect(collection.copies, 11);
  });

  test(
      'split listings replace linked holding once; inactive listing does not remove Hold',
      () {
    final result = reconciler.reconcile([
      holding('scan:a', quantity: 10),
      holding('hold', cardId: 'h', link: 'inactive'),
    ], [
      InventoryListing.fromJson(
          listing('one', cardId: 'a', quantity: 2, source: 'scan:a')),
      InventoryListing.fromJson(
          listing('two', cardId: 'a', quantity: 3, source: 'scan:a')),
      InventoryListing.fromJson(
          listing('inactive', cardId: 'h', status: 'inactive')),
    ]);
    final collection =
        CardCollection(status: CollectionStatus.ready, items: result);
    expect(collection.quantityFor('a'), 5);
    expect(collection.quantityFor('h'), 1);
  });

  test('waits for both sources and clears ownership if either fails', () async {
    for (final failingPath in [
      '/api/marketplace-listings',
      '/api/marketplace-collection'
    ]) {
      final inventory = Completer<http.Response>();
      final holdings = Completer<http.Response>();
      final client = MockClient((request) =>
          request.url.path.endsWith('listings')
              ? inventory.future
              : holdings.future);
      final states = <CardCollection>[];
      final sub = service(client, () => Stream.value('alice'))
          .watch()
          .listen(states.add);
      holdings.complete(reply({'uid': 'alice', 'items': []},
          failingPath.endsWith('collection') ? 503 : 200));
      await Future<void>.delayed(Duration.zero);
      expect(states.any((s) => s.status == CollectionStatus.ready), isFalse);
      inventory.complete(reply({
        'listings': [listing('leaf', name: 'Leafeon')]
      }, failingPath.endsWith('listings') ? 503 : 200));
      await Future<void>.delayed(Duration.zero);
      expect(states.last.status, CollectionStatus.unavailable);
      expect(states.last.items, isEmpty);
      await sub.cancel();
      client.close();
    }
  });

  test(
      'account changes do not wait for old reads or publish their late rows; guest makes no calls',
      () async {
    final users = StreamController<String?>();
    final requests = <String, Completer<http.Response>>{};
    final client = MockClient((request) {
      final key = '${request.headers['Authorization']} ${request.url.path}';
      return (requests[key] = Completer<http.Response>()).future;
    });
    final values = <CardCollection>[];
    final sub = service(client, () => users.stream).watch().listen(values.add);
    users.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(values.last.status, CollectionStatus.guest);
    expect(requests, isEmpty);
    users.add('alice');
    await Future<void>.delayed(Duration.zero);
    users.add('bob');
    await Future<void>.delayed(Duration.zero);
    expect(requests.length, 4);
    void complete(String uid) {
      requests['Bearer $uid /api/marketplace-collection']!
          .complete(reply({'uid': uid, 'items': []}));
      requests['Bearer $uid /api/marketplace-listings']!.complete(reply({
        'listings': [listing(uid, uid: uid)]
      }));
    }

    complete('bob');
    await Future<void>.delayed(Duration.zero);
    expect(values.last.owns('bob'), isTrue);
    complete('alice');
    await Future<void>.delayed(Duration.zero);
    expect(values.last.owns('bob'), isTrue);
    expect(values.last.owns('alice'), isFalse);
    users.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(values.last.status, CollectionStatus.guest);
    expect(values.last.items, isEmpty);
    await sub.cancel();
    await users.close();
    client.close();
  });

  testWidgets(
      'Leafeon from listings reaches both Cardex and Portfolio; refresh re-reads both',
      (tester) async {
    final calls = <String, int>{};
    final client = MockClient((request) async {
      calls.update(request.url.path, (n) => n + 1, ifAbsent: () => 1);
      return request.url.path.endsWith('listings')
          ? reply({
              'listings': [listing('leaf', name: 'Leafeon')]
            })
          : reply({'uid': 'alice', 'items': []});
    });
    addTearDown(client.close);
    final controller = CardexController(
        collection: service(client, () => Stream.value('alice')));
    addTearDown(controller.dispose);
    controller.start(loadCatalog: false);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CardexScreen(controller: controller, onOpen: (_) {}))));
    await tester.pumpAndSettle();
    expect(albumCardNamed('Leafeon'), findsOneWidget);
    expect(find.text('×1'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PortfolioScreen(controller: controller, onOpen: (_) {}))));
    await tester.pumpAndSettle();
    expect(albumCardNamed('Leafeon'), findsOneWidget);
    await tester.tap(find.text('Aggiorna collezione'));
    await tester.pumpAndSettle();
    expect(calls.values, everyElement(2));
    expect(albumCardNamed('Leafeon'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
