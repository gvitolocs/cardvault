import 'dart:math' as math;

import 'compact_query.dart';
import 'pkd1.dart';
import 'rank_names.dart';
import 'tcg_eras.g.dart';
import 'typed_modifiers.dart';

const artAliases = {
  'il',
  'i',
  'ill',
  'illu',
  'illust',
  'illustra',
  'illustrat',
  'illustratio',
  'illus',
  'illustration',
  'illustrazione',
  'illustrationrare',
  'specialillustration',
  'specialillustrationrare',
  'ir',
  'sir',
  'fa',
  'fullart',
  'ar',
  'sar',
  'artrare',
  'raraillustrazione',
  'rarailustracion',
  'illustrationspecialerare',
  'seltenillustration',
  'seltenbesondereillustration',
};
const rarityPhrases = {
  'secretrare': 'secret',
  'ultrarare': 'ultra',
  'holorare': 'holo',
  'reverseholo': 'reverse',
  'hyperrare': 'hyper',
  'fullart': 'illustration'
};
const rarityAliases = {
  'ur': 'ultra',
  'sr': 'secret',
  'hr': 'hyper',
  'rh': 'reverse'
};
final _space = RegExp(r'\s+');
final _number =
    RegExp(r'^#?(\d{1,3})(?:/(\d{1,4}))?([a-z])?$', caseSensitive: false);
final _coded =
    RegExp(r'^#?([a-z]{1,5})(\d{1,3})(?:/(\d{1,4}))?$', caseSensitive: false);
final _pair = RegExp(r'^(?:&|and)$', caseSensitive: false);

class QueryToken {
  const QueryToken(
      {required this.kind,
      required this.token,
      this.compact = '',
      this.eraId = '',
      this.setNames = const [],
      this.needles = const [],
      this.prefix = false,
      this.slug = '',
      this.n,
      this.d,
      this.suffix = '',
      this.code = '',
      this.rarity = ''});
  final String kind, token, compact, eraId, slug, suffix, code, rarity;
  final List<String> setNames, needles;
  final bool prefix;
  final int? n, d;
}

class ParsedQuery {
  ParsedQuery(
      {required this.raw,
      required this.nameQuery,
      List<QueryToken> setTokens = const [],
      List<QueryToken> artTokens = const [],
      List<QueryToken> numberTokens = const [],
      List<QueryToken> rarityTokens = const []})
      : setTokens = List.unmodifiable(setTokens),
        artTokens = List.unmodifiable(artTokens),
        numberTokens = List.unmodifiable(numberTokens),
        rarityTokens = List.unmodifiable(rarityTokens);
  final String raw, nameQuery;
  final List<QueryToken> setTokens, artTokens, numberTokens, rarityTokens;
  bool get setOnly => setTokens.isNotEmpty && nameQuery.trim().isEmpty;
  bool get setAware => setTokens.isNotEmpty && nameQuery.trim().isNotEmpty;
  bool get bareCollector => numberTokens.isNotEmpty && nameQuery.trim().isEmpty;
  List<String> get eras =>
      setTokens.map((t) => t.eraId).where((s) => s.isNotEmpty).toSet().toList();
  Map<String, Object?> toGoldenJson() => {
        'nameQuery': nameQuery,
        'setTokens': setTokens
            .map((t) => {
                  'compact': t.compact,
                  'eraId': t.eraId,
                  'prefix': t.prefix,
                  'slug': t.slug,
                  'firstSet': t.setNames.isEmpty ? '' : t.setNames.first
                })
            .toList(),
        'numberTokens': numberTokens
            .map((t) => {
                  'compact': t.compact,
                  'n': t.n,
                  'd': t.d,
                  'suffix': t.suffix,
                  'code': t.code
                })
            .toList(),
        'artTokens': artTokens.map((t) => t.compact).toList(),
        'rarityTokens': rarityTokens.map((t) => [t.compact, t.rarity]).toList(),
        'eras': eras,
      };
}

