import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Read-only private Pokoin requests. Never persists credentials or responses.
class AccountApiProvider {
  AccountApiProvider(
      {FirebaseAuth? auth,
      http.Client? client,
      Future<String?> Function(String uid)? idToken})
      : _auth = auth,
        _client = client,
        _idToken = idToken;

  final FirebaseAuth? _auth;
  final http.Client? _client;
  final Future<String?> Function(String uid)? _idToken;

  Future<Map<String, dynamic>> get(String uid, String path,
      [Map<String, String> query = const {}]) async {
    if (uid.trim().isEmpty) throw StateError('Authentication required');
    final token = await (_idToken != null ? _idToken(uid) : _tokenFor(uid))
        .timeout(const Duration(seconds: 12));
    if (token == null || token.isEmpty) {
      throw StateError('Authentication required');
    }
    final client = _client ?? http.Client();
    try {
      final response = await client.get(
          Uri.https('api.pokoin.com', path, query.isEmpty ? null : query),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json'
          }).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw StateError(
            'Account inventory unavailable (${response.statusCode})');
      }
      final payload = jsonDecode(utf8.decode(response.bodyBytes));
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('Invalid account response');
      }
      return payload;
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<String?> _tokenFor(String uid) async {
    final user = (_auth ?? FirebaseAuth.instance).currentUser;
    if (user == null || user.uid != uid) throw StateError('Session changed');
    return user.getIdToken();
  }
}
