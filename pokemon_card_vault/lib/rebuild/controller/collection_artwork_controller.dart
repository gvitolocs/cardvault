import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../constants/card_language_constants.dart';
import '../model/card.dart';
import '../service/collection_artwork_service.dart';

/// Resolves scans only for mounted/visible sleeves, with two metadata GETs at
/// most. Entries contain public metadata, never private ownership or quantities.
class CollectionArtworkController extends ChangeNotifier {
  CollectionArtworkController({CollectionArtworkService? service})
      : _service = service ?? CollectionArtworkService();
  final CollectionArtworkService _service;
  final _metadata = <String, MarketplaceCard?>{};
  final _leases = <String, int>{};
  final _queue = Queue<String>();
  final _pending = <String>{};
  final _running = <String>{};
  bool _disposed = false, _started = false;
  bool preferenceReady = false;
  String language = 'IT';
  int _selectionRevision = 0;
  Future<void> _writes = Future.value();

  bool resolved(String id) => _metadata.containsKey(id);
  MarketplaceCard? metadataFor(String id) => _metadata[id];

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    final revision = _selectionRevision;
    try {
      final saved = await _service.readLanguage();
      if (!_disposed && revision == _selectionRevision) language = saved;
    } catch (_) {
      // Storage is optional; failed reads do not block collection rendering.
    }
    if (_disposed) return;
    preferenceReady = true;
    notifyListeners();
    _drain();
  }

  void selectLanguage(String value) {
    final code = value.toUpperCase();
    if (_disposed || !cardLanguageLabels.containsKey(code)) return;
    _selectionRevision++;
    language = code;
    preferenceReady = true;
    // Serialize writes so an older slow write cannot overwrite a newer choice.
    _writes = _writes
        .then((_) => _service.writeLanguage(code))
        .catchError((Object _) {});
    notifyListeners();
    _drain();
  }

  VoidCallback acquire(String id) {
    if (_disposed || !RegExp(r'^[1-9]\d*$').hasMatch(id)) return () {};
    _leases.update(id, (count) => count + 1, ifAbsent: () => 1);
    final hadCached = _metadata.containsKey(id);
    final cached = _metadata.remove(id);
    if (hadCached) _metadata[id] = cached;
    // A missing/failed mapping is cached too: no automatic retry storm.
    if (!_metadata.containsKey(id) && cached == null && _pending.add(id)) {
      _queue.add(id);
    }
    unawaited(start());
    _drain();
    var released = false;
    return () {
      if (released || _disposed) return;
      released = true;
      final count = (_leases[id] ?? 1) - 1;
      if (count > 0) {
        _leases[id] = count;
      } else {
        _leases.remove(id);
        if (!_running.contains(id)) {
          _queue.remove(id);
          _pending.remove(id);
        }
      }
    };
  }

  void _drain() {
    if (_disposed || !preferenceReady) return;
    while (_running.length < 2 && _queue.isNotEmpty) {
      final id = _queue.removeFirst();
      if (!_leases.containsKey(id)) {
        _pending.remove(id);
        continue;
      }
      _running.add(id);
      unawaited(_load(id));
    }
  }

  Future<void> _load(String id) async {
    MarketplaceCard? result;
    try {
      result = await _service.fetchCard(id);
    } catch (_) {
      // Explicit catalogue fallback; never change a canonical ID or stock.
    }
    if (_disposed) return;
    _running.remove(id);
    _pending.remove(id);
    _metadata[id] = result;
    if (_metadata.length > 200) {
      final expired =
          _metadata.keys.where((key) => !_leases.containsKey(key)).firstOrNull;
      if (expired != null) _metadata.remove(expired);
    }
    notifyListeners();
    _drain();
  }

  @override
  void dispose() {
    _disposed = true;
    _queue.clear();
    _leases.clear();
    _service.dispose();
    super.dispose();
  }
}
