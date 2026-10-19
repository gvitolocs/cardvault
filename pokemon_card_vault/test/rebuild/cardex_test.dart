import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pokoin/rebuild/controller/cardex_controller.dart';
import 'package:pokoin/rebuild/controller/marketplace_controller.dart';
import 'package:pokoin/rebuild/model/cardex.dart';
import 'package:pokoin/rebuild/model/marketplace_home.dart';
import 'package:pokoin/rebuild/presentation/cardex/cardex_screen.dart';
import 'package:pokoin/rebuild/presentation/marketplace/marketplace_screen.dart';
import 'package:pokoin/rebuild/presentation/shared/component/utility_bar.dart';
import 'package:pokoin/rebuild/provider/cardex_provider.dart';
import 'package:pokoin/rebuild/provider/collection_provider.dart';
import 'package:pokoin/rebuild/service/cardex_service.dart';
import 'package:pokoin/rebuild/service/collection_service.dart';
import 'package:pokoin/rebuild/presentation/cardex/atomics/album_card.dart';

Finder albumCard(String id) => find
    .byWidgetPredicate((widget) => widget is AlbumCard && widget.card.id == id);

const expansion =
    MarketplaceExpansion(name: 'Base Set', slug: 'base-set', cardCount: 3);
const secondExpansion =
    MarketplaceExpansion(name: 'Jungle', slug: 'jungle', cardCount: 1);
const pikachu = MarketplaceCardPreview(
    id: '116', name: 'Pikachu', expansion: 'Base Set', number: '58/102');
const raichu = MarketplaceCardPreview(
    id: '52', name: 'Raichu', expansion: 'Base Set', number: '14/102');
const otherPikachu = MarketplaceCardPreview(
    id: '117', name: 'Pikachu', expansion: 'Jungle', number: '60/64');

class AccountSource extends CollectionProvider {
  final users = StreamController<String?>.broadcast();
  final records = <String, StreamController<List<OwnedCard>>>{};
  @override
  Stream<String?> watchUserId() => users.stream;
  @override
  Stream<List<OwnedCard>> watchItems(String uid) => records
      .putIfAbsent(uid, () => StreamController<List<OwnedCard>>.broadcast())
      .stream;
  Future<void> close() async {
    await users.close();
    for (final stream in records.values) {
      await stream.close();
    }
  }
}

class Catalog extends CardexService {
  final pending = <({String slug, int offset, Completer<CardexPage> result})>[];
  @override
  Future<List<MarketplaceExpansion>> loadExpansions() async =>
      [expansion, secondExpansion];
  @override
  Future<CardexPage> loadPage(String slug, {int offset = 0}) {
    final result = Completer<CardexPage>();
    pending.add((slug: slug, offset: offset, result: result));
    return result.future;
  }
}

Future<void> flush() => Future<void>.delayed(Duration.zero);
CardexPage page(List<MarketplaceCardPreview> cards,
        {int offset = 0,
        bool hasMore = false,
        MarketplaceExpansion set = expansion}) =>
    CardexPage(
        expansion: set,
        cards: cards,
        offset: offset,
        hasMore: hasMore,
        total: set.cardCount);

