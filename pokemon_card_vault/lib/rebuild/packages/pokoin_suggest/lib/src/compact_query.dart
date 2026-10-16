import 'dart:collection';

import 'package:unorm_dart/unorm_dart.dart' as unorm;

final _compactMemo = LinkedHashMap<String, String>();
final _asciiOnly = RegExp(r'^[\x00-\x7f]*$');
final _asciiNonAlphanumeric = RegExp(r'[^a-z0-9]+');
final _delta = RegExp('[δΔ]');
final _latinCombining = RegExp(r'[\u0300-\u036f]');
final _nonLetterOrNumber = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Matches the web's NFKC -> strip delta -> NFD -> strip Latin marks -> NFC.
/// Kana voicing marks stay intact. ASCII never enters Unicode normalization.
String compactQuery(String value) {
  final cached = _compactMemo[value];
  if (cached != null) {
    return cached;
  }
  final compact = _asciiOnly.hasMatch(value)
      ? value.toLowerCase().replaceAll(_asciiNonAlphanumeric, '')
      : unorm
          .nfc(unorm
              .nfd(unorm.nfkc(value).replaceAll(_delta, ''))
              .replaceAll(_latinCombining, ''))
          .toLowerCase()
          .replaceAll(_nonLetterOrNumber, '');
  if (_compactMemo.length >= 20000) {
    _compactMemo.clear();
  }
  _compactMemo[value] = compact;
  return compact;
}

bool suggestLiveReady(String query) => compactQuery(query).length >= 3;
