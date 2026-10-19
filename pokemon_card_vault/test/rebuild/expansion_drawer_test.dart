import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/rebuild/controller/cardex_controller.dart';
import 'package:pokoin/rebuild/constants/expansion_era_constants.dart';
import 'package:pokoin/rebuild/controller/marketplace_controller.dart';
import 'package:pokoin/rebuild/model/cardex.dart';
import 'package:pokoin/rebuild/model/marketplace_home.dart';
import 'package:pokoin/rebuild/presentation/cardex/cardex_screen.dart';
import 'package:pokoin/rebuild/presentation/marketplace/marketplace_screen.dart';
import 'package:pokoin/rebuild/presentation/shared/component/expansion_drawer.dart';
import 'package:pokoin/rebuild/provider/collection_provider.dart';
import 'package:pokoin/rebuild/service/cardex_service.dart';
import 'package:pokoin/rebuild/service/collection_service.dart';
import 'package:pokoin/rebuild/service/expansion_era_service.dart';

MarketplaceExpansion set(String name, String slug) =>
    MarketplaceExpansion(name: name, slug: slug, cardCount: 100);
final base = set('Base Set', 'base-set');
final dark = set('Dark Explorers', 'dark-explorers');
final future = set('Unknown Future Set', 'unknown-future-set');

class GuestCollection extends CollectionProvider {
  @override
  Stream<String?> watchUserId() => Stream.value(null);
}

class DrawerCatalog extends CardexService {
  int calls = 0;
  bool fail = false;
  Completer<List<MarketplaceExpansion>>? held;
  final loaded = <String>[];
  @override
  Future<List<MarketplaceExpansion>> loadExpansions() async {
    calls++;
    if (held != null) return held!.future;
    if (fail) throw StateError('Offline');
    return [base, dark, future];
  }

  @override
  Future<CardexPage> loadPage(String slug, {int offset = 0}) async {
    loaded.add(slug);
    return CardexPage(
        expansion: [base, dark, future].firstWhere((e) => e.slug == slug),
        cards: const [],
        offset: offset,
        hasMore: false,
        total: 100);
  }
}

