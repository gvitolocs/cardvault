import 'package:flutter/material.dart';

class CardPalette {
  const CardPalette({
    required this.typeGradient,
    required this.darkSurfaceGradient,
    required this.lightSurfaceGradient,
    required this.imageFrameColor,
  });

  final LinearGradient typeGradient;
  final LinearGradient darkSurfaceGradient;
  final LinearGradient lightSurfaceGradient;
  final Color imageFrameColor;

  Color get typeColor => typeGradient.colors.last;
}

const _gradientBegin = Alignment.topLeft;
const _gradientEnd = Alignment.bottomRight;
const _fallbackPalette = CardPalette(
  typeGradient: LinearGradient(
    begin: _gradientBegin,
    end: _gradientEnd,
    colors: [Color(0xFF94A3B8), Color(0xFF475569)],
  ),
  darkSurfaceGradient: LinearGradient(
    begin: _gradientBegin,
    end: _gradientEnd,
    colors: [Color(0xFF31394D), Color(0xFF141928)],
  ),
  lightSurfaceGradient: LinearGradient(
    begin: _gradientBegin,
    end: _gradientEnd,
    colors: [Color(0xFFEEF0F4), Color(0xFFEDEEF0)],
  ),
  imageFrameColor: Color(0xFF243E68),
);

const _palettesByType = {
  'fire': CardPalette(
    typeGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFFFF6B3D), Color(0xFFFFB020)],
    ),
    darkSurfaceGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFF4F292B), Color(0xFF3C2D18)],
    ),
    lightSurfaceGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFFFFE7E0), Color(0xFFFFF7E9)],
    ),
    imageFrameColor: Color(0xFF8F4A24),
  ),
  'water': CardPalette(
    typeGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFF38BDF8), Color(0xFF2563EB)],
    ),
    darkSurfaceGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFF18405F), Color(0xFF0C1C45)],
    ),
    lightSurfaceGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFFDFF4FE), Color(0xFFE9EFFD)],
    ),
    imageFrameColor: Color(0xFF155E9C),
  ),
  'lightning': CardPalette(
    typeGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFFFDE047), Color(0xFFF59E0B)],
    ),
    darkSurfaceGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFF3A392B), Color(0xFF3A2914)],
    ),
    lightSurfaceGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFFFFFCEA), Color(0xFFFEF5E7)],
    ),
    imageFrameColor: Color(0xFF8A691B),
  ),
  'grass': CardPalette(
    typeGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFF34D399), Color(0xFF65A30D)],
    ),
    darkSurfaceGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFF164745), Color(0xFF1A2A14)],
    ),
    lightSurfaceGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFFDFF8EF), Color(0xFFF0F6E7)],
    ),
    imageFrameColor: Color(0xFF1F7A49),
  ),
  'psychic': CardPalette(
    typeGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFFA78BFA), Color(0xFFEC4899)],
    ),
    darkSurfaceGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFF373260), Color(0xFF381633)],
    ),
    lightSurfaceGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFFF1ECFE), Color(0xFFFDEDF5)],
    ),
    imageFrameColor: Color(0xFF6D3D86),
  ),
  'fighting': CardPalette(
    typeGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFFB45309), Color(0xFFEF4444)],
    ),
    darkSurfaceGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFF3A231C), Color(0xFF381520)],
    ),
    lightSurfaceGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFFF3E3D8), Color(0xFFFDECEC)],
    ),
    imageFrameColor: Color(0xFF7F3028),
  ),
  'darkness': CardPalette(
    typeGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFF64748B), Color(0xFF111827)],
    ),
    darkSurfaceGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFF242C41), Color(0xFF080C1A)],
    ),
    lightSurfaceGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFFE6E9EC), Color(0xFFE7E8E9)],
    ),
    imageFrameColor: Color(0xFF303A52),
  ),
  'metal': CardPalette(
    typeGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFFCBD5E1), Color(0xFF64748B)],
    ),
    darkSurfaceGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFF313749), Color(0xFF1A2030)],
    ),
    lightSurfaceGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFFF9FAFC), Color(0xFFF0F1F3)],
    ),
    imageFrameColor: Color(0xFF5A6378),
  ),
  'fairy': CardPalette(
    typeGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFFF9A8D4), Color(0xFFC084FC)],
    ),
    darkSurfaceGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFF4E3B55), Color(0xFF2E2349)],
    ),
    lightSurfaceGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFFFEF1F8), Color(0xFFF9F3FF)],
    ),
    imageFrameColor: Color(0xFF7F5A9D),
  ),
  'dragon': CardPalette(
    typeGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFF818CF8), Color(0xFFF59E0B)],
    ),
    darkSurfaceGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFF2C335F), Color(0xFF3A2914)],
    ),
    lightSurfaceGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFFEBEDFE), Color(0xFFFEF5E7)],
    ),
    imageFrameColor: Color(0xFF70613D),
  ),
  'colorless': CardPalette(
    typeGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFFE5E7EB), Color(0xFF94A3B8)],
    ),
    darkSurfaceGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFF363A4B), Color(0xFF242A3A)],
    ),
    lightSurfaceGradient: LinearGradient(
      begin: _gradientBegin,
      end: _gradientEnd,
      colors: [Color(0xFFFCFCFD), Color(0xFFF4F6F8)],
    ),
    imageFrameColor: Color(0xFF576174),
  ),
};

