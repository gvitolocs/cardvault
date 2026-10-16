import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/rebuild/model/account.dart';
import 'package:pokoin/rebuild/provider/account_provider.dart';
import 'package:pokoin/rebuild/service/account_service.dart';

class FakeAccountProvider extends AccountProvider {
  FakeAccountProvider({this.guest = false, this.user});
  bool guest;
  AccountUser? user;
  Object? initializationError, loginError;
  Completer<void>? bootstrap;
  final changes = StreamController<AccountUser?>.broadcast(sync: true);
  String? submittedEmail, submittedPassword, resetEmail;
  int loginCalls = 0;
  int googleCalls = 0;
  bool googleCancelled = false;
  Completer<void>? googlePending;
  @override
  Future<bool> signInWithGoogle() async {
    ++googleCalls;
    if (googlePending != null) await googlePending!.future;
    if (googleCancelled) return false;
    if (loginError != null) throw loginError!;
    emit(const AccountUser(
        id: 'alice', email: 'alice@example.test', displayName: 'Alice'));
    return true;
  }

  @override
  Future<void> initialize() async {
    if (bootstrap != null) await bootstrap!.future;
    if (initializationError != null) throw initializationError!;
  }

  @override
  Future<bool> readGuestMode() async => guest;
  @override
  Future<void> saveGuestMode(bool enabled) async {
    guest = enabled;
  }

  @override
  Stream<AccountUser?> watchUser() => Stream<AccountUser?>.multi((sink) {
        sink.add(user);
        final subscription = changes.stream.listen(sink.add);
        sink.onCancel = subscription.cancel;
      });
  void emit(AccountUser? value) {
    user = value;
    changes.add(value);
  }

  @override
  Future<void> signIn(String email, String password) async {
    ++loginCalls;
    submittedEmail = email;
    submittedPassword = password;
    if (loginError != null) throw loginError!;
    emit(AccountUser(id: 'alice', email: email, displayName: 'Alice'));
  }

  @override
  Future<void> signOut() async => emit(null);
  @override
  Future<void> resetPassword(String email) async {
    resetEmail = email;
  }

  Future<void> close() => changes.close();
}

AccountService guestAccountService() {
  final provider = FakeAccountProvider(guest: true);
  addTearDown(provider.close);
  return AccountService(provider: provider);
}
