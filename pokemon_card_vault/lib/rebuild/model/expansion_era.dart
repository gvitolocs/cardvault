import 'marketplace_home.dart';

class ExpansionEraGroup {
  ExpansionEraGroup(
      {required this.id,
      required this.title,
      required Iterable<MarketplaceExpansion> expansions})
      : expansions = List.unmodifiable(expansions);
  final String id, title;
  final List<MarketplaceExpansion> expansions;
}