const _typeAliases = {
  'dark': 'darkness',
  'electric': 'lightning',
  'normal': 'colorless',
  'steel': 'metal',
};

CardPalette cardPaletteForType(String type) {
  final key = type.trim().toLowerCase();
  return _palettesByType[_typeAliases[key] ?? key] ?? _fallbackPalette;
}

CardPalette cardPaletteFromPayload(
  Map<String, dynamic> payload, {
  required String fallbackType,
}) {
  if (payload.isEmpty) {
    return cardPaletteForType(fallbackType);
  }

  final fallback = cardPaletteForType(
    '${payload['key'] ?? fallbackType}'.trim(),
  );
  return CardPalette(
    typeGradient: _gradientFromPayload(
      payload['typeGradient'],
      fallback.typeGradient,
    ),
    darkSurfaceGradient: _gradientFromPayload(
      payload['darkSurfaceGradient'],
      fallback.darkSurfaceGradient,
    ),
    lightSurfaceGradient: _gradientFromPayload(
      payload['lightSurfaceGradient'],
      fallback.lightSurfaceGradient,
    ),
    imageFrameColor:
        _colorFromPayload(payload['imageFrameColor']) ?? fallback.imageFrameColor,
  );
}

List<Color> cardTypeGradientColors(String type) {
  return cardPaletteForType(type).typeGradient.colors;
}

Color cardTypeColor(String type) => cardPaletteForType(type).typeColor;

LinearGradient cardTypeGradient(String type) {
  return cardPaletteForType(type).typeGradient;
}

LinearGradient cardTypeGradientForPayload(
  Map<String, dynamic> payload, {
  required String fallbackType,
}) {
  return cardPaletteFromPayload(
    payload,
    fallbackType: fallbackType,
  ).typeGradient;
}

LinearGradient cardDarkSurfaceGradient(String type) {
  return cardPaletteForType(type).darkSurfaceGradient;
}

LinearGradient cardDarkSurfaceGradientForPayload(
  Map<String, dynamic> payload, {
  required String fallbackType,
}) {
  return cardPaletteFromPayload(
    payload,
    fallbackType: fallbackType,
  ).darkSurfaceGradient;
}

LinearGradient cardLightSurfaceGradient(String type) {
  return cardPaletteForType(type).lightSurfaceGradient;
}

LinearGradient cardLightSurfaceGradientForPayload(
  Map<String, dynamic> payload, {
  required String fallbackType,
}) {
  return cardPaletteFromPayload(
    payload,
    fallbackType: fallbackType,
  ).lightSurfaceGradient;
}

Color cardImageFrameColor(String type) {
  return cardPaletteForType(type).imageFrameColor;
}

Color cardImageFrameColorForPayload(
  Map<String, dynamic> payload, {
  required String fallbackType,
}) {
  return cardPaletteFromPayload(
    payload,
    fallbackType: fallbackType,
  ).imageFrameColor;
}

LinearGradient cardAccentHeaderGradient(String type) {
  final palette = cardPaletteForType(type);
  return cardAccentHeaderGradientForPalette(palette);
}

LinearGradient cardAccentHeaderGradientForPayload(
  Map<String, dynamic> payload, {
  required String fallbackType,
}) {
  return cardAccentHeaderGradientForPalette(
    cardPaletteFromPayload(payload, fallbackType: fallbackType),
  );
}

LinearGradient cardAccentHeaderGradientForPalette(CardPalette palette) {
  return LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      palette.imageFrameColor,
      palette.darkSurfaceGradient.colors.last,
    ],
  );
}

LinearGradient _gradientFromPayload(Object? value, LinearGradient fallback) {
  if (value is! List || value.length < 2) {
    return fallback;
  }
  final colors = value
      .map(_colorFromPayload)
      .whereType<Color>()
      .toList(growable: false);
  if (colors.length < 2) {
    return fallback;
  }
  return LinearGradient(
    begin: _gradientBegin,
    end: _gradientEnd,
    colors: colors,
  );
}

Color? _colorFromPayload(Object? value) {
  final text = '${value ?? ''}'.trim();
  if (text.isEmpty) {
    return null;
  }
  final hex = text.startsWith('#') ? text.substring(1) : text;
  final normalized = hex.length == 6 ? 'FF$hex' : hex;
  final parsed = int.tryParse(normalized, radix: 16);
  return parsed == null ? null : Color(parsed);
}

