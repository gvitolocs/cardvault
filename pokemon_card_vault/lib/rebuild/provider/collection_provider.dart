import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../firebase_options.dart';
import '../model/cardex.dart';

/// Lettura privata via BFF: Firestore non permette accesso client alla collezione.
class CollectionProvider {
  CollectionProvider(
      {FirebaseAuth? auth,
      http.Client? client,
      Future<String?> Function(String uid)? idToken,
      Stream<String?> Function()? userIds})
      : _auth = auth,
        _client = client,
        _idToken = idToken,
        _userIds = userIds;
  final FirebaseAuth? _auth;
  final http.Client? _client;
  final Future<String?> Function(String uid)? _idToken;
  final Stream<String?> Function()? _userIds;

  Stream<String?> watchUserId() async* {
    if (_userIds != null) {
      yield* _userIds();
      return;
    }
    if (_auth == null && Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform);
    }
    yield* (_auth ?? FirebaseAuth.instance)
        .authStateChanges()
        .map((user) => user?.uid)
        .distinct();
  }

  // La cancellazione del listener non deve attendere la vecchia richiesta HTTP
  // prima di caricare il nuovo account. Il service scarta i risultati obsoleti.
  Stream<List<OwnedCard>> watchItems(String uid) =>
      Stream.fromFuture(fetchItems(uid));

  Future<List<OwnedCard>> fetchItems(String uid) async {
    if (uid.trim().isEmpty) throw StateError('Authentication required');
    final token = await (_idToken != null ? _idToken(uid) : _tokenFor(uid))
        .timeout(const Duration(seconds: 12));
    if (token == null || token.isEmpty) {
      throw StateError('Authentication required');
    }
    final client = _client ?? http.Client();
    try {
      final response = await client.get(
          Uri.https('api.pokoin.com', '/api/marketplace-collection'),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json'
          }).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw StateError('Collection unavailable (${response.statusCode})');
      }
      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic> ||
          payload['uid'] != uid ||
          payload['items'] is! List) {
        throw const FormatException('Invalid private collection');
      }
      final result = <OwnedCard>[];
      for (final row in payload['items'] as List) {
        if (row is! Map<String, dynamic> ||
            row['uid'] != uid ||
            '${row['cardId'] ?? row['blueprintId'] ?? ''}'.trim().isEmpty ||
            num.tryParse('${row['quantity']}') == null) {
          throw const FormatException('Invalid collection item');
        }
        result.add(OwnedCard.fromJson(row));
      }
      return List.unmodifiable(result);
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<String?> _tokenFor(String uid) async {
    final user = (_auth ?? FirebaseAuth.instance).currentUser;
    if (user == null || user.uid != uid) {
      throw StateError('Session changed');
    }
    return user.getIdToken();
  }
}
