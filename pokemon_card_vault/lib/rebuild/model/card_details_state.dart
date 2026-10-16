import 'card.dart';
import 'listing.dart';

class CardInfoState {
  const CardInfoState({this.card, this.loading = true, this.hasError = false});
  final MarketplaceCard? card;
  final bool loading, hasError;
}

enum ListingSort { lowestPrice, highestPrice }

class ListingsState {
  const ListingsState(
      {this.all = const [],
      this.visible = const [],
      this.loading = true,
      this.hasError = false,
      this.condition,
      this.language,
      this.sort = ListingSort.lowestPrice});
  final List<MarketplaceListing> all, visible;
  final bool loading, hasError;
  final String? condition, language;
  final ListingSort sort;
}
