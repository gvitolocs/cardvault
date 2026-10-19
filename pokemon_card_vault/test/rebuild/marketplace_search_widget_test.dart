import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/rebuild/controller/marketplace_controller.dart';
import 'package:pokoin/rebuild/presentation/marketplace/marketplace_screen.dart';
import 'package:pokoin/rebuild/presentation/marketplace/atomics/search_card_tile.dart';
import 'package:pokoin/rebuild/presentation/marketplace/atomics/suggestion_card_tile.dart';
import 'package:pokoin/rebuild/presentation/card_details/card_details.dart';
import 'package:pokoin/rebuild/service/card_service.dart';
import 'package:pokoin/rebuild/cache/marketplace_image_cache.dart';
import 'package:pokoin/rebuild/model/marketplace_home.dart';
import 'package:pokoin/rebuild/model/marketplace_search.dart';
import 'package:pokoin/rebuild/presentation/card_details/atomics/card_artwork_image.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'marketplace_search_controller_test.dart';
import 'card_color_palette_test.dart' as palette;
import 'card_details_test.dart' as fixtures;

void main() {
  for (final width in [320.0, 390.0, 900.0]) {
    testWidgets(
        'real search at width $width opens canonical details and clears',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final search = SearchServiceStub();
      final detailRequests = <String>[];
      final client = MockClient((request) async {
        detailRequests.add(request.url.queryParameters['cardId']!);
        return http.Response('{}', 503);
      });
      final details = CardService(client: client);
      final controller =
          MarketplaceController(searchService: search, cardService: details);
      addTearDown(search.dispose);
      addTearDown(details.dispose);
      addTearDown(client.close);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
          MaterialApp(home: MarketplaceScreen(controller: controller)));
      expect(find.byType(DropdownButtonFormField<String>), findsNothing,
          reason: 'Filters start collapsed');
      await tester.enterText(find.byType(TextField), 'Pikachu');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 300));
      search.responses.single.complete(searchPage(['632778'], hasMore: true));
      await tester.pumpAndSettle();
      expect(find.text('Risultati'), findsOneWidget);
      expect(find.textContaining('demo'), findsNothing);
      expect(find.byType(SearchCardTile), findsOneWidget);
      await tester.ensureVisible(find.text('Carta 632778'));
      await tester.tap(find.text('Carta 632778'));
      await tester.pumpAndSettle();
      expect(find.byType(CardDetails), findsOneWidget);
      expect(tester.widget<CardDetails>(find.byType(CardDetails)).initialColor,
          isNull,
          reason:
              'An unloaded thumbnail must not supply the placeholder color');
      expect(detailRequests, isNotEmpty);
      expect(detailRequests.every((id) => id == '632778'), isTrue);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Carica altri'));
      await tester.tap(find.text('Carica altri'));
      await tester.pump();
      expect(search.requests.last.offset, 24);
      search.responses.last.completeError(StateError('Offline'));
      await tester.pumpAndSettle();
      expect(find.text('Riprova'), findsOneWidget);
      expect(find.text('Carta 632778'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Cancella ricerca'));
      await tester.tap(find.byTooltip('Cancella ricerca'));
      await tester.pumpAndSettle();
      expect(controller.search.state.isActive, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final fromPopup in [false, true]) {
    testWidgets(
        'search ${fromPopup ? "popup" : "grid"} opens details with the loaded thumbnail color before metadata',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final cacheDirectory =
          Directory.systemTemp.createTempSync('pokoin_search_palette_');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => cacheDirectory.path);
      addTearDown(() async {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        await MarketplaceImageCache.instance.dispose();
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        expect(cacheDirectory.parent.absolute.path,
            Directory.systemTemp.absolute.path);
        expect(cacheDirectory.path.split(Platform.pathSeparator).last,
            startsWith('pokoin_search_palette_'));
        await cacheDirectory.delete(recursive: true);
      });
      final bytes =
          (await tester.runAsync(() => palette.cardImage(palette.green)))!;
      final cached = MemoryImage(bytes).resolve(ImageConfiguration.empty);
      final ready = Completer<void>();
      final listener = ImageStreamListener((info, _) {
        info.dispose();
        if (!ready.isCompleted) ready.complete();
      });
      cached.addListener(listener);
      addTearDown(() => cached.removeListener(listener));
      for (var i = 0; i < 100 && !ready.isCompleted; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(ready.isCompleted, isTrue);
      const thumbnailUrl =
          'https://cdn.pokoin.com/search-palette_homepage.webp';
      const fullUrl = 'https://cdn.pokoin.com/search-palette.jpg';
      for (final entry in [
        (thumbnailUrl, 40),
        (thumbnailUrl, 145),
        (fullUrl, 266)
      ]) {
        final provider = ResizeImage.resizeIfNeeded(
            entry.$2,
            null,
            CachedNetworkImageProvider(entry.$1,
                cacheManager: MarketplaceImageCache.instance));
        final key = await provider.obtainKey(ImageConfiguration.empty);
        PaintingBinding.instance.imageCache
            .putIfAbsent(key, () => cached.completer!);
      }
      final response = Completer<http.Response>();
      var metadataRequests = 0;
      final client = MockClient((request) {
        if (request.url.path.endsWith('marketplace-listings')) {
          return Future.value(fixtures.response({'listings': []}));
        }
        metadataRequests++;
        expect(request.url.queryParameters['cardId'], '24');
        return response.future;
      });
      final service = CardService(client: client);
      final search = SearchServiceStub();
      final controller =
          MarketplaceController(cardService: service, searchService: search);
      addTearDown(client.close);
      addTearDown(service.dispose);
      addTearDown(search.dispose);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
          MaterialApp(home: MarketplaceScreen(controller: controller)));
      await tester.enterText(find.byType(TextField), 'Carta verde');
      if (!fromPopup) FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 300));
      search.responses.single.complete(MarketplaceSearchPage(cards: const [
        MarketplaceCardPreview(
            id: '24',
            name: 'Carta verde',
            expansion: '151',
            imageUrl: thumbnailUrl,
            fullImageUrl: fullUrl),
      ], hasMore: false));
      await tester.pumpAndSettle();
      final result = find.descendant(
          of: find.byType(fromPopup ? SuggestionCardTile : SearchCardTile),
          matching: find.text('Carta verde'));
      await tester.ensureVisible(result);
      await tester.pumpAndSettle();
      await tester.tap(result);
      for (var i = 0;
          i < 100 && find.byType(CardDetails).evaluate().isEmpty;
          i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CardDetails), findsOneWidget);
      final sampledColor =
          tester.widget<CardDetails>(find.byType(CardDetails)).initialColor;
      expect(sampledColor, isNotNull);
      if (fromPopup) {
        // Scaling the smaller thumbnail blends a few border pixels.
        expect(sampledColor!.r, closeTo(palette.green.r, 0.01));
        expect(sampledColor.g, closeTo(palette.green.g, 0.01));
        expect(sampledColor.b, closeTo(palette.green.b, 0.01));
      } else {
        expect(sampledColor, palette.green);
      }
      expect(find.byType(CardArtworkImage), findsNothing,
          reason:
              'Details must not sample the full image again when the color is supplied');
      expect(response.isCompleted, isFalse);
      final scaffold = find.descendant(
          of: find.byType(CardDetails), matching: find.byType(Scaffold));
      expect(Theme.of(tester.element(scaffold)).scaffoldBackgroundColor,
          sampledColor);
      response.complete(fixtures.response({
        'card': {
          ...fixtures.cardJson,
          'heroImageUrl': fullUrl,
          'types': ['Fire'],
        }
      }));
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(scaffold)).scaffoldBackgroundColor,
          sampledColor);
      expect(find.byType(CardArtworkImage), findsNothing);
      expect(metadataRequests, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
