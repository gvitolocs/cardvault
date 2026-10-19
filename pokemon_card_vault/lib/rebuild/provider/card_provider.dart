import 'dart:convert';
import 'package:http/http.dart' as http;
import '../model/card.dart';
import '../model/listing.dart';
import 'marketplace_http_provider.dart';

/// GET pubbliche del catalogo e delle inserzioni native/CardTrader effettive.
class CardProvider {
  CardProvider({http.Client? client, Uri? apiBase})
      : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _base = apiBase ??
            Uri.parse(const String.fromEnvironment('MARKETPLACE_API_BASE_URL',
                defaultValue: 'https://api.pokoin.com'));
  final http.Client _client;
  final bool _ownsClient;
  final Uri _base;
  late final _http = MarketplaceHttpProvider(_client);
  bool _disposed = false;

  Future<Map<String, dynamic>> _get(String path, String id,
      {String? limit}) async {
    if (!RegExp(r'^\d+$').hasMatch(id) || _disposed) {
      throw StateError('Invalid request');
    }
    final response = await _http.get(
        _base.resolve(path).replace(queryParameters: {
          'cardId': id,
          if (limit != null) 'limit': limit,
        }),
        timeout: const Duration(seconds: 15));
    if (response.statusCode != 200) throw StateError('Data unavailable');
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid data');
    }
    return data;
  }

  Future<MarketplaceCard> fetchCard(String id) async {
    final data = await _get('/api/marketplace-card-page', id);
    if (data['card'] is! Map<String, dynamic>) {
      throw const FormatException('Missing card');
    }
    final card = MarketplaceCard.fromJson(data['card'] as Map<String, dynamic>);
    if (card.id != id || card.name.isEmpty) {
      throw const FormatException('Invalid card');
    }
    return card;
  }

  Future<List<MarketplaceListing>> fetchListings(String id) async {
    final data = await _get('/api/marketplace-listings', id, limit: '80');
    final rows = data['listings'];
    if (rows is! List) throw const FormatException('Missing listings');
    final unique = <String, MarketplaceListing>{};
    for (final row in rows.whereType<Map<String, dynamic>>()) {
      final listing = MarketplaceListing.fromJson(row);
      if (listing.cardId == id && listing.isAvailable) {
        unique.putIfAbsent(listing.id, () => listing);
      }
    }
    final result = unique.values.toList()
      ..sort((a, b) {
        final price = a.pricePkn.compareTo(b.pricePkn);
        return price == 0 ? a.id.compareTo(b.id) : price;
      });
    return List.unmodifiable(result);
  }

  void dispose() {
    _disposed = true;
    _http.dispose();
    if (_ownsClient) _client.close();
  }
}
