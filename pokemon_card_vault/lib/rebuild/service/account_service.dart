import '../model/account.dart';
import '../provider/account_provider.dart';

class AccountService {
  AccountService({AccountProvider? provider})
      : _provider = provider ?? AccountProvider();
  final AccountProvider _provider;
  bool _guest = false;
  int _choiceVersion = 0;

  Stream<AccountSession> watchSession() async* {
    final version = _choiceVersion;
    try {
      final storedGuest = await _provider.readGuestMode();
      if (version == _choiceVersion) _guest = storedGuest;
    } catch (_) {/* Il login Firebase resta utilizzabile senza preferenze. */}
    if (_guest) yield const AccountSession(status: AccountStatus.guest);
    try {
      await _provider.initialize();
    } catch (_) {
      if (_guest) return;
      rethrow;
    }
    // Il primo evento Firebase viene emesso dopo il ripristino della sessione.
    yield* _provider.watchUser().map((user) => AccountSession(
        user: user,
        status: user != null
            ? AccountStatus.authenticated
            : _guest
                ? AccountStatus.guest
                : AccountStatus.signedOut));
  }

  Future<void> signIn(String email, String password) async {
    final normalized = _email(email);
    if (password.isEmpty) throw const AccountFailure('missing-password');
    await _provider.signIn(normalized, password);
    await _rememberAuthenticated();
  }

  Future<bool> signInWithGoogle() async {
    if (!await _provider.signInWithGoogle()) return false;
    await _rememberAuthenticated();
    return true;
  }

  Future<void> _rememberAuthenticated() async {
    ++_choiceVersion;
    _guest = false;
    // La persistenza Firebase determina l'accesso; il flag ospite è secondario.
    try {
      await _provider.saveGuestMode(false);
    } catch (_) {/* sessione valida */}
  }

  Future<void> continueAsGuest() async {
    ++_choiceVersion;
    _guest = true;
    try {
      await _provider.saveGuestMode(true);
    } catch (_) {/* ospite per questa apertura */}
  }

  Future<void> signOut() async {
    ++_choiceVersion;
    _guest = false;
    try {
      await _provider.saveGuestMode(false);
    } catch (_) {/* Firebase deve comunque uscire. */}
    await _provider.signOut();
  }

  Future<void> resetPassword(String email) async {
    try {
      await _provider.resetPassword(_email(email));
    } on AccountFailure catch (error) {
      if (error.code != 'user-not-found') rethrow;
    }
  }

  String _email(String email) {
    final value = email.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
      throw const AccountFailure('invalid-email');
    }
    return value;
  }
}
