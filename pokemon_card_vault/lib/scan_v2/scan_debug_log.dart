import 'dart:developer' as developer;
import 'dart:io';

/// Internal scan log for later debugging. Not shown in the UI.
class ScanDebugLog {
  ScanDebugLog._();

  static const name = 'pokoin.scan';
  static const maxBytes = 512 * 1024;

  static File? file;
  static IOSink? _sink;

  static Future<void> attach(Directory dir) async {
    final next = File('${dir.path}/scan_debug.log');
    try {
      if (next.existsSync() && next.lengthSync() > maxBytes) {
        final data = next.readAsBytesSync();
        next.writeAsBytesSync(data.sublist(data.length - maxBytes ~/ 2));
      }
      file = next;
      await _sink?.flush();
      await _sink?.close();
      _sink = next.openWrite(mode: FileMode.append);
      i('log attached path=${next.path}');
    } catch (error) {
      developer.log('log attach failed: $error', name: name);
    }
  }

  static void i(String message) {
    developer.log(message, name: name);
    final line = '${DateTime.now().toUtc().toIso8601String()} $message\n';
    try {
      _sink?.write(line);
    } catch (_) {}
  }

  static Future<void> flush() async {
    try {
      await _sink?.flush();
    } catch (_) {}
  }
}
