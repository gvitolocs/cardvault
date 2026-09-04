import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'scan_debug_log.dart';

/// OpenCLIP ViT-B-32 check against the TrainingAI / CardVault classifier.
/// Used only to confirm or replace an imprecise Milo hit.
class VitHit {
  const VitHit({
    required this.id,
    required this.name,
    required this.score,
  });

  final String id;
  final String name;
  final double score;
}

class VitClassifier {
  VitClassifier({http.Client? client}) : _client = client ?? http.Client();

  static const endpoint = 'https://pokoin.com/api/trainingai-card-classify';
  static const fallback = 'https://trainingai.pokoin.com/api/classify';

  final http.Client _client;

  Future<VitHit?> classify(
    Uint8List jpeg, {
    int topK = 5,
    Duration timeout = const Duration(seconds: 6),
    bool tryFallback = true,
  }) async {
    if (jpeg.isEmpty) return null;
    final urls = tryFallback ? [endpoint, fallback] : [endpoint];
    for (final url in urls) {
      try {
        final response = await _client
            .post(
              Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'imageBase64': base64Encode(jpeg),
                'topK': topK,
              }),
            )
            .timeout(timeout);
        if (response.statusCode >= 400) {
          ScanDebugLog.i('vit $url status=${response.statusCode}');
          continue;
        }
        final hit = _parse(jsonDecode(response.body));
        if (hit != null) {
          ScanDebugLog.i('vit $url id=${hit.id} name=${hit.name} score=${hit.score.toStringAsFixed(3)}');
          return hit;
        }
      } catch (error) {
        ScanDebugLog.i('vit $url error $error');
      }
    }
    return null;
  }

  VitHit? _parse(Object? decoded) {
    if (decoded is! Map) return null;
    final rows = decoded['predictions'] ??
        decoded['matches'] ??
        decoded['results'] ??
        decoded['hits'] ??
        decoded['data'];
    if (rows is! List || rows.isEmpty) return null;
    final first = rows.first;
    if (first is! Map) return null;
    final id = '${first['id'] ?? first['card_id'] ?? first['blueprint_id'] ?? ''}';
    final name = '${first['name'] ?? first['label'] ?? ''}';
    final score = (first['score'] as num?)?.toDouble() ??
        (first['confidence'] as num?)?.toDouble() ??
        (first['cosine'] as num?)?.toDouble() ??
        0;
    if (id.isEmpty && name.isEmpty) return null;
    return VitHit(id: id, name: name, score: score);
  }
}
