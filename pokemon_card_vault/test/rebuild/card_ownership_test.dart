import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:pokoin/rebuild/controller/cardex_controller.dart';
import 'package:pokoin/rebuild/controller/card_details_controller.dart';
import 'package:pokoin/rebuild/controller/cart_controller.dart';
import 'package:pokoin/rebuild/model/cardex.dart';
import 'package:pokoin/rebuild/model/marketplace_home.dart';
import 'package:pokoin/rebuild/presentation/card_details/card_details.dart';
import 'package:pokoin/rebuild/presentation/cardex/cardex_screen.dart';
import 'package:pokoin/rebuild/presentation/cardex/atomics/album_card.dart';
import 'package:pokoin/rebuild/presentation/portfolio/portfolio_screen.dart';
import 'package:pokoin/rebuild/presentation/shared/atomics/collection_quantity_badge.dart';
import 'package:pokoin/rebuild/presentation/shared/atomics/marketplace_thumbnail.dart';
import 'package:pokoin/rebuild/presentation/shared/component/card_language_selector.dart';
import 'package:pokoin/rebuild/service/card_ownership_service.dart';
import 'package:pokoin/rebuild/service/card_service.dart';
import 'package:pokoin/rebuild/service/collection_service.dart';
import 'cardex_test.dart' as collection_fixtures;
import 'card_details_test.dart' as detail_fixtures;

const audino = MarketplaceCardPreview(
    id: '24', name: 'Audino', expansion: 'Obsidian Flames', number: '173/197');
OwnedCard copy(String language, int quantity,
        {String id = '24', bool reverse = false, String image = ''}) =>
    OwnedCard(
        card: MarketplaceCardPreview(
            id: id,
            name: 'Audino',
            expansion: 'Obsidian Flames',
            number: '173/197',
            imageUrl: image),
        quantity: quantity,
        language: language,
        reverse: reverse);
CardCollection owned() => CardCollection(
    status: CollectionStatus.ready, items: [copy('it', 2), copy('EN', 1)]);
Finder option(String code) => find.byWidgetPredicate(
    (widget) => widget is PopupMenuItem<String> && widget.value == code);

