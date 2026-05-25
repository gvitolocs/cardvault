import 'package:flutter/material.dart';

const Color listingChipGold = Color(0xFFFACC15);

String listingMinimalConditionLabel(String condition) {
  final normalized = condition.trim().toLowerCase();
  switch (normalized) {
    case 'near mint':
    case 'nm':
      return 'NM';
    case 'slightly played':
    case 'lightly played':
    case 'lp':
    case 'excellent':
    case 'ex':
    case 'sp':
      return 'SP';
    case 'moderately played':
    case 'good':
    case 'gd':
    case 'mp':
      return 'MP';
    case 'played':
    case 'pl':
      return 'PL';
    case 'poor':
    case 'po':
    case 'damaged':
      return 'Poor';
    default:
      return condition.trim().isEmpty ? 'NM' : condition.trim();
  }
}

Color listingConditionColor(String code) {
  switch (listingMinimalConditionLabel(code)) {
    case 'NM':
      return const Color(0xFF22C55E);
    case 'SP':
      return const Color(0xFF84CC16);
    case 'MP':
      return listingChipGold;
    case 'PL':
      return const Color(0xFFF97316);
    case 'Poor':
      return const Color(0xFFEF4444);
    default:
      return listingChipGold;
  }
}

String listingLanguageLabel(String code) {
  final normalized = code.trim().toUpperCase();
  final flag = _listingLanguageFlags[normalized] ?? '🌐';
  return '$flag $normalized';
}

const Map<String, String> _listingLanguageFlags = {
  'EN': '🇬🇧',
  'IT': '🇮🇹',
  'FR': '🇫🇷',
  'DE': '🇩🇪',
  'ES': '🇪🇸',
  'JP': '🇯🇵',
  'PT': '🇵🇹',
  'NL': '🇳🇱',
  'PL': '🇵🇱',
  'RU': '🇷🇺',
  'KO': '🇰🇷',
  'ZH': '🇨🇳',
  'ZHT': '🇹🇼',
  'ID': '🇮🇩',
  'TH': '🇹🇭',
  'VI': '🇻🇳',
};

String listingCountryFlag(String country) {
  switch (country.toUpperCase()) {
    case 'CN':
    case 'CHN':
    case 'ZH':
      return '🇨🇳';
    case 'IT':
      return '🇮🇹';
    case 'FR':
      return '🇫🇷';
    case 'DE':
      return '🇩🇪';
    case 'ES':
      return '🇪🇸';
    case 'US':
    case 'USA':
      return '🇺🇸';
    case 'GB':
    case 'UK':
      return '🇬🇧';
    case 'CA':
      return '🇨🇦';
    case 'PT':
      return '🇵🇹';
    case 'NL':
      return '🇳🇱';
    case 'BE':
      return '🇧🇪';
    case 'PL':
      return '🇵🇱';
    case 'KR':
    case 'KO':
      return '🇰🇷';
    case 'TW':
      return '🇹🇼';
    case 'JP':
      return '🇯🇵';
    case 'EU':
    default:
      return '🇪🇺';
  }
}

bool listingIsCardTraderLinked({
  required String source,
  required String sourceListingId,
}) {
  final normalizedSource = source.trim().toLowerCase();
  final normalizedSourceId = sourceListingId.trim().toLowerCase();
  return normalizedSource == 'cardtrader' ||
      normalizedSource.startsWith('cardtrader') ||
      normalizedSourceId.contains('cardtrader') ||
      normalizedSourceId.contains('cardtrader.com');
}

String listingDisplaySellerName({
  required String? sellerName,
  required bool reserveAvailable,
  required bool isCardTraderLinked,
  String fallback = 'Pokoin seller',
}) {
  final cleanName = sellerName?.trim() ?? '';
  if (reserveAvailable || isCardTraderLinked) {
    return cleanName.isEmpty ? 'pknreserve' : cleanName;
  }
  return cleanName.isEmpty ? fallback : cleanName;
}

String listingFoilBadgeLabel(String code, {bool compact = false}) {
  final emoji = _foilStateEmoji(code);
  final label = compact && code == 'reverse' ? 'REV' : _foilStateLabel(code);
  return emoji.isEmpty ? label : '$emoji $label';
}

String _foilStateLabel(String code) {
  switch (code) {
    case 'holo':
      return 'Holo';
    case 'reverse':
      return 'Reverse';
    case 'stamped':
      return 'Stamped';
    case 'promo':
      return 'Promo';
    case 'other':
      return 'Other';
    case 'standard':
    default:
      return 'Standard';
  }
}

String _foilStateEmoji(String code) {
  switch (code) {
    case 'holo':
    case 'reverse':
      return '✨';
    case 'stamped':
      return '🏷️';
    case 'promo':
      return '🎁';
    case 'other':
      return '💿';
    case 'standard':
    default:
      return '';
  }
}

class ListingMetaChip extends StatelessWidget {
  const ListingMetaChip({
    super.key,
    required this.text,
    this.color = listingChipGold,
    this.borderColor,
  });

  final String text;
  final Color color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: borderColor ?? color.withValues(alpha: 0.38),
        ),
      ),
      child: Text(
        cleanText,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class ListingConditionChip extends StatelessWidget {
  const ListingConditionChip({super.key, required this.condition});

  final String condition;

  @override
  Widget build(BuildContext context) {
    final label = listingMinimalConditionLabel(condition);
    return ListingMetaChip(
      text: label,
      color: listingConditionColor(label),
    );
  }
}
