import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../model/shipping_address.dart';

/// Owner-only encrypted-address API. Addresses never enter local snapshots or logs.
class AccountAddressesProvider {
  AccountAddressesProvider(
      {http.Client? client, Future<String?> Function(String)? token})
      : _client = client,
        _token = token;
  final http.Client? _client;
  final Future<String?> Function(String)? _token;
  Future<Map<String, dynamic>> _request(String uid, String method,
      {Map<String, dynamic>? body, Map<String, String>? query}) async {
    final user = _token == null ? FirebaseAuth.instance.currentUser : null;
    if (_token == null && user?.uid != uid) throw StateError('Session changed');
    final token = await (_token != null ? _token(uid) : user!.getIdToken())
        .timeout(const Duration(seconds: 12));
    if (token == null ||
        token.isEmpty ||
        (_token == null && FirebaseAuth.instance.currentUser?.uid != uid)) {
      throw StateError('Session changed');
    }
    final client = _client ?? http.Client();
    try {
      final uri = Uri.https('api.pokoin.com', '/api/account-addresses', query);
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json'
      };
      final response = await (switch (method) {
        'POST' => client.post(uri, headers: headers, body: jsonEncode(body)),
        'PUT' => client.put(uri, headers: headers, body: jsonEncode(body)),
        'DELETE' => client.delete(uri, headers: headers),
        _ => client.get(uri, headers: headers),
      })
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Address request rejected');
      }
      if (response.bodyBytes.isEmpty) return {};
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map<String, dynamic> ||
          (json['uid'] != null && json['uid'] != uid)) {
        throw const FormatException('Invalid address response');
      }
      return json;
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<List<ShippingAddress>> read(String uid, {bool reveal = true}) async {
    final data = await _request(uid, 'GET', query: {if (reveal) 'reveal': '1'});
    if (data['addresses'] is! List) {
      throw const FormatException('Invalid addresses');
    }
    return [
      for (final raw in data['addresses'] as List)
        ShippingAddress.fromJson(Map<String, dynamic>.from(raw as Map))
    ];
  }

  Future<void> save(String uid, ShippingAddress address) async {
    final data = await _request(uid, address.id.isEmpty ? 'POST' : 'PUT',
        query: address.id.isEmpty ? null : {'id': address.id},
        body: address.toJson());
    final row = data['address'];
    if (row is! Map || row['id'] is! String || (row['id'] as String).isEmpty) {
      throw const FormatException('Address not acknowledged');
    }
  }

  Future<void> remove(String uid, String id) async {
    if (id.isEmpty) throw const FormatException('Missing address');
    await _request(uid, 'DELETE', query: {'id': id});
  }
}
