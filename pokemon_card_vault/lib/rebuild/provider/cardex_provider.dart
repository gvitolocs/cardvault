import 'dart:convert';
import 'package:http/http.dart' as http;
import '../model/cardex.dart';
import '../model/marketplace_home.dart';
import 'marketplace_http_provider.dart';

/// DAO del catalogo completo, indipendente dalle offerte disponibili.
class CardexProvider {
  CardexProvider({http.Client? client, Uri? apiBase})
      : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _base = apiBase ??
            Uri.parse(const String.fromEnvironment('MARKETPLACE_API_BASE_URL',
                defaultValue: 'https://api.pokoin.com'));
  final http.Client _client;
  final bool _ownsClient;
  final Uri _base;
  late final _http = MarketplaceHttpProvider(_client);

  Future<Map<String, dynamic>> _get(Map<String, String> query) async {
    final response = await _http.get(
        _base
            .resolve('/api/marketplace-expansion-page')
            .replace(queryParameters: query),
        timeout: const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('Catalog unavailable');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid catalog');
    }
    return json;
  }

  Future<List<MarketplaceExpansion>> fetchExpansions() async {
    final json = await _get({'limit': '2000'});
    if (json['expansions'] is! List) {
      throw const FormatException('Missing expansions');
    }
    return List.unmodifiable((json['expansions'] as List).map((row) {
      if (row is! Map) throw const FormatException('Invalid expansion');
      final expansion =
          MarketplaceExpansion.fromJson(Map<String, dynamic>.from(row));
      if (expansion.slug.isEmpty || expansion.name.isEmpty) {
        throw const FormatException('Invalid expansion identity');
      }
      return expansion;
    }));
  }

  Future<CardexPage> fetchPage(String slug,
      {int offset = 0, int limit = 48}) async {
    if (slug.trim().isEmpty || offset < 0 || limit < 1 || limit > 400) {
      throw ArgumentError('Invalid catalog page');
    }
    final json = await _get({
      'slug': slug,
      'productType': 'card',
      'offset': '$offset',
      'limit': '$limit'
    });
    final total = int.tryParse('${json['total']}');
    final returnedOffset = int.tryParse('${json['offset']}');
    if (json['expansion'] is! Map ||
        json['cards'] is! List ||
        json['hasMore'] is! bool ||
        total == null ||
        total < 0 ||
        returnedOffset != offset) {
      throw const FormatException('Invalid album page');
    }
    final expansion = MarketplaceExpansion.fromJson(
        Map<String, dynamic>.from(json['expansion'] as Map));
    if (expansion.slug != slug) throw const FormatException('Wrong expansion');
    final cards = (json['cards'] as List).map((row) {
      if (row is! Map) throw const FormatException('Invalid album card');
      final card =
          MarketplaceCardPreview.fromJson(Map<String, dynamic>.from(row));
      if (!RegExp(r'^[1-9]\d*$').hasMatch(card.id) || card.name.isEmpty) {
        throw const FormatException('Invalid card identity');
      }
      return card;
    }).toList();
    if (json['hasMore'] == true && cards.isEmpty) {
      throw const FormatException('Empty unfinished page');
    }
    return CardexPage(
        expansion: expansion,
        cards: cards,
        offset: offset,
        hasMore: json['hasMore'] as bool,
        total: total);
  }

  void dispose() {
    _http.dispose();
    if (_ownsClient) _client.close();
  }
}
