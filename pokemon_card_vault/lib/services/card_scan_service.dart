import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/scan_marketplace.dart';

Uri cardScanIdentifyUri([Uri? base]) {
  final origin = base ?? Uri.base;
  if (origin.host == 'cardscan.pokoin.com') {
    return origin.replace(path: '/identify', query: '');
  }
  return origin.replace(path: '/cardscan/identify', query: '');
}

class CardScanIdentifyResult {
  const CardScanIdentifyResult({
    required this.hits,
    this.detectMs = 0,
    this.identifyMs = 0,
    this.error = '',
  });

  final List<CardScanHit> hits;
  final double detectMs;
  final double identifyMs;
  final String error;

  CardScanHit? get top1 => hits.isEmpty ? null : hits.first;
}

class CardScanService {
  CardScanService({http.Client? client, this.identifyUri})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Uri? identifyUri;

  Future<CardScanIdentifyResult> identifyBytes(List<int> bytes) async {
    if (bytes.isEmpty) {
      return const CardScanIdentifyResult(
        hits: [],
        error: 'No image to identify.',
      );
    }
    try {
      final uri = identifyUri ?? cardScanIdentifyUri();
      final request = http.MultipartRequest('POST', uri)
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: 'card.jpg',
          ),
        );
      final streamed = await _client.send(request);
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode >= 400) {
        return CardScanIdentifyResult(
          hits: const [],
          error: 'Scan API ${streamed.statusCode}: ${_errorFromBody(body)}',
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        return const CardScanIdentifyResult(
          hits: [],
          error: 'Scan API returned an unexpected payload.',
        );
      }
      final hitsRaw = decoded['hits'];
      final hits = <CardScanHit>[];
      if (hitsRaw is List) {
        for (final row in hitsRaw) {
          if (row is Map) {
            hits.add(
              CardScanHit.fromJson(Map<String, dynamic>.from(row)),
            );
          }
        }
      }
      return CardScanIdentifyResult(
        hits: hits,
        detectMs: (decoded['detect_ms'] is num)
            ? (decoded['detect_ms'] as num).toDouble()
            : 0,
        identifyMs: (decoded['identify_ms'] is num)
            ? (decoded['identify_ms'] as num).toDouble()
            : 0,
      );
    } catch (error) {
      return CardScanIdentifyResult(
        hits: const [],
        error: 'Could not reach scan API: $error',
      );
    }
  }

  String _errorFromBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['detail'] != null) {
        return '${decoded['detail']}';
      }
    } catch (_) {}
    return body.trim().isEmpty ? 'request failed' : body.trim();
  }
}
