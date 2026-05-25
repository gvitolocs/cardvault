import 'dart:convert';

import 'package:flutter/foundation.dart';

typedef SearchDebugListener = void Function();

class SearchDebugTrace {
  SearchDebugTrace._();

  static final SearchDebugTrace instance = SearchDebugTrace._();

  final List<Map<String, Object?>> _events = [];
  final List<SearchDebugListener> _listeners = [];
  final Stopwatch _clock = Stopwatch()..start();
  String _sessionId = '';
  int _nextId = 0;
  bool _enabled = false;
  bool _requested = false;
  bool _authorized = false;

  bool get enabled => _enabled;
  bool get requested => _requested;
  bool get authorized => _authorized;
  String get sessionId {
    _ensureSession();
    return _sessionId;
  }

  List<Map<String, Object?>> get events =>
      List.unmodifiable(_events.map(Map<String, Object?>.from));

  void configureFromUri(Uri uri) {
    final enabledByQuery = uri.queryParameters['searchDebug'] == '1';
    if (enabledByQuery) {
      _requested = true;
      if (_authorized) {
        start(source: 'query_param');
      }
    }
  }

  void setAuthorized(bool value) {
    if (_authorized == value) {
      return;
    }
    _authorized = value;
    if (!_authorized) {
      _enabled = false;
      _notify();
      return;
    }
    if (_requested) {
      start(source: 'authorized_query_param');
    }
  }

  void start({String source = 'manual'}) {
    _requested = true;
    if (!_authorized) {
      return;
    }
    _enabled = true;
    _ensureSession();
    record('debug.start', {'source': source});
  }

  void stop() {
    record('debug.stop');
    _enabled = false;
    _notify();
  }

  void clear() {
    _events.clear();
    _nextId = 0;
    _sessionId = '';
    if (_enabled) {
      _ensureSession();
      record('debug.clear');
    }
    _notify();
  }

  void addListener(SearchDebugListener listener) {
    _listeners.add(listener);
  }

  void removeListener(SearchDebugListener listener) {
    _listeners.remove(listener);
  }

  void record(String type, [Map<String, Object?> data = const {}]) {
    if (!_enabled) {
      return;
    }
    _ensureSession();
    _events.add({
      'id': ++_nextId,
      'type': type,
      'sessionId': _sessionId,
      'elapsedMs': _clock.elapsedMilliseconds,
      'at': DateTime.now().toIso8601String(),
      'data': _sanitize(data),
    });
    if (_events.length > 2500) {
      _events.removeRange(0, _events.length - 2500);
    }
    _notify();
  }

  String exportJson() {
    _ensureSession();
    return const JsonEncoder.withIndent('  ').convert({
      'session': {
        'id': _sessionId,
        'exportedAt': DateTime.now().toIso8601String(),
        'eventCount': _events.length,
      },
      'events': _events,
    });
  }

  void _ensureSession() {
    if (_sessionId.isNotEmpty) {
      return;
    }
    _sessionId =
        'search-${DateTime.now().millisecondsSinceEpoch}-${shortHash(UniqueKey().toString())}';
  }

  Object? _sanitize(Object? value) {
    if (value == null ||
        value is String ||
        value is num ||
        value is bool) {
      return value;
    }
    if (value is Iterable) {
      return value.take(80).map(_sanitize).toList(growable: false);
    }
    if (value is Map) {
      return {
        for (final entry in value.entries.take(80))
          '${entry.key}': _sanitize(entry.value),
      };
    }
    return '$value';
  }

  void _notify() {
    for (final listener in List<SearchDebugListener>.of(_listeners)) {
      listener();
    }
  }
}
