import 'package:pokoin_suggest/era_catalog.dart';
import 'package:pokoin_suggest/pokoin_suggest.dart' show compactQuery;
import '../constants/expansion_era_constants.dart';
import '../model/expansion_era.dart';
import '../model/marketplace_home.dart';

/// Le espansioni vengono dall'API; le ere dal catalogo condiviso già incluso.
/// Nessun raggruppamento per semplice sottostringa o data presunta.
class ExpansionEraService {
  static const other = otherExpansionEraId;
  late final Map<String, String> _aliases = _buildAliases();

  Map<String, String> _buildAliases() {
    final aliases = <String, String>{};
    for (final era in tcgEraCatalog) {
      final id = era['id'] as String;
      for (final name in [
        id,
        for (final key in ['en', 'jp', 'cn', 'extras'])
          ...(era[key] as List).cast<String>()
      ]) {
        aliases.putIfAbsent(compactQuery(name), () => id);
        aliases.putIfAbsent(
            compactQuery(name.replaceAll('&', 'and')), () => id);
      }
    }
    return aliases;
  }

  String eraFor(MarketplaceExpansion expansion) {
    for (final value in [expansion.name, expansion.slug]) {
      final exact = _aliases[compactQuery(value)];
      if (exact != null) return exact;
      // Varianti editoriali presenti nel catalogo Pokoin, non match generici.
      final base = value.replaceFirst(
          RegExp(
              r'(?:[\s-]+|\s*\()(?:shadowless|promos?|black[\s-]+star[\s-]+promos?)\)?$',
              caseSensitive: false),
          '');
      final variant = _aliases[compactQuery(base)];
      if (variant != null) return variant;
    }
    return other;
  }

  List<ExpansionEraGroup> group(Iterable<MarketplaceExpansion> expansions) {
    final buckets = <String, List<MarketplaceExpansion>>{};
    final seen = <String>{};
    for (final expansion in expansions) {
      if (!seen.add(expansion.slug)) continue;
      (buckets[eraFor(expansion)] ??= []).add(expansion);
    }
    return List.unmodifiable([
      for (final id in [
        for (final era in tcgEraCatalog) era['id'] as String,
        other
      ])
        if (buckets[id] case final values?)
          ExpansionEraGroup(
              id: id,
              title: expansionEraTitles[id] ?? id,
              expansions: values
                ..sort((a, b) =>
                    a.name.toLowerCase().compareTo(b.name.toLowerCase()))),
    ]);
  }

  List<ExpansionEraGroup> filter(List<ExpansionEraGroup> groups, String query) {
    final needle = compactQuery(query);
    if (needle.isEmpty) return groups;
    return List.unmodifiable([
      for (final group in groups)
        if (compactQuery('${group.title} ${group.id}').contains(needle))
          group
        else if (group.expansions
                .where((item) =>
                    compactQuery('${item.name} ${item.slug}').contains(needle))
                .toList()
            case final matches when matches.isNotEmpty)
          ExpansionEraGroup(
              id: group.id, title: group.title, expansions: matches),
    ]);
  }
}
