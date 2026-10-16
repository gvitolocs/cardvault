import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/browser_location.dart';
import 'pokoin_api_auth.dart';

const Set<String> _sensitivePayloadKeys = {
  'authorization',
  'cookie',
  'credential',
  'password',
  'secret',
  'token',
  'apikey',
  'api_key',
  'privatekey',
  'private_key',
  'session',
};

bool flutterDebugRequestedFromUri(Uri uri) {
  return uri.queryParameters['flutterDebug'] == '1' ||
      uri.queryParameters['flutterDebugLogs'] == '1';
}

Object? sanitizeFlutterDebugValue(Object? value, {int depth = 0}) {
  if (value == null || value is num || value is bool) {
    return value;
  }
  if (value is String) {
    return value.length <= 1000 ? value : value.substring(0, 1000);
  }
  if (depth >= 4) {
    return '[truncated]';
  }
  if (value is Iterable) {
    return value
        .take(80)
        .map((entry) => sanitizeFlutterDebugValue(entry, depth: depth + 1))
        .toList(growable: false);
  }
  if (value is Map) {
    return {
      for (final entry in value.entries.take(60))
        if (!_isSensitiveKey('${entry.key}'))
          (_cleanPayloadKey('${entry.key}')):
              sanitizeFlutterDebugValue(entry.value, depth: depth + 1),
    };
  }
  return '$value';
}

String _cleanPayloadKey(String key) {
  final trimmed = key.trim();
  return trimmed.isEmpty ? 'key' : trimmed;
}

bool _isSensitiveKey(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '');
  return _sensitivePayloadKeys.any(normalized.contains);
}

class FlutterDebugLog {
  FlutterDebugLog._();

  static final FlutterDebugLog instance = FlutterDebugLog._();
  static const int _maxBufferedEvents = 500;
  static const int _maxPendingSends = 1000;

  http.Client _client = http.Client();
  PokoinApiAuthService _auth = PokoinApiAuthService.instance();
  bool _authorized = false;
  bool _requested = false;
  bool _enabled = false;
  String _debugUserId = '';
  String _sessionId = '';
  int _sequence = 0;
  int _inFlight = 0;
  bool _disabledByServer = false;
  final List<Map<String, Object?>> _bufferedEvents = [];
  final List<Map<String, Object?>> _sendQueue = [];

  bool get enabled => _enabled && !_disabledByServer;
  bool get requested => _requested;
  String get sessionId {
    _ensureSession();
    return _sessionId;
  }

  @visibleForTesting
  void configureForTest({
    http.Client? client,
    PokoinApiAuthService? auth,
    bool authorized = true,
    bool requested = true,
  }) {
    _client = client ?? _client;
    _auth = auth ?? _auth;
    _authorized = authorized;
    _requested = requested;
    _enabled = authorized && requested;
    _disabledByServer = false;
    _bufferedEvents.clear();
    _sendQueue.clear();
    _inFlight = 0;
  }

  void configureFromUri(Uri uri) {
    if (flutterDebugRequestedFromUri(uri)) {
      final wasRequested = _requested;
      _requested = true;
      if (_authorized && (!wasRequested || !enabled)) {
        start(source: 'query_param');
      }
    }
  }

  void setAuthorized(bool value, {String userId = ''}) {
    final wasAuthorized = _authorized;
    final previousUserId = _debugUserId;
    _authorized = value;
    _debugUserId = userId.trim();
    if (!_authorized) {
      _enabled = false;
      return;
    }
    if (!wasAuthorized || previousUserId != _debugUserId || !enabled) {
      start(
          source: _requested ? 'authorized_query_param' : 'authorized_profile');
    }
  }

  void start({String source = 'manual'}) {
    _requested = true;
    if (!_authorized || _disabledByServer) {
      return;
    }
    _enabled = true;
    _flushBufferedEvents();
    record('debug.start', category: 'debug', payload: {'source': source});
  }

