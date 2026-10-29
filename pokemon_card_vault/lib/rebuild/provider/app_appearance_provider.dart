import 'package:shared_preferences/shared_preferences.dart';

/// One device-wide display setting, unrelated to authentication or inventory.
class AppAppearanceProvider {
  static const key = 'rebuild.appAppearance.v1';
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(key);
  Future<void> write(String id) async {
    final saved =
        await (await SharedPreferences.getInstance()).setString(key, id);
    if (!saved) throw StateError('Theme preference was not saved');
  }
}
