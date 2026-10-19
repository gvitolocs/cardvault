import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/rebuild/controller/cardex_controller.dart';
import 'package:pokoin/rebuild/model/cardex.dart';
import 'package:pokoin/rebuild/presentation/cardex/cardex_screen.dart';
import 'package:pokoin/rebuild/presentation/portfolio/portfolio_screen.dart';
import 'package:pokoin/rebuild/presentation/shared/atomics/card_ownership_frame.dart';
import 'package:pokoin/rebuild/presentation/shared/atomics/card_language_flag.dart';
import 'package:pokoin/rebuild/presentation/shared/atomics/collection_quantity_badge.dart';
import 'package:pokoin/rebuild/presentation/shared/component/card_language_selector.dart';
import 'package:pokoin/rebuild/service/card_ownership_service.dart';
import 'card_ownership_test.dart' as fixtures;

void main() {
  const service = CardOwnershipService();
  test(
      'partial evidence confirms only the exact positive print/language, never totals or absence',
      () {
    final loading = CardCollection(
        status: CollectionStatus.loading,
        items: [fixtures.copy('en-US', 2), fixtures.copy('it_IT', 1)]);
    final view = service.describe(loading, '24');
    expect(view.known, isFalse);
    expect(view.total, 0);
    expect(view.languages, isEmpty);
    expect(view.selected, isNull);
    expect(view.hasConfirmedCopies, isTrue);
    expect(view.displayLanguage, 'IT');
    final unknown = service.describe(loading, 'another-print');
    expect(unknown.hasConfirmedCopies, isFalse);
    expect(unknown.evidence, isNull);
    for (final status in [
      CollectionStatus.guest,
      CollectionStatus.unavailable
    ]) {
      final stale = service.describe(
          CardCollection(status: status, items: loading.items), '24');
      expect(stale.evidence, isNull);
      expect(stale.hasConfirmedCopies, isFalse);
      expect(stale.displayPreview, isNull);
    }
  });

  test(
      'evidence uses the same supplied language image before and after reconciliation',
      () {
    final rows = [
      fixtures.copy('EN', 2, image: 'https://cdn.pokoin.com/en.webp'),
      fixtures.copy('IT', 1, image: 'https://cdn.pokoin.com/it.webp')
    ];
    final preview = service.describe(
        CardCollection(status: CollectionStatus.loading, items: rows), '24');
    final ready = service.describe(
        CardCollection(status: CollectionStatus.ready, items: rows), '24');
    expect(preview.displayPreview?.imageUrl, ready.displayPreview?.imageUrl);
    expect(preview.displayLanguage, ready.displayLanguage);
    expect(preview.total, 0);
    expect(ready.total, 3);
  });

  for (final portfolio in [false, true]) {
    testWidgets(
        '${portfolio ? "Portfolio" : "Cardex"} has green frame and flag on first preview, without final counts/menu',
        (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = CardexController()
        ..collection = CardCollection(
            status: CollectionStatus.loading, items: fixtures.owned().items);
      addTearDown(controller.dispose);
      var opened = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: portfolio
                  ? PortfolioScreen(
                      controller: controller, onOpen: (_) => opened++)
                  : CardexScreen(
                      controller: controller, onOpen: (_) => opened++))));
      // Do not settle: synchronization is deliberately still pending.
      await tester.pump();
      expect(controller.ownershipKnown, isFalse);
      expect(
          tester
              .widget<CardOwnershipFrame>(find.byType(CardOwnershipFrame))
              .owned,
          isTrue);
      expect(
          tester.widget<CardLanguageBadge>(find.byType(CardLanguageBadge)).code,
          'IT');
      expect(
          tester
              .widget<CardLanguageSelector>(find.byType(CardLanguageSelector))
              .ownership
              .known,
          isFalse);
      expect(find.byType(CollectionQuantityBadge), findsNothing);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(find.text('Sincronizzazione…'), findsNothing);
      final frame = tester.getRect(find.byType(CardOwnershipFrame));
      final flag = tester.getRect(find.byType(CardLanguageBadge));
      final decoration = tester
          .widget<Container>(find
              .descendant(
                  of: find.byType(CardOwnershipFrame),
                  matching: find.byType(Container))
              .first)
          .decoration;
      await tester.tap(find.byType(CardLanguageBadge));
      await tester.pump();
      expect(opened, 0);
      expect(find.byType(PopupMenuItem<String>), findsNothing);
      if (!portfolio) {
        for (final text in [
          'Cardex',
          'Le mie carte',
          'Il tuo album, una carta alla volta.',
          'Caricamento della tua collezione…',
          '1 carte caricate · sincronizzazione in corso',
          'Le tue carte a colori. Apri Espansioni in alto per vedere anche le mancanti.'
        ]) {
          expect(find.text(text), findsNothing);
        }
      }
      controller.collection = fixtures.owned();
      controller.notifyListeners();
      await tester.pumpAndSettle();
      final readyFrame = tester.getRect(find.byType(CardOwnershipFrame));
      final readyFlag = tester.getRect(find.byType(CardLanguageBadge));
      expect(readyFrame.size, frame.size);
      expect(
          readyFlag.topLeft - readyFrame.topLeft, flag.topLeft - frame.topLeft);
      if (!portfolio) expect(readyFrame, frame);
      expect(
          tester
              .widget<Container>(find
                  .descendant(
                      of: find.byType(CardOwnershipFrame),
                      matching: find.byType(Container))
                  .first)
              .decoration,
          same(decoration));
      expect(find.text('×3'), findsOneWidget);
      await tester.tap(find.byTooltip('Lingue possedute di Audino'));
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<String>), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'a failed personal read removes provisional chrome with its cards and offers retry',
      (tester) async {
    final controller = CardexController()
      ..collection = CardCollection(
          status: CollectionStatus.loading, items: fixtures.owned().items);
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CardexScreen(controller: controller, onOpen: (_) {}))));
    await tester.pump();
    expect(find.byType(CardOwnershipFrame), findsOneWidget);
    controller.collection =
        CardCollection(status: CollectionStatus.unavailable);
    controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byType(CardOwnershipFrame), findsNothing);
    expect(find.byType(CardLanguageBadge), findsNothing);
    expect(find.text('Riprova collezione'), findsOneWidget);
    expect(find.textContaining('non è disponibile'), findsOneWidget);
  });
}
