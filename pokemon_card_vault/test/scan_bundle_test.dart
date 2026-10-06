import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: avoid_relative_lib_imports
import '../lib/scan_v2/scan_assets.dart';

class _Bundle extends CachingAssetBundle {
  _Bundle(this.files);
  final Map<String, List<int>> files;
  int loads = 0;
  @override
  Future<ByteData> load(String key) async {
    loads++;
    final bytes = files[key];
    if (bytes == null) throw FlutterError('Missing test asset: $key');
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

class _DiskBundle extends CachingAssetBundle {
  _DiskBundle(this.root);
  final Directory root;
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File('${root.path}/$key').readAsBytes());
}

// Tiny fixtures exercise provisioning only, never recognition or APK assets.
_Bundle _fixture(String gallery) => _Bundle({
      'assets/models/card_detector.tflite': [1, 2],
      'assets/models/milo_cnn.onnx': [3, 4],
      'assets/milo_cnn_index/$gallery/embeddings.bin': List.filled(512, 0),
      'assets/milo_cnn_index/$gallery/metadata.jsonl':
          utf8.encode('{"id":1}\n'),
      'assets/milo_cnn_index/$gallery/manifest.json': utf8.encode(jsonEncode({
        'n': 1,
        'dim': 128,
        'embedder': 'mobilenet_v2_448_128',
        'identity': 'ct_id',
      })),
    });

void main() {
  late Directory root;
  setUp(
      () => root = Directory.systemTemp.createTempSync('pokoin-bundle-test-'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<ScanAssetStatus> prepare(_Bundle bundle,
          {String revision = '58:one'}) =>
      ScanAssetStore.prepareAndroidBundle(
          bundle: bundle, destinationRoot: root, bundleRevision: revision);

  test('missing APK assets do not publish partial files or claim readiness',
      () async {
    final bundle = _fixture('western')
      ..files.remove('assets/models/milo_cnn.onnx');
    final result = await prepare(bundle);
    expect(result.ready, isFalse);
    expect(result.missing, ['assets/models/milo_cnn.onnx']);
    expect(root.listSync(), isEmpty);
  });

  test('invalid matrix preserves the existing model and clears staging',
      () async {
    final old = File('${root.path}/milo_cnn.onnx')..writeAsBytesSync([9]);
    final bundle = _fixture('western');
    bundle.files['assets/milo_cnn_index/western/embeddings.bin'] = [1];
    await expectLater(prepare(bundle), throwsFormatException);
    expect(old.readAsBytesSync(), [9]);
    expect(root.listSync(), hasLength(1));
  });

  test('wrong embedder or metadata is rejected before publication', () async {
    for (final key in ['manifest.json', 'metadata.jsonl']) {
      final bundle = _fixture('western');
      bundle.files['assets/milo_cnn_index/western/$key'] = utf8.encode('{}');
      await expectLater(prepare(bundle), throwsFormatException);
      expect(root.listSync(), isEmpty);
    }
  });

  test(
      'ready bundle provisions CNN and skips copying for the same APK revision',
      () async {
    final bundle = _fixture('western');
    expect((await prepare(bundle)).ready, isTrue);
    expect(File('${root.path}/milo_cnn.onnx').readAsBytesSync(), [3, 4]);
    expect(File('${root.path}/milo.onnx').existsSync(), isFalse);
    final loads = bundle.loads;
    expect((await prepare(bundle)).ready, isTrue);
    expect(bundle.loads, loads);
    expect(root.listSync().whereType<Directory>(), hasLength(1));
    expect(Directory('${root.path}/western').existsSync(), isTrue);
  });

  test('a new APK revision refreshes same-size models', () async {
    final bundle = _fixture('western');
    await prepare(bundle);
    bundle.files['assets/models/milo_cnn.onnx'] = [5, 6];
    await prepare(bundle, revision: '58:two');
    expect(File('${root.path}/milo_cnn.onnx').readAsBytesSync(), [5, 6]);
  });

  test('cached matrix corruption is repaired automatically', () async {
    final bundle = _fixture('western');
    await prepare(bundle);
    File('${root.path}/western/embeddings.bin').writeAsBytesSync([1]);
    expect((await prepare(bundle)).ready, isTrue);
    expect(File('${root.path}/western/embeddings.bin').lengthSync(), 512);
  });

  test('Android cannot substitute an unrelated milo.onnx for the CNN', () {
    File('${root.path}/milo.onnx').writeAsBytesSync([1]);
    expect(ScanAssetStore.inspectRoot(root, requireCnn: true).missing,
        contains('milo_cnn.onnx'));
  });

  for (final gallery in ScanAssetStore.galleries) {
    test('original supplied Android pack provisions $gallery', () async {
      // Supports both direct app tests and the isolated scanner harness.
      final project = Directory('assets/models').existsSync()
          ? Directory.current
          : Directory('../cardvault-repo/pokemon_card_vault');
      expect(Directory('${project.path}/assets/models').existsSync(), isTrue,
          reason: 'This integration test requires the original local pack.');
      final result = await ScanAssetStore.prepareAndroidBundle(
          gallery: gallery,
          destinationRoot: root,
          bundle: _DiskBundle(project),
          bundleRevision: 'original-pack');
      expect(result.ready, isTrue);
      final manifest = jsonDecode(
          File('${root.path}/$gallery/manifest.json').readAsStringSync());
      expect(manifest['n'],
          {'western': 26689, 'japanese': 24067, 'chinese': 10956}[gallery]);
      expect(File('${root.path}/milo_cnn.onnx').lengthSync(), 9524623);
      expect(File('${root.path}/card_detector.tflite').lengthSync(), 5327632);
    });
  }
}
