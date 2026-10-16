import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/rebuild/controller/marketplace_search_controller.dart';
import 'package:pokoin/rebuild/model/marketplace_home.dart';
import 'package:pokoin/rebuild/model/marketplace_search.dart';
import 'package:pokoin/rebuild/service/marketplace_search_service.dart';

class SearchServiceStub extends MarketplaceSearchService {
  final requests = <MarketplaceSearchRequest>[];
  final responses = <Completer<MarketplaceSearchPage>>[];
  bool wasDisposed = false;
  @override
  Future<MarketplaceSearchPage> search(MarketplaceSearchRequest request) {
    requests.add(request);
    final response = Completer<MarketplaceSearchPage>();
    responses.add(response);
    return response.future;
  }

  @override
  void dispose() {
    wasDisposed = true;
    super.dispose();
  }
}

MarketplaceSearchPage searchPage(List<String> ids,
        {bool hasMore = false, int? total}) =>
    MarketplaceSearchPage(cards: [
      for (final id in ids)
        MarketplaceCardPreview(id: id, name: 'Carta $id', expansion: '151')
    ], hasMore: hasMore, total: total);

void main() {
  testWidgets(
      'debounces typing and clearing invalidates late results and errors',
      (tester) async {
    final service = SearchServiceStub();
    final controller = MarketplaceSearchController(service: service);
    addTearDown(service.dispose);
    addTearDown(controller.dispose);
    controller.setQuery('Pika');
    await tester.pump(const Duration(milliseconds: 200));
    controller.setQuery('Pikachu');
    await tester.pump(const Duration(milliseconds: 299));
    expect(service.requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(service.requests.single.query, 'Pikachu');
    controller.setQuery('Mew');
    await tester.pump(const Duration(milliseconds: 300));
    service.responses.last.complete(searchPage(['48']));
    await tester.pump();
    service.responses.first.completeError(StateError('Late failure'));
    await tester.pump();
    expect(controller.state.cards.single.id, '48');
    expect(controller.state.hasError, isFalse);
    controller.setQuery('Umbreon');
    await tester.pump(const Duration(milliseconds: 300));
    controller.setQuery('');
    service.responses.last.complete(searchPage(['72']));
    await tester.pump();
    expect(controller.state.isActive, isFalse);
    expect(controller.state.cards, isEmpty);
  });

  test('pagination coalesces taps, deduplicates IDs, retries the same offset',
      () async {
    final service = SearchServiceStub();
    final controller = MarketplaceSearchController(service: service);
    addTearDown(service.dispose);
    addTearDown(controller.dispose);
    controller.setQuery('Pikachu');
    final first = controller.submit();
    service.responses.first.complete(searchPage(['24', '48'], hasMore: true));
    await first;
    expect(controller.state.total, isNull);
    final more = controller.loadMore();
    await controller.loadMore();
    expect(service.requests.map((r) => r.offset), [0, 24]);
    service.responses.last.completeError(StateError('Offline'));
    await more;
    expect(controller.state.cards.map((c) => c.id), ['24', '48']);
    expect(controller.state.hasError, isTrue);
    final retry = controller.retry();
    expect(service.requests.last.offset, 24);
    service.responses.last.complete(searchPage(['48', '72']));
    await retry;
    expect(controller.state.cards.map((c) => c.id), ['24', '48', '72']);
    expect(controller.state.hasMore, isFalse);
  });

  test(
      'filters invalidate previous pages and disposal ignores pending responses',
      () async {
    final service = SearchServiceStub();
    final controller = MarketplaceSearchController(service: service);
    addTearDown(service.dispose);
    controller.setQuery('Pikachu');
    final first = controller.submit();
    controller.setFilters(productType: 'card', printLanguage: 'japanese');
    expect(service.requests.last.offset, 0);
    expect(service.requests.last.printLanguage, 'japanese');
    service.responses.first.complete(searchPage(['24']));
    await first;
    expect(controller.state.cards, isEmpty);
    controller.dispose();
    service.responses.last.completeError(StateError('Late failure'));
    await Future<void>.delayed(Duration.zero);
    expect(service.wasDisposed, isFalse);
  });

  test('initial failure remains retryable', () async {
    final service = SearchServiceStub();
    final controller = MarketplaceSearchController(service: service);
    addTearDown(service.dispose);
    addTearDown(controller.dispose);
    controller.setQuery('Pikachu');
    final first = controller.submit();
    service.responses.first.completeError(StateError('Offline'));
    await first;
    expect(controller.state.hasError, isTrue);
    final retry = controller.retry();
    service.responses.last.complete(searchPage([]));
    await retry;
    expect(controller.state.hasError, isFalse);
    expect(controller.state.cards, isEmpty);
    expect(controller.state.isLoading, isFalse);
  });

  test('unknown server total clears the previous count after a refresh',
      () async {
    final service = SearchServiceStub();
    final controller = MarketplaceSearchController(service: service);
    addTearDown(service.dispose);
    addTearDown(controller.dispose);
    controller.setQuery('Pikachu');
    final first = controller.submit();
    service.responses.first.complete(searchPage(['24'], total: 42));
    await first;
    expect(controller.state.total, 42);
    final refresh = controller.submit();
    service.responses.last.complete(searchPage(['24']));
    await refresh;
    expect(controller.state.total, isNull);
  });
}
