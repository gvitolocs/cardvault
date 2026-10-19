import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:pokoin/rebuild/presentation/card_details/component/listing_details.dart';
import 'package:pokoin/rebuild/presentation/card_details/component/card_listing_composer.dart';
import 'package:pokoin/rebuild/controller/card_details_controller.dart';
import 'package:pokoin/rebuild/controller/cart_controller.dart';
import 'package:pokoin/rebuild/model/marketplace_home.dart';
import 'package:pokoin/rebuild/presentation/card_details/card_details.dart';
import 'package:pokoin/rebuild/service/card_service.dart';
import 'card_details_test.dart' as fixtures;

void main() {
  final capture = Platform.environment['CARD_DETAILS_QA'] == '1';
  setUpAll(() async {
    final fontPath = Platform.environment['CARD_DETAILS_QA_FONT'];
    if (capture && fontPath != null) {
      final loader = FontLoader('DetailQA')
        ..addFont(Future.value(
            ByteData.sublistView(await File(fontPath).readAsBytes())));
      await loader.load();
    }
    final iconsPath = Platform.environment['CARD_DETAILS_QA_ICONS'];
    if (capture && iconsPath != null) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(
            ByteData.sublistView(await File(iconsPath).readAsBytes())));
      await loader.load();
    }
  });

  for (final scenario in [
    (width: 320.0, height: 640.0, scale: 2.0),
    (width: 390.0, height: 844.0, scale: 1.0),
    (width: 768.0, height: 1024.0, scale: 1.0),
    (width: 1320.0, height: 900.0, scale: 1.0),
  ]) {
    testWidgets(
        'details fit ${scenario.width}px at ${scenario.scale}x through all panels',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(scenario.width, scenario.height);
      tester.platformDispatcher.textScaleFactorTestValue = scenario.scale;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      var requests = 0;
      final service = CardService(client: MockClient((request) async {
        requests++;
        if (request.url.path == '/api/marketplace-listings') {
          return fixtures.response({
            'listings': [
              {
                ...fixtures.offerJson('live-a', price: 78, condition: 'MP'),
                'sellerName': 'redshakkio'
              },
              {
                ...fixtures.offerJson('live-b', price: 190),
                'sellerName': 'Card Garden'
              },
              {
                ...fixtures.offerJson('live-c',
                    price: 220, condition: 'SP', language: 'EN'),
                'sellerName': 'TCG Corner'
              },
            ]
          });
        }
        expect(request.url.path, '/api/marketplace-card-page');
        return fixtures.response({
          'card': {
            ...fixtures.cardJson,
            'name': scenario.scale == 2
                ? 'Mega Charizard ex versione speciale'
                : 'Caterpie',
            'set': 'HeartGold & SoulSilver',
            'number': '057/123',
            'artist': 'Tomokazu Komiya',
            'types': ['Erba'],
          }
        });
      }));
      addTearDown(service.dispose);
      final cart = CartController();
      addTearDown(cart.dispose);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
              fontFamily: capture ? 'DetailQA' : null),
          home: CardDetails(
              initialColor: scenario.width == 320
                  ? Colors.white
                  : const Color(0xFFF4A267),
              preview: const MarketplaceCardPreview(
                  id: '24',
                  name: 'Caterpie',
                  expansion: 'HeartGold & SoulSilver',
                  number: '057/123',
                  imageUrl: ''),
              controller: CardDetailsController(cardId: '24', service: service),
              cart: cart),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('123,50'), findsNothing);
      await tester.tap(find.byTooltip('Salva nei preferiti'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Rimuovi dai preferiti'), findsOneWidget);

      Future<void> snapshot(String name) async {
        if (!capture || scenario.width != 390 && scenario.width != 1320) return;
        await tester.runAsync(() async {
          final boundary = boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final picture = await boundary.toImage(pixelRatio: 1);
          final bytes =
              await picture.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory('build/card-details-preview')
            ..createSync(recursive: true);
          await File('${directory.path}/${scenario.width.toInt()}-$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }

      await snapshot('header');
      for (final title in [
        'Andamento prezzi',
        'Vendi la tua carta',
        'Migliore offerta',
        'Shop'
      ]) {
        await tester.scrollUntilVisible(find.text(title), 300,
            scrollable: find.byType(Scrollable).first, maxScrolls: 60);
        await tester.pumpAndSettle();
        expect(find.text(title).hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await snapshot(title == 'Vendi la tua carta'
            ? 'composer'
            : title == 'Migliore offerta'
                ? 'best-deal'
                : title == 'Shop'
                    ? 'shop'
                    : 'history');
      }
      await tester.scrollUntilVisible(
          find.descendant(
              of: find.byType(ListingDetails),
              matching: find.text('redshakkio')),
          300,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 60);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await snapshot('offer');
      await tester.scrollUntilVisible(find.text('Shop'), -300,
          scrollable: find.byType(Scrollable).first, maxScrolls: 60);
      await tester.pumpAndSettle();
      final shop = find.byType(ListingDetails);
      final languageFilter =
          find.descendant(of: shop, matching: find.text('Lingua: tutte'));
      await tester.ensureVisible(languageFilter);
      await tester.pumpAndSettle();
      await tester.tap(languageFilter);
      await tester.pumpAndSettle();
      await tester.tap(find.text('EN').last);
      await tester.pumpAndSettle();
      expect(
          tester.widget<ListingDetails>(shop).state.visible.single.sellerName,
          'TCG Corner');
      expect(cart.itemCount, 0);
      expect(requests, 2);
      expect(tester.takeException(), isNull);

      // La tastiera e la validazione non devono spingere i controlli fuori pagina.
      await tester.scrollUntilVisible(find.text('Vendi la tua carta'), -300,
          scrollable: find.byType(Scrollable).first, maxScrolls: 60);
      await tester.pumpAndSettle();
      final price = find
          .descendant(
              of: find.byType(CardListingComposer),
              matching: find.byType(TextFormField))
          .first;
      await tester.ensureVisible(price);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.enterText(price, '-2');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      tester.testTextInput.hide();
      await tester.ensureVisible(find.text('Anteprima annuncio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anteprima annuncio'));
      await tester.pumpAndSettle();
      expect(find.text('Inserisci un prezzo valido'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(cart.itemCount, 0);

      // Richiudere il modulo conserva la bozza e toglie il focus ai campi.
      await tester.scrollUntilVisible(find.text('Vendi la tua carta'), -300,
          scrollable: find.byType(Scrollable).first, maxScrolls: 60);
      await tester.pumpAndSettle();
      await tester.ensureVisible(price);
      await tester.enterText(price, '245');
      final composer = find.byType(CardListingComposer);
      final fields =
          find.descendant(of: composer, matching: find.byType(TextFormField));
      await tester.ensureVisible(fields.at(1));
      await tester.enterText(fields.at(1), '2');
      await tester.ensureVisible(fields.at(2));
      await tester.enterText(fields.at(2), 'Bozza da conservare');
      final graded = find.widgetWithText(FilterChip, 'Gradata');
      await tester.ensureVisible(graded);
      await tester.pumpAndSettle();
      await tester.tap(graded);
      await tester.pumpAndSettle();
      await tester.ensureVisible(fields.at(2));
      await tester.enterText(fields.at(2), 'Bozza da conservare');
      final draftFocus = tester
          .widget<EditableText>(find.descendant(
              of: fields.at(2), matching: find.byType(EditableText)))
          .focusNode;
      expect(draftFocus.hasFocus, isTrue);
      final openHeight = tester.getSize(composer).height;
      await tester.ensureVisible(find.byTooltip('Richiudi modulo di vendita'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Richiudi modulo di vendita'));
      await tester.pumpAndSettle();
      expect(find.text('Anteprima annuncio'), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(tester.getSize(composer).height, lessThan(openHeight / 2));
      expect(draftFocus.hasFocus, isFalse);
      await snapshot('composer-collapsed');
      await tester.tap(find.byTooltip('Apri modulo di vendita'));
      await tester.pumpAndSettle();
      expect(tester.state<FormFieldState<String>>(price).value, '245');
      expect(tester.state<FormFieldState<String>>(fields.at(1)).value, '2');
      expect(tester.state<FormFieldState<String>>(fields.at(2)).value,
          'Bozza da conservare');
      expect(tester.widget<FilterChip>(graded).selected, isTrue);
      expect(tester.takeException(), isNull);
      expect(cart.itemCount, 0);
      expect(requests, 2);
    });
  }
}