void main() {
  const service = CardOwnershipService();
  final capture = Platform.environment['OWNERSHIP_QA'] == '1';
  setUpAll(() async {
    if (!capture) return;
    for (final entry in {
      'OwnershipQA': 'C:/Windows/Fonts/segoeui.ttf',
      'Segoe UI Emoji': 'C:/Windows/Fonts/seguiemj.ttf',
      'MaterialIcons':
          'C:/Users/raffa/develop/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(entry.key)
            ..addFont(Future.value(
                ByteData.sublistView(await File(entry.value).readAsBytes()))))
          .load();
    }
  });

  test(
      'one print groups language aliases and finishes without losing any copies',
      () {
    final collection = CardCollection(status: CollectionStatus.ready, items: [
      copy('IT', 2),
      copy('Italian', 1, reverse: true),
      copy('it_IT', 3),
      copy('en-US', 4),
      copy('EN', 2),
      copy('JP', 1),
      copy('ja', 1),
      copy('', 2),
      copy('XX', 1),
      copy('IT', 0),
      copy('IT', 7, id: 'other-print'),
    ]);
    final view = service.describe(collection, '24');
    expect(collection.cards.length,
        2); // Other print/expansion is never name-merged.
    expect(view.total, 17);
    expect(view.languages.firstWhere((l) => l.code == 'IT').quantity, 6);
    expect(view.languages.firstWhere((l) => l.code == 'EN').quantity, 6);
    expect(view.languages.firstWhere((l) => l.code == 'JA').quantity, 2);
    expect(view.languages.firstWhere((l) => l.code == 'UND').quantity, 2);
    expect(view.languages.firstWhere((l) => l.code == 'XX').quantity, 1);
    expect(view.languages.firstWhere((l) => l.code == 'FR').owned, isFalse);
    expect(view.languages.map((l) => l.quantity).reduce((a, b) => a + b),
        view.total);
  });

  test(
      'selection prefers owned language; missing, unknown and unavailable remain distinct',
      () {
    final collection = owned();
    expect(
        service
            .describe(collection, '24', selectedLanguage: 'en')
            .selectedLanguage,
        'EN');
    expect(
        service
            .describe(collection, '24', selectedLanguage: 'FR')
            .selectedLanguage,
        'IT');
    final missing = service.describe(collection, 'missing');
    expect(missing.known, isTrue);
    expect(missing.selected, isNull);
    expect(missing.languages.every((l) => !l.owned), isTrue);
    for (final status in [
      CollectionStatus.guest,
      CollectionStatus.loading,
      CollectionStatus.unavailable
    ]) {
      final unknown = service.describe(
          CardCollection(status: status, items: collection.items), '24');
      expect(unknown.known, isFalse);
      expect(unknown.languages, isEmpty);
      expect(unknown.total, 0);
    }
  });

  test(
      'controller selection is read-only, rejects unowned languages and keeps total',
      () {
    final controller = CardexController()..collection = owned();
    addTearDown(controller.dispose);
    final original = controller.collection.items;
    controller.selectOwnedLanguage('24', 'EN');
    expect(controller.ownershipFor('24').selectedLanguage, 'EN');
    expect(controller.ownershipFor('24').selected!.quantity, 1);
    controller.selectOwnedLanguage('24', 'FR');
    expect(controller.ownershipFor('24').selectedLanguage, 'EN');
    expect(controller.collection.items, same(original));
    expect(controller.collection.copies, 3);
    expect(controller.collection.cards, hasLength(1));
  });

  test('selected artwork comes only from supplied same-language data', () {
    final collection = CardCollection(status: CollectionStatus.ready, items: [
      copy('IT', 1, image: 'https://cdn.pokoin.com/it.webp'),
      copy('EN', 2, image: 'https://cdn.pokoin.com/en.webp'),
    ]);
    final en = service.describe(collection, '24', selectedLanguage: 'EN');
    expect(en.selected!.preview!.imageUrl, 'https://cdn.pokoin.com/en.webp');
    final noImage = service.describe(owned(), '24', selectedLanguage: 'EN');
    expect(noImage.selected!.preview!.imageUrl, isEmpty);
  });

  test('account changes clear selected languages and private ownership',
      () async {
    final provider = collection_fixtures.AccountSource();
    final controller =
        CardexController(collection: CollectionService(provider: provider));
    controller.start(loadCatalog: false);
    provider.users.add('alice');
    await collection_fixtures.flush();
    provider.records['alice']!.add(owned().items);
    await collection_fixtures.flush();
    controller.selectOwnedLanguage('24', 'EN');
    expect(controller.ownershipFor('24').selectedLanguage, 'EN');
    provider.users.add(null);
    await collection_fixtures.flush();
    expect(controller.ownershipFor('24').known, isFalse);
    expect(controller.ownershipFor('24').languages, isEmpty);
    provider.users.add('bob');
    await collection_fixtures.flush();
    provider.records['bob']!.add(owned().items);
    await collection_fixtures.flush();
    expect(controller.ownershipFor('24').selectedLanguage, 'IT');
    controller.dispose();
    await provider.close();
  });

  for (final scenario in [
    (width: 390.0, scale: 1.0),
    (width: 320.0, scale: 2.0),
    (width: 900.0, scale: 1.0)
  ]) {
    testWidgets(
        'corner flag keeps one card and grey disabled languages at ${scenario.width}/${scenario.scale}',
        (tester) async {
      tester.view.physicalSize = Size(scenario.width, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = CardexController()..collection = owned();
      addTearDown(controller.dispose);
      var opened = 0;
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
              theme: ThemeData(
                  brightness: Brightness.dark,
                  useMaterial3: true,
                  fontFamily: capture ? 'OwnershipQA' : null),
              home: MediaQuery(
                  data: MediaQueryData(
                      size: Size(scenario.width, 1600),
                      textScaler: TextScaler.linear(scenario.scale)),
                  child: Scaffold(
                      body: CardexScreen(
                          controller: controller, onOpen: (_) => opened++))))));
      await tester.pumpAndSettle();
      expect(find.byType(AlbumCard), findsOneWidget);
      expect(find.text('Audino'), findsNothing);
      expect(find.text('173/197 · Obsidian Flames'), findsOneWidget);
      expect(find.byType(CollectionQuantityBadge), findsOneWidget);
      expect(find.text('×3'), findsOneWidget);
      expect(find.text('Posseduta · ×3'), findsNothing);
      expect(tester.getRect(find.byType(CardLanguageSelector)).bottom,
          lessThan(tester.getRect(find.byType(CollectionQuantityBadge)).top));
      if (scenario.width == 390) {
        final grid = tester.widget<GridView>(find.byType(GridView).first);
        expect(
            (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
                .crossAxisCount,
            2);
      }
      expect(tester.takeException(), isNull);
      Future<void> snapshot(String suffix) async {
        if (!capture || scenario.width != 390) return;
        await tester.runAsync(() async {
          final renderer = boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final picture = await renderer.toImage(pixelRatio: 1);
          final bytes =
              await picture.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('build/card-ownership-preview')
            ..createSync(recursive: true);
          await File('${directory.path}/$suffix.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }

      await snapshot('album');
      await tester.tap(find.byTooltip('Lingue possedute di Audino'));
      await tester.pumpAndSettle();
      expect(opened, 0);
      expect(
          tester.widget<PopupMenuItem<String>>(option('FR')).enabled, isFalse);
      expect(
          find.descendant(
              of: option('FR'), matching: find.byType(ColorFiltered)),
          findsOneWidget);
      final greyLabel = tester.widget<Text>(
          find.descendant(of: option('FR'), matching: find.text('Francese')));
      expect(greyLabel.style!.color, const Color(0xFF909090));
      expect(
          tester.widget<PopupMenuItem<String>>(option('EN')).enabled, isTrue);
      expect(tester.takeException(), isNull);
      await snapshot('language-menu');
      await tester.tap(option('FR'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(controller.ownershipFor('24').selectedLanguage, 'IT');
      await tester.ensureVisible(option('EN'));
      await tester.tap(option('EN'));
      await tester.pumpAndSettle();
      expect(controller.ownershipFor('24').selectedLanguage, 'EN');
      expect(find.byType(AlbumCard), findsOneWidget);
      expect(find.text('×3'), findsOneWidget);
      expect(find.byType(PopupMenuItem<String>), findsNothing);
      expect(opened, 0);
      await tester.tap(find.byType(AlbumCard));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'Portfolio shares language selection and still has a single thumbnail',
      (tester) async {
    final controller = CardexController()..collection = owned();
    addTearDown(controller.dispose);
    controller.selectOwnedLanguage('24', 'EN');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PortfolioScreen(controller: controller, onOpen: (_) {}))));
    await tester.pumpAndSettle();
    expect(find.byType(AlbumCard), findsOneWidget);
    expect(
        tester
            .widget<CardLanguageSelector>(find.byType(CardLanguageSelector))
            .ownership
            .selectedLanguage,
        'EN');
    expect(find.text('1 carte diverse · 3 copie'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'collection detail has corner flag, retains total and makes no extra requests on selection',
      (tester) async {
    var requests = 0;
    final remote = CardService(client: MockClient((request) async {
      requests++;
      return detail_fixtures.response(request.url.path.endsWith('card-page')
          ? {
              'card': {...detail_fixtures.cardJson, 'name': 'Audino'}
            }
          : {'listings': []});
    }));
    addTearDown(remote.dispose);
    final collection = CardexController()..collection = owned();
    addTearDown(collection.dispose);
    final cart = CartController();
    addTearDown(cart.dispose);
    await tester.pumpWidget(MaterialApp(
        home: CardDetails(
            preview: audino,
            controller: CardDetailsController(cardId: '24', service: remote),
            ownershipController: collection,
            cart: cart)));
    await tester.pumpAndSettle();
    expect(find.byType(CardLanguageSelector), findsOneWidget);
    expect(find.text('×3'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.byTooltip('Lingue possedute di Audino'), 160,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byTooltip('Lingue possedute di Audino'));
    await tester.pumpAndSettle();
    await tester.tap(option('EN'));
    await tester.pumpAndSettle();
    expect(collection.ownershipFor('24').selectedLanguage, 'EN');
    expect(find.text('×3'), findsOneWidget);
    expect(requests, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'unknown ownership never shows missing-language flags or quantity badges',
      (tester) async {
    final controller = CardexController()
      ..cards = [audino]
      ..collectionAlbum = false
      ..collection = CardCollection(status: CollectionStatus.unavailable);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CardexScreen(controller: controller, onOpen: (_) {}))));
    await tester.pumpAndSettle();
    expect(find.byType(CardLanguageSelector), findsNothing);
    expect(find.byType(CollectionQuantityBadge), findsNothing);
    expect(find.byType(MarketplaceThumbnail), findsOneWidget);
    expect(find.text('Catalogo'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
