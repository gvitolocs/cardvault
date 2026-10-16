import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/rebuild/provider/expansion_catalog_provider.dart';

class _CatalogBundle extends CachingAssetBundle {
  _CatalogBundle(this.source);
  final String source;
  final keys = <String>[];

  @override
  Future<ByteData> load(String key) async {
    keys.add(key);
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(source)));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalog provider reads the configured asset and converts numeric order',
      () async {
    final bundle = _CatalogBundle('{"Set storico": 9, "Set nuovo": 2.0}');
    final provider = ExpansionCatalogProvider(bundle: bundle);
    expect(await provider.loadOrder(), {'Set storico': 9, 'Set nuovo': 2});
    expect(bundle.keys, ['assets/data/marketplace-expansion-order.json']);
  });

  test('catalog errors reach the caller for its empty-order fallback',
      () async {
    final provider =
        ExpansionCatalogProvider(bundle: _CatalogBundle('invalid'));
    await expectLater(provider.loadOrder(), throwsFormatException);
  });

  test('default catalog provider loads the actual bundled catalog', () async {
    final order = await ExpansionCatalogProvider().loadOrder();
    expect(order, isNotEmpty);
  });
}