void main() {
  test('catalog DAO encodes slug and pagination and keeps cards without offers',
      () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'api.pokoin.com');
      expect(request.url.path, '/api/marketplace-expansion-page');
      expect(request.url.queryParameters, {
        'slug': 'base-set',
        'productType': 'card',
        'offset': '48',
        'limit': '48'
      });
      return http.Response(
          jsonEncode({
            'expansion': {
              'name': 'Base Set',
              'slug': 'base-set',
              'cardCount': 102
            },
            'cards': [
              {
                'id': '116',
                'name': 'Pikachu',
                'set': 'Base Set',
                'number': '58/102',
                'price': null
              }
            ],
            'offset': 48,
            'total': 102,
            'hasMore': true,
          }),
          200);
    });
    final provider = CardexProvider(client: client);
    addTearDown(client.close);
    addTearDown(provider.dispose);
    final result = await provider.fetchPage('base-set', offset: 48);
    expect(result.cards.single.id, '116');
    expect(result.cards.single.pricePkn, isNull);
    expect(result.hasMore, isTrue);
  });

  test('malformed or failed catalogs are not treated as empty albums',
      () async {
    for (final status in [200, 503]) {
      final client = MockClient((_) async => http.Response('{}', status));
      final provider = CardexProvider(client: client);
      await expectLater(provider.fetchPage('base-set'),
          throwsA(anyOf(isA<StateError>(), isA<FormatException>())));
      provider.dispose();
      client.close();
    }
  });

  test(
      'ownership counts copies, ignores zero stock, and distinguishes print IDs',
      () {
    final collection = CardCollection(status: CollectionStatus.ready, items: [
      const OwnedCard(card: pikachu, quantity: 2),
      const OwnedCard(card: pikachu, quantity: 1, reverse: true),
      const OwnedCard(card: raichu, quantity: 0),
    ]);
    expect(collection.quantityFor('116'), 3);
    expect(collection.cards.length, 1);
    expect(collection.copies, 3);
    expect(collection.owns('52'), isFalse);
    expect(collection.owns(otherPikachu.id), isFalse);
  });

  test('session changes clear ownership and suppress the previous user stream',
      () async {
    final source = AccountSource();
    final values = <CardCollection>[];
    final subscription =
        CollectionService(provider: source).watch().listen(values.add);
    await flush();
    source.users.add('alice');
    await flush();
    source.records['alice']!.add([const OwnedCard(card: pikachu, quantity: 1)]);
    await flush();
    expect(values.last.owns('116'), isTrue);
    source.users.add('bob');
    await flush();
    expect(values.last.status, CollectionStatus.loading);
    expect(values.last.items, isEmpty);
    source.records['alice']!.add([const OwnedCard(card: raichu, quantity: 2)]);
    source.records['bob']!.add([]);
    await flush();
    expect(values.last.status, CollectionStatus.ready);
    expect(values.last.items, isEmpty);
    source.records['bob']!.addError(StateError('offline'));
    await flush();
    expect(values.last.status, CollectionStatus.unavailable);
    source.users.add(null);
    await flush();
    expect(values.last.status, CollectionStatus.guest);
    await subscription.cancel();
    expect(source.users.hasListener, isFalse);
    expect(source.records['bob']!.hasListener, isFalse);
    await source.close();
  });

  test(
      'album ignores obsolete responses and retries pagination without skipping rows',
      () async {
    final catalog = Catalog();
    final controller = CardexController(catalog: catalog);
    addTearDown(catalog.dispose);
    addTearDown(controller.dispose);
    final old = controller.selectExpansion(expansion);
    final current = controller.selectExpansion(secondExpansion);
    catalog.pending[1].result
        .complete(page([otherPikachu], set: secondExpansion));
    await current;
    catalog.pending[0].result.complete(page([pikachu]));
    await old;
    expect(controller.cards.single.id, '117');
    final first = controller.selectExpansion(expansion);
    catalog.pending.last.result.complete(page([pikachu], hasMore: true));
    await first;
    final fail = controller.loadMore();
    catalog.pending.last.result.completeError(StateError('offline'));
    await fail;
    expect(controller.pageError, isTrue);
    expect(controller.cards.single.id, '116');
    final retry = controller.loadMore();
    expect(catalog.pending.last.offset, 1);
    catalog.pending.last.result.complete(page([pikachu, raichu], offset: 1));
    await retry;
    expect(controller.cards.map((card) => card.id), ['116', '52']);
    expect(controller.pageError, isFalse);
    expect(controller.hasMore, isFalse);
  });

  testWidgets('Cardex shows guest catalog neutrally and filters real ownership',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = AccountSource();
    final catalog = Catalog();
    final controller = CardexController(
        catalog: catalog, collection: CollectionService(provider: source));
    addTearDown(catalog.dispose);
    addTearDown(source.close);
    addTearDown(controller.dispose);
    controller.start();
    await tester.pump();
    catalog.pending.single.result.complete(page([pikachu, raichu]));
    source.users.add(null);
    String? opened;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CardexScreen(
                controller: controller, onOpen: (card) => opened = card.id))));
    await tester.pumpAndSettle();
    expect(find.text('Mancante'), findsNothing);
    expect(find.text('Catalogo'), findsNWidgets(2));
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Mancanti'))
            .onSelected,
        isNull);
    source.users.add('alice');
    await tester.pump();
    source.records['alice']!.add([const OwnedCard(card: pikachu, quantity: 2)]);
    await tester.pumpAndSettle();
    expect(find.text('×2'), findsOneWidget);
    expect(albumCard('52'), findsNothing);
    final selecting = controller.selectExpansion(expansion);
    catalog.pending.last.result.complete(page([pikachu, raichu]));
    await selecting;
    await tester.pumpAndSettle();
    expect(find.text('Mancante'), findsOneWidget);
    await tester.tap(find.text('Mancanti'));
    await tester.pumpAndSettle();
    expect(albumCard('116'), findsNothing);
    expect(albumCard('52'), findsOneWidget);
    await tester.tap(albumCard('52'));
    expect(opened, '52');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('five destinations and Profile Wallet preserve navigation',
      (tester) async {
    final controller = MarketplaceController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: MarketplaceScreen(controller: controller, showDiscovery: false)));
    final bar = tester.widget<NavigationBar>(find.descendant(
        of: find.byType(UtilityBar), matching: find.byType(NavigationBar)));
    expect(bar.destinations.length, 5);
    expect(find.text('Portfolio'), findsOneWidget);
    expect(find.text('Cardex'), findsOneWidget);
    await tester.tap(find.text('Profilo'));
    await tester.pumpAndSettle();
    expect(controller.selectedTab, 4);
    expect(find.byTooltip('Wallet'), findsNothing);
    await tester.tap(find.text('Wallet'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Accedi al tuo account Pokoin per consultare il saldo e il wallet collegato.'),
        findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(controller.selectedTab, 4);
    expect(tester.takeException(), isNull);
  });
}
