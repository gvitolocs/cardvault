import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
// ignore: avoid_relative_lib_imports
import '../lib/widgets/scanner_navigation_shell.dart';
// ignore: avoid_relative_lib_imports
import '../lib/scan_v2/scan_asset_gate.dart';
// ignore: avoid_relative_lib_imports
import '../lib/scan_v2/scan_assets.dart';

ScanAssetStatus status(String gallery, {bool ready = false}) => ScanAssetStatus(
      root: Directory('unused'),
      gallery: gallery,
      missing: ready ? [] : ['assets/models/card_detector.tflite'],
    );

Widget app({required ScanAssetInspector inspect}) => MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(
        body: ScanAssetGate(
      inspect: inspect,
      builder: (_, gallery) => Text('Camera ready: $gallery'),
    )));

void main() {
  testWidgets('missing pack keeps Marketplace navigation available',
      (tester) async {
    final router = GoRouter(initialLocation: '/cardscan', routes: [
      GoRoute(
          path: '/marketplace',
          builder: (_, __) => const Scaffold(body: Text('Marketplace page'))),
      GoRoute(
          path: '/cardscan',
          builder: (_, __) => ScannerNavigationShell(
              body: ScanAssetGate(
                  inspect: (g) async => status(g),
                  builder: (_, g) => Text('Camera ready: $g')))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(
        MaterialApp.router(theme: ThemeData.dark(), routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Scanner non disponibile'), findsOneWidget);
    await tester.tap(find.text('Ricerca'));
    await tester.pumpAndSettle();
    expect(find.text('Marketplace page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0]) {
    testWidgets('missing bundle is a fallback, not a package store at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(inspect: (g) async => status(g)));
      await tester.pumpAndSettle();
      expect(find.text('Scanner non disponibile'), findsOneWidget);
      expect(find.textContaining('Camera ready'), findsNothing);
      expect(find.text('Warming up'), findsNothing);
      expect(find.text('Scarica pacchetto'), findsNothing);
      expect(find.text('assets/models/card_detector.tflite'), findsNothing);
      await tester.tap(find.text('Dettagli tecnici'));
      await tester.pumpAndSettle();
      expect(find.text('assets/models/card_detector.tflite'), findsOneWidget);
      expect(find.text('Riprova').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('complete bundle automatically opens camera without setup',
      (tester) async {
    await tester.pumpWidget(app(inspect: (g) async => status(g, ready: true)));
    await tester.pumpAndSettle();
    expect(find.text('Camera ready: western'), findsOneWidget);
    expect(find.text('Scanner non disponibile'), findsNothing);
    expect(find.text('Riprova'), findsNothing);
  });

  testWidgets('retry prepares models and opens camera', (tester) async {
    var ready = false;
    await tester.pumpWidget(app(inspect: (g) async => status(g, ready: ready)));
    await tester.pumpAndSettle();
    ready = true;
    await tester.tap(find.text('Riprova'));
    await tester.pumpAndSettle();
    expect(find.text('Camera ready: western'), findsOneWidget);
  });

  testWidgets('preparation failure is visible and recoverable', (tester) async {
    await tester
        .pumpWidget(app(inspect: (_) async => throw StateError('unavailable')));
    await tester.pumpAndSettle();
    expect(find.text('Impossibile preparare i modelli dello scanner. Riprova.'),
        findsOneWidget);
    expect(find.textContaining('Camera ready'), findsNothing);
    expect(find.text('Riprova'), findsOneWidget);
  });

  testWidgets('preparation is automatic and shows progress without a button',
      (tester) async {
    final pending = Completer<ScanAssetStatus>();
    await tester.pumpWidget(app(inspect: (_) => pending.future));
    await tester.pump();
    expect(find.text('Preparazione scanner'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Riprova'), findsNothing);
    pending.complete(status('western', ready: true));
    await tester.pumpAndSettle();
    expect(find.text('Camera ready: western'), findsOneWidget);
  });

  testWidgets('late preparation result after navigation is ignored',
      (tester) async {
    final pending = Completer<ScanAssetStatus>();
    await tester.pumpWidget(app(inspect: (_) => pending.future));
    await tester.pumpWidget(const MaterialApp(home: Text('Marketplace')));
    pending.complete(status('western'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
