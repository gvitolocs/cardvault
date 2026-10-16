import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/marketplace_home.dart';
import '../model/marketplace_home_payload.dart';
import 'marketplace_http_provider.dart';

/// Endpoint discovery e conversione delle risposte in dati tipizzati.
class MarketplaceHomeProvider {
  MarketplaceHomeProvider({
    http.Client? client,
    Uri? apiBase,
    this.timeout = const Duration(seconds: 8),
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        apiBase = apiBase ??
            Uri.parse(const String.fromEnvironment('MARKETPLACE_API_BASE_URL',
                defaultValue: 'https://api.pokoin.com'));

  final http.Client _client;
  late final _http = MarketplaceHttpProvider(_client);
  final bool _ownsClient;
  final Uri apiBase;
  final Duration timeout;

  Future<MarketplaceHomePayload?> fetchHome() async {
    final home = await _getJson([
      '/api/marketplace-home-page?limit=48',
      '/api/marketplace-home',
    ], requiredList: 'cards', requireSections: true);
    if (home == null) return null;
    final sections = Map<String, dynamic>.from(home['sections'] as Map);
    final topIds = _ids(sections['bestSellerIds']);
    final newIds = _ids(sections['newArrivalIds']);
    final wanted = {...topIds, ...newIds};
    // Filtra gli ID prima di costruire le anteprime complete.
    final cards = _maps(home['cards'])
        .where((row) =>
            wanted.contains('${row['id'] ?? row['card_id'] ?? ''}'.trim()))
        .map(MarketplaceCardPreview.fromJson)
        .toList(growable: false);
    return MarketplaceHomePayload(
        cards: cards, bestSellerIds: topIds, newArrivalIds: newIds);
  }

  Future<List<MarketplaceExpansion>?> fetchExpansions() async {
    final payload = await _getJson([
      '/api/marketplace-expansion-page?limit=1000',
    ], requiredList: 'expansions');
    if (payload == null) return null;
    return _maps(payload['expansions'])
        .map(MarketplaceExpansion.fromJson)
        .toList(growable: false);
  }

  Future<Map<String, dynamic>?> _getJson(
    List<String> paths, {
    required String requiredList,
    bool requireSections = false,
  }) async {
    // Il fallback condivide il budget: non aggiunge altri otto secondi.
    final elapsed = Stopwatch()..start();
    for (final path in paths) {
      final remaining = timeout - elapsed.elapsed;
      if (remaining <= Duration.zero) return null;
      try {
        final response =
            await _http.get(apiBase.resolve(path), timeout: remaining);
        // Accesso negato, limiti e indisponibilità non si aggirano con un altro
        // endpoint sullo stesso server. Il retry resta esplicito nella UI.
        if (response.statusCode == 401 ||
            response.statusCode == 403 ||
            response.statusCode == 429 ||
            response.statusCode >= 500) {
          return null;
        }
        if (response.statusCode != 200) continue;
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is! Map ||
            decoded[requiredList] is! List ||
            (requireSections && decoded['sections'] is! Map)) {
          continue;
        }
        return Map<String, dynamic>.from(decoded);
      } catch (_) {
        // Nessun payload valido: il chiamante gestisce indisponibilità e retry.
      }
    }
    return null;
  }

  void dispose() {
    _http.dispose();
    if (_ownsClient) _client.close();
  }

  static List<String> _ids(Object? value) => value is List
      ? value
          .map((id) => '$id'.trim())
          .where((id) => id.isNotEmpty)
          .toList(growable: false)
      : const [];

  static Iterable<Map<String, dynamic>> _maps(Object? value) => value is List
      ? value.whereType<Map>().map((row) => Map<String, dynamic>.from(row))
      : const [];
}
