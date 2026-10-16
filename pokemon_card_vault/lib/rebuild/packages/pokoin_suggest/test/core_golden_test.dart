import 'dart:convert';
import 'dart:io';

import 'package:pokoin_suggest/pokoin_suggest.dart';
import 'package:test/test.dart';

List<dynamic> _cases(String filename) =>
    jsonDecode(File('test/golden/$filename').readAsStringSync()) as List;
Object _round(double value) =>
    value.isFinite ? (value * 1e9).round() / 1e9 : 'Infinity';
List<Object> _row(RankedName row) =>
    [row.display, _round(row.distance), row.withinCap, _round(row.score)];

void main() {
  final dictionary = decodePkd1(
      File('../../../../assets/suggest/dictionary.pkd1').readAsBytesSync(),
      expectedContentHash: bundledDictionaryContentHash);
  final engine = NameRanker(dictionary);

  test('all 620 Unicode normalization cases match the web', () {
    for (final pair in _cases('compact.json')) {
      expect(compactQuery(pair[0] as String), pair[1],
          reason: pair[0] as String);
    }
  });

  test('all distance cases match, with and without cutoff', () {
    for (final pair in _cases('distance.json')) {
      final q = pair[0] as String;
      final name = pair[1] as String;
      expect(_round(prefixEditDistance(q, name)), pair[2],
          reason: '$q -> $name');
      expect(_round(prefixEditDistance(q, name, cutoff: maxDistance(q.length))),
          pair[3],
          reason: '$q -> $name (cutoff)');
    }
  });

  for (final c in _cases('queries.json')) {
    final query = c['q'] as String;
    test('core parity: $query', () {
      expect(compactQuery(query), c['compact']);
      expect(maxDistance(compactQuery(query).length), c['maxDistance']);
      final mods = engine.typedModifiers(query);
      expect(mods.mods, c['mods']);
      expect(mods.nameCompact, c['nameCompact']);
      expect(
          engine.rankNames(query).take(5).map(_row).toList(), c['rankNames']);
    });
  }

  test('cutoff ranking equals exhaustive ranking for the whole query corpus',
      () {
    for (final c in _cases('queries.json')) {
      final q = c['q'] as String;
      expect(engine.rankNames(q).map(_row).toList(),
          engine.rankNamesExhaustive(q).map(_row).toList(),
          reason: q);
    }
  });

  test('memo and exact lookup preserve immutable results and canonical names',
      () {
    expect(engine.namePoolHasCompact('pikachugx'), isTrue);
    expect(engine.namePoolHasCompact('nosuchblueprint'), isFalse);
    final before = engine.rankNames('charizard');
    expect(identical(before, engine.rankNames('charizard')), isTrue);
    expect(() => before.clear(), throwsUnsupportedError);
    for (var i = 0; i < 40; i++) {
      engine.rankNames('pikachu $i', fill: 5);
    }
    expect(engine.rankNames('charizard').map(_row).toList(),
        before.map(_row).toList());
    expect(engine.rankNames(''), isEmpty);
  });

  test('mechanic filters and XY Mega aliases preserve the web rules', () {
    expect(hasRivalMechanic('Pikachu GX', ['ex']), isTrue);
    expect(hasRivalMechanic('Pikachu', ['ex']), isFalse);
    expect(hasRivalMechanic('Pikachu EX', ['ex']), isFalse);
    expect(displayHasModifier('M Rayquaza EX', 'mega'), isTrue);
    expect(displayHasModifier('Call of Legends', 'legend'), isFalse);
    expect(megaAliasCompact('mega rayquaza'), 'mrayquaza');
    expect(suggestLiveReady('pi'), isFalse);
    expect(suggestLiveReady('pika'), isTrue);
  });
}
