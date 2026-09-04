import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'scan_debug_log.dart';

class ScanBox {
  const ScanBox({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.conf,
    this.quad = const [],
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final double conf;
  final List<double> quad;

  Rect get rect => Rect.fromLTRB(x1, y1, x2, y2);

  List<double> get corners {
    if (quad.length >= 8) return quad;
    return [x1, y1, x2, y1, x2, y2, x1, y2];
  }

  bool get isRotated {
    final c = corners;
    return (c[1] - c[3]).abs() > 3 || (c[0] - c[6]).abs() > 3;
  }

  factory ScanBox.fromMap(Map<Object?, Object?> raw) {
    final quad = (raw['quad'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const <double>[];
    return ScanBox(
      x1: (raw['x1'] as num?)?.toDouble() ?? 0,
      y1: (raw['y1'] as num?)?.toDouble() ?? 0,
      x2: (raw['x2'] as num?)?.toDouble() ?? 0,
      y2: (raw['y2'] as num?)?.toDouble() ?? 0,
      conf: (raw['conf'] as num?)?.toDouble() ?? 0,
      quad: quad,
    );
  }

  factory ScanBox.fromQuad(List<double> quad, double conf) {
    if (quad.length < 8) {
      return ScanBox(x1: 0, y1: 0, x2: 0, y2: 0, conf: conf);
    }
    final xs = [quad[0], quad[2], quad[4], quad[6]];
    final ys = [quad[1], quad[3], quad[5], quad[7]];
    return ScanBox(
      x1: xs.reduce((a, b) => a < b ? a : b),
      y1: ys.reduce((a, b) => a < b ? a : b),
      x2: xs.reduce((a, b) => a > b ? a : b),
      y2: ys.reduce((a, b) => a > b ? a : b),
      conf: conf,
      quad: quad,
    );
  }
}

class ScanHit {
  const ScanHit({
    required this.rank,
    required this.boxIndex,
    required this.score,
    required this.id,
    required this.name,
    required this.collectorNumber,
    required this.setName,
    required this.yoloConf,
    required this.quad,
  });

  final int rank;
  final int boxIndex;
  final double score;
  final String id;
  final String name;
  final String collectorNumber;
  final String setName;
  final double yoloConf;
  final List<double> quad;

  String get title => name.isNotEmpty ? name : (id.isNotEmpty ? id : 'Unknown card');

  String get subtitle {
    final parts = [
      if (collectorNumber.isNotEmpty) collectorNumber,
      if (setName.isNotEmpty) setName,
      if (id.isNotEmpty)
        '${ScanEngine.identity == 'ct_id' ? 'CardTrader' : 'TCGplayer'} $id',
    ];
    return parts.join(' • ');
  }

  factory ScanHit.fromMap(Map<Object?, Object?> raw) {
    final quad = (raw['quad'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList() ??
        const <double>[];
    return ScanHit(
      rank: (raw['rank'] as num?)?.toInt() ?? 0,
      boxIndex: (raw['boxIndex'] as num?)?.toInt() ?? 0,
      score: (raw['score'] as num?)?.toDouble() ?? 0,
      id: '${raw['id'] ?? ''}',
      name: '${raw['name'] ?? ''}',
      collectorNumber: '${raw['collectorNumber'] ?? ''}',
      setName: '${raw['set'] ?? ''}',
      yoloConf: (raw['yoloConf'] as num?)?.toDouble() ?? 0,
      quad: quad,
    );
  }
}

enum ScanMode { fast, multi }

class ScanResult {
  const ScanResult({
    required this.ok,
    required this.mode,
    required this.imgW,
    required this.imgH,
    required this.yoloBoxes,
    this.yoloRaw = 0,
    this.visionBoxes = 0,
    this.yoloConfs = const [],
    required this.yoloMs,
    this.visionMs = 0,
    required this.miloMs,
    this.preprocessMs = 0,
    this.predictMs = 0,
    this.searchMs = 0,
    this.gemvMs = 0,
    this.topkMs = 0,
    this.embeds = 0,
    required this.totalMs,
    required this.miloN,
    required this.hits,
    required this.boxes,
  });

  final bool ok;
  final ScanMode mode;
  final int imgW;
  final int imgH;
  final int yoloBoxes;
  final int yoloRaw;
  final int visionBoxes;
  final List<double> yoloConfs;
  final int yoloMs;
  final int visionMs;
  final int miloMs;
  final int preprocessMs;
  final int predictMs;
  final int searchMs;
  final int gemvMs;
  final int topkMs;
  final int embeds;
  final int totalMs;
  final int miloN;
  final List<ScanHit> hits;
  final List<ScanBox> boxes;

  ScanHit? get top => hits.isEmpty ? null : hits.first;

  List<ScanHit> get cards {
    if (mode != ScanMode.multi) return hits;
    final seen = <int>{};
    return hits.where((h) => seen.add(h.boxIndex)).toList();
  }
}

class ScanEngine {
  ScanEngine._();

  static const _channel = MethodChannel('pokoin.scan/engine');
  static const galleries = ['western', 'japanese', 'chinese'];
  static bool _ready = false;
  static int miloN = 0;
  static String identity = 'ct_id';
  static String miloBackend = 'none';
  static String yoloBackend = 'pending';
  static String gpuOwner = 'yolo';
  static int warmupMs = 0;
  static int predictMs = 0;
  static String gallery = 'western';
  static String? _supportDir;

  static Future<Map<String, dynamic>?> pickBackCamera() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMapMethod<String, dynamic>('pickBackCamera');
    } catch (error) {
      ScanDebugLog.i('pickBackCamera failed $error');
      return null;
    }
  }

  static Future<void> init() async {
    if (_ready) return;
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/fast_scan');
    await dir.create(recursive: true);
    _supportDir = dir.path;
    final stamp = await _bundleStamp();
    final stampFile = File('${dir.path}/bundle.stamp');
    final sameBuild =
        stampFile.existsSync() && stampFile.readAsStringSync() == stamp;
    await Future.wait([
      _copyAsset(
        'assets/models/card_detector.tflite',
        '${dir.path}/card_detector.tflite',
        force: !sameBuild,
      ),
      _copyAsset(
        'assets/models/milo.onnx',
        '${dir.path}/milo.onnx',
        force: !sameBuild,
      ),
      _copyAsset(
        'assets/models/milo_fp16.onnx',
        '${dir.path}/milo_fp16.onnx',
        force: !sameBuild,
      ),
      if (Platform.isAndroid)
        _copyAsset(
          'assets/models/milo_cnn.onnx',
          '${dir.path}/milo_cnn.onnx',
          force: !sameBuild,
        ),
      if (Platform.isIOS) _copyMiloCoreML(dir, force: !sameBuild),
      _ensureGallery(dir.path, gallery, force: !sameBuild),
    ]);
    if (!sameBuild) {
      for (final name in [
        'milo_qnn_gpu_ctx.onnx',
        'milo_qnn_gpu.skip',
        'milo_qnn_gpu.pending',
        'milo_qnn_gpu.prep',
      ]) {
        final stale = File('${dir.path}/$name');
        if (stale.existsSync()) stale.deleteSync();
      }
    }
    await stampFile.writeAsString(stamp, flush: true);
    await ScanDebugLog.attach(dir);
    identity = await _readIdentity('${dir.path}/western/manifest.json');
    final result = await _channel.invokeMapMethod<String, dynamic>('init', {
      'dir': dir.path,
      'gallery': gallery,
    });
    miloN = (result?['miloN'] as num?)?.toInt() ?? 0;
    miloBackend = '${result?['miloBackend'] ?? 'none'}';
    yoloBackend = '${result?['yoloBackend'] ?? yoloBackend}';
    gpuOwner = '${result?['gpuOwner'] ?? gpuOwner}';
    warmupMs = (result?['warmupMs'] as num?)?.toInt() ?? 0;
    predictMs = (result?['predictMs'] as num?)?.toInt() ?? 0;
    gallery = '${result?['gallery'] ?? gallery}';
    final yolo = result?['yolo'] == true;
    final milo = result?['milo'] == true;
    ScanDebugLog.i(
      'init yolo=$yolo milo=$milo backend=$miloBackend yoloBackend=${result?['yoloBackend'] ?? 'none'} '
      'gpuOwner=$gpuOwner warmupMs=$warmupMs predictMs=$predictMs miloN=$miloN identity=$identity gallery=$gallery '
      'dir=${dir.path}',
    );
    if (milo) {
      _ready = true;
      return;
    }
    throw StateError('Scan engine failed to load Milo');
  }

  static Future<void> setGallery(String name) async {
    await init();
    if (!galleries.contains(name) || name == gallery) return;
    final dir = _supportDir;
    if (dir == null) return;
    final stamp = await _bundleStamp();
    final stampFile = File('$dir/bundle.stamp');
    final sameBuild =
        stampFile.existsSync() && stampFile.readAsStringSync() == stamp;
    await _ensureGallery(dir, name, force: !sameBuild);
    final result = await _channel.invokeMapMethod<String, dynamic>('setCatalog', {
      'dir': dir,
      'gallery': name,
    });
    gallery = '${result?['gallery'] ?? name}';
    miloN = (result?['miloN'] as num?)?.toInt() ?? miloN;
    identity = await _readIdentity('$dir/$gallery/manifest.json');
    ScanDebugLog.i('catalog gallery=$gallery miloN=$miloN identity=$identity');
  }

  /// Exclusive Adreno owner. Android: YOLO GpuDelegate XOR identify CNN
  /// GpuDelegate (`milo_cnn.tflite`). Restarts the UI process. iOS ignores this.
  static Future<String> setGpuOwner(String owner) async {
    await init();
    if (!Platform.isAndroid) return gpuOwner;
    final result = await _channel.invokeMapMethod<String, dynamic>('setGpuOwner', {
      'owner': owner,
    });
    gpuOwner = '${result?['gpuOwner'] ?? owner}';
    yoloBackend = '${result?['yoloBackend'] ?? yoloBackend}';
    miloBackend = '${result?['miloBackend'] ?? miloBackend}';
    ScanDebugLog.i(
      'gpu owner=$gpuOwner yolo=$yoloBackend milo=$miloBackend restart=${result?['restart']}',
    );
    return gpuOwner;
  }

  /// YOLO GPU/CPU inside the YOLO-owner process. No-op if Milo owns Adreno.
  static Future<String> setYoloGpu(bool gpu) async {
    await init();
    if (!Platform.isAndroid) return yoloBackend;
    if (gpuOwner == 'milo') return yoloBackend;
    final result = await _channel.invokeMapMethod<String, dynamic>('setYoloAccel', {
      'gpu': gpu,
    });
    yoloBackend = '${result?['yoloBackend'] ?? yoloBackend}';
    miloBackend = '${result?['miloBackend'] ?? miloBackend}';
    ScanDebugLog.i(
      'accel switch yolo=$yoloBackend milo=$miloBackend yoloGpu=$gpu',
    );
    return yoloBackend;
  }

  static Future<ScanResult> scan(
    Uint8List bytes, {
    int topK = 5,
    ScanMode mode = ScanMode.fast,
  }) async {
    await init();
    final raw = await _channel.invokeMapMethod<String, dynamic>('scan', {
      'bytes': bytes,
      'topK': topK,
      'mode': mode == ScanMode.multi ? 'multi' : 'fast',
    });
    return _parse(raw);
  }

  /// Live camera path: BGRA (iOS) or YUV420 (Android). Avoids JPEG encode/decode.
  static Future<ScanResult> scanFrame({
    required String format,
    required int width,
    required int height,
    int topK = 5,
    ScanMode mode = ScanMode.fast,
    bool identify = true,
    Uint8List? bgra,
    int bgraStride = 0,
    Uint8List? y,
    Uint8List? u,
    Uint8List? v,
    int yStride = 0,
    int uStride = 0,
    int vStride = 0,
    int uvPixelStride = 1,
    int sensorOrientation = 0,
  }) async {
    await init();
    final raw = await _channel.invokeMapMethod<String, dynamic>('scanFrame', {
      'format': format,
      'width': width,
      'height': height,
      'topK': topK,
      'mode': mode == ScanMode.multi ? 'multi' : 'fast',
      'identify': identify,
      'sensorOrientation': sensorOrientation,
      'bgra': bgra,
      'bgraStride': bgraStride,
      'y': y,
      'u': u,
      'v': v,
      'yStride': yStride,
      'uStride': uStride,
      'vStride': vStride,
      'uvPixelStride': uvPixelStride,
    });
    return _parse(raw);
  }

  static Future<ScanResult> identifyFrame({
    required String format,
    required int width,
    required int height,
    required List<ScanBox> boxes,
    int topK = 5,
    ScanMode mode = ScanMode.fast,
    Uint8List? bgra,
    int bgraStride = 0,
    Uint8List? y,
    Uint8List? u,
    Uint8List? v,
    int yStride = 0,
    int uStride = 0,
    int vStride = 0,
    int uvPixelStride = 1,
    int sensorOrientation = 0,
  }) async {
    await init();
    final raw = await _channel.invokeMapMethod<String, dynamic>('identifyFrame', {
      'format': format,
      'width': width,
      'height': height,
      'topK': topK,
      'mode': mode == ScanMode.multi ? 'multi' : 'fast',
      'sensorOrientation': sensorOrientation,
      'boxes': [
        for (final box in boxes)
          {
            'x1': box.x1,
            'y1': box.y1,
            'x2': box.x2,
            'y2': box.y2,
            'conf': box.conf,
            'quad': box.corners,
            'rotated': box.isRotated,
          },
      ],
      'bgra': bgra,
      'bgraStride': bgraStride,
      'y': y,
      'u': u,
      'v': v,
      'yStride': yStride,
      'uStride': uStride,
      'vStride': vStride,
      'uvPixelStride': uvPixelStride,
    });
    return _parse(raw);
  }

  /// Opens the card page in a real browser. Plain https://pokoin.com is a
  /// Universal Link on this phone (CardVault). Chrome gets the https URL as
  /// an x-callback query and reuses the same tab.
  static Future<bool> openInDefaultBrowser(Uri uri) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('openUrl', {
        'url': uri.toString(),
      });
      var ok = false;
      var handler = '';
      if (raw is bool) {
        ok = raw;
      } else if (raw is Map) {
        ok = raw['ok'] == true;
        handler = '${raw['handler'] ?? ''}';
      }
      ScanDebugLog.i('openUrl handler=$handler launched=$ok');
      if (ok) return true;
    } catch (error) {
      ScanDebugLog.i('openUrl native failed $error');
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static ScanResult _parse(Map<String, dynamic>? raw) {
    if (raw == null) {
      throw StateError('Scan returned no result');
    }
    final hits = ((raw['hits'] as List?) ?? const [])
        .whereType<Map>()
        .map((entry) => ScanHit.fromMap(Map<Object?, Object?>.from(entry)))
        .toList();
    var boxes = ((raw['boxes'] as List?) ?? const [])
        .whereType<Map>()
        .map((entry) => ScanBox.fromMap(Map<Object?, Object?>.from(entry)))
        .toList();
    if (boxes.isEmpty) {
      boxes = hits
          .map((hit) => ScanBox.fromQuad(hit.quad, hit.yoloConf))
          .where((box) => box.x2 > box.x1 && box.y2 > box.y1)
          .toList();
    }
    return ScanResult(
      ok: raw['ok'] == true,
      mode: raw['mode'] == 'multi' ? ScanMode.multi : ScanMode.fast,
      imgW: (raw['imgW'] as num?)?.toInt() ?? 0,
      imgH: (raw['imgH'] as num?)?.toInt() ?? 0,
      yoloBoxes: (raw['yoloBoxes'] as num?)?.toInt() ?? boxes.length,
      yoloRaw: (raw['yoloRaw'] as num?)?.toInt() ?? 0,
      visionBoxes: (raw['visionBoxes'] as num?)?.toInt() ?? 0,
      yoloConfs: ((raw['yoloConfs'] as List?) ?? const [])
          .map((e) => (e as num).toDouble())
          .toList(),
      yoloMs: (raw['yoloMs'] as num?)?.toInt() ?? 0,
      visionMs: (raw['visionMs'] as num?)?.toInt() ?? 0,
      miloMs: (raw['miloMs'] as num?)?.toInt() ?? 0,
      preprocessMs: (raw['preprocessMs'] as num?)?.toInt() ?? 0,
      predictMs: (raw['predictMs'] as num?)?.toInt() ?? 0,
      searchMs: (raw['searchMs'] as num?)?.toInt() ?? 0,
      gemvMs: (raw['gemvMs'] as num?)?.toInt() ?? 0,
      topkMs: (raw['topkMs'] as num?)?.toInt() ?? 0,
      embeds: (raw['embeds'] as num?)?.toInt() ?? 0,
      totalMs: (raw['totalMs'] as num?)?.toInt() ?? 0,
      miloN: (raw['miloN'] as num?)?.toInt() ?? miloN,
      hits: hits,
      boxes: boxes,
    );
  }

  static Future<void> _copyMiloCoreML(Directory dir, {bool force = false}) async {
    const files = [
      'Manifest.json',
      'Data/com.apple.CoreML/model.mlmodel',
      'Data/com.apple.CoreML/weights/weight.bin',
    ];
    try {
      final destRoot = Directory('${dir.path}/milo.mlpackage');
      var copied = 0;
      var changed = false;
      for (final rel in files) {
        final asset = 'assets/models/milo.mlpackage/$rel';
        final destPath = '${destRoot.path}/$rel';
        final dest = File(destPath);
        await dest.parent.create(recursive: true);
        final before = dest.existsSync() ? dest.lengthSync() : -1;
        await _copyAsset(asset, destPath, force: force);
        copied++;
        if (!dest.existsSync() || dest.lengthSync() != before) {
          changed = true;
        }
      }
      if (changed) {
        final compiled = Directory('${dir.path}/milo.mlmodelc');
        if (compiled.existsSync()) {
          await compiled.delete(recursive: true);
        }
        final stamp = File('${dir.path}/milo.mlmodelc.stamp');
        if (stamp.existsSync()) await stamp.delete();
      }
      ScanDebugLog.i('coreml asset files=$copied changed=$changed');
    } catch (error) {
      ScanDebugLog.i('coreml copy skip $error');
    }
  }

  static Future<void> _ensureGallery(
    String root,
    String name, {
    bool force = false,
  }) async {
    if (!galleries.contains(name)) {
      throw ArgumentError.value(name, 'name', 'unknown gallery');
    }
    final dest = Directory('$root/$name');
    await dest.create(recursive: true);
    final assetRoot = Platform.isAndroid
        ? 'assets/milo_cnn_index/$name'
        : 'assets/milo_index/$name';
    await Future.wait([
      _copyAsset(
        '$assetRoot/embeddings.bin',
        '${dest.path}/embeddings.bin',
        force: force,
      ),
      _copyAsset(
        '$assetRoot/metadata.jsonl',
        '${dest.path}/metadata.jsonl',
        force: force,
      ),
      _copyAsset(
        '$assetRoot/manifest.json',
        '${dest.path}/manifest.json',
        force: force,
      ),
    ]);
  }

  static Future<String> _bundleStamp() async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('bundleStamp');
      if (raw != null && '$raw'.isNotEmpty) return '$raw';
    } catch (_) {}
    return '0';
  }

  static Future<void> _copyAsset(
    String asset,
    String destPath, {
    bool force = false,
  }) async {
    final dest = File(destPath);
    if (!force && dest.existsSync() && dest.lengthSync() > 0) {
      return;
    }
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    if (!force && dest.existsSync() && dest.lengthSync() == bytes.length) {
      return;
    }
    await dest.parent.create(recursive: true);
    await dest.writeAsBytes(bytes, flush: true);
  }

  static Future<String> _readIdentity(String path) async {
    try {
      final raw = await File(path).readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['identity'] is String) {
        final value = (decoded['identity'] as String).trim();
        if (value.isNotEmpty) return value;
      }
    } catch (_) {}
    return 'tcgplayer';
  }
}
