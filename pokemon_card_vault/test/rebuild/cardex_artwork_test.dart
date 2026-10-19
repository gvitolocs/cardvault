import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/rebuild/constants/cardex_artwork_constants.dart';
import 'package:pokoin/rebuild/model/cardex.dart';
import 'package:pokoin/rebuild/model/marketplace_home.dart';
import 'package:pokoin/rebuild/presentation/cardex/atomics/album_card.dart';
import 'package:pokoin/rebuild/presentation/cardex/atomics/album_card_caption.dart';
import 'package:pokoin/rebuild/presentation/cardex/atomics/cardex_artwork_window.dart';
import 'package:pokoin/rebuild/presentation/cardex/component/album_grid.dart';
import 'package:pokoin/rebuild/presentation/cardex/component/card_album.dart';
import 'package:pokoin/rebuild/presentation/shared/atomics/marketplace_thumbnail.dart';
import 'package:pokoin/rebuild/style/cardex_style.dart';

class _ScanBands extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.red);
    canvas.drawRect(
        Rect.fromLTWH(0, size.height * CardexArtworkConstants.top, size.width,
            size.height * CardexArtworkConstants.height),
        Paint()..color = const Color(0xFF00FF00));
    canvas.drawRect(
        Rect.fromLTRB(
            0,
            size.height *
                (CardexArtworkConstants.top + CardexArtworkConstants.height),
            size.width,
            size.height),
        Paint()..color = Colors.blue);
    final art = Rect.fromLTWH(
        size.width * CardexArtworkConstants.left,
        size.height * CardexArtworkConstants.top,
        size.width * CardexArtworkConstants.width,
        size.height * CardexArtworkConstants.height);
    for (final marker in [
      (art.topLeft, Colors.yellow),
      (art.topRight - Offset(art.width * .1, 0), Colors.purple),
      (art.bottomLeft - Offset(0, art.height * .1), Colors.orange),
      (art.bottomRight - Offset(art.width * .1, art.height * .1), Colors.cyan),
    ]) {
      canvas.drawRect(marker.$1 & Size(art.width * .1, art.height * .1),
          Paint()..color = marker.$2);
    }
  }

  @override
  bool shouldRepaint(_ScanBands oldDelegate) => false;
}

