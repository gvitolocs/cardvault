import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
    return 'The selected scan pack is missing or incomplete: '
        '${missing.join(', ')}';
  }
}

/// Native engines need real files in application support. Android provisions
/// its compatible CNN pack from the APK, never from an assumed CDN endpoint.
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

  static bool _hasData(File file) => file.existsSync() && file.lengthSync() > 0;

  /// Stage a complete Android CNN pack before opening the camera. Validate all
  /// files before publishing, and write the APK revision last. An absent or
  /// invalid bundle does not overwrite previously provisioned files.
  static Future<ScanAssetStatus> prepareAndroidBundle({
    String gallery = 'western',
    AssetBundle? bundle,
    Directory? destinationRoot,
    String? bundleRevision,
  }) async {
    if (!galleries.contains(gallery)) {
      throw ArgumentError.value(gallery, 'gallery', 'unknown scan gallery');
    }
    final destination = destinationRoot ?? await root();
    await destination.create(recursive: true);
    var revision = bundleRevision;
    if (revision == null) {
      try {
        revision = await const MethodChannel('pokoin.scan/engine')
            .invokeMethod<String>('bundleStamp');
      } catch (_) {
        // Without a reliable APK revision, do not reuse an unverified cache.
      }
    }
    final stamp = File('${destination.path}/bundle-$gallery.stamp');
    final current =
        inspectRoot(destination, gallery: gallery, requireCnn: true);
    if (revision != null &&
        revision.isNotEmpty &&
        current.ready &&
        stamp.existsSync() &&
        await stamp.readAsString() == revision) {
      try {
        _validateAndroidGallery(destination, gallery, checkMetadata: true);
        return current;
      } on FormatException {
        // Repair truncated/corrupt runtime data from the original APK.
      }
    }
    final source = bundle ?? rootBundle;
    final files = <String, String>{
      'card_detector.tflite': 'assets/models/card_detector.tflite',
      'milo_cnn.onnx': 'assets/models/milo_cnn.onnx',
      for (final file in _galleryFiles)
        '$gallery/$file': 'assets/milo_cnn_index/$gallery/$file',
    };
    final staging = await destination.createTemp('.bundle-$gallery-');
    try {
      final missing = <String>[];
      for (final entry in files.entries) {
        ByteData data;
        try {
          data = await source.load(entry.value);
        } on FlutterError {
          missing.add(entry.value);
          continue;
        }
        if (data.lengthInBytes == 0) {
          missing.add(entry.value);
          continue;
        }
        final file = File('${staging.path}/${entry.key}');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
      if (missing.isNotEmpty) {
        return ScanAssetStatus(
            root: destination, gallery: gallery, missing: missing);
      }
      _validateAndroidGallery(staging, gallery, checkMetadata: true);
      if (stamp.existsSync()) await stamp.delete();
      for (final relative in files.keys) {
        final file = File('${destination.path}/$relative');
        await file.parent.create(recursive: true);
        await File('${staging.path}/$relative').rename(file.path);
      }
      await stamp.writeAsString(revision ?? '', flush: true);
      return inspectRoot(destination, gallery: gallery, requireCnn: true);
    } finally {
      await staging.delete(recursive: true);
    }
  }

  static void _validateAndroidGallery(Directory root, String gallery,
      {bool checkMetadata = false}) {
    final base = '${root.path}/$gallery';
    final manifest = jsonDecode(File('$base/manifest.json').readAsStringSync());
    if (manifest is! Map ||
        manifest['dim'] != 128 ||
        manifest['embedder'] != 'mobilenet_v2_448_128' ||
        manifest['identity'] != 'ct_id' ||
        manifest['n'] is! int ||
        (manifest['n'] as int) <= 0) {
      throw const FormatException('Incompatible Android CNN gallery.');
    }
    final n = manifest['n'] as int;
    if (File('$base/embeddings.bin').lengthSync() != n * 128 * 4) {
      throw const FormatException('Incomplete Android embedding matrix.');
    }
    if (checkMetadata) {
      final rows = const LineSplitter()
          .convert(File('$base/metadata.jsonl').readAsStringSync())
          .where((line) => line.trim().isNotEmpty);
      if (rows.length != n ||
          rows.any((row) {
            final record = jsonDecode(row);
            return record is! Map || int.tryParse('${record['id']}') == null;
          })) {
        throw const FormatException('Incomplete Android gallery metadata.');
      }
    }
  }

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
    bool requireCnn = false,
  }) {
    if (!galleries.contains(gallery)) {
      throw ArgumentError.value(gallery, 'gallery', 'unknown scan gallery');
    }
    final missing = <String>[
      for (final relative in _modelFiles)
        if (!_hasData(File('${root.path}/$relative'))) relative,
    ];
    final hasMilo = (!requireCnn && _hasData(File('${root.path}/milo.onnx'))) ||
        _hasData(File('${root.path}/milo_cnn.onnx'));
    if (!hasMilo) {
      missing.add(requireCnn ? 'milo_cnn.onnx' : 'milo.onnx or milo_cnn.onnx');
    }
    for (final file in _galleryFiles) {
      final relative = '$gallery/$file';
      if (!_hasData(File('${root.path}/$relative'))) missing.add(relative);
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
    Directory? destinationRoot,
    Duration timeout = const Duration(seconds: 45),
    void Function(String path, int received, int? total)? onProgress,
  }) async {
    // Validate the entire plan before writing any files.
    for (final entry in files.entries) {
      if (!isAllowedPath(entry.key, gallery: gallery) ||
          entry.value.scheme != 'https' ||
          entry.value.host.isEmpty ||
          entry.value.userInfo.isNotEmpty) {
        throw ArgumentError('Invalid scan asset path or HTTPS URL.');
      }
    }
    if (!galleries.contains(gallery)) {
      throw ArgumentError.value(gallery, 'gallery', 'unknown scan gallery');
    }
    final root = destinationRoot ?? await ScanAssetStore.root();
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
          timeout: timeout,
          onProgress: onProgress,
        );
      }
    } finally {
      if (ownsClient) httpClient.close();
    }
    return inspectRoot(root, gallery: gallery);
  }

  static bool isAllowedPath(String path, {required String gallery}) {
    if (!galleries.contains(gallery)) return false;
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
    required Duration timeout,
    void Function(String path, int received, int? total)? onProgress,
  }) async {
    final request = http.Request('GET', uri);
    request.followRedirects = false;
    request.headers['Accept-Encoding'] = 'identity';
    final response = await client.send(request).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Scan asset download failed (${response.statusCode})',
        uri: uri,
      );
    }
    if (response.headers['content-type']?.contains('text/html') == true) {
      throw HttpException('Scan asset source returned a web page.', uri: uri);
    }

    final destination = File('${root.path}/$relative');
    await destination.parent.create(recursive: true);
    final temporary = File(
      '${destination.path}.${DateTime.now().microsecondsSinceEpoch}.part',
    );
    var received = 0;
    final sink = temporary.openWrite();
    try {
      try {
        await for (final chunk in response.stream.timeout(timeout)) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(relative, received, response.contentLength);
        }
        await sink.flush();
        if (received == 0 ||
            (response.contentLength != null &&
                received != response.contentLength)) {
          throw HttpException('Scan asset download is empty or incomplete.',
              uri: uri);
        }
      } finally {
        await sink.close();
      }
      await temporary.rename(destination.path);
    } catch (_) {
      if (temporary.existsSync()) await temporary.delete();
      rethrow;
    }
  }
}