String cardPaletteHint({
  required String type,
  String name = '',
  Iterable<String> tags = const [],
}) {
  final direct = type.trim().toLowerCase();
  if (direct.isNotEmpty &&
      direct != 'card' &&
      direct != 'pokemon' &&
      direct != 'pokémon' &&
      direct != 'trading card' &&
      direct != 'pokemon card' &&
      direct != 'pokémon card') {
    return direct;
  }

  final text = [
    name,
    ...tags,
  ].join(' ').toLowerCase();
  if (_hasAny(text, const [
    'electric',
    'lightning',
    'electrike',
    'manectric',
    'pikachu',
    'raichu',
    'zapdos',
    'jolteon',
    'luxio',
    'luxray',
    'mareep',
    'flaaffy',
    'ampharos',
    'voltorb',
    'electabuzz',
    'heliolisk',
    'helioptile',
    'magnemite',
    'magneton',
    'magnezone',
  ])) {
    return 'lightning';
  }
  if (_hasAny(text, const [
    'water',
    'squirtle',
    'wartortle',
    'blastoise',
    'buizel',
    'floatzel',
    'kingler',
    'krabby',
    'vaporeon',
    'gyarados',
    'lapras',
    'psyduck',
    'golduck',
    'totodile',
    'croconaw',
    'feraligatr',
    'mudkip',
    'marshtomp',
    'swampert',
    'piplup',
    'prinplup',
    'empoleon',
    'oshawott',
    'dewott',
    'samurott',
    'froakie',
    'frogadier',
    'greninja',
    'sobble',
    'drizzile',
    'inteleon',
    'quaxly',
    'quaxwell',
    'quaquaval',
  ])) {
    return 'water';
  }
  if (_hasAny(text, const [
    'fire',
    'charmander',
    'charmeleon',
    'charizard',
    'flareon',
    'vulpix',
    'ninetales',
    'growlithe',
    'arcanine',
    'ponyta',
    'rapidash',
    'magmar',
    'magmortar',
    'moltres',
    'cyndaquil',
    'quilava',
    'typhlosion',
    'torchic',
    'combusken',
    'blaziken',
    'chimchar',
    'monferno',
    'infernape',
    'tepig',
    'pignite',
    'emboar',
    'fennekin',
    'braixen',
    'delphox',
    'litten',
    'torracat',
    'incineroar',
    'scorbunny',
    'raboot',
    'cinderace',
    'fuecoco',
    'crocalor',
    'skeledirge',
  ])) {
    return 'fire';
  }
  if (_hasAny(text, const [
    'grass',
    'bulbasaur',
    'ivysaur',
    'venusaur',
    'celebi',
    'chikorita',
    'bayleef',
    'meganium',
    'treecko',
    'grovyle',
    'sceptile',
    'turtwig',
    'grotle',
    'torterra',
    'snivy',
    'servine',
    'serperior',
    'chespin',
    'quilladin',
    'chesnaught',
    'rowlet',
    'dartrix',
    'decidueye',
    'grookey',
    'thwackey',
    'rillaboom',
    'sprigatito',
    'floragato',
    'meowscarada',
  ])) {
    return 'grass';
  }
  if (_hasAny(text, const [
    'psychic',
    'mew',
    'mewtwo',
    'abra',
    'kadabra',
    'alakazam',
    'kirlia',
    'ralts',
    'gardevoir',
    'gallade',
    'espeon',
    'mr. mime',
    'mime jr',
    'solosis',
    'duosion',
    'reuniclus',
  ])) {
    return 'psychic';
  }
  if (_hasAny(text, const [
    'fighting',
    'rockruff',
    'lycanroc',
    'hawlucha',
    'machop',
    'machoke',
    'machamp',
    'lucario',
    'riolu',
    'hitmonlee',
    'hitmonchan',
    'hitmontop',
    'makuhita',
    'hariyama',
    'meditite',
    'medicham',
  ])) {
    return 'fighting';
  }
  if (_hasAny(text, const [
    'fairy',
    'alcremie',
    'milcery',
    'sylveon',
    'clefairy',
    'clefable',
    'cleffa',
    'jigglypuff',
    'wigglytuff',
    'igglybuff',
    'togepi',
    'togetic',
    'togekiss',
    'flabebe',
    'floette',
    'florges',
    'comfey',
    'ribombee',
    'cutiefly',
  ])) {
    return 'fairy';
  }
  if (_hasAny(text, const [
    'metal',
    'steel',
    'aggron',
    'aron',
    'lairon',
    'steelix',
    'scizor',
    'skarmory',
    'mawile',
    'beldum',
    'metang',
    'metagross',
    'dialga',
  ])) {
    return 'metal';
  }
  return direct;
}

bool _hasAny(String text, List<String> needles) {
  for (final needle in needles) {
    if (text.contains(needle)) {
      return true;
    }
  }
  return false;
}
