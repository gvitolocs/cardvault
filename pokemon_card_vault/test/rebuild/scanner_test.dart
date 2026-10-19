import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pokoin/rebuild/controller/scanner_controller.dart';
import 'package:pokoin/rebuild/model/scanner.dart';
import 'package:pokoin/rebuild/presentation/scanner/scanner_screen.dart';
import 'package:pokoin/rebuild/provider/scanner_provider.dart';
import 'package:pokoin/rebuild/provider/scanner_market_provider.dart';
import 'package:pokoin/rebuild/service/scanner_service.dart';

const row = ScannedCard(
    id: 'row-1',
    cardId: '124',
    name: 'Pikachu',
    setName: 'Scarlatto e Violetto',
    number: '025/198',
    imageUrl: '');
const candidate = ScannerCandidate(
    cardId: '124',
    name: 'Pikachu',
    setName: 'Scarlatto e Violetto',
    number: '025/198',
    score: .9);
const other = ScannerCandidate(
    cardId: '126',
    name: 'Raichu',
    setName: 'Scarlatto e Violetto',
    number: '026/198',
    score: .75);

class Source extends ScannerService {
  List<ScannedCard> rows = [];
  bool failAdd = false, failSave = false;
  Completer<ScannerBatch>? pending;
  Completer<ScannerMarketData>? pendingPrice;
  int additions = 0, saves = 0, prepares = 0;
  List<ScannedCard> saved = [];
  @override
  Future<void> prepare() async {
    prepares++;
  }

  @override
  Future<ScannerMarketData> marketData(ScannedCard card) async =>
      pendingPrice != null
          ? pendingPrice!.future
          : const ScannerMarketData(suggested: 7.5);
  @override
  Future<ScannerBatch> open(String uid) async => pending != null
      ? pending!.future
      : ScannerBatch(id: 'batch', cards: rows);
  @override
  Future<ScannerBatch> read(String uid, String id) async =>
      ScannerBatch(id: id, cards: rows);
  @override
  Future<ScannedCard> add(
      String uid, String id, ScannerCandidate candidate) async {
    additions++;
    final added = ScannedCard(
        id: 'row-$additions',
        cardId: candidate.cardId,
        name: candidate.name,
        setName: candidate.setName,
        number: candidate.number,
        imageUrl: '');
    rows = [...rows, added];
    if (failAdd) throw TimeoutException('Response lost after commit');
    return added;
  }

  @override
  Future<void> save(String uid, String id, List<ScannedCard> cards,
      ScanDestination destination) async {
    saves++;
    saved = cards;
    if (failSave) throw const FormatException('Possesso non confermato');
  }
}

class Api {
  bool submitted = false, visible = true, invalidSubmit = false;
  int posts = 0;
  final calls = <http.Request>[];
  late final provider = ScannerProvider(
      token: (_) async => 'token',
      client: MockClient((request) async {
        calls.add(request);
        expect(request.headers['Authorization'], 'Bearer token');
        if (request.method == 'POST') posts++;
        Map<String, dynamic> data;
        if (request.url.path == '/api/marketplace-collection') {
          data = {
            'uid': 'alice',
            'items': visible
                ? [
                    {'id': 'scan:row-1', 'cardId': '124', 'quantity': 1}
                  ]
                : []
          };
        } else if (request.url.queryParameters['action'] == 'submit') {
          submitted = true;
          data = invalidSubmit
              ? {}
              : {
                  'batch': {'id': 'batch', 'status': 'submitted'},
                  'result': {
                    'intent': jsonDecode(request.body)['intent'],
                    'ownership': 1
                  }
                };
        } else if (request.method == 'GET') {
          data = {
            'batch': {
              'id': 'batch',
              'status': submitted ? 'submitted' : 'open',
              if (submitted) 'submitResult': {'intent': 'collection'}
            },
            'items': submitted
                ? []
                : [
                    {'id': 'row-1', 'cardId': '124', 'status': 'active'}
                  ]
          };
        } else {
          data = {};
        }
        return http.Response(jsonEncode(data), 200);
      }));
}

