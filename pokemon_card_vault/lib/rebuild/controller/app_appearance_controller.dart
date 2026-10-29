import 'package:flutter/foundation.dart';
import '../model/app_appearance.dart';
import '../service/app_appearance_service.dart';

class AppAppearanceController extends ChangeNotifier {
  AppAppearanceController({AppAppearanceService? service})
      : _service = service ?? AppAppearanceService();
  final AppAppearanceService _service;
  AppAppearance appearance = AppAppearance.defaultTheme;
  String? feedback;
  bool _disposed = false, _started = false;
  int _revision = 0;
  Future<void> _writes = Future.value();

  Future<void> load() async {
    if (_disposed || _started) return;
    _started = true;
    final revision = _revision;
    try {
      final saved = await _service.load();
      if (_disposed || revision != _revision) return;
      appearance = saved;
      notifyListeners();
    } catch (_) {
      // Appearance storage must never block login or browsing.
    }
  }

  Future<void> select(AppAppearance value) {
    if (_disposed) return Future.value();
    final revision = ++_revision;
    appearance = value;
    feedback = null;
    notifyListeners();
    _writes = _writes.then((_) => _service.save(value)).catchError((Object _) {
      if (_disposed || revision != _revision) return;
      feedback = 'Tema applicato. Non è stato possibile salvare la preferenza.';
      notifyListeners();
    });
    return _writes;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
