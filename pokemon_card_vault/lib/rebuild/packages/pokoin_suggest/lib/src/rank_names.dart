import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'compact_query.dart';
import 'pkd1.dart';
import 'prefix_edit_distance.dart';
import 'typed_modifiers.dart' as modifiers;

const rankFill = 48;
const distanceLambda = 4.236;
const popularityPoints = 2.0;
const perfectMatchPoints = 4.0;
const bareMegaPoints = 1.25;
const popularityPriorRef = 400;
const _hasModifier = 1 << 13;
const _xyMega = 1 << 14;
final _logPriorRef = math.log(1 + popularityPriorRef);

/// Only selected rows become objects. Text stays in the dictionary until read.
class RankedName {
  const RankedName._(this._column, this.index, this.distance, this.withinCap,
      this.score, this.kind);
  final SuggestColumn _column;
  final int index;
  final double distance, score;
  final bool withinCap;
  final String kind;
  String get slug => _column.slug(index) ?? '';
  String get display => _column.display(index);
  String get compact => String.fromCharCodes(_column.compactCodeUnits(index));
  int get prior => _column.priors[index];
}

/// Web-compatible name ranking over PKD1 typed columns, without per-row strings
/// or persistent row objects. Own one instance per dictionary/search engine.
class NameRanker {
  NameRanker(this.dictionary, {SuggestColumn? pool, String kind = 'name'})
      : _column = pool ?? dictionary.names,
        _kind = kind,
        _flags = Uint16List((pool ?? dictionary.names).length),
        _popularity = Float64List((pool ?? dictionary.names).length),
        _scores = Float64List((pool ?? dictionary.names).length),
        _distances = Float64List((pool ?? dictionary.names).length) {
    final column = _column;
    for (var row = 0; row < column.length; row++) {
      final display = column.display(row);
      var mask = 0;
      for (var mod = 0; mod < modifiers.modifierCompacts.length; mod++) {
        if (modifiers.displayHasModifier(
            display, modifiers.modifierCompacts[mod])) {
          mask |= 1 << mod;
        }
      }
      if (modifiers.modifierName.hasMatch(display)) {
        mask |= _hasModifier;
      }
      if (modifiers.xyMegaTitle.hasMatch(display)) {
        mask |= _xyMega;
      }
      _flags[row] = mask;
      final prior = math.max(1, column.priors[row]);
      _popularity[row] = math.min(popularityPoints,
          popularityPoints * math.log(1 + prior) / _logPriorRef);
    }
  }

  final SuggestDictionary dictionary;
  final SuggestColumn _column;
  final String _kind;
  final Uint16List _flags;
  final Float64List _popularity, _scores, _distances;
  final _distance = PrefixDistanceWorkspace();
  final _memo = LinkedHashMap<String, List<RankedName>>();

  modifiers.TypedModifiers typedModifiers(String query) =>
      modifiers.typedModifiers(query, namePoolHasCompact: namePoolHasCompact);

  bool namePoolHasCompact(String compact) {
    if (compact.isEmpty) {
      return false;
    }
    final units = compact.codeUnits;
    final column = dictionary.names;
    final pool = column.compactPool;
    final index = dictionary.sortedNameIndexes;
    var low = 0;
    var high = index.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      final row = index[mid];
      final start = column.compactStart(row);
      final length = column.compactEnd(row) - start;
      var order = 0;
      for (var i = 0; i < math.min(length, units.length); i++) {
        order = pool[start + i].compareTo(units[i]);
        if (order != 0) {
          break;
        }
      }
      if (order == 0) {
        order = length.compareTo(units.length);
      }
      if (order == 0) {
        return true;
      }
      if (order < 0) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return false;
  }

  List<RankedName> rankNames(String query, {int fill = rankFill}) {
    final compact = compactQuery(query);
    if (compact.isEmpty) {
      return const [];
    }
    final limit = math.max(1, fill == 0 ? rankFill : fill);
    final alias = modifiers.megaAliasCompact(query);
    final key = '$compact~$alias|names|$limit';
    final cached = _memo[key];
    if (cached != null) {
      return cached;
    }
    final result = _rank(query, compact, alias, limit, bounded: true);
    _memo[key] = result;
    if (_memo.length > 32) {
      _memo.remove(_memo.keys.first);
    }
    return result;
  }

  List<RankedName> rankNamesExhaustive(String query, {int fill = rankFill}) {
    final compact = compactQuery(query);
    if (compact.isEmpty) {
      return const [];
    }
    return _rank(query, compact, modifiers.megaAliasCompact(query),
        math.max(1, fill == 0 ? rankFill : fill),
        bounded: false);
  }

