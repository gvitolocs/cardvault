import 'dart:convert';
import 'dart:io';

import 'package:pokoin_suggest/pokoin_suggest.dart';
import 'package:test/test.dart';

void main() {
  final engine = SuggestEngine(decodePkd1(
      File('../../../../assets/suggest/dictionary.pkd1').readAsBytesSync(),
      expectedContentHash: bundledDictionaryContentHash));
  final cases =
      jsonDecode(File('test/golden/queries.json').readAsStringSync()) as List;
  double round(double n) => (n * 1e9).round() / 1e9;
  List<Object> row(RankedName r) =>
      [r.display, round(r.distance), r.withinCap, round(r.score)];
  for (final c in cases) {
    final q = c['q'] as String;
    test('intent parity: $q', () {
      final parsed = engine.parseTypedQuery(q);
      expect(parsed.toGoldenJson(), c['parsed']);
      expect(parsed.setOnly, c['setOnly']);
      expect(parsed.setAware, c['setAware']);
      expect(parsed.bareCollector, c['bareCollector']);
      expect(engine.rankArtists(q).take(1).map(row).toList(), c['rankArtists']);
      expect(engine.rankSets(q).take(1).map(row).toList(), c['rankSets']);
      expect(engine.catalogIntent(q).toGoldenJson(), c['intent']);
      expect(engine.typedMeiliQuery(q), c['meiliQuery']);
      expect(engine.catalogRecall(q), c['catalogRecall']);
    });
  }
}
