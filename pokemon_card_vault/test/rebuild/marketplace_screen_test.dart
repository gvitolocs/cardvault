import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/rebuild/controller/marketplace_controller.dart';
import 'package:pokoin/rebuild/presentation/shared/component/marketplace_cart_sheet.dart';
import 'package:pokoin/rebuild/model/demo_catalog.dart';
import 'package:pokoin/rebuild/presentation/marketplace/marketplace_screen.dart';
import 'package:pokoin/rebuild/presentation/card_details/card_details.dart';
import 'package:pokoin/rebuild/service/card_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('grid and filtered cards open CardDetails without demo API calls',
      (tester) async {
    var requests = 0;
    final service = CardService(client: MockClient((_) async {
      requests++;
      return http.Response('{}', 404);
    }));
    final controller = MarketplaceController(cardService: service);
    addTearDown(service.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: MarketplaceScreen(controller: controller, showDiscovery: false)));
    for (final query in ['', 'Pikachu']) {
      controller.setSearchQuery(query);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Pikachu ex'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pikachu ex'));
      await tester.pumpAndSettle();
      expect(find.byType(CardDetails), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Prezzo di esempio: 24,90 €'), findsOneWidget);
      expect(find.text('Carta demo · dati di esempio'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(controller.searchQuery, query);
    }
    expect(requests, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('cart sheet reacts to additions and removal while open',
      (tester) async {
    final controller = MarketplaceController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: MarketplaceScreen(controller: controller, showDiscovery: false),
    ));
    await tester.tap(find.byTooltip('Carrello, 0 articoli'));
    await tester.pumpAndSettle();
    expect(find.byType(MarketplaceCartSheet), findsOneWidget);
    expect(find.text('Il tuo carrello è vuoto. Esplora le carte!'),
        findsOneWidget);
    controller.cart.addCard(demoCards.first);
    controller.cart.addCard(demoCards.first);
    await tester.pumpAndSettle();
    expect(find.text('2 × 24,90 €'), findsOneWidget);
    expect(find.text('Totale di esempio: 49,80 €'), findsOneWidget);
    await tester.tap(find.byTooltip('Rimuovi Pikachu ex'));
    await tester.pumpAndSettle();
    expect(controller.cart.itemCount, 0);
    expect(find.text('Il tuo carrello è vuoto. Esplora le carte!'),
        findsOneWidget);
    expect(find.text('Totale di esempio: 49,80 €'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'binds search input in both directions and clears through controller',
      (tester) async {
    final controller = MarketplaceController()..setSearchQuery('Pikachu');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: MarketplaceScreen(controller: controller, showDiscovery: false),
    ));
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Pikachu');
    await tester.enterText(find.byType(TextField), 'Umbreon');
    expect(controller.visibleCards.single.id, 'demo-3');
    controller.setSearchQuery('205/165');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '205/165');
    await tester.tap(find.byTooltip('Cancella ricerca'));
    await tester.pumpAndSettle();
    expect(controller.searchQuery, isEmpty);
    expect(controller.visibleCards, hasLength(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'switches injected controllers and leaves their lifecycle to owner',
      (tester) async {
    final first = MarketplaceController()..setSearchQuery('Pikachu');
    final second = MarketplaceController()..setSearchQuery('Mew');
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Widget screen(MarketplaceController controller) => MaterialApp(
          home: MarketplaceScreen(controller: controller, showDiscovery: false),
        );
    await tester.pumpWidget(screen(first));
    await tester.pumpWidget(screen(second));
    first.setSearchQuery('Umbreon');
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Mew');
    await tester.pumpWidget(const SizedBox.shrink());
    // Rimuovere lo screen scollega le subscription, senza disporre il controller.
    second.setSearchQuery('Pikachu');
    second.cart.addCard(demoCards.first);
    expect(second.cart.itemCount, 1);
    expect(tester.takeException(), isNull);
  });
}
