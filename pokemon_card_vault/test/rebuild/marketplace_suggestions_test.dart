import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin_suggest/pokoin_suggest.dart' show ArtistQuery;
import 'package:pokoin/rebuild/controller/marketplace_search_controller.dart';
import 'package:pokoin/rebuild/model/marketplace_suggestions.dart';
import 'package:pokoin/rebuild/presentation/marketplace/component/marketplace_search.dart';
import 'package:pokoin/rebuild/service/marketplace_suggestion_service.dart';

import 'marketplace_search_controller_test.dart';

class SuggestionServiceStub extends MarketplaceSuggestionService {
  @override
  Future<ArtistQuery?> resolveArtist(String query) async => null;
  final requests = <String>[];
  final replies = <Completer<List<LocalSuggestion>>>[];
  bool warm = false;
  @override
  Future<void> warmUp() async {
    warm = true;
  }

  @override
  Future<List<LocalSuggestion>> suggest(String query) {
    requests.add(query);
    final reply = Completer<List<LocalSuggestion>>();
    replies.add(reply);
    return reply.future;
  }
}

const pikachuSuggestion =
    LocalSuggestion(display: 'Pikachu', query: 'Pikachu', kind: 'name');

void main() {
  testWidgets('popup fits a small viewport with keyboard and enlarged text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 844);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final suggestions = SuggestionServiceStub();
    final api = SearchServiceStub();
    final controller = MarketplaceSearchController(
        service: api, suggestionService: suggestions);
    addTearDown(api.dispose);
    addTearDown(suggestions.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: Scaffold(
            body: MarketplaceSearch(
                controller: controller,
                discovery: const Text('Discovery'),
                onOpen: (_) {}))));
    await tester.enterText(find.byType(TextField), 'pika');
    suggestions.replies.last.complete([
      for (var i = 0; i < 6; i++)
        LocalSuggestion(
            display: 'Pikachu speciale con nome molto lungo $i',
            query: 'Pikachu $i',
            kind: 'name')
    ]);
    await tester.pump();
    expect(find.text('Mostra tutti i risultati'), findsOneWidget);
    expect(tester.getBottomLeft(find.text('Mostra tutti i risultati')).dy,
        lessThan(544));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 300));
    api.responses.single.complete(searchPage([]));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('bundled dictionary worker supplies the visible popup',
      (tester) async {
    final suggestions = MarketplaceSuggestionService();
    final api = SearchServiceStub();
    final controller = MarketplaceSearchController(
        service: api, suggestionService: suggestions);
    addTearDown(api.dispose);
    addTearDown(suggestions.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MarketplaceSearch(
                controller: controller,
                discovery: const Text('Discovery'),
                onOpen: (_) {}))));
    await tester.enterText(find.byType(TextField), 'charziard');
    await tester.pump();
    for (var i = 0; i < 150 && controller.suggestions.loading; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(controller.suggestions.hasError, isFalse);
    expect(controller.suggestions.loading, isFalse);
    expect(controller.suggestions.items.first.display, 'Charizard');
    await tester.tap(find.text('Charizard').first);
    await tester.pump();
    expect(api.requests.single.query, 'Charizard');
    api.responses.single.complete(searchPage([]));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('stale suggestions and disposal do not replace current state', () async {
    final suggestions = SuggestionServiceStub();
    final api = SearchServiceStub();
    final controller = MarketplaceSearchController(
        service: api, suggestionService: suggestions);
    addTearDown(api.dispose);
    addTearDown(suggestions.dispose);
    addTearDown(controller.dispose);
    controller.setQuery('pi');
    expect(suggestions.requests, isEmpty);
    controller.setQuery('pika');
    controller.setQuery('char');
    suggestions.replies.last.complete([
      const LocalSuggestion(
          display: 'Charizard', query: 'Charizard', kind: 'name')
    ]);
    await Future<void>.delayed(Duration.zero);
    suggestions.replies.first.complete([pikachuSuggestion]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.suggestions.items.single.display, 'Charizard');
    controller.setQuery('');
    expect(controller.suggestions.items, isEmpty);
  });

  test(
      'selecting a suggestion preserves filters and submits one canonical query',
      () async {
    final suggestions = SuggestionServiceStub();
    final api = SearchServiceStub();
    final controller = MarketplaceSearchController(
        service: api, suggestionService: suggestions);
    addTearDown(api.dispose);
    addTearDown(suggestions.dispose);
    addTearDown(controller.dispose);
    controller.setFilters(productType: 'card', printLanguage: 'japanese');
    api.responses.first.complete(searchPage([]));
    await Future<void>.delayed(Duration.zero);
    final selected = controller.selectSuggestion(pikachuSuggestion);
    expect(api.requests.last.query, 'Pikachu');
    expect(api.requests.last.printLanguage, 'japanese');
    expect(api.requests.last.productType, 'card');
    expect(controller.suggestions.items, isEmpty);
    api.responses.last.complete(searchPage(['24']));
    await selected;
    expect(controller.state.cards.single.id, '24');
  });

  for (final width in [320.0, 390.0, 900.0]) {
    testWidgets(
        'separate popup at width $width selects a name and submits search',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final suggestions = SuggestionServiceStub();
      final api = SearchServiceStub();
      final controller = MarketplaceSearchController(
          service: api, suggestionService: suggestions);
      addTearDown(api.dispose);
      addTearDown(suggestions.dispose);
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: MarketplaceSearch(
                  controller: controller,
                  discovery: const Text('Discovery'),
                  onOpen: (_) {}))));
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'pik');
      expect(suggestions.warm, isTrue);
      suggestions.replies.last.complete([pikachuSuggestion]);
      await tester.pump();
      expect(find.text('Suggerimenti'), findsOneWidget);
      expect(find.text('Pikachu'), findsOneWidget);
      await tester.tap(find.text('Pikachu'));
      await tester.pump();
      expect(find.text('Suggerimenti'), findsNothing);
      expect(api.requests.single.query, 'Pikachu');
      api.responses.single.complete(searchPage([]));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'local failure keeps server search usable and popup closes on clear',
      (tester) async {
    final suggestions = SuggestionServiceStub();
    final api = SearchServiceStub();
    final controller = MarketplaceSearchController(
        service: api, suggestionService: suggestions);
    addTearDown(api.dispose);
    addTearDown(suggestions.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MarketplaceSearch(
                controller: controller,
                discovery: const Text('Discovery'),
                onOpen: (_) {}))));
    await tester.enterText(find.byType(TextField), 'pikachu');
    suggestions.replies.last.completeError(StateError('Invalid dictionary'));
    await tester.pump(const Duration(milliseconds: 300));
    api.responses.single.complete(searchPage([]));
    await tester.pumpAndSettle();
    expect(controller.suggestions.hasError, isTrue);
    expect(controller.state.hasError, isFalse);
    await tester.tap(find.byTooltip('Cancella ricerca'));
    await tester.pumpAndSettle();
    expect(controller.suggestions.items, isEmpty);
    expect(controller.state.query, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