QueryToken? parseCollectorWord(String word) {
  final raw = word.trim();
  final number = _number.firstMatch(raw);
  if (number != null) {
    return QueryToken(
        kind: 'number',
        token: word,
        compact: compactQuery(raw.replaceFirst(RegExp(r'^#'), '')),
        n: int.parse(number[1]!),
        d: number[2] == null ? null : int.parse(number[2]!),
        suffix: (number[3] ?? '').toLowerCase());
  }
  final coded = _coded.firstMatch(raw);
  if (coded == null) {
    return null;
  }
  final code = coded[1]!.toLowerCase();
  return QueryToken(
      kind: 'number',
      token: word,
      compact: compactQuery('$code${coded[2]}'),
      n: int.parse(coded[2]!),
      d: coded[3] == null ? null : int.parse(coded[3]!),
      code: code);
}

class _PackedSet {
  const _PackedSet(this.eraId, this.names, this.needles, {this.slug = ''});
  final String eraId, slug;
  final List<String> names, needles;
}

class TypedQueryParser {
  TypedQueryParser(this.dictionary, this.names) {
    final aliasRows = <SuggestPoolRow>[];
    final seenPool = <String>{};
    void remember(
        String compact, _PackedSet packed, String display, bool poolable) {
      if (compact.isEmpty || compact == 'ex') {
        return;
      }
      _aliases.putIfAbsent(compact, () => packed);
      if (!poolable || compact.length < 6 || !seenPool.add(compact)) {
        return;
      }
      aliasRows.add(SuggestPoolRow(
          display: display,
          compact: compactQuery(display),
          collationRank: eraAliasCollationRanks[aliasRows.length]));
    }

    for (final era in tcgEraCatalog) {
      final setNames = [
        for (final key in ['en', 'jp', 'cn'])
          ...(era[key] as List).cast<String>()
      ];
      final needles = {_alias(era['id'] as String), ...setNames.map(_alias)};
      for (final extra in (era['extras'] as List).cast<String>()) {
        final compact = _alias(extra);
        if (compact.length >= 2 && compact != 'ex') {
          needles.add(compact);
        }
      }
      final packed = _PackedSet(era['id'] as String,
          List.unmodifiable(setNames), List.unmodifiable(needles));
      for (final extra in (era['extras'] as List).cast<String>()) {
        final compact = _alias(extra);
        if (compact.length >= 2) {
          remember(
              compact, packed, extra.replaceAll('-', ' '), compact.length >= 6);
        }
      }
      for (final label in setNames) {
        final compact = _alias(label);
        if (compact.length >= 6) {
          remember(compact, packed, label, true);
        }
      }
    }
    for (final entry in const {
      'hgss': 'HeartGold & SoulSilver',
      'hgs': 'HeartGold & SoulSilver',
      'sl': 'Call of Legends',
      'col': 'Call of Legends',
      'legen': 'Call of Legends',
      'legend': 'Call of Legends',
      'legends': 'Call of Legends'
    }.entries) {
      var packed = _aliases[_alias(entry.key)];
      for (final row in _aliases.values) {
        if (packed == null && row.eraId == entry.value) {
          packed = row;
        }
      }
      if (packed != null) {
        _aliases[entry.key] = packed;
      }
    }
    if (aliasRows.length != eraAliasCollationRanks.length) {
      throw StateError('Era aliases differ from pinned source');
    }
    _aliasRanker =
        NameRanker(dictionary, pool: SuggestColumn.fromRows(aliasRows));
    final seenPrefix = <String>{};
    void addPrefix(String display) {
      final compact = _alias(display);
      if (compact.length >= 4 && compact != 'ex' && seenPrefix.add(compact)) {
        _prefixes.add((setIndex: -1, display: display, compact: compact));
      }
    }

    for (var i = 0; i < dictionary.sets.length; i++) {
      final compact = String.fromCharCodes(dictionary.sets.compactCodeUnits(i));
      if (compact.length >= 4 && compact != 'ex' && seenPrefix.add(compact)) {
        _prefixes.add((setIndex: i, display: '', compact: ''));
      }
    }
    for (final era in tcgEraCatalog) {
      for (final key in ['en', 'jp', 'cn']) {
        for (final label in (era[key] as List).cast<String>()) {
          addPrefix(label);
        }
      }
    }
  }
  final SuggestDictionary dictionary;
  final NameRanker names;
  final _aliases = <String, _PackedSet>{};
  final _prefixes = <({int setIndex, String display, String compact})>[];
  late final NameRanker _aliasRanker;
  String _alias(String value) => compactQuery(value.replaceAll('-', ' '));

