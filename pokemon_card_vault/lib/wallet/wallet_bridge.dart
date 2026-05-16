import 'dart:async';

class WalletBridge {
  bool get hasProvider => false;

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

  Future<Map<String, String>> signInWithGoogle() {
    throw UnsupportedError('Google sign-in is only available in the browser.');
  }

  Future<void> signOut() async {}
}

WalletBridge createWalletBridge() => WalletBridge();
