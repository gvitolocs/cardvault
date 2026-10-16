import 'dart:convert';
import 'dart:typed_data';

import 'package:pokoin_suggest/pokoin_suggest.dart';
import 'package:test/test.dart';

Uint8List dictionaryBytes(
    {bool equalRanks = false, bool unicodeCompact = false}) {
  Uint8List lengths(List<String> strings) => Uint8List.fromList(
      strings.map((value) => utf8.encode(value).length).toList());
  Uint8List words(List<int> values) {
    final bytes = Uint8List(values.length * 2);
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i < values.length; i++) {
      data.setUint16(i * 2, values[i], Endian.little);
    }
    return bytes;
  }

  final sections = <String, Uint8List>{
    'STRS': Uint8List.fromList(utf8.encode(
        'PikachuFlab\u00e9b\u00e9Base Setbase-setMitsuhiro Aritamitsuhiro-arita${unicodeCompact ? 'ピカチュウ😀' : 'flabebe'}')),
    'NDLN': lengths(['Pikachu', 'Flab\u00e9b\u00e9']),
    'SDLN': lengths(['Base Set']),
    'SSLN': lengths(['base-set']),
    'ADLN': lengths(['Mitsuhiro Arita']),
    'ASLN': lengths(['mitsuhiro-arita']),
    'NPRI': words([428, 5]),
    'SPRI': words([102]),
    'APRI': words([100]),
    'NCXI': words([1]),
    'SCXI': words([]),
    'ACXI': words([]),
    'NCXL': lengths([unicodeCompact ? 'ピカチュウ😀' : 'flabebe']),
    'SCXL': Uint8List(0),
    'ACXL': Uint8List(0),
    'NCOL': words(equalRanks ? [0, 0] : [1, 0]),
    'SCOL': words([0]),
    'ACOL': words([0]),
    'SNAT': Uint8List.fromList([0]),
    'NATP': Uint8List.fromList([1, 7, ...utf8.encode('western')]),
  };
  var size = 36 + sections.length * 12;
  final entries = <({String tag, int offset, Uint8List bytes})>[];
  const sectionOrder = [
    'STRS',
    'NDLN',
    'NPRI',
    'NCXI',
    'NCXL',
    'SDLN',
    'SSLN',
    'SPRI',
    'SNAT',
    'SCXI',
    'SCXL',
    'ADLN',
    'ASLN',
    'APRI',
    'ACXI',
    'ACXL',
    'NCOL',
    'SCOL',
    'ACOL',
    'NATP',
  ];
  for (final tag in sectionOrder) {
    size = (size + 3) & ~3;
    entries.add((tag: tag, offset: size, bytes: sections[tag]!));
    size += sections[tag]!.length;
  }
  final bytes = Uint8List(size);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, ascii.encode('PKD1'));
  data.setUint16(4, 1, Endian.little);
  data.setUint16(6, entries.length, Endian.little);
  data.setUint32(24, 2, Endian.little);
  data.setUint32(28, 1, Endian.little);
  data.setUint32(32, 1, Endian.little);
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final position = 36 + i * 12;
    bytes.setRange(position, position + 4, ascii.encode(entry.tag));
    data.setUint32(position + 4, entry.offset, Endian.little);
    data.setUint32(position + 8, entry.bytes.length, Endian.little);
    bytes.setRange(
        entry.offset, entry.offset + entry.bytes.length, entry.bytes);
  }
  return bytes;
}

void main() {
  test('decodes typed columns, shipped compacts, slugs and collation', () {
    final dictionary = decodePkd1(dictionaryBytes(),
        expectedContentHash: '00000000000000000000000000000000');
    expect(dictionary.names.length, 2);
    expect(dictionary.names.display(1), 'Flab\u00e9b\u00e9');
    expect(
        String.fromCharCodes(dictionary.names.compactCodeUnits(0)), 'pikachu');
    expect(
        String.fromCharCodes(dictionary.names.compactCodeUnits(1)), 'flabebe');
    expect(dictionary.names.priors, [428, 5]);
    expect(dictionary.names.collationRanks, [1, 0]);
    expect(dictionary.sortedNameIndexes, [1, 0]);
    expect(dictionary.sets.slug(0), 'base-set');
    expect(dictionary.artists.slug(0), 'mitsuhiro-arita');
    expect(dictionary.nationalities[dictionary.sets.nationalityIndexes![0]],
        'western');
    expect(() => dictionary.names.priors[0] = 0, throwsUnsupportedError);
  });

  test('accepts a file view with unaligned buffer origin', () {
    final file = dictionaryBytes();
    final backing = Uint8List(file.length + 1)
      ..setRange(1, file.length + 1, file);
    expect(
        decodePkd1(Uint8List.sublistView(backing, 1)).names.priors.first, 428);
  });

  test('accepts shared collation ranks from the reference encoder', () {
    expect(decodePkd1(dictionaryBytes(equalRanks: true)).names.collationRanks,
        [0, 0]);
  });

  test('decodes shipped compacts as UTF-16, including surrogate pairs', () {
    expect(
        decodePkd1(dictionaryBytes(unicodeCompact: true))
            .names
            .compactCodeUnits(1),
        'ピカチュウ😀'.codeUnits);
  });

  test('rejects unexpected section count and section order', () {
    final count = dictionaryBytes();
    ByteData.sublistView(count).setUint16(6, 21, Endian.little);
    expect(() => decodePkd1(count), throwsFormatException);
    final order = dictionaryBytes();
    order.setRange(36, 40, ascii.encode('NDLN'));
    expect(() => decodePkd1(order), throwsFormatException);
  });

  test('rejects invalid ranks, exception lengths and nationality indexes', () {
    int offset(Uint8List bytes, String tag) {
      final data = ByteData.sublistView(bytes);
      for (var i = 0; i < data.getUint16(6, Endian.little); i++) {
        final entry = 36 + 12 * i;
        if (ascii.decode(bytes.sublist(entry, entry + 4)) == tag) {
          return data.getUint32(entry + 4, Endian.little);
        }
      }
      throw StateError('Missing test column');
    }

    final rank = dictionaryBytes();
    ByteData.sublistView(rank)
        .setUint16(offset(rank, 'NCOL'), 2, Endian.little);
    expect(() => decodePkd1(rank), throwsFormatException);
    final compact = dictionaryBytes();
    compact[offset(compact, 'NCXL')] = 255;
    expect(() => decodePkd1(compact), throwsFormatException);
    final nationality = dictionaryBytes();
    nationality[offset(nationality, 'SNAT')] = 1;
    expect(() => decodePkd1(nationality), throwsFormatException);
  });

  test('rejects truncated files, unknown formats and version mismatch', () {
    final file = dictionaryBytes();
    for (final length in [0, 35, 100, file.length - 1]) {
      expect(() => decodePkd1(Uint8List.sublistView(file, 0, length)),
          throwsFormatException);
    }
    expect(() => decodePkd1(file, expectedContentHash: 'wrong'),
        throwsFormatException);
    ByteData.sublistView(file).setUint16(4, 2, Endian.little);
    expect(() => decodePkd1(file), throwsFormatException);
  });

  test('rejects overlapping and missing columns', () {
    final file = dictionaryBytes();
    final data = ByteData.sublistView(file);
    data.setUint32(
        36 + 12 + 4, data.getUint32(36 + 4, Endian.little), Endian.little);
    expect(() => decodePkd1(file), throwsFormatException);
    final missing = dictionaryBytes();
    missing.setRange(36, 40, ascii.encode('NONE'));
    expect(() => decodePkd1(missing), throwsFormatException);
  });
}
