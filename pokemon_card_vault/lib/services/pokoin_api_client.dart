import 'dart:convert';

import 'package:http/http.dart' as http;

import 'pokoin_api_auth.dart';

class PokoinApiClient {
  PokoinApiClient({
    http.Client? client,
    PokoinApiAuthService? auth,
  })  : _client = client ?? http.Client(),
        _auth = auth ?? PokoinApiAuthService.instance();

  final http.Client _client;
  final PokoinApiAuthService _auth;

  Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
    bool requireAuth = true,
  }) async {
    final requestHeaders = await _headers(headers, requireAuth: requireAuth);
    return _client
        .get(uri, headers: requestHeaders)
        .timeout(const Duration(seconds: 15));
  }

  Future<http.Response> postJson(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    bool requireAuth = true,
  }) async {
    final requestHeaders = await _headers(
      {
        'Content-Type': 'application/json',
        ...?headers,
      },
      requireAuth: requireAuth,
    );
    return _client
        .post(
          uri,
          headers: requestHeaders,
          body: jsonEncode(body ?? const {}),
        )
        .timeout(const Duration(seconds: 20));
  }

  Future<http.Response> sendJson(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    bool requireAuth = true,
  }) async {
    final requestHeaders = await _headers(
      {
        'Content-Type': 'application/json',
        ...?headers,
      },
      requireAuth: requireAuth,
    );
    final request = http.Request(method, uri)
      ..headers.addAll(requestHeaders)
      ..body = jsonEncode(body ?? const {});
    final response = await _client.send(request).timeout(
          const Duration(seconds: 20),
        );
    final text = await response.stream.bytesToString();
    return http.Response(text, response.statusCode, headers: response.headers);
  }

  Future<Map<String, String>> _headers(
    Map<String, String>? headers, {
    required bool requireAuth,
  }) async {
    return {
      ...?headers,
      ...await _auth.authorizationHeaders(requireSignedIn: requireAuth),
    };
  }
}
