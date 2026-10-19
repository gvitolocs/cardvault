import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pokoin/rebuild/controller/cardex_controller.dart';
import 'package:pokoin/rebuild/model/cardex.dart';
import 'package:pokoin/rebuild/model/inventory_listing.dart';
import 'package:pokoin/rebuild/model/marketplace_home.dart';
import 'package:pokoin/rebuild/presentation/cardex/cardex_screen.dart';
import 'package:pokoin/rebuild/presentation/cardex/atomics/album_card.dart';
import 'package:pokoin/rebuild/presentation/cardex/component/card_album_loading.dart';
import 'package:pokoin/rebuild/presentation/shared/atomics/collection_quantity_badge.dart';
import 'package:pokoin/rebuild/presentation/shared/component/card_language_selector.dart';
import 'package:pokoin/rebuild/presentation/shared/component/viewport_artwork.dart';
import 'package:pokoin/rebuild/provider/inventory_provider.dart';
import 'package:pokoin/rebuild/service/card_ownership_service.dart';
import 'inventory_collection_test.dart' as fixtures;

const publicCard = MarketplaceCardPreview(
    id: 'public', name: 'Public catalog', expansion: 'Public set');

void main() {
  test('inventory uses consistent owner page sizes and reads ALL offset pages',
      () async {
    final calls = <(int, int)>[];
    final rows = List.generate(2731, (i) => fixtures.listing('$i'));
    final client = MockClient((request) async {
      final offset = int.parse(request.url.queryParameters['offset']!);
      final limit = int.parse(request.url.queryParameters['limit']!);
      calls.add((offset, limit));
      return fixtures
          .reply({'listings': rows.skip(offset).take(limit).toList()});
    });
    addTearDown(client.close);
    final snapshots =
        await InventoryProvider(client: client, idToken: (_) async => 'token')
            .watchItems('alice')
            .toList();
    expect(calls, [(0, 1000), (1000, 1000), (2000, 1000)]);
    expect(snapshots.map((s) => s.items.length), [1000, 2000, 2731]);
    expect(snapshots.map((s) => s.complete), [false, false, true]);
    expect(snapshots.first.items.length,
        1000); // Not a mutable view of the final list.
  });

  test('owner loading avoids incompatible limit=2 preview snapshots', () async {
    final calls = <(int, int)>[];
    final rows = List.generate(
        16,
        (index) => fixtures.listing('$index',
            status: index < 3 ? 'inactive' : 'active'));
    final client = MockClient((request) async {
      final offset = int.parse(request.url.queryParameters['offset']!);
      final limit = int.parse(request.url.queryParameters['limit']!);
      calls.add((offset, limit));
      // Shape observed on the phone: limit=2 has a stamped fast snapshot;
      // the normal path returns the complete small inventory, overlapping it.
      return fixtures.reply(limit == 2
          ? {'listings': rows.take(2).toList(), 'stamp': 'preview'}
          : {'listings': rows});
    });
    addTearDown(client.close);
    final snapshots =
        await InventoryProvider(client: client, idToken: (_) async => 'token')
            .watchItems('alice')
            .toList();
    expect(calls, [(0, 1000)]);
    expect(snapshots.single.complete, isTrue);
    expect(snapshots.single.items.length, 16);
    expect(snapshots.single.items.where((row) => row.isOwned).length, 13);
  });

  test(
      'cancelling an in-flight first page is immediate and prevents subsequent requests',
      () async {
    final pending = Completer<http.Response>();
    var calls = 0;
    final client = MockClient((_) {
      calls++;
      return pending.future;
    });
    addTearDown(client.close);
    final snapshots = <InventorySnapshot>[];
    final sub = InventoryProvider(client: client, idToken: (_) async => 'token')
        .watchItems('alice')
        .listen(snapshots.add);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    await sub.cancel().timeout(const Duration(seconds: 1));
    pending.complete(fixtures.reply({
      'listings': [fixtures.listing('a'), fixtures.listing('b')]
    }));
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(snapshots, isEmpty);
  });

  testWidgets(
      'personal first two appear before slow remainder/Hold, without Guest flash or false counts',
      (tester) async {
    final first = Completer<http.Response>();
    final rest = Completer<http.Response>();
    final holds = Completer<http.Response>();
    final client = MockClient((request) {
      if (request.url.path.endsWith('collection')) return holds.future;
      return request.url.queryParameters['offset'] == '0'
          ? first.future
          : rest.future;
    });
    addTearDown(client.close);
    final controller = CardexController(
        collection:
            fixtures.service(client, () => Stream.value('alice'), pageSize: 2))
      ..cards = [publicCard];
    addTearDown(controller.dispose);
    controller.start(loadCatalog: false);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CardexScreen(controller: controller, onOpen: (_) {}))));
    await tester.pump();
    expect(find.byType(CardAlbumLoading), findsOneWidget);
    expect(controller.viewingCollection, isTrue);
    expect(controller.visibleCards, isEmpty);
    expect(find.text('La tua collezione è ancora vuota.'), findsNothing);

    first.complete(fixtures.reply({
      'listings': [fixtures.listing('a'), fixtures.listing('b')]
    }));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.collection.status, CollectionStatus.loading);
    expect(controller.visibleCards.map((card) => card.id), ['a', 'b']);
    expect(find.text('Le mie carte'), findsNothing);
    expect(find.byType(AlbumCard), findsNWidgets(2));
    expect(find.byType(CollectionQuantityBadge), findsNothing);
    expect(find.byType(CardLanguageSelector), findsNWidgets(2));
    expect(
        tester
            .widgetList<CardLanguageSelector>(find.byType(CardLanguageSelector))
            .every((selector) =>
                !selector.ownership.known &&
                selector.ownership.hasConfirmedCopies),
        isTrue);
    expect(find.text('Mancante'), findsNothing);
    expect(find.text('Catalogo'), findsNothing);
    expect(find.text('2 carte caricate · sincronizzazione in corso'),
        findsNothing);
    expect(
        const CardOwnershipService()
            .describe(controller.collection, 'not-yet-loaded')
            .known,
        isFalse);

    rest.complete(fixtures.reply({
      'listings': [fixtures.listing('c')]
    }));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.visibleCards.map((card) => card.id), ['a', 'b', 'c']);
    expect(controller.ownershipKnown, isFalse);
    holds.complete(fixtures.reply({
      'uid': 'alice',
      'items': [
        {
          'uid': 'alice',
          'id': 'mirror',
          'listingId': 'a',
          'cardId': 'a',
          'quantity': 99
        },
        {'uid': 'alice', 'id': 'held', 'cardId': 'h', 'quantity': 1},
      ]
    }));
    await tester.pumpAndSettle();
    expect(controller.collection.status, CollectionStatus.ready);
    expect(
        controller.visibleCards.map((card) => card.id), ['a', 'b', 'c', 'h']);
    expect(controller.collection.copies, 4); // No mirrored stock double count.
    expect(controller.visibleCards.any((card) => card.id == 'public'), isFalse);
    expect(find.text('Caricamento della tua collezione…'), findsNothing);
    expect(find.byType(CardLanguageSelector), findsNWidgets(4));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'a later page error clears previews and never falls back to Guest catalog',
      (tester) async {
    final rest = Completer<http.Response>();
    final client = MockClient((request) async {
      if (request.url.path.endsWith('collection')) {
        return fixtures.reply({'uid': 'alice', 'items': []});
      }
      if (request.url.queryParameters['offset'] == '0') {
        return fixtures.reply({
          'listings': [fixtures.listing('a'), fixtures.listing('b')]
        });
      }
      return rest.future;
    });
    addTearDown(client.close);
    final controller = CardexController(
        collection:
            fixtures.service(client, () => Stream.value('alice'), pageSize: 2))
      ..cards = [publicCard];
    addTearDown(controller.dispose);
    controller.start(loadCatalog: false);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CardexScreen(controller: controller, onOpen: (_) {}))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.visibleCards.length, 2);
    rest.complete(fixtures.reply({}, 503));
    await tester.pumpAndSettle();
    expect(controller.collection.status, CollectionStatus.unavailable);
    expect(controller.viewingCollection, isTrue);
    expect(controller.visibleCards, isEmpty);
    expect(find.byType(AlbumCard), findsNothing);
    expect(find.text('Riprova collezione'), findsOneWidget);
    expect(find.text('La tua collezione è ancora vuota.'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('guest preview and explicitly selected public albums remain available',
      () {
    final controller = CardexController()..cards = [publicCard];
    addTearDown(controller.dispose);
    controller.collection = CardCollection(status: CollectionStatus.guest);
    expect(controller.viewingCollection, isFalse);
    expect(controller.visibleCards.single.id, 'public');
    controller.collection = CardCollection(status: CollectionStatus.loading);
    expect(controller.viewingCollection, isTrue);
    expect(controller.visibleCards, isEmpty);
    controller.collectionAlbum = false;
    expect(controller.visibleCards.single.id, 'public');
    expect(controller.ownershipKnown, isFalse);
  });

  testWidgets(
      'offscreen artwork is not constructed until vertical scroll reveals it',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 500);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final started = <int>{};
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CustomScrollView(slivers: [
      SliverToBoxAdapter(
          child: Builder(
              builder: (context) => Column(children: [
                    for (var i = 0; i < 6; i++)
                      SizedBox(
                          height: 250,
                          child: ViewportArtwork(
                              position: Scrollable.of(context).position,
                              builder: (_) {
                                started.add(i);
                                return Text('Image $i');
                              })),
                  ]))),
    ]))));
    await tester.pumpAndSettle();
    expect(started, {0, 1});
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(started, containsAll([0, 1, 2, 3]));
    expect(started, isNot(contains(5)));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
