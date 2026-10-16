import 'dart:collection';

import 'compact_query.dart';
import 'pkd1.dart';
import 'rank_names.dart';
import 'typed_query.dart';

class CatalogIntent {
  const CatalogIntent(
      {required this.kind,
      this.display = '',
      this.slug = '',
      this.compact = '',
      this.prior = 0,
      this.ranked = const []});
  final String kind, display, slug, compact;
  final int prior;
  final List<RankedName> ranked;
  Map<String, String> toGoldenJson() =>
      {'kind': kind, 'display': display, 'slug': slug};
}

class SuggestEngine {
  SuggestEngine(this.dictionary) : names = NameRanker(dictionary) {
    parser = TypedQueryParser(dictionary, names);
    sets = NameRanker(dictionary, pool: dictionary.sets, kind: 'set');
    final artistRows = <SuggestPoolRow>[];
    final seen = <String>{};
    for (var i = 0; i < dictionary.artists.length; i++) {
      final display = dictionary.artists.display(i);
      final slug = dictionary.artists.slug(i)!;
      void add(String compact) {
        if (compact.isEmpty || !seen.add('$slug:$compact')) {
          return;
        }
        artistRows.add(SuggestPoolRow(
            display: display,
            compact: compact,
            slug: slug,
            prior: dictionary.artists.priors[i],
            collationRank: dictionary.artists.collationRanks[i]));
      }

      add(String.fromCharCodes(dictionary.artists.compactCodeUnits(i)));
      final parts =
          display.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      if (parts.length > 1 && compactQuery(parts.last).length >= 5) {
        add(compactQuery(parts.last));
      }
    }
    artists = NameRanker(dictionary,
        pool: SuggestColumn.fromRows(artistRows), kind: 'artist');
  }
  final SuggestDictionary dictionary;
  final NameRanker names;
  late final NameRanker artists, sets;
  late final TypedQueryParser parser;
  final _intentMemo = LinkedHashMap<String, CatalogIntent>();

  List<RankedName> rankNames(String query, {int fill = rankFill}) =>
      names.rankNames(query, fill: fill);
  List<RankedName> rankArtists(String query, {int fill = 12}) =>
      artists.rankNames(query, fill: fill);
  List<RankedName> rankSets(String query, {int fill = 12}) =>
      sets.rankNames(query, fill: fill);
  ParsedQuery parseTypedQuery(String query) => parser.parseTypedQuery(query);
  String typedMeiliQuery(String query) => parser.typedMeiliQuery(query);
  List<String> catalogRecall(String query, {int limit = 6}) =>
      parser.catalogRecall(query, limit: limit);

  int? _setRow(ParsedQuery parsed) {
    final token = parsed.setTokens.first;
    final pool = dictionary.sets;
    String compact(int i) => String.fromCharCodes(pool.compactCodeUnits(i));
    if (token.compact.isNotEmpty) {
      for (var i = 0; i < pool.length; i++) {
        if (compact(i) == token.compact) {
          return i;
        }
      }
      for (var i = 0; i < pool.length; i++) {
        if (compact(i).startsWith(token.compact)) {
          return i;
        }
      }
    }
    if (token.slug.isNotEmpty) {
      for (var i = 0; i < pool.length; i++) {
        if (pool.slug(i) == token.slug) {
          return i;
        }
      }
    }
    for (final name in token.setNames) {
      final key = compactQuery(name);
      for (var i = 0; i < pool.length; i++) {
        if (compact(i) == key) {
          return i;
        }
      }
    }
    return null;
  }

  CatalogIntent catalogIntent(String raw) {
    final key = compactQuery(raw);
    final memo = _intentMemo[key];
    if (key.isNotEmpty && memo != null) {
      return memo;
    }
    final parsed = parseTypedQuery(raw);
    final rankQuery = parsed.setAware ? parsed.nameQuery : raw;
    final nameRows = parsed.setOnly ? <RankedName>[] : rankNames(rankQuery);
    final compact = compactQuery(parsed.setAware ? rankQuery : raw);
    late final CatalogIntent result;
    CatalogIntent fromRows(String kind, List<RankedName> rows) => rows.isEmpty
        ? CatalogIntent(kind: kind)
        : CatalogIntent(
            kind: kind,
            ranked: rows,
            display: rows.first.display,
            compact: rows.first.compact,
            slug: rows.first.slug,
            prior: rows.first.prior);
    bool prefix(RankedName? row) =>
        row != null &&
        compact.isNotEmpty &&
        (row.compact.startsWith(compact) || compact.startsWith(row.compact));
    if (parsed.setOnly) {
      final set = _setRow(parsed);
      final token = parsed.setTokens.first;
      result = CatalogIntent(
          kind: 'set',
          display: set == null
              ? (token.setNames.isEmpty ? raw : token.setNames.first)
              : dictionary.sets.display(set),
          slug: set == null ? token.slug : dictionary.sets.slug(set)!,
          compact: set == null
              ? compact
              : String.fromCharCodes(dictionary.sets.compactCodeUnits(set)),
          prior: set == null ? 0 : dictionary.sets.priors[set]);
    } else if (parsed.setAware) {
      result = fromRows('name', nameRows);
    } else {
      final artistRows = compact.isEmpty ? <RankedName>[] : rankArtists(raw);
      final setRows = compact.isEmpty ? <RankedName>[] : rankSets(raw);
      final name = nameRows.isEmpty ? null : nameRows.first;
      final artist = artistRows.isEmpty ? null : artistRows.first;
      final set = setRows.isEmpty ? null : setRows.first;
      if (artist != null && artist.compact == compact) {
        result = fromRows('artist', artistRows);
      } else if (set != null && set.compact == compact) {
        result = fromRows('set', setRows);
      } else if (prefix(artist) && !prefix(name)) {
        result = fromRows('artist', artistRows);
      } else if (compact.length >= 5 && prefix(set) && !prefix(name)) {
        result = fromRows('set', setRows);
      } else {
        result = fromRows('name', nameRows);
      }
    }
    if (key.isNotEmpty) {
      _intentMemo[key] = result;
      if (_intentMemo.length > 24) {
        _intentMemo.remove(_intentMemo.keys.first);
      }
    }
    return result;
  }
}
