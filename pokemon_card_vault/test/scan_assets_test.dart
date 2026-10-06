import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// The isolated scanner harness imports this same test and the real source.
// ignore: avoid_relative_lib_imports
import '../lib/scan_v2/scan_assets.dart';

void main() {
  test('runtime scan pack reports only the selected gallery as missing', () {
    final status = ScanAssetStore.inspectRoot(
      Directory(r'C:\pokoin-test-assets'),
      gallery: 'japanese',
    );

    expect(status.ready, isFalse);
    expect(status.missing, contains('japanese/embeddings.bin'));
    expect(status.missing, isNot(contains('western/embeddings.bin')));
  });

  test('download paths cannot escape the scan asset root', () {
    expect(
      ScanAssetStore.isAllowedPath(
        '../private.bin',
        gallery: 'western',
      ),
      isFalse,
    );
    expect(
      ScanAssetStore.isAllowedPath(
        'western/embeddings.bin',
        gallery: 'western',
      ),
      isTrue,
    );
  });

  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('pokoin-scan-test-'));
  tearDown(() => root.deleteSync(recursive: true));

  void seed(String path, List<int> bytes) {
    final file = File('${root.path}/$path');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
  }

  test('zero-byte assets remain missing; a complete selected pack is ready',
      () {
    for (final path in [
      'card_detector.tflite',
      'milo_cnn.onnx',
      'japanese/embeddings.bin',
      'japanese/metadata.jsonl',
      'japanese/manifest.json'
    ]) {
      seed(path, []);
    }
    expect(ScanAssetStore.inspectRoot(root, gallery: 'japanese').missing,
        hasLength(5));
    for (final path in [
      'card_detector.tflite',
      'milo_cnn.onnx',
      'japanese/embeddings.bin',
      'japanese/metadata.jsonl',
      'japanese/manifest.json'
    ]) {
      seed(path, [1]);
    }
    expect(ScanAssetStore.inspectRoot(root, gallery: 'japanese').ready, isTrue);
    expect(ScanAssetStore.inspectRoot(root).ready, isFalse);
  });

  test('entire download plan is validated before any request or write',
      () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return http.Response('data', 200);
    });
    addTearDown(client.close);
    await expectLater(
        ScanAssetStore.download(
            gallery: 'western',
            destinationRoot: root,
            client: client,
            files: {
              'card_detector.tflite': Uri.parse('https://packs.test/model'),
              '../private': Uri.parse('https://packs.test/private')
            }),
        throwsArgumentError);
    expect(calls, 0);
    expect(root.listSync(), isEmpty);
  });

  test('successful download publishes the file and leaves no partial files',
      () async {
    final client = MockClient((_) async => http.Response('model-data', 200));
    addTearDown(client.close);
    await ScanAssetStore.download(
        gallery: 'western',
        destinationRoot: root,
        client: client,
        files: {'card_detector.tflite': Uri.parse('https://packs.test/model')});
    expect(File('${root.path}/card_detector.tflite').readAsStringSync(),
        'model-data');
    expect(root.listSync().whereType<File>().map((f) => f.path), hasLength(1));
  });

  for (final response in [
    http.Response('', 200),
    http.Response('oops', 503),
    http.Response('<html>not a model</html>', 200,
        headers: {'content-type': 'text/html'})
  ]) {
    test(
        'invalid response preserves an existing model (${response.statusCode}, ${response.body.length})',
        () async {
      seed('card_detector.tflite', [1, 2, 3]);
      final client = MockClient((_) async => response);
      addTearDown(client.close);
      await expectLater(
          ScanAssetStore.download(
              gallery: 'western',
              destinationRoot: root,
              client: client,
              files: {
                'card_detector.tflite': Uri.parse('https://packs.test/model')
              }),
          throwsA(isA<HttpException>()));
      expect(File('${root.path}/card_detector.tflite').readAsBytesSync(),
          [1, 2, 3]);
      expect(root.listSync(), hasLength(1));
    });
  }

  test('request timeout does not create a model', () async {
    final client = MockClient((_) => Completer<http.Response>().future);
    addTearDown(client.close);
    await expectLater(
        ScanAssetStore.download(
            gallery: 'western',
            destinationRoot: root,
            client: client,
            timeout: const Duration(milliseconds: 10),
            files: {
              'card_detector.tflite': Uri.parse('https://packs.test/model')
            }),
        throwsA(isA<TimeoutException>()));
    expect(root.listSync(), isEmpty);
  });
}
