import '../model/cardex.dart';
import '../model/marketplace_home.dart';
import '../provider/cardex_provider.dart';

class CardexService {
  CardexService({CardexProvider? provider})
      : _provider = provider ?? CardexProvider(),
        _ownsProvider = provider == null;
  final CardexProvider _provider;
  final bool _ownsProvider;

  Future<List<MarketplaceExpansion>> loadExpansions() =>
      _provider.fetchExpansions();
  Future<CardexPage> loadPage(String slug, {int offset = 0}) =>
      _provider.fetchPage(slug, offset: offset);

  List<MarketplaceCardPreview> mergeCards(
          Iterable<MarketplaceCardPreview> first,
          Iterable<MarketplaceCardPreview> next) =>
      List.unmodifiable({
        for (final card in [...first, ...next]) card.id: card,
      }.values);

  void dispose() {
    if (_ownsProvider) _provider.dispose();
  }
}
