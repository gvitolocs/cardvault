import 'compact_query.dart';

const modifierCompacts = [
  'vmax',
  'vstar',
  'vunion',
  'tagteam',
  'legend',
  'break',
  'lvx',
  'delta',
  'prime',
  'mega',
  'gx',
  'ex',
  'v',
];
final _modifierWords = modifierCompacts.toSet();
final _whitespace = RegExp(r'\s+');
final xyMegaTitle = RegExp(r'^M\s+[A-Z]');
final modifierName = RegExp(
    r'\b(ex|gx|v|vmax|vstar|v-?union|mega|lv\.?\s*[x\d]+|tag team|legend|break|delta|prime|prism star|gold star)\b',
    caseSensitive: false);
RegExp _insensitive(String pattern) => RegExp(pattern, caseSensitive: false);
final _modifierPatterns = {
  'v': _insensitive(r'(^|[\s&])v(?!\s*(max|star))'),
  'tagteam': _insensitive(r'tag\s*team'),
  'legend': _insensitive(r'\blegend\b'),
  'break': _insensitive(r'\bbreak\b'),
  'lvx': _insensitive(r'lv\.?\s*x\b'),
  'vunion': _insensitive(r'v[\s-]*union'),
  'delta': _insensitive(r'delta\s*species|\u03b4'),
  'prime': _insensitive(r'\bprime\b'),
  'mega': _insensitive(r'\bmega\b'),
  'gx': _insensitive(r'\bgx\b'),
  'ex': _insensitive(r'\bex\b'),
  'vmax': _insensitive(r'\bvmax\b'),
  'vstar': _insensitive(r'\bvstar\b'),
};
final _excludedPatterns = {
  'legend': _insensitive(r'call of legends|shining legends|hidden legends'),
  'break': _insensitive(r'breakthrough|breakpoint'),
  'prime': _insensitive(r'primeape|prime catcher'),
};

bool displayHasModifier(String display, String mod) {
  if (mod == 'mega' && xyMegaTitle.hasMatch(display)) {
    return true;
  }
  final pattern = _modifierPatterns[mod];
  if (pattern == null || !pattern.hasMatch(display)) {
    return false;
  }
  return !(_excludedPatterns[mod]?.hasMatch(display) ?? false);
}

bool hasRivalMechanic(String display, List<String> mods) {
  if (mods.isEmpty) {
    return false;
  }
  final present =
      modifierCompacts.where((mod) => displayHasModifier(display, mod));
  return present.isNotEmpty && !present.any(mods.contains);
}

bool isModifierWord(String word) => _modifierWords.contains(compactQuery(word));

class TypedModifiers {
  TypedModifiers(List<String> mods, this.nameCompact)
      : mods = List.unmodifiable(mods);
  final List<String> mods;
  final String nameCompact;
}

List<String> _words(String query) =>
    query.trim().split(_whitespace).where((word) => word.isNotEmpty).toList();

TypedModifiers typedModifiers(String query,
    {required bool Function(String compact) namePoolHasCompact}) {
  final words = _words(query);
  final mods = <String>[];
  final nameWords = <String>[];
  for (final word in words) {
    final compact = compactQuery(word);
    if (_modifierWords.contains(compact)) {
      mods.add(compact);
    } else {
      nameWords.add(word);
    }
  }
  if (mods.isEmpty) {
    final phrase = compactQuery(
        words.skip(words.length < 2 ? 0 : words.length - 2).join(' '));
    if (words.length >= 2 && _modifierWords.contains(phrase)) {
      mods.add(phrase);
    } else if (words.length == 1) {
      final full = compactQuery(words[0]);
      for (final token in modifierCompacts) {
        if (full.length > token.length + 2 && full.endsWith(token)) {
          mods.add(token);
          break;
        }
      }
    } else {
      for (final word in words) {
        final full = compactQuery(word);
        if (!namePoolHasCompact(full)) {
          continue;
        }
        for (final mod in modifierCompacts) {
          if (full.length > mod.length + 2 && full.endsWith(mod)) {
            mods.add(mod);
            break;
          }
        }
      }
    }
  }
  return TypedModifiers(mods, compactQuery(nameWords.join(' ')));
}

String megaAliasCompact(String query) {
  final words = _words(query);
  if (words.length < 2 || compactQuery(words[0]) != 'mega') {
    return '';
  }
  final rest = compactQuery(words.skip(1).join(' '));
  return rest.isEmpty ? '' : 'm$rest';
}
