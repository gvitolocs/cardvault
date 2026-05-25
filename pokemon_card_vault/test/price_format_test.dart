import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/utils/price_format.dart';

void main() {
  group('formatPknAmount', () {
    test('omits decimal cents for whole PKN amounts without suffix', () {
      expect(formatPknAmount(50326), '50326');
      expect(formatPknAmount(50326.00), '50326');
    });

    test('keeps meaningful fractional PKN amounts without suffix', () {
      expect(formatPknAmount(50326.5), '50326.5');
      expect(formatPknAmount(50326.55), '50326.55');
    });
  });

  group('formatPkn', () {
    test('omits decimal cents for whole PKN amounts', () {
      expect(formatPkn(14328), '14328 PKN');
      expect(formatPkn(14328.00), '14328 PKN');
      expect(formatPkn(2000, decimals: 0), '2000 PKN');
    });

    test('keeps meaningful fractional PKN amounts', () {
      expect(formatPkn(14328.5), '14328.5 PKN');
      expect(formatPkn(14328.55), '14328.55 PKN');
    });
  });
}
