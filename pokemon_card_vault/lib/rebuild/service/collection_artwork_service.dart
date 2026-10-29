import '../constants/card_language_constants.dart';
import '../model/card.dart';
import '../provider/artwork_preferences_provider.dart';
import 'card_service.dart';

/// Public metadata and a local display preference, separate from owner stock.
class CollectionArtworkService {
  CollectionArtworkService(
      {CardService? cards, ArtworkPreferencesProvider? preferences})
      : _cards = cards ?? CardService(),
        _ownsCards = cards == null,
        _preferences = preferences ?? ArtworkPreferencesProvider();
  final CardService _cards;
  final bool _ownsCards;
  final ArtworkPreferencesProvider _preferences;
  Future<MarketplaceCard> fetchCard(String id) => _cards.fetchCard(id);
  Future<String> readLanguage() async {
    final code = (await _preferences.readLanguage())?.toUpperCase();
    return cardLanguageLabels.containsKey(code) ? code! : 'IT';
  }

  Future<void> writeLanguage(String code) => _preferences.writeLanguage(code);
  void dispose() {
    if (_ownsCards) _cards.dispose();
  }
}
