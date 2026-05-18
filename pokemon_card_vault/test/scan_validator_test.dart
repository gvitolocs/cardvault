import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/screens/scan_screen.dart';

void main() {
  test('validator display prefers higher stake duplicate identity', () {
    const lowStake = ValidatorInfo(
      peerId: 'peer-low',
      validator: 'validator-key',
      stake: 10,
      authorized: true,
      local: false,
      connected: true,
    );
    const highStake = ValidatorInfo(
      peerId: 'peer-high',
      validator: 'validator-key',
      stake: 100,
      authorized: true,
      local: false,
      connected: true,
    );

    expect(highStake.isBetterDisplayThan(lowStake), isTrue);
    expect(lowStake.isBetterDisplayThan(highStake), isFalse);
  });
}
