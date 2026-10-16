import 'dart:convert';
import 'package:http/http.dart' as http;
import '../model/card.dart';
import '../model/listing.dart';

/// GET pubbliche originali; nessuna inizializzazione Firebase/Hive o polling.
class CardService {
  CardService({http.Client? client, Uri? apiBase})
      : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _base = apiBase ??
            Uri.parse(const String.fromEnvironment('MARKETPLACE_API_BASE_URL',
                defaultValue: 'https://api.pokoin.com'));
  final http.Client _client;
  final bool _ownsClient;
  final Uri _base;
  final _cards = <String, ({MarketplaceCard card, DateTime loadedAt})>{};
  final _pendingCards = <String, Future<MarketplaceCard>>{};
  final _pendingListings = <String, Future<List<MarketplaceListing>>>{};
  bool _disposed = false;

  Future<Map<String, dynamic>> _get(String path, String id,
      {String? limit}) async {
    if (!RegExp(r'^\d+$').hasMatch(id) || _disposed) {
      throw StateError('Invalid request');
    }
    final response = await _client
        .get(_base.resolve(path).replace(queryParameters: {
          'cardId': id,
          if (limit != null) 'limit': limit,
        }))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw StateError('Data unavailable');
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid data');
    }
    return data;
  }

  Future<MarketplaceCard> fetchCard(String id) {
    final cached = _cards[id];
    if (cached != null &&
        DateTime.now().difference(cached.loadedAt) <
            const Duration(minutes: 5)) {
      return Future.value(cached.card);
    }
    return _pendingCards.putIfAbsent(
        id,
        () => _fetchCard(id).whenComplete(() {
              _pendingCards.remove(id);
            }));
  }

  Future<MarketplaceCard> _fetchCard(String id) async {
    // Il BFF restituisce la proiezione completa senza richiedere storico,
    // live offers o carte simili. Le offerte hanno un caricamento indipendente.
    final data = await _get('/api/marketplace-card-page', id);
    final row = data['card'];
    if (row is! Map<String, dynamic>) {
      throw const FormatException('Missing card');
    }
    final card = MarketplaceCard.fromJson(row);
    if (card.id != id || card.name.isEmpty) {
      throw const FormatException('Invalid card');
    }
    if (!_disposed) {
      _cards.remove(id);
      if (_cards.length >= 20) _cards.remove(_cards.keys.first);
      _cards[id] = (card: card, loadedAt: DateTime.now());
    }
    return card;
  }

  Future<List<MarketplaceListing>> fetchListings(String id) =>
      _pendingListings.putIfAbsent(
          id,
          () => _fetchListings(id).whenComplete(() {
                _pendingListings.remove(id);
              }));

  Future<List<MarketplaceListing>> _fetchListings(String id) async {
    // Come CardListingService originale: offerte native e CardTrader live.
    // Non memorizzare disponibilità tra aperture; niente polling/refresh periodico.
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
    return List.unmodifiable(unique.values);
  }

  void dispose() {
    _disposed = true;
    _cards.clear();
    if (_ownsClient) _client.close();
  }
}
