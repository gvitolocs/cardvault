import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../model/cart_item.dart';
import 'cart_codec.dart';

abstract class CartRemoteProvider {
  Future<List<ListingCartItem>> read(String uid);
  Future<List<ListingCartItem>> apply(String uid, Map<String, CartEdit> edits);
}

/// Stesso documento della versione precedente; Firebase viene inizializzato
/// dall'account gate. Nessun accesso remoto per gli ospiti.
class FirestoreCartProvider implements CartRemoteProvider {
  FirestoreCartProvider({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore,
        _auth = auth;
  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;
  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  void _checkUser(String uid) {
    if (uid.isEmpty ||
        (_auth ?? FirebaseAuth.instance).currentUser?.uid != uid) {
      throw StateError('Cart session changed');
    }
  }

  List<Object?> _rows(Map<String, dynamic>? data) {
    if (data == null) return [];
    if (data['items'] is! List) {
      throw const FormatException('Invalid remote cart');
    }
    return List<Object?>.from(data['items'] as List);
  }

  @override
  Future<List<ListingCartItem>> read(String uid) async {
    _checkUser(uid);
    final document = await _db
        .collection('user_carts')
        .doc(uid)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 12));
    _checkUser(uid);
    return CartCodec.decodeItems(_rows(document.data()));
  }

  @override
  Future<List<ListingCartItem>> apply(String uid, Map<String, CartEdit> edits) {
    _checkUser(uid);
    final reference = _db.collection('user_carts').doc(uid);
    return _db.runTransaction((transaction) async {
      _checkUser(uid);
      final document = await transaction.get(reference);
      _checkUser(uid);
      final rows = CartCodec.applyEdits(_rows(document.data()), edits);
      transaction.set(
          reference,
          {
            'items': rows,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
      return CartCodec.decodeItems(rows);
    }, timeout: const Duration(seconds: 12), maxAttempts: 3);
  }
}
