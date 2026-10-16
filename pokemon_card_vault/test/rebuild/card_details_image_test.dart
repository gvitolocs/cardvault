import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pokoin/rebuild/cache/marketplace_image_cache.dart';
import 'package:pokoin/rebuild/controller/card_details_controller.dart';
import 'package:pokoin/rebuild/controller/cart_controller.dart';
import 'package:pokoin/rebuild/model/card.dart';
import 'package:pokoin/rebuild/model/marketplace_home.dart';
import 'package:pokoin/rebuild/presentation/card_details/card_details.dart';
import 'package:pokoin/rebuild/presentation/card_details/atomics/card_artwork_image.dart';
import 'package:pokoin/rebuild/service/card_service.dart';

import 'card_color_palette_test.dart' as palette;
import 'card_details_test.dart' as fixtures;

const imageUrl = 'https://cdn.pokoin.com/detail-image-test.jpg';
const updatedImageUrl = 'https://cdn.pokoin.com/detail-image-updated.jpg';

void main() {
  testWidgets(
      'details open full artwork and retain the displayed frame during metadata updates',
      (tester) async {
    final cacheDirectory =
        Directory.systemTemp.createTempSync('pokoin_detail_images_');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => cacheDirectory.path);
    addTearDown(() async {
      await MarketplaceImageCache.instance.dispose();
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      expect(cacheDirectory.parent.absolute.path,
          Directory.systemTemp.absolute.path);
      await cacheDirectory.delete(recursive: true);
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final bytes =
        (await tester.runAsync(() => palette.cardImage(palette.green)))!;
    final memory = MemoryImage(bytes);
    final cached = memory.resolve(ImageConfiguration.empty);
    final provider = ResizeImage.resizeIfNeeded(
        266,
        null,
        CachedNetworkImageProvider(imageUrl,
            cacheManager: MarketplaceImageCache.instance));
    final key = await provider.obtainKey(ImageConfiguration.empty);
    final ready = Completer<void>();
    ImageInfo? cachedInfo;
    final listener = ImageStreamListener((info, __) {
      cachedInfo?.dispose();
      cachedInfo = info;
      if (!ready.isCompleted) ready.complete();
    });
    cached.addListener(listener);
    for (var i = 0; i < 100 && !ready.isCompleted; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(ready.isCompleted, isTrue);
    PaintingBinding.instance.imageCache
        .putIfAbsent(key, () => cached.completer!);
    final reply = Completer<http.Response>();
    final service = CardService(client: MockClient((_) => reply.future));
    final cart = CartController();
    addTearDown(service.dispose);
    addTearDown(cart.dispose);
    final controller = CardDetailsController(cardId: '24', service: service);
    await tester.pumpWidget(MaterialApp(
        home: CardDetails(
            preview: MarketplaceCardPreview.fromJson({
              'id': '24',
              'name': 'Carta',
              'set': 'Set',
              'homepageImageUrl':
                  'https://cdn.pokoin.com/detail-image-test_homepage.webp',
              'heroImageUrl': imageUrl,
            }),
            controller: controller,
            cart: cart)));
    expect(tester.widget<CardArtworkImage>(find.byType(CardArtworkImage)).image,
        provider,
        reason: 'Details must use the full URL already present in search data');
    final artwork = tester.state(find.byType(CardArtworkImage));
    final image = tester.state(find.descendant(
        of: find.byType(CardArtworkImage), matching: find.byType(Image)));
    reply.complete(fixtures.response({
      'card': {...fixtures.cardJson, 'heroImageUrl': imageUrl}
    }));
    await tester.pump();
    await tester.pump();
    expect(tester.state(find.byType(CardArtworkImage)), same(artwork));
    expect(
        tester.state(find.descendant(
            of: find.byType(CardArtworkImage), matching: find.byType(Image))),
        same(image));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(tester.state(find.byType(CardArtworkImage)), same(artwork));
    expect(
        tester.state(find.descendant(
            of: find.byType(CardArtworkImage), matching: find.byType(Image))),
        same(image));
    final rawImage = find.descendant(
        of: find.byType(CardArtworkImage), matching: find.byType(RawImage));
    final oldFrame = tester.widget<RawImage>(rawImage).image;
    expect(oldFrame, isNotNull);
    final updated = ResizeImage.resizeIfNeeded(
        266,
        null,
        CachedNetworkImageProvider(updatedImageUrl,
            cacheManager: MarketplaceImageCache.instance));
    final updateKey = await updated.obtainKey(ImageConfiguration.empty);
    final pendingFrame = Completer<ImageInfo>();
    PaintingBinding.instance.imageCache.putIfAbsent(
        updateKey, () => OneFrameImageStreamCompleter(pendingFrame.future));
    controller.info.value = CardInfoState(
        card: MarketplaceCard.fromJson({
          ...fixtures.cardJson,
          'heroImageUrl': updatedImageUrl,
        }),
        loading: false);
    await tester.pump();
    expect(tester.widget<RawImage>(rawImage).image, same(oldFrame),
        reason: 'A changed full URL must keep the previous frame until ready');
    pendingFrame.complete(cachedInfo!.clone());
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    cached.removeListener(listener);
    cachedInfo?.dispose();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
}
