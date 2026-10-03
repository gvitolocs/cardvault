import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Test the real widgets from a Flutter-only harness without Windows native hooks.
// ignore: avoid_relative_lib_imports
import '../lib/widgets/marketplace_cart_navigation.dart';
// ignore: avoid_relative_lib_imports
import '../lib/widgets/marketplace_mobile_listing.dart';

void main() {
  for (final width in [260.0, 320.0, 390.0, 600.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('offer cart action fits width $width at text scale $scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var tapped = 0;
        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(22),
              children: [
                MarketplaceMobileListingLayout(
                  seller: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('pkhreserve long seller name',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('IT ★ pkhreserve',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                  product: const Wrap(
                    spacing: 5,
                    children: [
                      Text('NM'),
                      Text('JP'),
                      Text('RES'),
                      Text('GRD')
                    ],
                  ),
                  price: const Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('22 PKN',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text('3 avail.',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                  actions: Row(
                    children: [
                      Expanded(
                        child: MarketplaceListingCartButton(
                          inCart: false,
                          onPressed: () => tapped++,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 40,
                        child: IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.token),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ));
        final button = find.byType(FilledButton);
        expect(find.text('Aggiungi al carrello').hitTestable(), findsOneWidget);
        final bounds = tester.getRect(button);
        expect(bounds.left, greaterThanOrEqualTo(22));
        expect(bounds.right, lessThanOrEqualTo(width - 22));
        expect(bounds.height, greaterThanOrEqualTo(48));
        expect(find.byType(SingleChildScrollView), findsNothing);
        await tester.tap(button);
        expect(tapped, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('offer button updates from add to remove after a tap',
      (tester) async {
    var inCart = false;
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => MarketplaceListingCartButton(
            inCart: inCart,
            onPressed: () => setState(() {
              inCart = !inCart;
              tapped++;
            }),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Aggiungi al carrello'));
    await tester.pump();
    expect(find.text('Rimuovi dal carrello').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Rimuovi dal carrello'));
    await tester.pump();
    expect(find.text('Aggiungi al carrello'), findsOneWidget);
    expect(tapped, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable offer button is disabled', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: MarketplaceListingCartButton(inCart: false, onPressed: null),
      ),
    ));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
  });

  testWidgets('owner action fits without exposing a purchase button',
      (tester) async {
    var managed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 216,
          child: MarketplaceMobileListingLayout(
            seller: const Text('My shop'),
            product: const Text('NM · JP'),
            price: const Text('22 PKN'),
            actions: Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Manage listing',
                onPressed: () => managed = true,
                icon: const Icon(Icons.more_horiz),
              ),
            ),
          ),
        ),
      ),
    ));
    expect(find.byType(MarketplaceListingCartButton), findsNothing);
    await tester.tap(find.byTooltip('Manage listing'));
    expect(managed, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0, 600.0]) {
    testWidgets('utility bar retains four destinations at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tapped = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          bottomNavigationBar: MarketplaceUtilityBar(
            onSearch: () => tapped.add('search'),
            onScanner: () => tapped.add('scanner'),
            onListings: () => tapped.add('listings'),
            onProfile: () => tapped.add('profile'),
          ),
        ),
      ));
      expect(find.text('Carrello'), findsNothing);
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      for (final label in ['Ricerca', 'Scanner', 'Elenco', 'Profilo']) {
        await tester.tap(find.text(label));
        await tester.pump();
      }
      expect(tapped, ['search', 'scanner', 'listings', 'profile']);
      expect(tester.takeException(), isNull);
    });
  }
}