  List<RankedName> _rank(String query, String compact, String alias, int limit,
      {required bool bounded}) {
    final typed = typedModifiers(query);
    var modsMask = 0;
    for (final mod in typed.mods) {
      modsMask |= 1 << modifiers.modifierCompacts.indexOf(mod);
    }
    final matchPoints = typed.mods.length == 1 &&
            typed.mods[0] == 'mega' &&
            typed.nameCompact.isEmpty
        ? bareMegaPoints
        : perfectMatchPoints;
    final cap = maxDistance(compact.length);
    var candidates = _scan(compact, alias, modsMask, matchPoints, cap,
        bounded ? cap : double.infinity);
    if (bounded && candidates.isEmpty) {
      candidates =
          _scan(compact, alias, modsMask, matchPoints, cap, double.infinity);
    } else if (!bounded) {
      final within =
          candidates.where((row) => _distances[row] <= cap + 1e-9).toList();
      if (within.isNotEmpty) {
        candidates = within;
      }
    }
    final column = _column;
    candidates.sort((a, b) {
      final scoreOrder = _scores[b].compareTo(_scores[a]);
      if (scoreOrder != 0) {
        return scoreOrder;
      }
      final lengthOrder = (column.compactEnd(a) - column.compactStart(a))
          .compareTo(column.compactEnd(b) - column.compactStart(b));
      if (lengthOrder != 0) {
        return lengthOrder;
      }
      final collationOrder =
          column.collationRanks[a].compareTo(column.collationRanks[b]);
      return collationOrder == 0 ? a.compareTo(b) : collationOrder;
    });
    return List.unmodifiable(candidates.take(limit).map((row) => RankedName._(
        column,
        row,
        _distances[row],
        _distances[row] <= cap + 1e-9,
        _scores[row],
        _kind)));
  }

  List<int> _scan(String compact, String alias, int modsMask,
      double matchPoints, double cap, double cutoff) {
    final queryUnits = compact.codeUnits;
    final aliasUnits = alias.codeUnits;
    final column = _column;
    final pool = column.compactPool;
    final candidates = <int>[];
    final exMask = 1 << modifiers.modifierCompacts.indexOf('ex');
    final gxMask = 1 << modifiers.modifierCompacts.indexOf('gx');
    for (var row = 0; row < column.length; row++) {
      final start = column.compactStart(row);
      final end = column.compactEnd(row);
      if (start == end) {
        continue;
      }
      final flags = _flags[row];
      final usesAlias = alias.isNotEmpty && flags & _xyMega != 0;
      // A shorter name already needs more deletions than the permitted cap.
      if (cutoff.isFinite &&
          compact.length - (end - start) > cutoff &&
          (!usesAlias || alias.length - (end - start) > cutoff)) {
        continue;
      }
      var distance = cutoff == keyboardCost && queryUnits.length <= 3
          ? _shortDistance(queryUnits, pool, start, end)
          : _distance.distance(queryUnits, pool,
              start: start, end: end, cutoff: cutoff);
      var queryLength = compact.length;
      if (usesAlias) {
        final viaAlias = _distance.distance(aliasUnits, pool,
            start: start, end: end, cutoff: cutoff);
        if (viaAlias < distance) {
          distance = viaAlias;
          queryLength = alias.length;
        }
      }
      if (cutoff.isFinite && distance > cap + 1e-9) {
        continue;
      }
      final bonus =
          modsMask != 0 && flags & modsMask == modsMask ? matchPoints : 0.0;
      var penalty = 1.0;
      if (modsMask == 0 && flags & _hasModifier != 0) {
        final joinedMechanic = compact.length > 3 &&
            ((flags & exMask != 0 && compact.endsWith('ex')) ||
                (flags & gxMask != 0 && compact.endsWith('gx')));
        if (!joinedMechanic) {
          penalty = 0.05;
        }
      }
      final extra = math.max(0, end - start - queryLength);
      final suffixWeight = queryLength <= 5 ? 0.75 : 0.04;
      _scores[row] = (_popularity[row] + bonus) *
          math.exp(-distanceLambda * distance) /
          (1 + suffixWeight * extra) *
          penalty;
      _distances[row] = distance;
      candidates.add(row);
    }
    return candidates;
  }

  // With a 0.5 cap no insertion/deletion is affordable. The only possibilities
  // are one neighboring-key substitution or one adjacent transposition.
  double _shortDistance(List<int> query, Uint16List pool, int start, int end) {
    if (end - start < query.length) {
      return double.infinity;
    }
    var first = -1;
    var second = -1;
    for (var i = 0; i < query.length; i++) {
      if (query[i] != pool[start + i]) {
        if (first < 0) {
          first = i;
        } else if (second < 0) {
          second = i;
        } else {
          return double.infinity;
        }
      }
    }
    if (first < 0) {
      return 0;
    }
    if (second < 0) {
      // Reuse the authoritative substitution cost on this single code unit.
      return _distance.distance(query, pool,
          start: start, end: end, cutoff: keyboardCost);
    }
    return second == first + 1 &&
            query[first] == pool[start + second] &&
            query[second] == pool[start + first]
        ? transposeCost
        : double.infinity;
  }
}
