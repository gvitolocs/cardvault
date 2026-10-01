import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ScanAssetStatus {
  const ScanAssetStatus({
    required this.root,
    required this.gallery,
    required this.missing,
  });

  final Directory root;
  final String gallery;
  final List<String> missing;

  bool get ready => missing.isEmpty;

  String get message {
    if (ready) return 'Scan assets ready for $gallery.';
    return 'Download the selected scan pack before starting the camera: '
        '${missing.join(', ')}';
  }
}

/// Runtime-managed scan data. Large models and galleries are intentionally not
/// Flutter assets: the user selects which pack to download for this device.
class ScanAssetStore {
  ScanAssetStore._();

  static const galleries = <String>['western', 'japanese', 'chinese'];
  static const _modelFiles = <String>[
    'card_detector.tflite',
  ];
  static const _optionalModelFiles = <String>[
    'milo.onnx',
    'milo_fp16.onnx',
    'milo_cnn.onnx',
  ];
  static const _galleryFiles = <String>[
    'embeddings.bin',
    'metadata.jsonl',
    'manifest.json',
  ];

  static Future<Directory> root() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/fast_scan');
    await dir.create(recursive: true);
    return dir;
  }

  static Future<ScanAssetStatus> inspect({String gallery = 'western'}) async {
    return inspectRoot(await root(), gallery: gallery);
  }

  static ScanAssetStatus inspectRoot(
    Directory root, {
    String gallery = 'western',
  }) {
    if (!galleries.contains(gallery)) {
      throw ArgumentError.value(gallery, 'gallery', 'unknown scan gallery');
    }
    final missing = <String>[
      for (final relative in _modelFiles)
        if (!File('${root.path}/$relative').existsSync()) relative,
    ];
    final hasMilo = File('${root.path}/milo.onnx').existsSync() ||
        File('${root.path}/milo_cnn.onnx').existsSync();
    if (!hasMilo) missing.add('milo.onnx or milo_cnn.onnx');
    for (final file in _galleryFiles) {
      final relative = '$gallery/$file';
      if (!File('${root.path}/$relative').existsSync()) missing.add(relative);
    }
    return ScanAssetStatus(root: root, gallery: gallery, missing: missing);
  }

  /// Downloads exactly the files selected by the caller into the runtime pack.
  /// Keys are paths relative to the scan root, e.g. `western/embeddings.bin`.
  /// The caller decides which gallery and URLs to provide.
  static Future<ScanAssetStatus> download({
    required String gallery,
    required Map<String, Uri> files,
    http.Client? client,
    void Function(String path, int received, int? total)? onProgress,
  }) async {
    final root = await ScanAssetStore.root();
    final httpClient = client ?? http.Client();
    final ownsClient = client == null;
    try {
      for (final entry in files.entries) {
        if (!isAllowedPath(entry.key, gallery: gallery)) {
          throw ArgumentError.value(
            entry.key,
            'files',
            'path is not a valid scan asset for $gallery',
          );
        }
        await _downloadOne(
          httpClient,
          root,
          entry.key,
          entry.value,
          onProgress: onProgress,
        );
      }
    } finally {
      if (ownsClient) httpClient.close();
    }
    return inspectRoot(root, gallery: gallery);
  }

  static bool isAllowedPath(String path, {required String gallery}) {
    if (path.contains('..') || path.startsWith('/') || path.contains('\\')) {
      return false;
    }
    return _modelFiles.contains(path) ||
        _optionalModelFiles.contains(path) ||
        path.startsWith('$gallery/') &&
            _galleryFiles.contains(path.substring(gallery.length + 1));
  }

  static Future<void> _downloadOne(
    http.Client client,
    Directory root,
    String relative,
    Uri uri, {
    void Function(String path, int received, int? total)? onProgress,
  }) async {
    final request = http.Request('GET', uri);
    final response = await client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Scan asset download failed (${response.statusCode})',
        uri: uri,
      );
    }

    final destination = File('${root.path}/$relative');
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.part');
    if (temporary.existsSync()) await temporary.delete();
    var received = 0;
    final sink = temporary.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(relative, received, response.contentLength);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (destination.existsSync()) await destination.delete();
    await temporary.rename(destination.path);
  }
}
