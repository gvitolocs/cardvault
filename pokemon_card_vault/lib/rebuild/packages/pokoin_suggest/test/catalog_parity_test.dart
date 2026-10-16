import 'dart:convert';
import 'dart:io';

import 'package:pokoin_suggest/pokoin_suggest.dart';
import 'package:test/test.dart';

void main() {
  test('every real PKD1 row matches the pinned upstream catalog', () {
    final reference = jsonDecode(utf8.decode(gzip
            .decode(File('test/reference/catalog.json.gz').readAsBytesSync())))
        as Map<String, dynamic>;
    final bytes =
        File('../../../../assets/suggest/dictionary.pkd1').readAsBytesSync();
    final dictionary =
        decodePkd1(bytes, expectedContentHash: bundledDictionaryContentHash);
    expect(bytes.length, 345880);
    expect(dictionary.contentHash, reference['hash']);
    expect(dictionary.names.length, 10009);
    expect(dictionary.sets.length, 838);
    expect(dictionary.artists.length, 444);
    final columns = [dictionary.names, dictionary.sets, dictionary.artists];
    for (var kind = 0; kind < columns.length; kind++) {
      final expected = reference[['names', 'sets', 'artists'][kind]] as List;
      final column = columns[kind];
      for (var row = 0; row < column.length; row++) {
        final actual = [
          column.display(row),
          if (kind != 0) column.slug(row),
          column.priors[row],
          if (kind == 1)
            dictionary.nationalities[column.nationalityIndexes![row]],
          String.fromCharCodes(column.compactCodeUnits(row)),
          column.collationRanks[row],
        ];
        expect(actual, expected[row], reason: 'kind $kind row $row');
      }
    }
    final names = reference['names'] as List;
    final expectedIndex = List<int>.generate(names.length, (i) => i)
      ..sort((a, b) {
        final comparison =
            (names[a][2] as String).compareTo(names[b][2] as String);
        return comparison == 0 ? a.compareTo(b) : comparison;
      });
    expect(dictionary.sortedNameIndexes, expectedIndex);
  });

  test('asset and all golden fixtures share upstream provenance', () {
    final manifest = jsonDecode(
        File('../../../../assets/suggest/manifest.json').readAsStringSync());
    final meta = jsonDecode(File('test/golden/meta.json').readAsStringSync());
    expect(manifest['sourceCommit'], bundledDictionarySourceCommit);
    expect(meta['sourceCommit'], bundledDictionarySourceCommit);
    expect(meta['contentHash'], bundledDictionaryContentHash);
    for (final entry in {
      'queries': 'queries.json',
      'compact': 'compact.json',
      'distances': 'distance.json',
      'paint': 'paint.json',
    }.entries) {
      final cases =
          jsonDecode(File('test/golden/${entry.value}').readAsStringSync())
              as List;
      expect(cases.length, meta['counts'][entry.key]);
    }
  });
}
