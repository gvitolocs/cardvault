import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/scan_v2/scan_assets.dart';

void main() {
  test('runtime scan pack reports only the selected gallery as missing', () {
    final status = ScanAssetStore.inspectRoot(
      Directory(r'C:\pokoin-test-assets'),
      gallery: 'japanese',
    );

    expect(status.ready, isFalse);
    expect(status.missing, contains('japanese/embeddings.bin'));
    expect(status.missing, isNot(contains('western/embeddings.bin')));
  });

  test('download paths cannot escape the scan asset root', () {
    expect(
      ScanAssetStore.isAllowedPath(
        '../private.bin',
        gallery: 'western',
      ),
      isFalse,
    );
    expect(
      ScanAssetStore.isAllowedPath(
        'western/embeddings.bin',
        gallery: 'western',
      ),
      isTrue,
    );
  });
}
