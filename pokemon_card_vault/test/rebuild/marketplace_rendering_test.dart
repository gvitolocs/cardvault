import 'fixtures/cart_fixtures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/rebuild/main_mobile_prototype.dart';
import 'package:pokoin/rebuild/presentation/shared/atomics/card_illustration.dart';
import 'fixtures/account_fixtures.dart';

void main() {
  testWidgets('Scrolling reuses already built card illustrations',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MobileMarketplacePrototypeApp(
        cartService: memoryCartService(),
        showDiscovery: false,
        accountService: guestAccountService()));
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    // Warm both rows before measuring: newly entering cards may build once.
    scroll.position.jumpTo(150);
    await tester.pumpAndSettle();
    expect(find.byType(CardIllustration), findsWidgets);
    var rebuilds = 0;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (element.widget is CardIllustration) {
        rebuilds++;
      }
    };
    try {
      for (var frame = 1; frame <= 20; frame++) {
        scroll.position.jumpTo(150 + frame * 5);
        await tester.pump(const Duration(milliseconds: 16));
      }
    } finally {
      debugOnRebuildDirtyWidget = null;
    }
    expect(scroll.position.pixels, 250);
    expect(rebuilds, 0,
        reason: 'Scrolling must not rebuild existing card illustrations');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Adding to cart updates its badge without rebuilding cards',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MobileMarketplacePrototypeApp(
        cartService: memoryCartService(),
        showDiscovery: false,
        accountService: guestAccountService()));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byTooltip('Aggiungi al carrello demo').first);
    await tester.pumpAndSettle();
    expect(find.byType(CardIllustration), findsWidgets);
    var rebuilds = 0;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (element.widget is CardIllustration) {
        rebuilds++;
      }
    };
    try {
      await tester.tap(find.byTooltip('Aggiungi al carrello demo').first);
      await tester.pumpAndSettle();
    } finally {
      debugOnRebuildDirtyWidget = null;
    }
    expect(find.byTooltip('Carrello, 1 articoli'), findsOneWidget);
    expect(rebuilds, 0,
        reason: 'Cart changes must only update subscribed cart UI');
    expect(tester.takeException(), isNull);
  });
}
