import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../model/listing_draft.dart';

abstract class ScanClipboardProvider {
  Future<List<ListingDraft>> read(String? uid);
  Future<void> write(String? uid, List<ListingDraft> drafts);
}

/// Separate guest/account snapshots. A failed read is never treated as empty.
class HiveScanClipboardProvider implements ScanClipboardProvider {
  HiveScanClipboardProvider({Future<void> Function()? initialize})
      : _initialize = initialize ?? _initializeHive;
  final Future<void> Function() _initialize;
  static Future<void>? _initializing;
  static Future<void> _initializeHive() =>
      _initializing ??= Hive.initFlutter().catchError((Object error) {
        _initializing = null;
        throw error;
      });
  String boxName(String? uid) => uid == null
      ? 'rebuild_scan_clipboard_v1_guest'
      : 'rebuild_scan_clipboard_v1_${sha256.convert(utf8.encode(uid))}';
  Future<Box<String>> _box(String? uid) async {
    await _initialize();
    final name = boxName(uid);
    return Hive.isBoxOpen(name)
        ? Hive.box<String>(name)
        : Hive.openBox<String>(name);
  }

  @override
  Future<List<ListingDraft>> read(String? uid) async {
    final raw = (await _box(uid)).get('snapshot');
    if (raw == null) return [];
    final json = jsonDecode(raw) as Map;
    if (json['version'] != 1 || json['items'] is! List) {
      throw const FormatException('Invalid clipboard snapshot');
    }
    return [
      for (final item in json['items'] as List)
        ListingDraft.fromJson(Map<String, dynamic>.from(item as Map))
    ];
  }

  @override
  Future<void> write(String? uid, List<ListingDraft> drafts) async {
    final box = await _box(uid);
    await box.put(
        'snapshot',
        jsonEncode({
          'version': 1,
          'items': [for (final draft in drafts) draft.toJson()]
        }));
    await box.flush();
  }
}