  _PackedSet? _fromRanked(RankedName row) =>
      _aliases[row.compact] ?? _aliases[_alias(row.display)];
  RankedName? _aliasHit(String text) {
    final ranked = _aliasRanker.rankNames(text);
    return ranked.isEmpty ? null : ranked.first;
  }

  _PackedSet? _prefix(String compact) {
    if (compact.length < 4 ||
        compact == 'ex' ||
        isModifierWord(compact) ||
        artAliases.contains(compact) ||
        names.namePoolHasCompact(compact)) {
      return null;
    }
    final needle = compact.codeUnits;
    final pool = dictionary.sets.compactPool;
    bool matches(int row) {
      final start = dictionary.sets.compactStart(row);
      if (dictionary.sets.compactEnd(row) - start < needle.length) {
        return false;
      }
      for (var i = 0; i < needle.length; i++) {
        if (pool[start + i] != needle[i]) {
          return false;
        }
      }
      return true;
    }

    final hits = _prefixes
        .where((r) => r.setIndex >= 0
            ? matches(r.setIndex)
            : r.compact.startsWith(compact))
        .toList();
    if (hits.isEmpty) {
      return null;
    }
    var slug = '';
    for (final hit in hits) {
      if (slug.isEmpty && hit.setIndex >= 0) {
        slug = dictionary.sets.slug(hit.setIndex)!;
      }
    }
    return _PackedSet(
        '',
        List.unmodifiable(hits.map((h) =>
            h.setIndex >= 0 ? dictionary.sets.display(h.setIndex) : h.display)),
        List.unmodifiable({
          compact,
          ...hits.map((h) => h.setIndex >= 0
              ? String.fromCharCodes(
                  dictionary.sets.compactCodeUnits(h.setIndex))
              : h.compact)
        }),
        slug: slug);
  }

  QueryToken _setToken(String word, String compact, _PackedSet packed,
          {bool prefix = false}) =>
      QueryToken(
          kind: 'set',
          token: word,
          compact: compact,
          eraId: packed.eraId,
          setNames: packed.names,
          needles: packed.needles,
          prefix: prefix,
          slug: prefix ? packed.slug : '');
  bool _isPair(String word) => _pair.hasMatch(word.trim());
  bool isCardMechanicAt(List<String> words, int index) {
    final compact = compactQuery(words[index]);
    final prev = index > 0 ? compactQuery(words[index - 1]) : '';
    final prev2 = compactQuery(
        '${index > 1 ? words[index - 2] : ''} ${index > 0 ? words[index - 1] : ''}');
    if (prev2 == 'callof' ||
        prev == 'shining' ||
        prev == 'hidden' ||
        compact == 'legends') {
      return false;
    }
    final before = words.take(index).toList();
    final head = before
        .where((w) => compactQuery(w).isNotEmpty && !_isPair(w))
        .join(' ');
    bool has(String suffix) =>
        names.namePoolHasCompact(compactQuery('$head $suffix'));
    if (compact == 'legend' || compact == 'legen') {
      return before.any(_isPair) || has('legend');
    }
    if (compact == 'tagteam' || compact == 'tag' || compact == 'team') {
      return before.any(_isPair);
    }
    if (head.isEmpty) {
      return compact == 'mega';
    }
    if (compact == 'break') {
      return has('break');
    }
    if (compact == 'lvx' || compact == 'lv') {
      return has('lvx');
    }
    if (compact == 'vunion' || compact == 'union') {
      return has('vunion');
    }
    if (compact == 'delta' || compact == 'species') {
      return has('delta species') || has(compact);
    }
    if (compact == 'prime') {
      return has('prime');
    }
    if (compact == 'star') {
      return has('gold star') || has('prism star') || has('star');
    }
    if (compact == 'prism') {
      return has('prism star');
    }
    return false;
  }

