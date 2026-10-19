import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../firebase_options.dart';
import '../model/cardex.dart';
import 'account_api_provider.dart';

/// Lettura privata via BFF: Firestore non permette accesso client alla collezione.
class CollectionProvider {
  CollectionProvider(
      {FirebaseAuth? auth,
      http.Client? client,
      Future<String?> Function(String uid)? idToken,
      Stream<String?> Function()? userIds})
      : _auth = auth,
        _api = AccountApiProvider(auth: auth, client: client, idToken: idToken),
        _userIds = userIds;
  final FirebaseAuth? _auth;
  final AccountApiProvider _api;
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
    final payload = await _api.get(uid, '/api/marketplace-collection');
    if (payload['uid'] != uid || payload['items'] is! List) {
      throw const FormatException('Invalid private collection');
    }
    final result = <OwnedCard>[];
    for (final row in payload['items'] as List) {
      final quantity = row is Map ? num.tryParse('${row['quantity']}') : null;
      if (row is! Map<String, dynamic> ||
          row['uid'] != uid ||
          '${row['cardId'] ?? row['blueprintId'] ?? ''}'.trim().isEmpty ||
          quantity == null ||
          !quantity.isFinite ||
          quantity < 0 ||
          quantity != quantity.truncateToDouble()) {
        throw const FormatException('Invalid collection item');
      }
      result.add(OwnedCard.fromJson(row));
    }
    for (final entry in {
      'itemCount': result.length,
      'cardsOwned': result.fold<int>(0, (sum, row) => sum + row.quantity),
    }.entries) {
      if (payload.containsKey(entry.key) &&
          num.tryParse('${payload[entry.key]}') != entry.value) {
        throw const FormatException('Incomplete private collection');
      }
    }
    return List.unmodifiable(result);
  }
}
