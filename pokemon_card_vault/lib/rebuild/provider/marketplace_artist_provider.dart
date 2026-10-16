import 'dart:convert';
import 'dart:isolate';

import 'package:http/http.dart' as http;
import 'package:pokoin_suggest/pokoin_suggest.dart' show compactQuery;

import '../model/marketplace_artist_catalog.dart';
import '../model/marketplace_home.dart';
import 'marketplace_http_provider.dart';

class MarketplaceArtistProvider {
  MarketplaceArtistProvider(
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

  Future<MarketplaceArtistCatalog> fetch(String slug) async {
    final response = await _http.get(
        apiBase
            .resolve('/api/marketplace-artist-cards')
            .replace(queryParameters: {'artistSlug': slug, 'limit': '5000'}),
        timeout: timeout);
    if (response.statusCode != 200) {
      throw StateError('Artist search unavailable');
    }
    final bytes = response.bodyBytes;
    // This API currently returns an artist's catalog, not a filtered page.
    // Decode/prepare its larger response away from UI frames.
    return Isolate.run(() => _decode(utf8.decode(bytes), slug));
  }

  static MarketplaceArtistCatalog _decode(String text, String slug) {
    final json = jsonDecode(text);
    if (json is! Map || json['cards'] is! List) {
      throw const FormatException('Invalid artist catalog');
    }
    final artist = json['artist'];
    final rows = json['cards'] as List;
    if (artist is! Map || artist['slug'] != slug) {
      throw const FormatException('Invalid artist identity');
    }
    final count = int.tryParse('${artist['cardCount']}');
    if (count == null || count > rows.length || rows.length > 5000) {
      throw const FormatException('Incomplete artist catalog');
    }
    final cards = <MarketplaceArtistCard>[];
    final ids = <String>{};
    for (final row in rows) {
      if (row is! Map) throw const FormatException('Invalid artist card');
      final data = Map<String, dynamic>.from(row);
      final card = MarketplaceCardPreview.fromJson(data);
      if (!RegExp(r'^[1-9]\d*$').hasMatch(card.id) || card.name.isEmpty) {
        throw const FormatException('Invalid artist card identity');
      }
      if (!ids.add(card.id)) continue;
      cards.add(MarketplaceArtistCard(
          card,
          List.unmodifiable([
            card.name,
            card.expansion,
            card.number,
            '${row['rarity'] ?? ''}',
            '${row['product_variant'] ?? ''}',
          ].map(compactQuery)),
          productType: '${row['product_type'] ?? row['productType'] ?? ''}',
          printBucket:
              '${row['effective_print_bucket'] ?? row['nationality'] ?? ''}'
                  .toLowerCase()));
    }
    return MarketplaceArtistCatalog(cards);
  }

  void cancelPending() => _http.cancelActive();
  void dispose() {
    _http.dispose();
    if (_ownsClient) _client.close();
  }
}