  bool _mechanicPhrase(List<String> words, int start, int count) {
    final slice = words.sublist(start, start + count);
    if (_isPair(slice.last)) {
      return true;
    }
    final compact = compactQuery(slice.join(' '));
    if (compact.startsWith('tagteam')) {
      final before = words.take(start);
      return before.any(_isPair) ||
          before.any((w) => compactQuery(w).length >= 3);
    }
    return count == 1 && isCardMechanicAt(words, start);
  }

  ({QueryToken token, int words})? _consumePhrase(
      List<String> words, int start) {
    for (var n = math.min(4, words.length - start); n >= 2; n--) {
      final token = words.sublist(start, start + n).join(' ');
      final compact = compactQuery(token);
      if (compact.length < 6) {
        continue;
      }
      final set = _aliasHit(token);
      if (set == null || !set.withinCap || set.compact.isEmpty) {
        continue;
      }
      final extraName = math.max(0, set.compact.length - compact.length);
      final extraQuery = math.max(0, compact.length - set.compact.length);
      if (extraName > 3 && extraQuery == 0 && set.distance > 1e-9) {
        continue;
      }
      final packed = _fromRanked(set);
      if (packed == null || _mechanicPhrase(words, start, n)) {
        continue;
      }
      final rankedNames = names.rankNames(token);
      if (rankedNames.isNotEmpty &&
          rankedNames.first.withinCap &&
          rankedNames.first.compact == compact &&
          rankedNames.first.distance <= set.distance) {
        continue;
      }
      return (token: _setToken(token, set.compact, packed), words: n);
    }
    return null;
  }

  QueryToken _classify(String word) {
    final compact = compactQuery(word);
    if (artAliases.contains(compact)) {
      return QueryToken(kind: 'art', token: word, compact: compact);
    }
    if (rarityAliases.containsKey(compact)) {
      return QueryToken(
          kind: 'rarity',
          token: word,
          compact: compact,
          rarity: rarityAliases[compact]!);
    }
    final exact =
        compact.length >= 2 && compact != 'ex' ? _aliases[compact] : null;
    if (exact != null) {
      return names.namePoolHasCompact(compact)
          ? QueryToken(kind: 'name', token: word)
          : _setToken(word, compact, exact);
    }
    final number = parseCollectorWord(word);
    if (number != null) {
      return number;
    }
    final prefix = _prefix(compact);
    if (prefix != null) {
      return _setToken(word, compact, prefix, prefix: true);
    }
    if (compact.length < 5) {
      return QueryToken(kind: 'name', token: word);
    }
    final set = _aliasHit(word);
    if (set == null || !set.withinCap) {
      return QueryToken(kind: 'name', token: word);
    }
    final rankedNames = names.rankNames(word);
    final name = rankedNames.isEmpty ? null : rankedNames.first;
    final nameOk = name?.withinCap ?? false;
    if (nameOk && name!.compact == compact) {
      return QueryToken(kind: 'name', token: word);
    }
    final sameFamily = nameOk &&
        (name!.compact.startsWith(set.compact) ||
            set.compact.startsWith(name.compact));
    if (!nameOk || sameFamily || set.distance + .25 < name!.distance) {
      final packed = _fromRanked(set);
      if (packed != null) {
        return _setToken(word, set.compact, packed);
      }
    }
    return QueryToken(kind: 'name', token: word);
  }

