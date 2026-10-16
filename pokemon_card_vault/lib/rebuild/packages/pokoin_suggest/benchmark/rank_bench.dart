import 'dart:convert';
import 'dart:io';

import 'package:pokoin_suggest/pokoin_suggest.dart';

// Run from the package root. Desktop AOT measurements are not device gates.
void main() {
  final bytes =
      File('../../../../assets/suggest/dictionary.pkd1').readAsBytesSync();
  final loadTimer = Stopwatch()..start();
  final dict =
      decodePkd1(bytes, expectedContentHash: bundledDictionaryContentHash);
  final decodeMs = loadTimer.elapsedMicroseconds / 1000;
  loadTimer.reset();
  final engine = NameRanker(dict);
  final setupMs = loadTimer.elapsedMicroseconds / 1000;
  final cases =
      jsonDecode(File('test/golden/queries.json').readAsStringSync()) as List;
  final queries = cases.map((c) => c['q'] as String).toList();
  for (final q in queries) {
    engine.rankNames(q);
  }
  final samples = <double>[];
  var checksum = 0;
  for (var pass = 0; pass < 5; pass++) {
    for (final q in queries) {
      final timer = Stopwatch()..start();
      final result = engine.rankNames(q);
      timer.stop();
      samples.add(timer.elapsedMicroseconds / 1000);
      if (result.isNotEmpty) {
        checksum += result.first.index;
      }
    }
  }
  samples.sort();
  double percentile(double p) =>
      samples[(p * samples.length).floor().clamp(0, samples.length - 1)];
  print(jsonEncode({
    'mode': 'desktop AOT, not a physical-device benchmark',
    'sourceCommit': bundledDictionarySourceCommit,
    'dictionaryRows': dict.names.length,
    'decodeMs': decodeMs,
    'rankerSetupMs': setupMs,
    'queries': queries.length,
    'samples': samples.length,
    'rankMs': {
      'p50': percentile(.5),
      'p95': percentile(.95),
      'p99': percentile(.99),
      'max': samples.last
    },
    'checksum': checksum,
  }));
}
