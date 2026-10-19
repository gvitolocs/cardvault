import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pokoin/rebuild/model/cardex.dart';
import 'package:pokoin/rebuild/model/marketplace_home.dart';
import 'package:pokoin/rebuild/presentation/cardex/component/card_album.dart';
import 'package:pokoin/rebuild/presentation/cardex/atomics/album_card.dart';
import 'package:pokoin/rebuild/provider/collection_provider.dart';
import 'package:pokoin/rebuild/controller/cardex_controller.dart';
import 'package:pokoin/rebuild/presentation/cardex/cardex_screen.dart';
import 'package:pokoin/rebuild/service/collection_service.dart';

Finder albumCard(String id) => find
    .byWidgetPredicate((widget) => widget is AlbumCard && widget.card.id == id);

void main() {
  test(
      'private collection BFF sends Firebase bearer, no client UID, and parses variants',
      () async {
    final client = MockClient((request) async {
      expect(request.url.toString(),
          'https://api.pokoin.com/api/marketplace-collection');
      expect(request.headers['Authorization'], 'Bearer test-token');
      return http.Response(
          jsonEncode({
            'uid': 'alice',
            'items': [
              {
                'uid': 'alice',
                'cardId': '116',
                'cardName': 'Pikachu',
                'quantity': 2.0
              },
              {
                'uid': 'alice',
                'blueprintId': '116',
                'name': 'Pikachu',
                'quantity': 1,
                'reverse': true
              },
              {'uid': 'alice', 'cardId': '117', 'quantity': 0},
            ]
          }),
          200);
    });
    addTearDown(client.close);
    final provider = CollectionProvider(
        client: client,
        idToken: (uid) async {
          expect(uid, 'alice');
          return 'test-token';
        });
    final collection = CardCollection(
        status: CollectionStatus.ready,
        items: await provider.fetchItems('alice'));
    expect(collection.quantityFor('116'), 3);
    expect(collection.owns('117'), isFalse);
    expect(collection.cards.single.name, 'Pikachu');
  });

  test(
      'unauthorized, invalid and wrong-account replies never become an empty collection',
      () async {
    for (final response in [
      http.Response('{}', 401),
      http.Response('{}', 503),
      http.Response('{}', 200),
      http.Response(jsonEncode({'uid': 'bob', 'items': []}), 200),
      http.Response(
          jsonEncode({
            'uid': 'alice',
            'items': [
              {'uid': 'bob', 'cardId': '116', 'quantity': 1}
            ]
          }),
          200),
      http.Response(
          jsonEncode({
            'uid': 'alice',
            'items': [
              {'uid': 'alice', 'quantity': 1}
            ]
          }),
          200),
    ]) {
      final client = MockClient((_) async => response);
      final provider =
          CollectionProvider(client: client, idToken: (_) async => 'test');
      await expectLater(provider.fetchItems('alice'), throwsA(anything));
      client.close();
    }
  });

  test('guest and missing-token reads never call the server', () async {
    final client =
        MockClient((_) async => throw StateError('must not request'));
    addTearDown(client.close);
    final provider =
        CollectionProvider(client: client, idToken: (_) async => null);
    await expectLater(provider.fetchItems(''), throwsStateError);
    await expectLater(provider.fetchItems('alice'), throwsStateError);
  });

  test('a valid empty private collection is not an error', () async {
    final client = MockClient((_) async =>
        http.Response(jsonEncode({'uid': 'alice', 'items': []}), 200));
    addTearDown(client.close);
    expect(
        await CollectionProvider(client: client, idToken: (_) async => 'test')
            .fetchItems('alice'),
        isEmpty);
  });

  test(
      'switching accounts does not wait for old HTTP or reveal its late holdings',
      () async {
    final users = StreamController<String?>();
    final pending = <String, Completer<http.Response>>{};
    final client = MockClient((request) {
      final uid = request.headers['Authorization']!.split(' ').last;
      return (pending[uid] = Completer<http.Response>()).future;
    });
    final values = <CardCollection>[];
    final subscription = CollectionService(
        provider: CollectionProvider(
            client: client,
            idToken: (uid) async => uid,
            userIds: () => users.stream)).watch().listen(values.add);
    users.add('alice');
    await Future<void>.delayed(Duration.zero);
    users.add('bob');
    await Future<void>.delayed(Duration.zero);
    expect(pending.keys, containsAll(['alice', 'bob']));
    expect(values.last.items, isEmpty);
    pending['bob']!.complete(http.Response(
        jsonEncode({
          'uid': 'bob',
          'items': [
            {'uid': 'bob', 'cardId': '2', 'quantity': 1}
          ]
        }),
        200));
    await Future<void>.delayed(Duration.zero);
    expect(values.last.owns('2'), isTrue);
    pending['alice']!.complete(http.Response(
        jsonEncode({
          'uid': 'alice',
          'items': [
            {'uid': 'alice', 'cardId': '1', 'quantity': 1}
          ]
        }),
        200));
    await Future<void>.delayed(Duration.zero);
    expect(values.last.owns('1'), isFalse);
    users.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(values.last.status, CollectionStatus.guest);
    expect(values.last.items, isEmpty);
    await subscription.cancel();
    await users.close();
    client.close();
  });

  final cards = List.generate(
      13,
      (i) => MarketplaceCardPreview(
          id: '${i + 1}',
          name: 'Carta ${i + 1}',
          expansion: 'Test',
          number: '${i + 1}/13'));

  testWidgets('Cardex uses wider taller pockets with one-pixel row gaps',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = CardexController();
    addTearDown(controller.dispose);
    controller.collection = CardCollection(
        status: CollectionStatus.ready,
        items: [
          for (final card in cards.take(6)) OwnedCard(card: card, quantity: 1)
        ]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CardexScreen(controller: controller, onOpen: (_) {}))));
    await tester.pumpAndSettle();
    final first = tester.getRect(albumCard('1'));
    final second = tester.getRect(albumCard('2'));
    final third = tester.getRect(albumCard('3'));
    final album = tester.getRect(find.byType(PageView));
    expect(album.left, 8);
    expect(album.right, 352);
    expect(album.height, greaterThan(420));
    expect(first.width, greaterThanOrEqualTo(166));
    expect(first.height, greaterThanOrEqualTo(136));
    expect(second.left - first.right, closeTo(2, .001));
    expect(third.top - first.bottom, closeTo(1, .001));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('personal Cardex screen fits narrow phones with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = CardexController();
    addTearDown(controller.dispose);
    controller.collection = CardCollection(
        status: CollectionStatus.ready,
        items: [OwnedCard(card: cards.first, quantity: 3)]);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(
                size: Size(320, 900), textScaler: TextScaler.linear(2)),
            child: Scaffold(
                body: CardexScreen(controller: controller, onOpen: (_) {})))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('×3'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('×3'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final width in [390.0, 900.0]) {
    testWidgets(
        'album flips at $width px, opens canonical IDs and keeps the final partial page',
        (tester) async {
      tester.view.physicalSize = Size(width, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? opened;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: CardAlbum(
                      cards: cards,
                      collection: CardCollection(
                          status: CollectionStatus.ready,
                          items: [OwnedCard(card: cards.first, quantity: 2)]),
                      onOpen: (card) => opened = card.id)))));
      expect(find.text('×2'), findsOneWidget);
      await tester.tap(albumCard('1'));
      expect(opened, '1');
      await tester.tap(find.byTooltip('Pagina successiva'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      if (width < 700) {
        expect(albumCard('7'), findsOneWidget);
        await tester.drag(find.byType(PageView), const Offset(-350, 0));
        await tester.pumpAndSettle();
      }
      expect(albumCard('13'), findsOneWidget);
      expect(
          tester
              .widget<IconButton>(find.byWidgetPredicate((widget) =>
                  widget is IconButton &&
                  widget.tooltip == 'Pagina successiva'))
              .onPressed,
          isNull);
      await tester.tap(albumCard('13'));
      expect(opened, '13');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'large text and reduced motion fit and paginate without animation',
      (tester) async {
    tester.view.physicalSize = const Size(320, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(
                size: Size(320, 2000),
                disableAnimations: true,
                textScaler: TextScaler.linear(2)),
            child: Scaffold(
                body: SingleChildScrollView(
                    child: CardAlbum(
                        cards: cards,
                        collection:
                            CardCollection(status: CollectionStatus.guest),
                        onOpen: (_) {}))))));
    await tester.tap(find.byTooltip('Pagina successiva'));
    await tester.pump();
    expect(find.text('Pagina 2 di 3 · 13 carte'), findsOneWidget);
    expect(
        tester
            .widget<PageView>(find.byType(PageView))
            .controller!
            .position
            .isScrollingNotifier
            .value,
        isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'shrinking cards clamps the current page without retaining private cards',
      (tester) async {
    Widget album(List<MarketplaceCardPreview> values) => MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: SizedBox(
                    width: 390,
                    child: CardAlbum(
                        cards: values,
                        collection:
                            CardCollection(status: CollectionStatus.ready),
                        onOpen: (_) {})))));
    await tester.pumpWidget(album(cards));
    await tester.ensureVisible(find.byTooltip('Pagina successiva'));
    await tester.tap(find.byTooltip('Pagina successiva'));
    await tester.pumpAndSettle();
    expect(find.text('Pagina 2 di 3 · 13 carte'), findsOneWidget);
    await tester.pumpWidget(album(cards.take(1).toList()));
    await tester.pumpAndSettle();
    expect(find.text('Pagina 1 di 1 · 1 carte'), findsOneWidget);
    expect(find.byType(AlbumCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
