import 'dart:math' as math;
import 'dart:typed_data';

const keyboardCost = 0.5;
const farCost = 1.0;
const indelCost = 1.0;
const transposeCost = keyboardCost;
const twoInsertKeyboardCost = 2 * farCost + keyboardCost;

const _keyNeighbors = {
  'q': 'wa',
  'w': 'qeas',
  'e': 'wrsd',
  'r': 'etdf',
  't': 'ryfg',
  'y': 'tugh',
  'u': 'yihj',
  'i': 'uojk',
  'o': 'ipkl',
  'p': 'ol',
  'a': 'qwsz',
  's': 'awedxz',
  'd': 'serfcx',
  'f': 'drtgvc',
  'g': 'ftyhbv',
  'h': 'gyujnb',
  'j': 'huiknm',
  'k': 'jiolm',
  'l': 'kop',
  'z': 'asx',
  'x': 'zsdc',
  'c': 'xdfv',
  'v': 'cfgb',
  'b': 'vghn',
  'n': 'bhjm',
  'm': 'njk',
  '1': '2q',
  '2': '13qw',
  '3': '24we',
  '4': '35er',
  '5': '46rt',
  '6': '57ty',
  '7': '68yu',
  '8': '79ui',
  '9': '80io',
  '0': '9op',
};
final _keyAdjacent = _adjacency();
Uint8List _adjacency() {
  final table = Uint8List(128 * 128);
  for (final entry in _keyNeighbors.entries) {
    final a = entry.key.codeUnitAt(0);
    for (final b in entry.value.codeUnits) {
      table[a * 128 + b] = 1;
      table[b * 128 + a] = 1;
    }
  }
  return table;
}

double maxDistance(int queryLength) {
  if (queryLength <= 0) {
    return 0;
  }
  if (queryLength <= 3) {
    return keyboardCost;
  }
  if (queryLength <= 5) {
    return farCost;
  }
  return twoInsertKeyboardCost;
}

final _defaultWorkspace = PrefixDistanceWorkspace();
double prefixEditDistance(String query, String name,
        {double cutoff = double.infinity}) =>
    _defaultWorkspace.distance(query.codeUnits, name.codeUnits, cutoff: cutoff);

/// Reuses three DP rows; a catalog name is read directly from its typed pool.
class PrefixDistanceWorkspace {
  Float64List _prev2 = Float64List(64);
  Float64List _prev = Float64List(64);
  Float64List _curr = Float64List(64);

  double distance(List<int> query, List<int> name,
      {int start = 0, int? end, double cutoff = double.infinity}) {
    final rows = query.length;
    final cols = (end ?? name.length) - start;
    if (rows == 0) {
      return 0;
    }
    if (cols == 0) {
      return rows * indelCost;
    }
    final bounded = cutoff.isFinite;
    final limit = bounded ? cutoff + 1e-9 : double.infinity;
    final width = bounded
        ? math.min(cols, rows + (cutoff / indelCost + 1e-9).floor())
        : cols;
    if (_prev.length < width + 1) {
      final size = math.max(width + 1, _prev.length * 2);
      _prev2 = Float64List(size);
      _prev = Float64List(size);
      _curr = Float64List(size);
    }
    var prev2 = _prev2;
    var prev = _prev;
    var curr = _curr;
    for (var j = 0; j <= width; j++) {
      prev[j] = j * indelCost;
    }
    var lastMin = 0.0;
    for (var i = 1; i <= rows; i++) {
      curr[0] = i * indelCost;
      var rowMin = curr[0];
      final qc = query[i - 1];
      final qp = i > 1 ? query[i - 2] : -1;
      for (var j = 1; j <= width; j++) {
        final nc = name[start + j - 1];
        final sub = qc == nc
            ? 0.0
            : qc < 128 && nc < 128 && _keyAdjacent[qc * 128 + nc] != 0
                ? keyboardCost
                : farCost;
        var best = prev[j] + indelCost;
        final left = curr[j - 1] + indelCost;
        if (left < best) {
          best = left;
        }
        final diagonal = prev[j - 1] + sub;
        if (diagonal < best) {
          best = diagonal;
        }
        if (i > 1 && j > 1 && qc == name[start + j - 2] && qp == nc) {
          final transposed = prev2[j - 2] + transposeCost;
          if (transposed < best) {
            best = transposed;
          }
        }
        curr[j] = best;
        if (best < rowMin) {
          rowMin = best;
        }
      }
      if (rowMin > limit && lastMin > limit) {
        return double.infinity;
      }
      lastMin = rowMin;
      final recycled = prev2;
      prev2 = prev;
      prev = curr;
      curr = recycled;
    }
    var best = prev[0];
    for (var j = 1; j <= width; j++) {
      if (prev[j] < best) {
        best = prev[j];
      }
    }
    return best;
  }
}
