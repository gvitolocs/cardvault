import 'cardex.dart';
import 'marketplace_home.dart';

class CardLanguageOwnership {
  const CardLanguageOwnership(
      {required this.code,
      required this.label,
      required this.quantity,
      this.preview});
  final String code, label;
  final int quantity;
  final MarketplaceCardPreview? preview;
  bool get owned => quantity > 0;
}

/// Positive evidence from already validated current-account rows. Not totals
/// or proof that any other language/card is absent while reconciliation runs.
class CardOwnershipEvidence {
  const CardOwnershipEvidence(
      {required this.language, required this.label, this.preview});
  final String language, label;
  final MarketplaceCardPreview? preview;
}

/// One canonical print, with language quantities but no duplicated album entries.
class CardOwnership {
  CardOwnership(
      {required this.cardId,
      required this.status,
      required this.total,
      required List<CardLanguageOwnership> languages,
      this.evidence,
      this.selectedLanguage})
      : languages = List.unmodifiable(languages);
  final String cardId;
  final CollectionStatus status;
  final int total;
  final List<CardLanguageOwnership> languages;
  final String? selectedLanguage;
  final CardOwnershipEvidence? evidence;
  bool get known => status == CollectionStatus.ready;
  bool get hasConfirmedCopies => known
      ? total > 0
      : status == CollectionStatus.loading && evidence != null;
  String? get displayLanguage =>
      selected?.code ?? (hasConfirmedCopies ? evidence?.language : null);
  MarketplaceCardPreview? get displayPreview =>
      selected?.preview ?? (hasConfirmedCopies ? evidence?.preview : null);
  CardLanguageOwnership? get selected {
    for (final language in languages) {
      if (language.code == selectedLanguage && language.owned) return language;
    }
    return null;
  }
}