void main() {
  const card = MarketplaceCardPreview(
      id: '229528',
      name: 'Ivysaur',
      expansion: 'EX Crystal Guardians',
      number: '35/100');

  for (final size in [
    const Size(160, 120),
    const Size(300, 200),
    const Size(300, 60)
  ]) {
    testWidgets(
        'art window excludes header/effects without distorting scan at $size',
        (tester) async {
      final boundary = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Center(
                  child: RepaintBoundary(
                      key: boundary,
                      child: SizedBox(
                          width: size.width,
                          height: size.height,
                          child: CardexArtworkWindow(
                              child: CustomPaint(painter: _ScanBands()))))))));
      final scan = tester.getSize(find.byType(CustomPaint).last);
      expect(scan.width / scan.height,
          closeTo(CardexStyle.cardAspectRatio, .00001));
      final window = tester.getRect(find.byType(CardexArtworkWindow));
      final scanRect = tester.getRect(find.byType(CustomPaint).last);
      final art = Rect.fromLTWH(
          scanRect.left + scan.width * CardexArtworkConstants.left,
          scanRect.top + scan.height * CardexArtworkConstants.top,
          scan.width * CardexArtworkConstants.width,
          scan.height * CardexArtworkConstants.height);
      expect(art.left, greaterThanOrEqualTo(window.left - .001));
      expect(art.right, lessThanOrEqualTo(window.right + .001));
      expect(art.top, greaterThanOrEqualTo(window.top - .001));
      expect(art.bottom, lessThanOrEqualTo(window.bottom + .001));
      // Pixel test exercises clipping, not just widget configuration.
      await tester.runAsync(() async {
        final picture = await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
        final pixels =
            await picture.toByteData(format: ui.ImageByteFormat.rawRgba);
        final localArt = art.shift(-window.topLeft);
        for (var y = (localArt.top + localArt.height * .15).ceil();
            y < localArt.bottom - localArt.height * .15;
            y += 5) {
          for (var x = (localArt.left + localArt.width * .15).ceil();
              x < localArt.right - localArt.width * .15;
              x += 5) {
            final offset = (y * picture.width + x) * 4;
            expect(pixels!.getUint32(offset), 0x00FF00FF);
          }
        }
        // All four illustration corners survive, for tall AND wide pockets.
        for (final sample in [
          (.05, .05, 0xFFEB3BFF),
          (.95, .05, 0x9C27B0FF),
          (.05, .95, 0xFF9800FF),
          (.95, .95, 0x00BCD4FF),
        ]) {
          final x = (localArt.left + localArt.width * sample.$1).floor();
          final y = (localArt.top + localArt.height * sample.$2).floor();
          expect(pixels!.getUint32((y * picture.width + x) * 4), sample.$3);
        }
        picture.dispose();
      });
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'only Cardex opts into landscape artwork; Portfolio retains full scan',
      (tester) async {
    final collection = CardCollection(
        status: CollectionStatus.ready,
        items: [const OwnedCard(card: card, quantity: 2)]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: SizedBox(
                    width: 390,
                    child: CardAlbum(
                        cards: const [card],
                        collection: collection,
                        onOpen: (_) {}))))));
    await tester.pumpAndSettle();
    expect(
        tester.widget<AlbumCard>(find.byType(AlbumCard)).artworkOnly, isTrue);
    expect(find.byType(CardexArtworkWindow), findsOneWidget);
    expect(tester.getSize(find.byType(AlbumCard)).width,
        greaterThan(tester.getSize(find.byType(AlbumCard)).height));
    expect(find.byType(MarketplaceThumbnail), findsOneWidget);
    // Fit the entire illustration window without revealing effects/header.
    expect(
        tester
            .widget<MarketplaceThumbnail>(find.byType(MarketplaceThumbnail))
            .height,
        closeTo(
            tester.getSize(find.byType(CardexArtworkWindow)).width /
                (CardexArtworkConstants.width * CardexStyle.cardAspectRatio),
            .001));
    expect(
        tester.getRect(find.byType(AlbumCardCaption)).top,
        greaterThanOrEqualTo(
            tester.getRect(find.byType(CardexArtworkWindow)).bottom - .001));
    expect(CardexArtworkConstants.top, .12);
    expect(CardexArtworkConstants.height, .34);
    expect(find.text('×2'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CustomScrollView(slivers: [
      AlbumGrid(cards: const [card], collection: collection, onOpen: (_) {})
    ]))));
    await tester.pumpAndSettle();
    expect(
        tester.widget<AlbumCard>(find.byType(AlbumCard)).artworkOnly, isFalse);
    expect(find.byType(CardexArtworkWindow), findsNothing);
    expect(tester.getSize(find.byType(AlbumCard)).height,
        greaterThan(tester.getSize(find.byType(AlbumCard)).width));
    expect(find.byType(MarketplaceThumbnail), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'overflow crop preserves the original bounded image decoding budget',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 180,
                height: 120,
                child: AlbumCard(
                    card: const MarketplaceCardPreview(
                        id: '229528',
                        name: 'Ivysaur',
                        expansion: 'EX Crystal Guardians',
                        imageUrl: 'https://cdn.pokoin.com/fixture.jpg'),
                    quantity: 0,
                    ownershipKnown: false,
                    artworkOnly: true,
                    onOpen: () {})))));
    final thumbnail =
        tester.widget<MarketplaceThumbnail>(find.byType(MarketplaceThumbnail));
    final pocketWidth = tester.getSize(find.byType(CardexArtworkWindow)).width;
    expect(thumbnail.decodeLogicalWidth, pocketWidth);
    expect(thumbnail.width,
        lessThanOrEqualTo(pocketWidth / CardexArtworkConstants.width + .001));
    expect(thumbnail.width / thumbnail.height,
        closeTo(CardexStyle.cardAspectRatio, .00001));
    final provider =
        tester.widget<Image>(find.byType(Image)).image as ResizeImage;
    expect(provider.width,
        (pocketWidth * tester.view.devicePixelRatio).round().clamp(1, 768));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'crop uses one unchanged URL and retains a visible empty-image fallback',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 180,
                height: 120,
                child: AlbumCard(
                    card: card,
                    quantity: 0,
                    ownershipKnown: false,
                    artworkOnly: true,
                    onOpen: () {})))));
    expect(
        tester
            .widget<MarketplaceThumbnail>(find.byType(MarketplaceThumbnail))
            .imageUrl,
        card.imageUrl);
    final window = tester.getRect(find.byType(CardexArtworkWindow));
    final icons = find.descendant(
        of: find.byType(CardexArtworkWindow),
        matching: find.byIcon(Icons.style_outlined));
    expect(
        icons.evaluate().any((element) =>
            window.contains(tester.getCenter(find.byWidget(element.widget)))),
        isTrue);
    expect(tester.takeException(), isNull);
  });

  // Optional visual QA uses a public API raster, never an app asset or a
  // generated crop. Default tests remain deterministic and network-free.
  final qaImage = Platform.environment['CARDEX_ARTWORK_QA_IMAGE'];
  if (qaImage != null) {
    testWidgets('public Ivysaur scan visual QA', (tester) async {
      final boundary = GlobalKey();
      final bytes = File(qaImage).readAsBytesSync();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Center(
                  child: RepaintBoundary(
                      key: boundary,
                      child: SizedBox(
                          width: 360,
                          height: 240,
                          child: CardexArtworkWindow(
                              child: Image.memory(bytes,
                                  fit: BoxFit.contain))))))));
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final picture = await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
        final png = await picture.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('build/cardex-artwork-preview')
          ..createSync(recursive: true);
        File('${directory.path}/ivysaur.png')
            .writeAsBytesSync(png!.buffer.asUint8List());
        picture.dispose();
      });
      expect(tester.takeException(), isNull);
    });
  }
}
