import '../constants/card_language_constants.dart';

/// Explicit Pokoin `langScans` mappings, not a name/number search or ID guess.
/// Only the advertised language/path is used with TCGdex's documented format.
abstract final class CardLanguageArtwork {
  static Map<String, String> parse(String manifest) {
    if (manifest.length > 2000) return const {};
    final result = <String, String>{};
    final ambiguous = <String>{};
    for (final group in manifest.split(';')) {
      final parts = group.trim().split(':');
      if (parts.length != 2) continue;
      final path = parts[1].trim();
      if (!RegExp(r'^[a-zA-Z0-9.-]+/[a-zA-Z0-9.-]+/[a-zA-Z0-9.-]+$')
              .hasMatch(path) ||
          path.length > 120 ||
          path.split('/').any((segment) => segment == '.' || segment == '..')) {
        continue;
      }
      for (final raw in parts[0].split(',')) {
        final language = raw.trim().toLowerCase();
        final code = language.toUpperCase();
        if (!cardLanguageLabels.containsKey(code) ||
            !RegExp(r'^[a-z]{2}(?:-[a-z]{2})?$').hasMatch(language)) {
          continue;
        }
        final url = 'https://assets.tcgdex.net/$language/$path/high.webp';
        if (result.containsKey(code) && result[code] != url) {
          ambiguous.add(code);
        }
        result[code] = url;
      }
    }
    for (final code in ambiguous) {
      result.remove(code);
    }
    return Map.unmodifiable(result);
  }
}
