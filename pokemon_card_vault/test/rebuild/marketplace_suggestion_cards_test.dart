import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/rebuild/controller/marketplace_search_controller.dart';
import 'package:pokoin/rebuild/model/marketplace_home.dart';
import 'package:pokoin/rebuild/model/marketplace_search.dart';
import 'package:pokoin/rebuild/presentation/marketplace/atomics/suggestion_card_tile.dart';
import 'package:pokoin/rebuild/presentation/marketplace/component/marketplace_search.dart';
import 'package:pokoin/rebuild/presentation/shared/atomics/marketplace_thumbnail.dart';

import 'marketplace_search_controller_test.dart';
import 'marketplace_suggestions_test.dart';

void main() {
  testWidgets(
      'popup shares debounced search, drops stale pages and caps versions',
      (tester) async {
    final api = SearchServiceStub();
    final controller = MarketplaceSearchController(service: api);
    addTearDown(api.dispose);
    addTearDown(controller.dispose);
    controller.setQuery('pika');
    await tester.pump(const Duration(milliseconds: 299));
    expect(api.requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    controller.setQuery('char');
    await tester.pump(const Duration(milliseconds: 300));
    api.responses.first.complete(searchPage(['24']));
    await tester.pump();
    expect(controller.suggestions.cards, isEmpty);
    expect(controller.suggestions.cardsLoading, isTrue);
    api.responses.last.complete(searchPage([
      for (var id = 100; id < 108; id++) '$id',
    ]));
    await tester.pump();
    expect(controller.suggestions.cards.map((c) => c.id),
        ['100', '101', '102', '103', '104', '105']);
    expect(controller.state.cards, hasLength(8));
    controller.dismissSuggestions();
    expect(controller.suggestions.cards, isEmpty);
    await controller.refreshSuggestions();
    expect(controller.suggestions.cards, hasLength(6));
    expect(api.requests, hasLength(2));
    controller.setFilters(productType: 'card', printLanguage: 'japanese');
    expect(controller.suggestions.cards, isEmpty);
    expect(api.requests.last.printLanguage, 'japanese');
    expect(api.requests.last.productType, 'card');
    controller.dismissSuggestions();
    api.responses.last.complete(searchPage(['48']));
    await tester.pump();
    expect(controller.suggestions.cards, isEmpty,
        reason: 'A late page cannot reopen a dismissed popup');
    await controller.refreshSuggestions();
    expect(controller.suggestions.cards.single.id, '48');
    controller.setQuery('pi');
    expect(controller.suggestions.cards, isEmpty);
    controller.setQuery('');
    controller.setFilters(productType: '', printLanguage: 'all');
  });

  for (final width in [320.0, 390.0, 900.0]) {
    testWidgets('version popup at width $width opens the selected canonical ID',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      final api = SearchServiceStub();
      final local = SuggestionServiceStub();
      final controller =
          MarketplaceSearchController(service: api, suggestionService: local);
      addTearDown(api.dispose);
      addTearDown(local.dispose);
      addTearDown(controller.dispose);
      MarketplaceCardPreview? selected;
      const card = MarketplaceCardPreview(
          id: '632778',
          name: 'Pikachu',
          expansion: 'Scarlet & Violet — 151',
          number: '#025/165',
          // Invalid/missing artwork must leave this exact version selectable.
          imageUrl: 'file:///unavailable.jpg',
          fullImageUrl: 'https://cdn.pokoin.com/632778.jpg');
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!),
          home: Scaffold(
              body: MarketplaceSearch(
                  controller: controller,
                  discovery: const SizedBox.shrink(),
                  onOpen: (card) => selected = card))));
      await tester.enterText(find.byType(TextField), 'pika');
      local.replies.last.completeError(StateError('Dictionary unavailable'));
      await tester.pump(const Duration(milliseconds: 300));
      api.responses.single
          .complete(MarketplaceSearchPage(cards: [card], hasMore: false));
      await tester.pumpAndSettle();
      final row = find.byType(SuggestionCardTile);
      expect(row, findsOneWidget);
      final thumbnail = tester.widget<MarketplaceThumbnail>(find.descendant(
          of: row, matching: find.byType(MarketplaceThumbnail)));
      expect(thumbnail.imageUrl, card.imageUrl);
      expect(thumbnail.width, 40);
      expect(thumbnail.height, 56);
      expect(find.descendant(of: row, matching: find.byType(Icon)),
          findsOneWidget);
      expect(find.text('Pikachu 025/165'), findsOneWidget);
      expect(tester.getBottomLeft(find.text('Mostra tutti i risultati')).dy,
          lessThan(544));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(selected, same(card));
      expect(selected!.id, '632778');
      expect(selected!.fullImageUrl, card.fullImageUrl);
      expect(find.byType(SuggestionCardTile), findsNothing);
      expect(api.requests, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('server failure retains local choices and clearing closes both',
      (tester) async {
    final api = SearchServiceStub();
    final local = SuggestionServiceStub();
    final controller =
        MarketplaceSearchController(service: api, suggestionService: local);
    addTearDown(api.dispose);
    addTearDown(local.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MarketplaceSearch(
                controller: controller,
                discovery: const SizedBox.shrink(),
                onOpen: (_) {}))));
    await tester.enterText(find.byType(TextField), 'pika');
    local.replies.last.complete([pikachuSuggestion]);
    await tester.pump(const Duration(milliseconds: 300));
    api.responses.single.completeError(StateError('Offline'));
    await tester.pumpAndSettle();
    expect(controller.suggestions.cardsError, isTrue);
    expect(find.text('Pikachu'), findsOneWidget);
    expect(find.text('Impossibile caricare le versioni. Riprova la ricerca.'),
        findsOneWidget);
    await tester.tap(find.byTooltip('Cancella ricerca'));
    await tester.pumpAndSettle();
    expect(find.text('Suggerimenti'), findsNothing);
    expect(controller.suggestions.cardsError, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
