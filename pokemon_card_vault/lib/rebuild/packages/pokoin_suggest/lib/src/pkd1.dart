import 'dart:convert';
import 'dart:typed_data';

enum SuggestKind { name, set, artist }

const _sectionOrder = [
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

/// Typed columns retain the file buffer; strings are decoded only on access.
class SuggestDictionary {
  SuggestDictionary._(this.contentHash, this.names, this.sets, this.artists,
      this.nationalities, this.sortedNameIndexes);

  final String contentHash;
  final SuggestColumn names;
  final SuggestColumn sets;
  final SuggestColumn artists;
  final List<String> nationalities;
  final Uint16List sortedNameIndexes;
}

class SuggestColumn {
  /// Build small auxiliary pools (artist surnames and era aliases), not names.
  factory SuggestColumn.fromRows(List<SuggestPoolRow> rows) {
    final bytes = BytesBuilder(copy: false);
    Uint32List offsets(List<String> values) {
      final result = Uint32List(values.length);
      for (var i = 0; i < values.length; i++) {
        result[i] = bytes.length;
        bytes.add(utf8.encode(values[i]));
      }
      return result.asUnmodifiableView();
    }

    final displays = rows.map((row) => row.display).toList();
    final slugs = rows.map((row) => row.slug).toList();
    final displayOffsets = offsets(displays);
    final slugOffsets = offsets(slugs);
    final compactOffsets = Uint32List(rows.length + 1);
    final units = <int>[];
    for (var i = 0; i < rows.length; i++) {
      compactOffsets[i] = units.length;
      units.addAll(rows[i].compact.codeUnits);
    }
    compactOffsets[rows.length] = units.length;
    return SuggestColumn._(
        bytes.takeBytes().asUnmodifiableView(),
        displayOffsets,
        Uint8List.fromList(displays.map((s) => utf8.encode(s).length).toList())
            .asUnmodifiableView(),
        slugOffsets,
        Uint8List.fromList(slugs.map((s) => utf8.encode(s).length).toList())
            .asUnmodifiableView(),
        Uint16List.fromList(rows.map((r) => r.prior).toList())
            .asUnmodifiableView(),
        Uint16List.fromList(rows.map((r) => r.collationRank).toList())
            .asUnmodifiableView(),
        null,
        Uint16List.fromList(units).asUnmodifiableView(),
        compactOffsets.asUnmodifiableView());
  }
  SuggestColumn._(
      this._strings,
      this._displayOffsets,
      this._displayLengths,
      this._slugOffsets,
      this._slugLengths,
      this.priors,
      this.collationRanks,
      this.nationalityIndexes,
      this._compacts,
      this._compactOffsets);

  final Uint8List _strings;
  final Uint32List _displayOffsets;
  final Uint8List _displayLengths;
  final Uint32List? _slugOffsets;
  final Uint8List? _slugLengths;
  final Uint16List priors;
  final Uint16List collationRanks;
  final Uint8List? nationalityIndexes;
  final Uint16List _compacts;
  final Uint32List _compactOffsets;

  int get length => priors.length;
  Uint16List get compactPool => _compacts;
  int compactStart(int index) => _compactOffsets[index];
  int compactEnd(int index) => _compactOffsets[index + 1];
  String display(int index) =>
      _text(_displayOffsets[index], _displayLengths[index]);
  String? slug(int index) => _slugOffsets == null
      ? null
      : _text(_slugOffsets[index], _slugLengths![index]);
  Uint16List compactCodeUnits(int index) => Uint16List.sublistView(
          _compacts, _compactOffsets[index], _compactOffsets[index + 1])
      .asUnmodifiableView();
  String _text(int offset, int length) =>
      utf8.decode(Uint8List.sublistView(_strings, offset, offset + length));

  int _compareCompacts(int a, int b) {
    var left = _compactOffsets[a];
    var right = _compactOffsets[b];
    final leftEnd = _compactOffsets[a + 1];
    final rightEnd = _compactOffsets[b + 1];
    while (left < leftEnd && right < rightEnd) {
      final order = _compacts[left++].compareTo(_compacts[right++]);
      if (order != 0) return order;
    }
    final order = (leftEnd - left).compareTo(rightEnd - right);
    return order == 0 ? a.compareTo(b) : order;
  }
}

class SuggestPoolRow {
  const SuggestPoolRow(
      {required this.display,
      required this.compact,
      required this.collationRank,
      this.prior = 1,
      this.slug = ''});
  final String display, compact, slug;
  final int prior, collationRank;
}

/// Validates PKD1 layout and, optionally, the pinned catalog version in its header.
/// The content hash identifies canonical tuple JSON, not the file's bytes.
SuggestDictionary decodePkd1(Uint8List input, {String? expectedContentHash}) {
  if (input.length < 36) throw const FormatException('Truncated PKD1 header');
  final bytes = input.asUnmodifiableView();
  final data = ByteData.sublistView(bytes);
  if (ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != 'PKD1' ||
      data.getUint16(4, Endian.little) != 1) {
    throw const FormatException('Unsupported dictionary format');
  }
  final sectionCount = data.getUint16(6, Endian.little);
  if (sectionCount != _sectionOrder.length) {
    throw const FormatException('Invalid PKD1 section count');
  }
  final headerEnd = 36 + sectionCount * 12;
  if (headerEnd > bytes.length) {
    throw const FormatException('Truncated section table');
  }
  final hash = bytes
      .sublist(8, 24)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  if (expectedContentHash != null &&
      hash != expectedContentHash.toLowerCase()) {
    throw const FormatException('Unexpected catalog version');
  }
  final counts = [
    for (var i = 0; i < 3; i++) data.getUint32(24 + i * 4, Endian.little)
  ];
  if (counts.any((count) => count > 65535)) {
    throw const FormatException('Dictionary row limit exceeded');
  }
  final sections = <String, Uint8List>{};
  final ranges = <({int offset, int end})>[];
  for (var i = 0; i < sectionCount; i++) {
    final position = 36 + i * 12;
    final tag = ascii.decode(bytes.sublist(position, position + 4));
    if (tag != _sectionOrder[i]) {
      throw const FormatException('Unexpected PKD1 section tag or order');
    }
    final offset = data.getUint32(position + 4, Endian.little);
    final length = data.getUint32(position + 8, Endian.little);
    if (sections.containsKey(tag) ||
        offset % 4 != 0 ||
        offset < headerEnd ||
        offset + length > bytes.length) {
      throw const FormatException('Invalid dictionary section');
    }
    sections[tag] = Uint8List.sublistView(bytes, offset, offset + length)
        .asUnmodifiableView();
    if (length > 0) ranges.add((offset: offset, end: offset + length));
  }
  ranges.sort((a, b) => a.offset.compareTo(b.offset));
  for (var i = 1; i < ranges.length; i++) {
    if (ranges[i].offset < ranges[i - 1].end) {
      throw const FormatException('Overlapping dictionary sections');
    }
  }
  Uint8List section(String tag, [int? length]) {
    final value = sections[tag];
    if (value == null || (length != null && value.length != length)) {
      throw FormatException('Invalid $tag column');
    }
    return value;
  }

  Uint16List words(String tag, [int? count]) {
    final value = section(tag, count == null ? null : count * 2);
    if (value.length.isOdd) throw FormatException('Invalid $tag word column');
    if (Endian.host == Endian.little && value.offsetInBytes.isEven) {
      return Uint16List.view(
              value.buffer, value.offsetInBytes, value.length ~/ 2)
          .asUnmodifiableView();
    }
    final source = ByteData.sublistView(value);
    return Uint16List.fromList([
      for (var i = 0; i < value.length; i += 2)
        source.getUint16(i, Endian.little)
    ]).asUnmodifiableView();
  }

  final strings = section('STRS');
  if (strings.isEmpty) throw const FormatException('Empty string pool');
  final displays = [
    section('NDLN', counts[0]),
    section('SDLN', counts[1]),
    section('ADLN', counts[2])
  ];
  final slugs = [null, section('SSLN', counts[1]), section('ASLN', counts[2])];
  var cursor = 0;
  Uint32List offsets(Uint8List lengths) {
    final result = Uint32List(lengths.length);
    for (var i = 0; i < lengths.length; i++) {
      result[i] = cursor;
      cursor += lengths[i];
      if (cursor > strings.length) {
        throw const FormatException('Truncated string pool');
      }
      utf8.decode(Uint8List.sublistView(strings, result[i], cursor));
    }
    return result.asUnmodifiableView();
  }

  final displayOffsets = <Uint32List>[];
  final slugOffsets = <Uint32List?>[];
  for (var i = 0; i < 3; i++) {
    displayOffsets.add(offsets(displays[i]));
    slugOffsets.add(slugs[i] == null ? null : offsets(slugs[i]!));
  }
  final exceptionIndexes = [words('NCXI'), words('SCXI'), words('ACXI')];
  final exceptionLengths = [
    section('NCXL', exceptionIndexes[0].length),
    section('SCXL', exceptionIndexes[1].length),
    section('ACXL', exceptionIndexes[2].length)
  ];
  final exceptionOffsets = [
    for (final lengths in exceptionLengths) offsets(lengths)
  ];
  if (cursor != strings.length) {
    throw const FormatException('Unexpected string pool data');
  }
  final compactPools = <Uint16List>[];
  final compactOffsets = <Uint32List>[];
  for (var kind = 0; kind < 3; kind++) {
    final indexes = exceptionIndexes[kind];
    for (var i = 0; i < indexes.length; i++) {
      if (indexes[i] >= counts[kind] ||
          (i > 0 && indexes[i] <= indexes[i - 1])) {
        throw const FormatException('Invalid compact exception index');
      }
    }
    // UTF-16 units never outnumber the UTF-8 bytes that encode these strings.
    final capacity = displays[kind].fold<int>(0, (n, length) => n + length) +
        exceptionLengths[kind].fold<int>(0, (n, length) => n + length);
    final pool = Uint16List(capacity);
    final positions = Uint32List(counts[kind] + 1);
    var position = 0;
    var exception = 0;
    for (var row = 0; row < counts[kind]; row++) {
      positions[row] = position;
      if (exception < indexes.length && indexes[exception] == row) {
        final start = exceptionOffsets[kind][exception];
        final compact = utf8.decode(Uint8List.sublistView(
            strings, start, start + exceptionLengths[kind][exception]));
        for (final unit in compact.codeUnits) {
          pool[position++] = unit;
        }
        exception++;
      } else {
        final start = displayOffsets[kind][row];
        for (var i = start; i < start + displays[kind][row]; i++) {
          var unit = strings[i];
          if (unit > 127) {
            throw const FormatException('Missing non-ASCII compact');
          }
          if (unit >= 65 && unit <= 90) unit += 32;
          if ((unit >= 97 && unit <= 122) || (unit >= 48 && unit <= 57)) {
            pool[position++] = unit;
          }
        }
      }
    }
    positions[counts[kind]] = position;
    compactPools.add(
        Uint16List.fromList(pool.sublist(0, position)).asUnmodifiableView());
    compactOffsets.add(positions.asUnmodifiableView());
  }
  final paletteBytes = section('NATP');
  if (paletteBytes.isEmpty) {
    throw const FormatException('Missing nationality palette');
  }
  final palette = <String>[];
  cursor = 1;
  for (var i = 0; i < paletteBytes[0]; i++) {
    if (cursor >= paletteBytes.length) {
      throw const FormatException('Truncated nationality palette');
    }
    final length = paletteBytes[cursor++];
    if (cursor + length > paletteBytes.length) {
      throw const FormatException('Truncated nationality');
    }
    palette.add(utf8.decode(paletteBytes.sublist(cursor, cursor + length)));
    cursor += length;
  }
  if (cursor != paletteBytes.length) {
    throw const FormatException('Unexpected nationality data');
  }
  final nationalities = section('SNAT', counts[1]);
  if (nationalities.any((i) => i >= palette.length)) {
    throw const FormatException('Invalid nationality index');
  }
  final columns = <SuggestColumn>[];
  for (var i = 0; i < 3; i++) {
    final prefix = ['N', 'S', 'A'][i];
    final collation = words('${prefix}COL', counts[i]);
    for (final rank in collation) {
      // The reference encoder gives collator-equivalent displays the same rank.
      if (rank >= counts[i]) {
        throw const FormatException('Invalid collation rank');
      }
    }
    columns.add(SuggestColumn._(
        strings,
        displayOffsets[i],
        displays[i],
        slugOffsets[i],
        slugs[i],
        words('${prefix}PRI', counts[i]),
        collation,
        i == 1 ? nationalities : null,
        compactPools[i],
        compactOffsets[i]));
  }
  final sorted = List<int>.generate(counts[0], (i) => i);
  sorted.sort(columns[0]._compareCompacts);
  return SuggestDictionary._(
      hash,
      columns[0],
      columns[1],
      columns[2],
      List.unmodifiable(palette),
      Uint16List.fromList(sorted).asUnmodifiableView());
}
