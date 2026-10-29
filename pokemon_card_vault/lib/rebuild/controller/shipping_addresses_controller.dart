import 'package:flutter/foundation.dart';
import '../model/shipping_address.dart';
import '../service/shipping_addresses_service.dart';

class ShippingAddressesController extends ChangeNotifier {
  ShippingAddressesController({ShippingAddressesService? service})
      : _service = service ?? ShippingAddressesService();
  final ShippingAddressesService _service;
  String? _uid, error;
  int _epoch = 0;
  bool _disposed = false, loading = false, busy = false, loaded = false;
  List<ShippingAddress> _items = [];
  List<ShippingAddress> get items => List.unmodifiable(_items);
  bool get authenticated => _uid != null;
  int get scopeRevision => _epoch;
  void setUser(String? uid) {
    if (_uid == uid) return;
    _uid = uid;
    ++_epoch;
    _items = [];
    error = null;
    loading = busy = loaded = false;
    if (!_disposed) notifyListeners();
  }

  bool _current(int epoch) => !_disposed && epoch == _epoch;
  Future<void> load() async {
    final uid = _uid, epoch = _epoch;
    if (uid == null || loading || busy || _disposed) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final items = await _service.read(uid);
      if (_current(epoch)) {
        _items = items;
        loaded = true;
      }
    } catch (_) {
      if (_current(epoch)) {
        error = 'Impossibile recuperare gli indirizzi. Riprova.';
      }
    } finally {
      if (_current(epoch)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> _change(Future<void> Function(String) operation) async {
    final uid = _uid, epoch = _epoch;
    if (uid == null || loading || busy || !loaded || _disposed) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await operation(uid);
      if (!_current(epoch)) return false;
      final items = await _service.read(uid);
      if (!_current(epoch)) return false;
      _items = items;
      return true;
    } catch (e) {
      if (_current(epoch) && e is! FormatException) loaded = false;
      if (_current(epoch)) {
        error = e is FormatException
            ? e.message
            : 'Modifica non confermata. Ricarica gli indirizzi prima di riprovare.';
      }
      return false;
    } finally {
      if (_current(epoch)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<bool> save(ShippingAddress address) =>
      _change((uid) => _service.save(uid, address));
  Future<bool> setDefault(ShippingAddress address) => save(address.asDefault());
  Future<bool> remove(String id) => _change((uid) => _service.remove(uid, id));
  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    _items = [];
    super.dispose();
  }
}
