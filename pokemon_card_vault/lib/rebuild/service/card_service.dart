import 'package:http/http.dart' as http;
import '../model/card.dart';
import '../model/listing.dart';
import '../provider/card_provider.dart';

/// GET pubbliche originali; nessuna inizializzazione Firebase/Hive o polling.
class CardService {
  CardService({http.Client? client, Uri? apiBase, CardProvider? provider})
      : _provider = provider ?? CardProvider(client: client, apiBase: apiBase),
        _ownsProvider = provider == null;
  final CardProvider _provider;
  final bool _ownsProvider;
  final _cards = <String, ({MarketplaceCard card, DateTime loadedAt})>{};
  final _pendingCards = <String, Future<MarketplaceCard>>{};
  final _pendingListings = <String, Future<List<MarketplaceListing>>>{};
  bool _disposed = false;

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
    if (_disposed) throw StateError('Service disposed');
    final card = await _provider.fetchCard(id);
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
    if (_disposed) throw StateError('Service disposed');
    return _provider.fetchListings(id);
  }

  void dispose() {
    _disposed = true;
    _cards.clear();
    if (_ownsProvider) _provider.dispose();
  }
}
