import 'listing.dart';

enum CartAddStatus {
  added,
  unavailable,
  full,
  notReady,
  failed,
  sessionChanged
}

class CartAddResult {
  const CartAddResult(this.status, {this.listing});
  final CartAddStatus status;
  final MarketplaceListing? listing;
}
