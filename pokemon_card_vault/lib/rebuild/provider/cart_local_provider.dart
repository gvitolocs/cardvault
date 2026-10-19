import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../model/cart_item.dart';
import 'cart_codec.dart';

abstract class CartLocalProvider {
  Future<CartSnapshot> read(String? uid);
  Future<void> write(String? uid, CartSnapshot snapshot);
}

/// Un solo put atomico per snapshot e modifiche pendenti. I vecchi box sono
/// letti soltanto alla prima apertura e non vengono cancellati o riscritti.
class HiveCartProvider implements CartLocalProvider {
  HiveCartProvider({Future<void> Function()? initialize})
      : _initialize = initialize ?? _initializeHive;
  final Future<void> Function() _initialize;
  static Future<void>? _initializing;
  static Future<void> _initializeHive() =>
      _initializing ??= Hive.initFlutter().catchError((Object error) {
        _initializing = null;
        throw error;
      });

  String boxName(String? uid) => uid == null
      ? 'rebuild_cart_v1_guest'
      : 'rebuild_cart_v1_user_${sha256.convert(utf8.encode(uid))}';

  Future<Box<Map>> _box(String name) async {
    await _initialize();
    return Hive.isBoxOpen(name) ? Hive.box<Map>(name) : Hive.openBox<Map>(name);
  }

  @override
  Future<CartSnapshot> read(String? uid) async {
    final box = await _box(boxName(uid));
    final saved = box.get('snapshot');
    if (saved != null) return CartCodec.decodeSnapshot(saved);
    final suffix = uid == null ? 'guest' : uid.replaceAll(':', '_');
    var rows = (await _box('cart_items_$suffix')).values.toList();
    if (uid == null && rows.isEmpty) {
      rows = (await _box('cart_items')).values.toList();
    }
    final items = CartCodec.decodeItems(rows);
    return CartSnapshot(items: items, pending: {
      if (uid != null)
        for (final item in items) item.listing.id: CartEdit(item),
    });
  }

  @override
  Future<void> write(String? uid, CartSnapshot snapshot) async {
    final box = await _box(boxName(uid));
    await box.put('snapshot', CartCodec.encodeSnapshot(snapshot));
    await box.flush();
  }
}
