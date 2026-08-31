import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

final Set<String> _recent = <String>{};

void logMarketplaceCardImage({
  required String url,
  String source = 'client',
  String status = 'error',
  String cardId = '',
  String ctId = '',
  String name = '',
  String fallbackUrl = '',
  String route = '',
  Object? error,
}) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    return;
  }
  final key = '$status|$trimmed';
  if (!_recent.add(key)) {
    return;
  }
  if (_recent.length > 80) {
    _recent.clear();
    _recent.add(key);
  }
  debugPrint(
    'marketplace-image $status source=$source cardId=$cardId ctId=$ctId url=$trimmed error=$error',
  );
  if (!kIsWeb && status != 'error') {
    return;
  }
  final uri = Uri.parse('https://api.pokoin.com/api/marketplace-image-log');
  final body = jsonEncode({
    'source': source,
    'status': status,
    'cardId': cardId,
    'ctId': ctId,
    'name': name,
    'url': trimmed,
    'fallbackUrl': fallbackUrl,
    'route': route,
    if (error != null) 'error': '$error',
  });
  http
      .post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: body,
      )
      .timeout(const Duration(seconds: 4))
      .catchError((_) => http.Response('', 599));
}
