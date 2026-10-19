import '../model/cardex.dart';
import '../model/inventory_listing.dart';

class InventoryReconciliationService {
  const InventoryReconciliationService();

  List<OwnedCard> reconcile(
      List<OwnedCard> holdings, List<InventoryListing> listings) {
    final owned =
        listings.where((row) => row.isOwned).map((row) => row.item).toList();
    // Only explicit record links identify the same stock across both APIs.
    // A shared canonical card ID alone does not: language/finish/copies can differ.
    final byId = {for (final row in owned) row.id: row};
    final byHolding = <String, Set<String>>{};
    for (final row in owned) {
      if (row.sourceListingId.isNotEmpty) {
        (byHolding[row.sourceListingId] ??= {}).add(row.card.id);
      }
    }
    return List.unmodifiable([
      // Preserve the progressive listing prefix when held stock arrives later.
      ...owned,
      ...holdings.where((holding) {
        final linked = byId[holding.listingId] ?? byId[holding.sourceListingId];
        return !(linked != null && linked.card.id == holding.card.id) &&
            !(holding.id.isNotEmpty &&
                (byHolding[holding.id]?.contains(holding.card.id) ?? false));
      }),
    ]);
  }
}
