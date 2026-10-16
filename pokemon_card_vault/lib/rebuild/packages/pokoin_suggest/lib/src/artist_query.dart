import 'compact_query.dart';
import 'pkd1.dart';
import 'rank_names.dart';

class ArtistQuery {
  const ArtistQuery(
      {required this.slug,
      required this.display,
      required this.remainingQuery});
  final String slug, display, remainingQuery;
}

/// Small artist-only prefix index, prepared in the suggestion isolate.
/// Ambiguous prefixes stay unresolved; literal catalog names are protected.
class ArtistQueryResolver {
  ArtistQueryResolver(this.dictionary, this.names) {
    void add(String alias, int row) {
      for (var size = 3; size <= alias.length; size++) {
        final prefix = alias.substring(0, size);
        _prefix.update(prefix, (old) => old == row ? row : -1,
            ifAbsent: () => row);
      }
      _exact.update(alias, (old) => old == row ? row : -1, ifAbsent: () => row);
    }

    for (var row = 0; row < dictionary.artists.length; row++) {
      final display = dictionary.artists.display(row);
      add(compactQuery(display), row);
      final words = display.split(RegExp(r'\s+'));
      final surname = compactQuery(words.last);
      if (words.length > 1 && surname.length >= 5) add(surname, row);
    }
  }

  final SuggestDictionary dictionary;
  final NameRanker names;
  final _prefix = <String, int>{}, _exact = <String, int>{};

  ArtistQuery? resolve(String raw) {
    if (raw.length > 180 || names.namePoolHasCompact(compactQuery(raw))) {
      return null;
    }
    final words = raw.trim().split(RegExp(r'\s+'));
    var bestScore = -1, bestRow = -1, bestStart = 0, bestEnd = 0;
    var tied = false;
    for (var start = 0; start < words.length; start++) {
      for (var end = start + 1;
          end <= words.length && end <= start + 6;
          end++) {
        final key = compactQuery(words.sublist(start, end).join(' '));
        if (key.length < 3) continue;
        final exact = _exact[key];
        final row = exact ?? _prefix[key];
        if (row == null || row < 0 || names.namePoolHasCompact(key)) continue;
        final score = (exact == null ? 0 : 1000) + key.length;
        if (score > bestScore) {
          bestScore = score;
          bestRow = row;
          bestStart = start;
          bestEnd = end;
          tied = false;
        } else if (score == bestScore && row != bestRow) {
          tied = true;
        }
      }
    }
    if (bestRow < 0 || tied) return null;
    return ArtistQuery(
        slug: dictionary.artists.slug(bestRow)!,
        display: dictionary.artists.display(bestRow),
        remainingQuery: [
          ...words.take(bestStart),
          ...words.skip(bestEnd),
        ].join(' '));
  }
}
