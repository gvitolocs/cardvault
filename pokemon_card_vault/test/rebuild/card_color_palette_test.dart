import 'dart:typed_data';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/rebuild/style/card_color_palette.dart';
import 'package:pokoin/rebuild/style/card_details_style.dart';
import 'package:pokoin/rebuild/presentation/card_details/atomics/card_artwork_image.dart';
import 'package:pokoin/rebuild/presentation/marketplace/atomics/card_palette_snapshot.dart';
import 'package:pokoin/rebuild/controller/card_details_controller.dart';
import 'package:pokoin/rebuild/controller/cart_controller.dart';
import 'package:pokoin/rebuild/model/marketplace_home.dart';
import 'package:pokoin/rebuild/presentation/card_details/card_details.dart';
import 'package:pokoin/rebuild/service/card_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'card_details_test.dart' as fixtures;

const orange = Color(0xFFF4A267);
const green = Color(0xFF82B775);

Future<Uint8List> cardImage(Color body) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
      const Rect.fromLTWH(0, 0, 100, 140), Paint()..color = Colors.yellow);
  canvas.drawRect(const Rect.fromLTWH(8, 8, 84, 124), Paint()..color = body);
  canvas.drawRect(
      const Rect.fromLTWH(8, 8, 84, 60), Paint()..color = Colors.blue);
  for (var row = 80.0; row < 120; row += 12) {
    canvas.drawRect(
        Rect.fromLTWH(20, row, 60, 2), Paint()..color = Colors.black);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(100, 140);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'printed ability background wins over border, illustration and black text',
      () {
    const width = 100, height = 140;
    final rgba = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final Color color;
        if (x < 8 || x > 92 || y < 8 || y > 132) {
          color = Colors.yellow;
        } else if (y < 68) {
          color = Colors.blue;
        } else if (y % 12 < 2 && x > 20 && x < 80) {
          color = Colors.black;
        } else {
          color = orange;
        }
        final offset = (y * width + x) * 4;
        rgba.setRange(offset, offset + 4, [
          (color.r * 255).round(),
          (color.g * 255).round(),
          (color.b * 255).round(),
          255,
        ]);
      }
    }
    expect(CardColorPalette.fromRgba(rgba, width, height), orange);
    expect(
        CardColorPalette.fromRgba(Uint8List(width * height * 4), width, height),
        isNull);
  });

  test('dynamic palette keeps page color and makes sections and fields darker',
      () {
    for (final color in [
      orange,
      green,
      Colors.blue,
      Colors.grey,
      Colors.white
    ]) {
      final theme = CardDetailsStyle.theme(ThemeData(), cardColor: color);
      expect(theme.scaffoldBackgroundColor, color);
      expect(theme.colorScheme.surface.computeLuminance(),
          lessThan(color.computeLuminance()));
      expect(theme.inputDecorationTheme.fillColor!.computeLuminance(),
          lessThan(theme.colorScheme.surface.computeLuminance()));
      final contrast = (Colors.white.computeLuminance() + .05) /
          (theme.colorScheme.surface.computeLuminance() + .05);
      expect(contrast, greaterThan(7));
    }
  });

  testWidgets('snapshot passes the thumbnail color before details data loads',
      (tester) async {
    final bytes = (await tester.runAsync(() => cardImage(Colors.white)))!;
    final reply = Completer<http.Response>();
    final service = CardService(client: MockClient((_) => reply.future));
    final cart = CartController();
    addTearDown(service.dispose);
    addTearDown(cart.dispose);
    Color? selected;
    var imageReady = false;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Scaffold(
          body: CardPaletteSnapshot(
        thumbnail: SizedBox(
            width: 196,
            height: 144,
            child: Image.memory(bytes, fit: BoxFit.contain,
                frameBuilder: (context, child, frame, synchronous) {
              imageReady = frame != null || synchronous;
              return child;
            })),
        builder: (context, thumbnail, onTap) => Material(
            color: Colors.purple,
            child: InkWell(
                onTap: onTap,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  thumbnail,
                  const Text('Tandemaus 22 PKN'),
                ]))),
        onSelected: (color) {
          selected = color;
          Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => CardDetails(
                  preview: const MarketplaceCardPreview(
                      id: '24', name: 'Tandemaus', expansion: '', imageUrl: ''),
                  controller:
                      CardDetailsController(cardId: '24', service: service),
                  initialColor: color,
                  cart: cart)));
        },
      ));
    })));
    for (var i = 0; i < 100 && !imageReady; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(imageReady, isTrue);
    await tester.tap(find.text('Tandemaus 22 PKN'));
    for (var i = 0; i < 100 && selected == null; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(selected, Colors.white);
    await tester.pump(const Duration(milliseconds: 400));
    final scaffold = find.descendant(
        of: find.byType(CardDetails), matching: find.byType(Scaffold));
    expect(
        Theme.of(tester.element(scaffold)).scaffoldBackgroundColor, selected);
    expect(reply.isCompleted, isFalse);
    reply.complete(fixtures.response({'card': fixtures.cardJson}));
    await tester.pumpAndSettle();
    expect(
        Theme.of(tester.element(scaffold)).scaffoldBackgroundColor, selected);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unloaded thumbnail opens details without sampling its icon',
      (tester) async {
    final selected = <Color?>[];
    await tester.pumpWidget(MaterialApp(
        home: CardPaletteSnapshot(
            thumbnail: const SizedBox(
                width: 196, height: 144, child: Icon(Icons.style)),
            onSelected: selected.add,
            builder: (context, thumbnail, onTap) =>
                GestureDetector(onTap: onTap, child: thumbnail))));
    await tester.tap(find.byType(Icon));
    await tester.pump();
    expect(selected, [null]);
  });

  testWidgets('artwork emits the sampled color once and updates for a new card',
      (tester) async {
    final orangeBytes = (await tester.runAsync(() => cardImage(orange)))!;
    final greenBytes = (await tester.runAsync(() => cardImage(green)))!;
    final selected = <Color>[];
    Widget artwork(Uint8List bytes) => MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 200,
                height: 280,
                child: CardArtworkImage(
                    image: MemoryImage(bytes), onColor: selected.add))));
    Future<void> waitForColors(int count) async {
      for (var i = 0; i < 100 && selected.length < count; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(selected.length, count);
    }

    await tester.pumpWidget(artwork(orangeBytes));
    await waitForColors(1);
    expect(selected.single, orange);
    await tester.pumpWidget(artwork(orangeBytes));
    await tester.pumpAndSettle();
    expect(selected, [orange]);
    await tester.pumpWidget(artwork(greenBytes));
    await waitForColors(2);
    expect(selected, [orange, green]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