  void stop() {
    record('debug.stop', category: 'debug');
    _enabled = false;
  }

  void record(
    String eventName, {
    String category = 'flutter',
    String routePath = '',
    Uri? browserUri,
    Map<String, Object?> payload = const {},
  }) {
    _ensureSession();
    final uri = browserUri ?? currentBrowserUri() ?? Uri.base;
    final path = routePath.trim().isNotEmpty ? routePath.trim() : uri.path;
    final sanitizedPayload = sanitizeFlutterDebugValue(payload);
    final sanitizedPayloadMap = sanitizedPayload is Map
        ? sanitizedPayload.map<String, Object?>(
            (key, value) => MapEntry('$key', value),
          )
        : const <String, Object?>{};
    final body = {
      'clientTimestamp': DateTime.now().toUtc().toIso8601String(),
      'sessionId': _sessionId,
      if (_debugUserId.isNotEmpty) 'debugUserId': _debugUserId,
      'routePath': path,
      'browserUrl': uri.toString(),
      'eventName': eventName,
      'category': category,
      'payload': {
        'sequence': ++_sequence,
        ...sanitizedPayloadMap,
      },
    };
    if (!enabled) {
      _bufferEvent(body);
      return;
    }
    _send(body);
  }

  void recordError(
    String eventName,
    Object error, {
    StackTrace? stackTrace,
    String category = 'error',
    Map<String, Object?> payload = const {},
  }) {
    record(
      eventName,
      category: category,
      payload: {
        ...payload,
        'error': '$error',
        if (stackTrace != null)
          'stack': stackTrace.toString().split('\n').take(8).toList(),
      },
    );
  }

  void _send(Map<String, Object?> body) {
    if (_disabledByServer) {
      return;
    }
    if (_sendQueue.length >= _maxPendingSends) {
      _sendQueue.removeAt(0);
    }
    _sendQueue.add(Map<String, Object?>.from(body));
    _drainSendQueue();
  }

  void _bufferEvent(Map<String, Object?> body) {
    if (_disabledByServer) {
      return;
    }
    if (_bufferedEvents.length >= _maxBufferedEvents) {
      _bufferedEvents.removeAt(0);
    }
    _bufferedEvents.add(Map<String, Object?>.from(body));
  }

  void _flushBufferedEvents() {
    if (_bufferedEvents.isEmpty || !enabled) {
      return;
    }
    final events = List<Map<String, Object?>>.from(_bufferedEvents);
    _bufferedEvents.clear();
    for (final event in events) {
      _send(event);
    }
  }

  void _drainSendQueue() {
    while (_inFlight < 4 && _sendQueue.isNotEmpty && !_disabledByServer) {
      final body = _sendQueue.removeAt(0);
      _inFlight += 1;
      unawaited(() async {
        try {
          final postBody = Map<String, Object?>.from(body);
          if (_debugUserId.isNotEmpty) {
            postBody['debugUserId'] = _debugUserId;
          }
          final headers = await _auth.authorizationHeaders();
          final response = await _client
              .post(
                Uri.base.resolve('/api/flutter-debug-logs'),
                headers: {
                  'Content-Type': 'application/json',
                  ...headers,
                },
                body: jsonEncode(postBody),
              )
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 401 ||
              response.statusCode == 403 ||
              response.statusCode == 503) {
            _disabledByServer = true;
            _enabled = false;
            _sendQueue.clear();
            _bufferedEvents.clear();
          }
        } catch (_) {
          // Debug logging must never affect the app flow being diagnosed.
        } finally {
          _inFlight -= 1;
          _drainSendQueue();
        }
      }());
    }
  }

  void _ensureSession() {
    if (_sessionId.isNotEmpty) {
      return;
    }
    _sessionId =
        'flutter-${DateTime.now().millisecondsSinceEpoch}-${shortHash(Object())}';
  }
}
