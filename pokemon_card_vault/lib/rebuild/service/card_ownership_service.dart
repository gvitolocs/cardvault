import '../constants/card_language_constants.dart';
import '../model/cardex.dart';
import '../model/card_ownership.dart';
import '../model/marketplace_home.dart';

/// Read-only presentation grouping. Does not combine stock/provenance records.
class CardOwnershipService {
  const CardOwnershipService();

  String normalizeLanguage(String value) {
    final code = value.trim().replaceAll('_', '-').toUpperCase();
    if (code.isEmpty) return unknownCardLanguage;
    final alias = cardLanguageAliases[code];
    if (alias != null) return alias;
    if (cardLanguageLabels.containsKey(code)) return code;
    // Locale forms such as en-US or it-IT describe the same owned language.
    final base = code.split('-').first;
    return cardLanguageLabels.containsKey(base) ? base : code;
  }

  CardOwnership describe(CardCollection collection, String cardId,
      {String? selectedLanguage}) {
    if (collection.status != CollectionStatus.ready) {
      return CardOwnership(
          cardId: cardId,
          status: collection.status,
          total: 0,
          evidence: collection.status == CollectionStatus.loading
              ? _evidence(collection, cardId)
              : null,
          languages: const []);
    }
    final rows = <String, List<OwnedCard>>{};
    for (final row in collection.items.where((row) => row.card.id == cardId)) {
      (rows[normalizeLanguage(row.language)] ??= []).add(row);
    }
    final codes = {...cardLanguageLabels.keys, ...rows.keys};
    final languages = [
      for (final code in codes)
        CardLanguageOwnership(
            code: code,
            label: cardLanguageLabels[code] ??
                (code == unknownCardLanguage ? unknownCardLanguageLabel : code),
            quantity: (rows[code] ?? const <OwnedCard>[])
                .fold<int>(0, (total, row) => total + row.quantity),
            preview: _preview(rows[code] ?? const [])),
    ];
    final selected =
        selectedLanguage == null ? null : normalizeLanguage(selectedLanguage);
    final owned = languages.where((language) => language.owned);
    return CardOwnership(
        cardId: cardId,
        status: collection.status,
        total: collection.quantityFor(cardId),
        languages: languages,
        selectedLanguage: owned.any((language) => language.code == selected)
            ? selected
            : owned.firstOrNull?.code);
  }

  CardOwnershipEvidence? _evidence(CardCollection collection, String cardId) {
    final rows = <String, List<OwnedCard>>{};
    for (final row in collection.items.where((row) => row.card.id == cardId)) {
      (rows[normalizeLanguage(row.language)] ??= []).add(row);
    }
    // Match the final default language order without inventing absent options.
    final code = [...cardLanguageLabels.keys, ...rows.keys]
        .where(rows.containsKey)
        .firstOrNull;
    if (code == null) return null;
    return CardOwnershipEvidence(
        language: code,
        label: cardLanguageLabels[code] ??
            (code == unknownCardLanguage ? unknownCardLanguageLabel : code),
        preview: _preview(rows[code]!));
  }

  // Prefer an image supplied for this language; never invent translated CDN URLs.
  MarketplaceCardPreview? _preview(List<OwnedCard> rows) {
    for (final row in rows) {
      if (row.card.imageUrl.isNotEmpty || row.card.fullImageUrl.isNotEmpty) {
        return row.card;
      }
    }
    return rows.firstOrNull?.card;
  }
}
