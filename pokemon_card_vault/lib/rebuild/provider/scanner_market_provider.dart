import 'dart:convert';
import 'package:http/http.dart' as http;
import '../model/card.dart';
import '../model/scanner.dart';

/// Public prices only; failures do not prevent reviewing or saving a collection.
class ScannerMarketProvider {
  ScannerMarketProvider({http.Client? client}) : _client = client;
  final http.Client? _client;
  Future<Map<String, dynamic>> _get(
      String path, Map<String, String> query) async {
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(Uri.https('api.pokoin.com', path, query))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return {};
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return data is Map<String, dynamic> ? data : {};
    } catch (_) {
      return {};
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<ScannerMarketSnapshot> fetch(String id) async {
    final data = await Future.wait([
      _get('/api/marketplace-card-page', {'cardId': id}),
      _get('/api/marketplace-card-sales', {'cardId': id, 'slices': '1'}),
    ]);
    final raw = data[0]['card'];
    final card =
        raw is Map<String, dynamic> ? MarketplaceCard.fromJson(raw) : null;
    return ScannerMarketSnapshot(
        card: card?.id == id ? card : null,
        slices: data[1]['slices'] is List
            ? (data[1]['slices'] as List)
                .whereType<Map<String, dynamic>>()
                .map(ScannerSaleSlice.new)
                .toList()
            : const []);
  }
}
