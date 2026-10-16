import 'dart:async';
import 'package:flutter/foundation.dart';
import '../model/account.dart';
import '../service/account_service.dart';

class AccountController extends ChangeNotifier {
  AccountController({AccountService? service})
      : _service = service ?? AccountService();
  final AccountService _service;
  StreamSubscription<AccountSession>? _subscription;
  final _sessions = StreamController<AccountSession>.broadcast(sync: true);
  AccountSession session =
      const AccountSession(status: AccountStatus.restoring);
  bool busy = false, _started = false, _disposed = false, _active = false;
  int _generation = 0;
  String? error, message;

  void initialize() {
    if (_started || _disposed) return;
    _started = true;
    _active = true;
    final request = ++_generation;
    _subscription = _service.watchSession().listen((value) {
      if (request == _generation) _setSession(value);
    }, onError: (Object failure, StackTrace stack) {
      if (_disposed || request != _generation) return;
      error =
          'Impossibile ripristinare l’account. Puoi riprovare o continuare come ospite.';
      _setSession(const AccountSession(status: AccountStatus.unavailable));
    }, onDone: () {
      if (request == _generation) _active = false;
    });
  }

  /// Replay dello stato corrente: Cardex usa esattamente la sessione del gate.
  Stream<String?> watchUserId() => Stream<String?>.multi((sink) {
        sink.add(session.user?.id);
        final subscription =
            _sessions.stream.listen((value) => sink.add(value.user?.id));
        sink.onCancel = subscription.cancel;
      }).distinct();

  void _setSession(AccountSession value) {
    if (_disposed) return;
    session = value;
    _sessions.add(value);
    notifyListeners();
  }

  Future<bool> signIn(String email, String password) => _run(() async {
        // Dopo un errore di bootstrap riapri anche lo stream Firebase.
        if (!_active || session.status == AccountStatus.unavailable) {
          retryInitialization();
        }
        await _service.signIn(email, password);
      });
  Future<bool> continueAsGuest() => _run(() async {
        await _service.continueAsGuest();
        _setSession(const AccountSession(status: AccountStatus.guest));
      });
  Future<bool> signInWithGoogle() async {
    var authenticated = false;
    final completed = await _run(() async {
      if (!_active || session.status == AccountStatus.unavailable) {
        retryInitialization();
      }
      authenticated = await _service.signInWithGoogle();
    });
    return completed && authenticated;
  }

  Future<bool> signOut() => _run(() async {
        await _service.signOut();
        _setSession(const AccountSession(status: AccountStatus.signedOut));
      });
  Future<bool> resetPassword(String email) => _run(() async {
        await _service.resetPassword(email);
        message =
            'Se l’indirizzo è associato a un account, riceverai un’email per reimpostare la password.';
      });

  void retryInitialization() {
    if (_disposed) return;
    unawaited(_subscription?.cancel());
    _started = false;
    error = null;
    _setSession(const AccountSession(status: AccountStatus.restoring));
    initialize();
  }

  void clearFeedback() {
    error = message = null;
  }

  Future<bool> _run(Future<void> Function() action) async {
    if (busy || _disposed) return false;
    busy = true;
    clearFeedback();
    notifyListeners();
    try {
      await action();
      return true;
    } catch (failure) {
      if (!_disposed) {
        error = failure is AccountFailure
            ? failure.message
            : 'Operazione non riuscita. Riprova oppure continua come ospite.';
      }
      return false;
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    unawaited(_sessions.close());
    super.dispose();
  }
}
