import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/rebuild/controller/cart_controller.dart';
import 'package:pokoin/rebuild/main_mobile_prototype.dart';
import 'package:pokoin/rebuild/model/cart_item.dart';
import 'package:pokoin/rebuild/model/account.dart';
import 'package:pokoin/rebuild/presentation/marketplace/marketplace_screen.dart';
import 'package:pokoin/rebuild/presentation/shared/component/marketplace_cart_sheet.dart';
import 'package:pokoin/rebuild/service/cart_service.dart';
import 'package:pokoin/rebuild/service/account_service.dart';
import 'package:pokoin/rebuild/provider/cart_codec.dart';
import 'fixtures/cart_fixtures.dart';
import 'fixtures/account_fixtures.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets(
        'restored cart edits and clears at ${width}px with enlarged text',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final local = MemoryCartLocal()
        ..saved[null] =
            CartSnapshot(items: [cartRow('a', quantity: 2, stock: 3)]);
      final service = CartService(local: local);
      final controller = CartController(service: service);
      addTearDown(service.dispose);
      addTearDown(controller.dispose);
      await service.loadForUser(null);
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 844),
                  textScaler: const TextScaler.linear(2)),
              child: Scaffold(
                  body: MarketplaceCartSheet(controller: controller)))));
      await tester.pumpAndSettle();
      expect(find.text('Carrello ospite · salvato su questo dispositivo'),
          findsOneWidget);
      expect(find.text('2 × 120,00 PKN'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Aumenta Carta vera'));
      await tester.tap(find.byTooltip('Aumenta Carta vera'));
      await tester.pumpAndSettle();
      expect(service.listingQuantity('a'), 3);
      expect(
          tester
              .widget<IconButton>(find.byWidgetPredicate((widget) =>
                  widget is IconButton &&
                  widget.tooltip == 'Aumenta Carta vera'))
              .onPressed,
          isNull);
      await tester.tap(find.byTooltip('Diminuisci Carta vera'));
      await tester.pumpAndSettle();
      expect(local.saved[null]!.items.single.quantity, 2);
      await tester.ensureVisible(find.text('Svuota carrello'));
      await tester.tap(find.text('Svuota carrello'));
      await tester.pumpAndSettle();
      expect(find.text('Il tuo carrello è vuoto. Esplora le carte!'),
          findsOneWidget);
      expect(local.saved[null]!.items, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'read failure is visible and retry restores rows without editing a missing snapshot',
      (tester) async {
    final local = MemoryCartLocal()
      ..failRead = true
      ..saved[null] = CartSnapshot(items: [cartRow('a')]);
    final service = CartService(local: local);
    final controller = CartController(service: service);
    addTearDown(service.dispose);
    addTearDown(controller.dispose);
    await service.loadForUser(null);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: MarketplaceCartSheet(controller: controller))));
    expect(find.text('Riprova carrello'), findsOneWidget);
    expect(
        find.text('Il tuo carrello è vuoto. Esplora le carte!'), findsNothing);
    expect(find.text('Carrello ospite · salvato su questo dispositivo'),
        findsNothing);
    local.failRead = false;
    await tester.tap(find.text('Riprova carrello'));
    await tester.pumpAndSettle();
    expect(find.text('Carta vera'), findsOneWidget);
    expect(find.text('Riprova carrello'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'application cart uses the account gate session and switches an open sheet',
      (tester) async {
    final accountProvider = FakeAccountProvider(guest: true);
    final local = MemoryCartLocal()
      ..saved[null] = CartSnapshot(items: [cartRow('guest')]);
    final remote = MemoryCartRemote()
      ..saved['alice'] = [CartCodec.encodeItem(cartRow('alice', quantity: 2))]
      ..saved['bob'] = [CartCodec.encodeItem(cartRow('bob', quantity: 3))];
    final service = CartService(local: local, remote: remote);
    addTearDown(service.dispose);
    addTearDown(accountProvider.close);
    await tester.pumpWidget(MobileMarketplacePrototypeApp(
        showDiscovery: false,
        accountService: AccountService(provider: accountProvider),
        cartService: service));
    await tester.pumpAndSettle();
    final market =
        tester.widget<MarketplaceScreen>(find.byType(MarketplaceScreen));
    expect(market.controller.cart.listingItems.single.listing.id, 'guest');
    accountProvider.emit(const AccountUser(
        id: 'alice', email: 'a@example.test', displayName: 'Alice'));
    await tester.pumpAndSettle();
    expect(market.controller.cart.listingItems.single.listing.id, 'alice');
    expect(find.byTooltip('Carrello, 2 articoli'), findsOneWidget);
    await tester.tap(find.byTooltip('Carrello, 2 articoli'));
    await tester.pumpAndSettle();
    accountProvider.emit(const AccountUser(
        id: 'bob', email: 'b@example.test', displayName: 'Bob'));
    await tester.pumpAndSettle();
    expect(find.byType(MarketplaceCartSheet), findsOneWidget);
    expect(market.controller.cart.listingItems.single.listing.id, 'bob');
    expect(find.text('3 × 120,00 PKN'), findsOneWidget);
    expect(local.saved[null]!.items.single.listing.id, 'guest');
    expect(remote.writes, isEmpty);
    await market.controller.account.signOut();
    await tester.pumpAndSettle();
    expect(find.byType(MarketplaceCartSheet), findsNothing);
    expect(market.controller.cart.listingItems.single.listing.id, 'guest');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
