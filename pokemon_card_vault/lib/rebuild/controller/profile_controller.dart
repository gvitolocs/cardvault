import 'dart:async';
import 'package:flutter/foundation.dart';
import '../model/account.dart';
import '../service/profile_service.dart';
import 'account_controller.dart';
import 'shipping_addresses_controller.dart';

class ProfileController extends ChangeNotifier {
  ProfileController(
      {required this.account,
      ProfileService? service,
      ShippingAddressesController? addressesController})
      : _service = service ?? ProfileService(),
        addresses = addressesController ?? ShippingAddressesController() {
    account.addListener(_sessionChanged);
    addresses.setUser(account.session.user?.id);
  }
  final ShippingAddressesController addresses;
  final AccountController account;
  final ProfileService _service;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  String? _uid;
  int _generation = 0;
  bool _started = false, _disposed = false, saving = false;
  AccountProfile? profile;
  AccountBalance? balance;
  List<AccountOrder>? orders;
  List<String>? favorites;
  final Set<String> errors = {};
  String? feedback;

  void start() {
    _started = true;
    _sessionChanged();
  }

  void _sessionChanged() {
    final uid = account.session.user?.id;
    addresses.setUser(uid);
    if (!_started || uid == _uid) return;
    _uid = uid;
    _bind();
  }

  void retry() => _bind();
  void _bind() {
    final request = ++_generation;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    profile = null;
    balance = null;
    orders = null;
    favorites = null;
    errors.clear();
    feedback = null;
    final uid = _uid;
    if (uid != null) {
      void listen<T>(String key, Stream<T> stream, void Function(T) update) {
        _subscriptions.add(stream.listen((value) {
          if (_disposed || request != _generation) return;
          update(value);
          errors.remove(key);
          notifyListeners();
        }, onError: (Object error, StackTrace stack) {
          if (_disposed || request != _generation) return;
          errors.add(key);
          notifyListeners();
        }));
      }

      listen('profile', _service.watchProfile(uid), (value) => profile = value);
      listen('balance', _service.watchBalance(uid), (value) => balance = value);
      listen('orders', _service.watchOrders(uid),
          (value) => orders = List.unmodifiable(value));
      listen('favorites', _service.watchFavorites(uid),
          (value) => favorites = List.unmodifiable(value));
    }
    if (!_disposed) notifyListeners();
  }

  Future<bool> saveName(String name) async {
    final uid = _uid;
    if (uid == null || saving || _disposed) return false;
    final request = _generation;
    saving = true;
    feedback = null;
    notifyListeners();
    try {
      await _service.updateDisplayName(uid, name);
      if (_disposed || request != _generation) return false;
      feedback = 'Nome aggiornato.';
      return true;
    } catch (failure) {
      if (!_disposed && request == _generation) {
        feedback = failure is AccountFailure
            ? failure.message
            : 'Impossibile aggiornare il nome.';
      }
      return false;
    } finally {
      if (!_disposed) {
        saving = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    addresses.dispose();
    account.removeListener(_sessionChanged);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}
