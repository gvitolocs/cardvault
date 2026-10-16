import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/marketplace_home.dart';
import '../model/marketplace_search.dart';
import 'marketplace_http_provider.dart';

class MarketplaceSearchProvider {
  MarketplaceSearchProvider(
      {http.Client? client,
      Uri? apiBase,
      this.timeout = const Duration(seconds: 12)})
      : _client = client ?? http.Client(),
        _ownsClient = client == null,
        apiBase = apiBase ??
            Uri.parse(const String.fromEnvironment('MARKETPLACE_API_BASE_URL',
                defaultValue: 'https://api.pokoin.com'));

  final http.Client _client;
  final bool _ownsClient;
  final Uri apiBase;
  final Duration timeout;
  late final _http = MarketplaceHttpProvider(_client);

  Future<MarketplaceSearchPage> fetch(MarketplaceSearchRequest request) async {
    final response = await _http.get(
        apiBase
            .resolve('/api/marketplace-search-page')
            .replace(queryParameters: {
          'query': request.query,
          'offset': '${request.offset}',
          'limit': '${request.limit}',
          'includeFacets': '0',
          'search_language': request.searchLanguage,
          'print_language': request.printLanguage,
          if (request.productType.isNotEmpty)
            'productType': request.productType,
        }),
        timeout: timeout);
    if (response.statusCode != 200) throw StateError('Search unavailable');
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map || json['cards'] is! List || json['hasMore'] is! bool) {
      throw const FormatException('Invalid search page');
    }
    final cards = <MarketplaceCardPreview>[];
    for (final row in json['cards'] as List) {
      if (row is! Map) throw const FormatException('Invalid search card');
      final card =
          MarketplaceCardPreview.fromJson(Map<String, dynamic>.from(row));
      if (!RegExp(r'^[1-9]\d*$').hasMatch(card.id) || card.name.isEmpty) {
        throw const FormatException('Invalid search identity');
      }
      cards.add(card);
    }
    final total = int.tryParse('${json['total']}');
    return MarketplaceSearchPage(
        cards: cards,
        hasMore: json['hasMore'] as bool,
        total: total != null && total >= 0 ? total : null);
  }

  void cancelPending() => _http.cancelActive();

  void dispose() {
    _http.dispose();
    if (_ownsClient) _client.close();
  }
}