void main() {
  test('era titles are shared immutable constants and preserve fallback labels',
      () {
    expect(expansionEraTitles['Original'], 'Rosso, Blu e Giallo');
    expect(expansionEraTitles['Black & White'], 'Bianco e Nero');
    expect(expansionEraTitles[otherExpansionEraId], 'Altre espansioni');
    expect(ExpansionEraService.other, otherExpansionEraId);
    expect(() => expansionEraTitles['Original'] = 'Changed',
        throwsUnsupportedError);
    final groups = ExpansionEraService().group([base, dark, future]);
    for (final group in groups) {
      expect(group.title, expansionEraTitles[group.id]);
    }
    final fallback =
        ExpansionEraService().group([set('Aquapolis', 'aquapolis')]).single;
    expect(fallback.title, 'e-Card');
  });
  test(
      'shared catalog groups exact sets, Japanese names and editorial variants',
      () {
    final service = ExpansionEraService();
    for (final entry in {
      'Base Set': 'Original',
      'Base Set Shadowless': 'Original',
      'Base Set 2': 'Original',
      'Dark Explorers': 'Black & White',
      'Dark Explorers Promos': 'Black & White',
      'Dark Rush': 'Black & White',
      'Darkness Ablaze': 'Sword & Shield',
      'Expedition Base Set': 'e-Card',
      'Neo Genesis': 'Neo',
      'EX Ruby & Sapphire': 'EX',
      'Scarlet and Violet': 'Scarlet & Violet',
      'Unknown Future Set': ExpansionEraService.other,
      'Not Really Base Set': ExpansionEraService.other,
    }.entries) {
      expect(service.eraFor(set(entry.key, entry.key)), entry.value,
          reason: entry.key);
    }
  });

  test(
      'groups retain every API slug once, search era or set and never synthesize expansions',
      () {
    final service = ExpansionEraService();
    final groups = service.group([base, dark, future, dark]);
    expect(groups.expand((g) => g.expansions).map((e) => e.slug).toSet(),
        {'base-set', 'dark-explorers', 'unknown-future-set'});
    expect(groups.last.id, ExpansionEraService.other);
    expect(
        service.filter(groups, 'Bianco e Nero').single.expansions.single.slug,
        dark.slug);
    expect(service.filter(groups, 'black white').single.id, 'Black & White');
    expect(
        service.filter(groups, 'DARK EXPLORERS').single.expansions.single.slug,
        dark.slug);
    expect(service.filter(groups, 'inesistente'), isEmpty);
    expect(() => groups.first.expansions.clear(), throwsUnsupportedError);
  });

  testWidgets(
      'drawer starts with eras collapsed, nests sets, searches and handles empty results',
      (tester) async {
    final catalog = DrawerCatalog();
    final controller = CardexController(catalog: catalog);
    addTearDown(catalog.dispose);
    addTearDown(controller.dispose);
    await controller.loadExpansions();
    MarketplaceExpansion? selected;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ExpansionDrawer(
                controller: controller,
                onSelect: (value) => selected = value,
                onCollection: () {},
                onClose: () {}))));
    await tester.pumpAndSettle();
    expect(find.text('Dark Explorers'), findsNothing);
    expect(find.text('Base Set'), findsNothing);
    await tester.tap(find.text('Bianco e Nero'));
    await tester.pumpAndSettle();
    expect(find.text('Dark Explorers'), findsOneWidget);
    expect(find.text('Base Set'), findsNothing);
    await tester.tap(find.text('Dark Explorers'));
    expect(selected?.slug, dark.slug);
    await tester.enterText(find.byType(TextField), 'rosso');
    await tester.pumpAndSettle();
    expect(find.text('Base Set'), findsOneWidget);
    expect(find.text('Dark Explorers'), findsNothing);
    await tester.enterText(find.byType(TextField), 'non esiste');
    await tester.pumpAndSettle();
    expect(find.text('Nessuna espansione trovata.'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancella filtro espansioni'));
    await tester.pumpAndSettle();
    expect(controller.expansionQuery, isEmpty);
    expect(find.text('Bianco e Nero'), findsOneWidget);
  });

  testWidgets(
      'drawer loading and errors retry without changing the selected album',
      (tester) async {
    final catalog = DrawerCatalog()..held = Completer();
    final controller = CardexController(catalog: catalog);
    addTearDown(catalog.dispose);
    addTearDown(controller.dispose);
    final loading = controller.loadExpansions();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ExpansionDrawer(
                controller: controller,
                onSelect: (_) {},
                onCollection: () {},
                onClose: () {}))));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    catalog.held!.completeError(StateError('Offline'));
    await loading;
    await tester.pumpAndSettle();
    expect(find.text('Impossibile caricare le espansioni.'), findsOneWidget);
    catalog.held = null;
    await tester.tap(find.text('Riprova espansioni'));
    await tester.pumpAndSettle();
    expect(catalog.calls, 2);
    expect(find.text('Bianco e Nero'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
        'global header opens right drawer and navigates to Cardex at 320px / $scale text',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final catalog = DrawerCatalog();
      final cardex = CardexController(
          catalog: catalog,
          collection: CollectionService(provider: GuestCollection()));
      final controller = MarketplaceController(cardexController: cardex);
      addTearDown(catalog.dispose);
      addTearDown(cardex.dispose);
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home:
              MarketplaceScreen(controller: controller, showDiscovery: false)));
      expect(
          tester.getCenter(find.byTooltip('Espansioni per era')).dx,
          greaterThan(
              tester.getCenter(find.byTooltip('Carrello, 0 articoli')).dx));
      await tester.tap(find.byTooltip('Espansioni per era'));
      await tester.pumpAndSettle();
      expect(catalog.calls, 1);
      final drawer = find.byType(ExpansionDrawer);
      final search =
          find.descendant(of: drawer, matching: find.byType(TextField));
      await tester.enterText(search, 'dark explorers');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Dark Explorers'));
      await tester.tap(find.text('Dark Explorers'));
      await tester.pumpAndSettle();
      expect(controller.selectedTab, 3);
      expect(cardex.expansion?.slug, dark.slug);
      expect(cardex.collectionAlbum, isFalse);
      expect(find.byType(CardexScreen), findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.text('Dark Explorers'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Espansioni per era'));
      await tester.pumpAndSettle();
      expect(catalog.calls, 1);
      await tester.tap(find.byTooltip('Chiudi espansioni'));
      await tester.pumpAndSettle();
      expect(cardex.expansion?.slug, dark.slug);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
