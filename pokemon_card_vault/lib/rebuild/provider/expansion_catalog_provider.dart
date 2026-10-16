import 'dart:convert';

import 'package:flutter/services.dart';

/// DAO per l'ordine delle espansioni nel catalogo incluso nell'app.
class ExpansionCatalogProvider {
  ExpansionCatalogProvider({AssetBundle? bundle})
      : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

  Future<Map<String, int>> loadOrder() async {
    final source = await _bundle
        .loadString('assets/data/marketplace-expansion-order.json');
    final json = jsonDecode(source) as Map<String, dynamic>;
    return json.map((key, value) => MapEntry(key, (value as num).toInt()));
  }
}
