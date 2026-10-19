import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/rebuild/controller/cardex_controller.dart';
import 'package:pokoin/rebuild/model/cardex.dart';
import 'package:pokoin/rebuild/model/marketplace_home.dart';
import 'package:pokoin/rebuild/presentation/cardex/cardex_screen.dart';
import 'package:pokoin/rebuild/presentation/cardex/atomics/album_card.dart';
import 'cardex_test.dart' as fixtures;

List<MarketplaceCardPreview> cards(int start, int count) => List.generate(
    count,
    (index) => MarketplaceCardPreview(
        id: '${start + index}',
        name: 'Card ${start + index}',
        expansion: 'Test'));

CardexController controller(fixtures.Catalog catalog) =>
    CardexController(catalog: catalog)
      ..expansion = fixtures.expansion
      ..collectionAlbum = false
      ..collection = CardCollection(status: CollectionStatus.guest)
      ..cards = cards(1, 48)
      ..hasMore = true;

// Seed a real first-page completion so the controller's next offset is 48.
Future<void> seed(CardexController value, fixtures.Catalog catalog) async {
  final first = value.selectExpansion(fixtures.expansion);
  catalog.pending.last.result
      .complete(fixtures.page(cards(1, 48), hasMore: true));
  await first;
}

void main() {
  test('prefetch starts near last two spreads, serializes and stops at the end',
      () async {
    final catalog = fixtures.Catalog();
    final value = controller(catalog);
    addTearDown(value.dispose);
    await seed(value, catalog);
    value.onAlbumPageVisible(30, 6);
    expect(catalog.pending.length, 1);
    value.onAlbumPageVisible(36, 6);
    value.onAlbumPageVisible(48, 6);
    expect(catalog.pending.length, 2);
    expect(catalog.pending.last.offset, 48);
    catalog.pending.last.result
        .complete(fixtures.page(cards(49, 48), offset: 48));
    await fixtures.flush();
    expect(value.cards.length, 96);
    value.onAlbumPageVisible(96, 6);
    expect(catalog.pending.length, 2);
  });

  test('prefetch never starts a private album request or retries an error loop',
      () async {
    final catalog = fixtures.Catalog();
    final value = controller(catalog);
    addTearDown(value.dispose);
    await seed(value, catalog);
    value.collectionAlbum = true;
    value.collection = CardCollection(status: CollectionStatus.ready);
    value.onAlbumPageVisible(48, 6);
    expect(catalog.pending.length, 1);
    value.collectionAlbum = false;
    value.onAlbumPageVisible(48, 6);
    catalog.pending.last.result.completeError(StateError('offline'));
    await fixtures.flush();
    expect(value.pageError, isTrue);
    value.onAlbumPageVisible(48, 6);
    expect(catalog.pending.length, 2);
    final retry = value.loadMore();
    expect(catalog.pending.length, 3);
    catalog.pending.last.result
        .complete(fixtures.page(cards(49, 1), offset: 48));
    await retry;
    expect(value.pageError, isFalse);
  });

  testWidgets(
      'page six prefetches without a button and append preserves album position',
      (tester) async {
    final catalog = fixtures.Catalog();
    final value = controller(catalog);
    addTearDown(value.dispose);
    await seed(value, catalog);
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: CardexScreen(controller: value, onOpen: (_) {}))));
    await tester.pumpAndSettle();
    expect(find.text('Carica altre carte'), findsNothing);
    expect(catalog.pending.length, 1);
    final pages = tester.widget<PageView>(find.byType(PageView)).controller!;
    pages.jumpToPage(4);
    await tester.pumpAndSettle();
    expect(catalog.pending.length, 1);
    pages.jumpToPage(5);
    await tester.pump();
    await tester.pump();
    expect(catalog.pending.length, 2);
    expect(find.text('Caricamento altre carte…'), findsOneWidget);
    catalog.pending.last.result
        .complete(fixtures.page(cards(49, 48), offset: 48, hasMore: true));
    await tester.pumpAndSettle();
    expect(find.text('Pagina 6 di 16 · 96 carte'), findsOneWidget);
    expect(pages.page, 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'empty owned-filter pages continue automatically until a match or end',
      (tester) async {
    final catalog = fixtures.Catalog();
    final value = controller(catalog);
    addTearDown(value.dispose);
    await seed(value, catalog);
    value.collection = CardCollection(
        status: CollectionStatus.ready,
        items: [OwnedCard(card: cards(999, 1).single, quantity: 1)]);
    value.filter = CardexFilter.owned;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: CardexScreen(controller: value, onOpen: (_) {}))));
    await tester.pump();
    expect(catalog.pending.last.offset, 48);
    catalog.pending.last.result
        .complete(fixtures.page(cards(49, 48), offset: 48, hasMore: true));
    await tester.pump();
    await tester.pump();
    expect(catalog.pending.last.offset, 96);
    catalog.pending.last.result
        .complete(fixtures.page(cards(999, 1), offset: 96));
    await tester.pumpAndSettle();
    expect(value.visibleCards.single.id, '999');
    expect(find.byType(AlbumCard), findsOneWidget);
    expect(catalog.pending.length, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failure shows only explicit retry, without automatic request storms',
      (tester) async {
    final catalog = fixtures.Catalog();
    final value = controller(catalog);
    addTearDown(value.dispose);
    await seed(value, catalog);
    value.cards = cards(1, 6);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: CardexScreen(controller: value, onOpen: (_) {}))));
    await tester.pump();
    catalog.pending.last.result.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(catalog.pending.length, 2);
    await tester.scrollUntilVisible(find.text('Riprova carte'), 180,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Riprova carte'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(catalog.pending.length, 2);
  });

  test(
      'a no-progress catalog page fails instead of stalling hidden auto loading',
      () async {
    final catalog = fixtures.Catalog();
    final value = controller(catalog);
    addTearDown(value.dispose);
    await seed(value, catalog);
    value.onAlbumPageVisible(48, 6);
    catalog.pending.last.result
        .complete(fixtures.page(cards(1, 48), offset: 48, hasMore: true));
    await fixtures.flush();
    expect(value.pageError, isTrue);
    expect(value.cards.length, 48);
    value.onAlbumPageVisible(48, 6);
    expect(catalog.pending.length, 2);
  });
}
