import 'dart:async';

class WalletSignInCoordinator {
  static bool _signing = false;

  static bool get isSigning => _signing;

  static Future<T> run<T>(Future<T> Function() action) async {
    if (_signing) {
      throw StateError('A wallet sign-in is already in progress.');
    }
    _signing = true;
    try {
      return await action();
    } finally {
      _signing = false;
    }
  }
}

class WalletBridge {
  bool get hasProvider => false;

  bool get isMobile => false;

  bool openMetaMaskDapp() => false;

  bool openMetaMaskDappUrl(String url) => false;

  Future<String?> currentAccount() async => null;

  void onAccountsChanged(void Function(String? address) callback) {}

  void onChainChanged(void Function() callback) {}

  Future<String?> requestAccount() async => null;

  Future<String> signMessage({
    required String address,
    required String message,
  }) {
    throw UnsupportedError('Browser wallet is not available on this platform.');
  }

  Future<void> addNetwork() async {}

  Future<void> switchNetwork() async {}

  Future<String> sendTransaction({
    required String from,
    required String to,
    required BigInt valueWei,
  }) {
    throw UnsupportedError('Browser wallet is not available on this platform.');
  }

  Future<String> sendDataTransaction({
    required String from,
    required String to,
    required String dataHex,
    BigInt? valueWei,
    int? nonce,
  }) {
    throw UnsupportedError('Browser wallet is not available on this platform.');
  }

  Future<String> sendExternalTransaction({
    required String from,
    required String to,
    required BigInt valueWei,
    required String chainIdHex,
  }) {
    throw UnsupportedError('Browser wallet is not available on this platform.');
  }

  Future<String> sendExternalTokenTransfer({
    required String from,
    required String tokenAddress,
    required String to,
    required BigInt amountUnits,
    required String chainIdHex,
  }) {
    throw UnsupportedError('Browser wallet is not available on this platform.');
  }

  Future<Map<String, String>> signInWithGoogle() {
    throw UnsupportedError('Google sign-in is only available in the browser.');
  }

  Future<void> signOut() async {}
}

WalletBridge createWalletBridge() => WalletBridge();