void capture(ScannerController controller,
    [List<ScannerCandidate> hits = const [candidate, other]]) {
  controller.recordRecognition(hits);
  controller.recordRecognition(hits);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('only native CardTrader identities become public marketplace ids', () {
    expect(ScannerService.publicCardId('123', identity: 'ct_id'), '246');
    expect(ScannerService.publicCardId('123', identity: 'tcgplayer'), isNull);
    expect(ScannerService.publicCardId('246', identity: 'card_id'), isNull);
  });
  test(
      'HTTP success must confirm ownership and private collection before success',
      () async {
    final api = Api();
    await ScannerService(provider: api.provider).save('alice', 'batch',
        [row.edit(price: '12,50', language: 'JP')], ScanDestination.collection);
    expect(api.calls.length, 4);
    expect(
        jsonDecode(api.calls[1].body)['patch'], containsPair('pricePkn', 12.5));
    expect(
        jsonDecode(api.calls[1].body)['patch'], containsPair('cardId', '124'));
    expect(api.calls.last.url.path, '/api/marketplace-collection');
    expect(api.submitted, true);
  });
  test('empty HTTP 200 submit response is not a successful ownership save',
      () async {
    final api = Api()..invalidSubmit = true;
    await expectLater(
        ScannerService(provider: api.provider)
            .save('alice', 'batch', [row], ScanDestination.collection),
        throwsFormatException);
  });
  test(
      'submitted retry verifies missing ownership without publishing another copy',
      () async {
    final api = Api()..visible = false;
    final service = ScannerService(provider: api.provider);
    await expectLater(
        service.save('alice', 'batch', [row], ScanDestination.collection),
        throwsFormatException);
    final posts = api.posts;
    await expectLater(
        service.save('alice', 'batch', [row], ScanDestination.collection),
        throwsFormatException);
    expect(api.posts, posts);
    api.visible = true;
    await service.save('alice', 'batch', [row], ScanDestination.collection);
    expect(api.posts, posts);
  });
  test('listing requires positive finite price before any private write',
      () async {
    final api = Api();
    for (final price in [
      '',
      '0',
      '0.001',
      '-1',
      'NaN',
      'Infinity',
      '1000000001'
    ]) {
      await expectLater(
          ScannerService(provider: api.provider).save('alice', 'batch',
              [row.edit(price: price)], ScanDestination.listing),
          throwsFormatException);
    }
    expect(api.posts, 0);
  });
  test('one held card counts once and retains top three best scores', () async {
    final source = Source();
    final controller = ScannerController(service: source)..setUser('alice');
    await controller.start();
    capture(controller, [other, candidate]);
    for (var i = 0; i < 8; i++) {
      controller.recordRecognition([candidate, other]);
    }
    expect(controller.quantity, 1);
    expect(controller.cards.single.cardId, '124');
    expect(controller.cards.single.alternatives.first.score, .9);
    expect(source.additions, 0);
    controller.dispose();
  });
  test(
      'continuous scans collect different cards and allow same card after leaving frame',
      () async {
    final controller = ScannerController(service: Source());
    capture(controller);
    expect(controller.cards, isEmpty); // Ready has not been pressed.
    await controller.start();
    capture(controller);
    capture(controller, [other]);
    controller.recordRecognition([]);
    controller.recordRecognition([]);
    capture(controller);
    expect(controller.cards.map((c) => c.cardId), ['124', '126', '124']);
    controller.pauseCamera(true);
    capture(controller, [other]);
    expect(controller.cards.length, 3);
    await controller.review();
    controller.dispose();
  });
  test(
      'low-scoring alternatives remain selectable but cannot trigger a capture alone',
      () async {
    const low = ScannerCandidate(
        cardId: '128',
        name: 'Terza versione',
        setName: 'Set',
        number: '3',
        score: .42);
    final controller = ScannerController(service: Source());
    await controller.start();
    capture(controller, [low]);
    expect(controller.cards, isEmpty);
    capture(controller, [candidate, other, low]);
    expect(controller.cards.single.alternatives.length, 3);
    controller.pauseCamera(true);
    controller.chooseCandidate(controller.cards.single.id, low);
    await controller.review();
    expect(controller.cards.single.cardId, '128');
    controller.dispose();
  });
  test(
      'review chooses alternate and saves canonical chosen printing with suggested price',
      () async {
    final source = Source();
    final controller = ScannerController(service: source)..setUser('alice');
    await controller.start();
    capture(controller);
    controller.pauseCamera(true);
    controller.chooseCandidate(controller.cards.single.id, other);
    await controller.review();
    expect(controller.cards.single.cardId, '126');
    expect(controller.cards.single.price, '7.50');
    expect(await controller.save(), true);
    expect(source.additions, 1);
    expect(source.saved.single.cardId, '126');
    expect(source.saved.single.isLocal, false);
    expect(controller.cards, isEmpty);
    controller.dispose();
  });
  test('failed ownership save retains cards for verification retry', () async {
    final source = Source()..failSave = true;
    final controller = ScannerController(service: source)..setUser('alice');
    await controller.start();
    capture(controller);
    expect(await controller.save(), false);
    expect(controller.cards.length, 1);
    source.failSave = false;
    expect(await controller.save(), true);
    expect(source.additions, 1);
    controller.dispose();
  });
  test(
      'uncertain add reconciles committed row before retry and does not add again',
      () async {
    final source = Source()..failAdd = true;
    final controller = ScannerController(service: source)..setUser('alice');
    await controller.start();
    capture(controller);
    expect(await controller.save(), false);
    expect(controller.needsReload, true);
    expect(await controller.save(), false);
    await controller.reload();
    expect(controller.needsReload, false);
    expect(controller.cards.single.isLocal, false);
    source.failAdd = false;
    expect(await controller.save(), true);
    expect(source.additions, 1);
    controller.dispose();
  });
  test('manual price typed while market data loads is preserved', () async {
    final source = Source()..pendingPrice = Completer<ScannerMarketData>();
    final controller = ScannerController(service: source)..setUser('alice');
    await controller.start();
    capture(controller);
    controller.pauseCamera(true);
    controller.edit(controller.cards.single.edit(price: '19'));
    source.pendingPrice!.complete(const ScannerMarketData(suggested: 7));
    await controller.review();
    expect(controller.cards.single.price, '19');
    expect(controller.cards.single.priceSuggested, false);
    controller.dispose();
  });
  test('late account response cannot restore private cards after logout',
      () async {
    final source = Source()..pending = Completer<ScannerBatch>();
    final controller = ScannerController(service: source)..setUser('alice');
    final pending = controller.reload();
    controller.setUser(null);
    source.pending!.complete(ScannerBatch(id: 'batch', cards: [row]));
    await pending;
    expect(controller.cards, isEmpty);
    controller.dispose();
  });
  test(
      'market suggestions use exact facets then nearest condition and English fallback',
      () {
    ScannerSaleSlice slice(String condition, String language, double median,
            {bool graded = false}) =>
        ScannerSaleSlice({
          'condition': condition,
          'language': language,
          'medianPkn': median,
          'day': '2026-10-19',
          'graded': graded
        });
    final prices = [
      slice('NM', 'IT', 10),
      slice('SP', 'IT', 8),
      slice('NM', 'EN', 11),
      slice('NM', 'IT', 999, graded: true)
    ];
    expect(ScannerService.suggestPrice(row, prices), 10);
    expect(ScannerService.suggestPrice(row.edit(condition: 'MP'), prices), 8);
    expect(ScannerService.suggestPrice(row.edit(language: 'FR'), prices), 11);
    expect(ScannerService.suggestPrice(row, []), isNull);
  });
  test('public generic card price remains available when sales API fails',
      () async {
    final calls = <http.Request>[];
    final market = ScannerMarketProvider(client: MockClient((request) async {
      calls.add(request);
      if (request.url.path == '/api/marketplace-card-sales') {
        return http.Response('{}', 503);
      }
      return http.Response(
          jsonEncode({
            'card': {'id': '124', 'name': 'Pikachu', 'pricePkn': 4.2}
          }),
          200);
    }));
    final data = await ScannerService(market: market).marketData(row);
    expect(data.suggested, 4.2);
    expect(data.card?.name, 'Pikachu');
    expect(calls.length, 2);
  });

  testWidgets(
      'Ready gates camera, sheet pauses continuous scan and top results stay inside sheet',
      (tester) async {
    final fontRoot = Platform.environment['SCANNER_PREVIEW_FONTS'];
    if (fontRoot != null) {
      await tester.runAsync(() async {
        for (final entry in {
          'Roboto': 'roboto-regular.ttf',
          'MaterialIcons': 'materialicons-regular.otf'
        }.entries) {
          final bytes = await File('$fontRoot/${entry.value}').readAsBytes();
          await (FontLoader(entry.key)
                ..addFont(Future.value(bytes.buffer.asByteData())))
              .load();
        }
      });
    }
    final source = Source();
    final controller = ScannerController(service: source)..setUser('alice');
    final previewKey = GlobalKey();
    var cameraBuilds = 0;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget app(double scale) => MaterialApp(
        theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            fontFamily: fontRoot == null ? null : 'Roboto',
            colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFFE9FF72),
                brightness: Brightness.dark,
                primary: const Color(0xFFE9FF72),
                surface: const Color(0xFF1D1F2C))),
        home: Scaffold(
            appBar: AppBar(title: const Text('pokoin')),
            body: MediaQuery(
                data: MediaQueryData(
                    size: const Size(390, 744),
                    textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(
                    key: previewKey,
                    child: ScannerScreen(
                        controller: controller,
                        onLogin: () {},
                        onSaved: () {},
                        cameraBuilder: (_) {
                          cameraBuilds++;
                          return const ColoredBox(color: Color(0xFF11121A));
                        })))));
    await tester.pumpWidget(app(1));
    await tester.pumpAndSettle();
    expect(cameraBuilds, 0);
    expect(source.prepares, 0);
    await tester.tap(find.text('Ready · Avvia scanner'));
    await tester.pumpAndSettle();
    expect(cameraBuilds, greaterThan(0));
    capture(controller);
    await tester.pumpAndSettle();
    expect(find.text('Scansionate · 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Apri o chiudi carte scansionate'));
    await tester.pumpAndSettle();
    expect(controller.cameraPaused, true);
    expect(find.text('Conferma 1 carta in collezione'), findsOneWidget);
    expect(find.text('Risultati · scegli tra i primi 2'), findsOneWidget);
    expect(find.text('Prezzo PK'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final boundary =
        previewKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('build/scanner-preview.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(app(1.8));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(controller.activated, false);
    controller.dispose();
  });
}
