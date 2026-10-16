import 'package:pokoin_suggest/pokoin_suggest.dart';
import 'marketplace_home.dart';
export 'package:pokoin_suggest/pokoin_suggest.dart' show LocalSuggestion;

class MarketplaceSuggestionsState {
  MarketplaceSuggestionsState(
      {List<LocalSuggestion> items = const [],
      List<MarketplaceCardPreview> cards = const [],
      this.loading = false,
      this.hasError = false,
      this.cardsLoading = false,
      this.cardsError = false})
      : items = List.unmodifiable(items),
        cards = List.unmodifiable(cards);
  final List<LocalSuggestion> items;
  final List<MarketplaceCardPreview> cards;
  final bool loading, hasError;
  final bool cardsLoading, cardsError;
}