  ParsedQuery parseTypedQuery(String query) {
    final raw = query.trim();
    final empty = ParsedQuery(raw: raw, nameQuery: raw);
    final words = raw.split(_space).where((w) => w.isNotEmpty).toList();
    if (words.length == 1) {
      final number = parseCollectorWord(raw);
      if (number != null) {
        return ParsedQuery(raw: raw, nameQuery: '', numberTokens: [number]);
      }
      final compact = compactQuery(raw);
      final packed = compact.length >= 8 ? _prefix(compact) : null;
      return packed == null
          ? empty
          : ParsedQuery(
              raw: raw,
              nameQuery: '',
              setTokens: [_setToken(raw, compact, packed, prefix: true)]);
    }
    if (words.length < 2 || names.namePoolHasCompact(compactQuery(raw))) {
      return empty;
    }
    final peeled = <String>[];
    final rarities = <QueryToken>[];
    for (var i = 0; i < words.length; i++) {
      final phrase = compactQuery(
          '${words[i]} ${i + 1 < words.length ? words[i + 1] : ''}');
      if (rarityPhrases.containsKey(phrase)) {
        rarities.add(QueryToken(
            kind: 'rarity',
            token: [words[i], if (i + 1 < words.length) words[i + 1]].join(' '),
            compact: phrase,
            rarity: rarityPhrases[phrase]!));
        i++;
      } else {
        peeled.add(words[i]);
      }
    }
    final classified = <QueryToken>[];
    for (var i = 0; i < peeled.length;) {
      final phrase = _consumePhrase(peeled, i);
      if (phrase != null) {
        classified.add(phrase.token);
        i += phrase.words;
      } else {
        classified.add(isCardMechanicAt(peeled, i)
            ? QueryToken(kind: 'name', token: peeled[i])
            : _classify(peeled[i]));
        i++;
      }
    }
    List<QueryToken> tokens(String kind) =>
        classified.where((t) => t.kind == kind).toList();
    final sets = tokens('set');
    final art = tokens('art');
    final numbers = tokens('number');
    rarities.addAll(tokens('rarity'));
    final nameWords = tokens('name').map((t) => t.token).toList();
    if ((sets.isEmpty && art.isEmpty && numbers.isEmpty && rarities.isEmpty) ||
        nameWords.isEmpty) {
      return empty;
    }
    return ParsedQuery(
        raw: raw,
        nameQuery: nameWords.join(' '),
        setTokens: sets,
        artTokens: art,
        numberTokens: numbers,
        rarityTokens: rarities);
  }

  String typedMeiliQuery(String query) {
    final raw = query.trim();
    final parsed = parseTypedQuery(raw);
    if (parsed.setAware || parsed.setOnly) {
      return raw;
    }
    final name = parsed.nameQuery.isEmpty ? raw : parsed.nameQuery.trim();
    final next = parseTypedQuery(name);
    if (next.setAware || next.numberTokens.isNotEmpty) {
      return name;
    }
    final compact = compactQuery(name);
    final ranked = names.rankNames(name);
    if (compact.isEmpty ||
        ranked.isEmpty ||
        !ranked.first.withinCap ||
        ranked.first.compact.startsWith(compact)) {
      return name;
    }
    return ranked.first.display;
  }

  List<String> catalogRecall(String query, {int limit = 6}) {
    final raw = query.trim();
    if (raw.isEmpty) {
      return const [];
    }
    final parsed = parseTypedQuery(raw);
    if (parsed.bareCollector || parsed.setOnly) {
      return [raw];
    }
    final words = (parsed.nameQuery.isEmpty ? raw : parsed.nameQuery)
        .trim()
        .split(_space)
        .where((w) => w.isNotEmpty)
        .toList();
    final stem = words
        .firstWhere((w) => !isModifierWord(w),
            orElse: () => words.isEmpty ? raw : words.first)
        .trim();
    final accepted = names.rankNames(stem).where((r) => r.withinCap).toList();
    final full =
        words.length >= 2 && compactQuery(raw) != compactQuery(stem) ? raw : '';
    if (accepted.any((r) => r.distance == 0)) {
      return [stem, if (full.isNotEmpty) full];
    }
    final seen = <String>{};
    final result = <String>[];
    for (final row in accepted) {
      final display = row.display.trim();
      if (display.isEmpty || !seen.add(compactQuery(display))) {
        continue;
      }
      result.add(display);
      if (result.length >= math.max(1, limit)) {
        break;
      }
    }
    if (result.isEmpty) {
      result.add(stem);
    }
    if (full.isNotEmpty &&
        !result.any((n) => compactQuery(n) == compactQuery(full))) {
      result.add(full);
    }
    return result;
  }
}
