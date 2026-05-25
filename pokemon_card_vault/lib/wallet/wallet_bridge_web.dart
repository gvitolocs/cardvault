import 'dart:async';
import 'dart:js_interop';

@JS('window.pokoinWallet.hasProvider')
external bool _hasProvider();

@JS('window.pokoinWallet.isMobile')
external bool _isMobile();

@JS('window.pokoinWallet.openMetaMaskDapp')
external bool _openMetaMaskDapp();

@JS('window.pokoinWallet.openMetaMaskDappUrl')
external bool _openMetaMaskDappUrl(JSString url);

@JS('window.pokoinWallet.requestAccounts')
external JSPromise<JSArray<JSString>> _requestAccounts();

@JS('window.pokoinWallet.getAccounts')
external JSPromise<JSArray<JSString>> _getAccounts();

@JS('window.pokoinWallet.onAccountsChanged')
external void _onAccountsChanged(JSFunction callback);

@JS('window.pokoinWallet.onChainChanged')
external void _onChainChanged(JSFunction callback);

@JS('window.pokoinWallet.signMessage')
external JSPromise<JSString> _signMessage(JSString address, JSString message);

@JS('window.pokoinWallet.addNetwork')
external JSPromise<JSAny?> _addNetwork();

@JS('window.pokoinWallet.switchNetwork')
external JSPromise<JSAny?> _switchNetwork();

@JS('window.pokoinWallet.sendTransaction')
external JSPromise<JSString> _sendTransaction(
  JSString from,
  JSString to,
  JSString valueHex,
);

@JS('window.pokoinWallet.sendDataTransaction')
external JSPromise<JSString> _sendDataTransaction(
  JSString from,
  JSString to,
  JSString valueHex,
  JSString dataHex,
  JSString nonceHex,
);

@JS('window.pokoinWallet.sendExternalTransaction')
external JSPromise<JSString> _sendExternalTransaction(
  JSString from,
  JSString to,
  JSString valueHex,
  JSString chainIdHex,
);

@JS('window.pokoinWallet.sendExternalTokenTransfer')
external JSPromise<JSString> _sendExternalTokenTransfer(
  JSString from,
  JSString tokenAddress,
  JSString to,
  JSString amountHex,
  JSString chainIdHex,
);

@JS('window.pokoinAuth.signInWithGoogle')
external JSPromise<JSObject> _signInWithGoogle();

@JS('window.pokoinAuth.signOut')
external JSPromise<JSAny?> _signOut();

@JS()
@staticInterop
class _GoogleUserPayload {}

extension _GoogleUserPayloadExtension on _GoogleUserPayload {
  external JSString get uid;
  external JSString get email;
  external JSString get displayName;
  external JSString get idToken;
}

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
  bool get hasProvider {
    try {
      return _hasProvider();
    } catch (_) {
      return false;
    }
  }

  bool get isMobile {
    try {
      return _isMobile();
    } catch (_) {
      return false;
    }
  }

  bool openMetaMaskDapp() {
    try {
      return _openMetaMaskDapp();
    } catch (_) {
      return false;
    }
  }

  bool openMetaMaskDappUrl(String url) {
    try {
      return _openMetaMaskDappUrl(url.toJS);
    } catch (_) {
      return false;
    }
  }

  Future<String?> currentAccount() async {
    final accounts = await _getAccounts().toDart;
    if (accounts.length == 0) {
      return null;
    }
    return accounts[0].toDart;
  }

  void onAccountsChanged(void Function(String? address) callback) {
    _onAccountsChanged(
      ((JSArray<JSString> accounts) {
        callback(accounts.length == 0 ? null : accounts[0].toDart);
      }).toJS,
    );
  }

  void onChainChanged(void Function() callback) {
    _onChainChanged((() => callback()).toJS);
  }

  Future<String?> requestAccount() async {
    final accounts = await _requestAccounts().toDart;
    if (accounts.length == 0) {
      return null;
    }
    return accounts[0].toDart;
  }

  Future<void> addNetwork() async {
    await _addNetwork().toDart;
  }

  Future<String> signMessage({
    required String address,
    required String message,
  }) async {
    final signature = await _signMessage(address.toJS, message.toJS).toDart;
    return signature.toDart;
  }

  Future<void> switchNetwork() async {
    await _switchNetwork().toDart;
  }

  Future<String> sendTransaction({
    required String from,
    required String to,
    required BigInt valueWei,
  }) async {
    final hash = await _sendTransaction(
      from.toJS,
      to.toJS,
      '0x${valueWei.toRadixString(16)}'.toJS,
    ).toDart;
    return hash.toDart;
  }

  Future<String> sendDataTransaction({
    required String from,
    required String to,
    required String dataHex,
    BigInt? valueWei,
    int? nonce,
  }) async {
    final hash = await _sendDataTransaction(
      from.toJS,
      to.toJS,
      '0x${(valueWei ?? BigInt.zero).toRadixString(16)}'.toJS,
      dataHex.toJS,
      nonce == null ? ''.toJS : '0x${nonce.toRadixString(16)}'.toJS,
    ).toDart;
    return hash.toDart;
  }

  Future<String> sendExternalTransaction({
    required String from,
    required String to,
    required BigInt valueWei,
    required String chainIdHex,
  }) async {
    final hash = await _sendExternalTransaction(
      from.toJS,
      to.toJS,
      '0x${valueWei.toRadixString(16)}'.toJS,
      chainIdHex.toJS,
    ).toDart;
    return hash.toDart;
  }

  Future<String> sendExternalTokenTransfer({
    required String from,
    required String tokenAddress,
    required String to,
    required BigInt amountUnits,
    required String chainIdHex,
  }) async {
    final hash = await _sendExternalTokenTransfer(
      from.toJS,
      tokenAddress.toJS,
      to.toJS,
      '0x${amountUnits.toRadixString(16)}'.toJS,
      chainIdHex.toJS,
    ).toDart;
    return hash.toDart;
  }

  Future<Map<String, String>> signInWithGoogle() async {
    final payload = (await _signInWithGoogle().toDart) as _GoogleUserPayload;
    return <String, String>{
      'uid': payload.uid.toDart,
      'email': payload.email.toDart,
      'displayName': payload.displayName.toDart,
      'idToken': payload.idToken.toDart,
    };
  }

  Future<void> signOut() async {
    await _signOut().toDart;
  }
}

WalletBridge createWalletBridge() => WalletBridge();
