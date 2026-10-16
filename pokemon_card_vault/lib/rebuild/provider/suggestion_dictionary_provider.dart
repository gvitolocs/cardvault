import 'package:flutter/services.dart';

class SuggestionDictionaryProvider {
  SuggestionDictionaryProvider({AssetBundle? bundle})
      : _bundle = bundle ?? rootBundle;
  final AssetBundle _bundle;
  Future<Uint8List> readBundled() async {
    final data = await _bundle.load('assets/suggest/dictionary.pkd1');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}
