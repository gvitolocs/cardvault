import 'package:cloud_firestore/cloud_firestore.dart';
import '../model/account.dart';

class ProfileProvider {
  ProfileProvider({FirebaseFirestore? firestore}) : _provided = firestore;
  final FirebaseFirestore? _provided;
  FirebaseFirestore get _db => _provided ?? FirebaseFirestore.instance;

  Stream<AccountProfile> watchProfile(String uid) => _db
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((doc) => AccountProfile.fromJson(doc.data() ?? {}));
  Stream<AccountBalance> watchBalance(String uid) => _db
      .collection('balances')
      .doc(uid)
      .snapshots()
      .map((doc) => AccountBalance.fromJson(doc.data() ?? {}));
  Stream<List<AccountOrder>> watchOrders(String uid) => _db
      .collection('orders')
      .where('uid', isEqualTo: uid)
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) {
            final json = doc.data();
            final createdAt = json['createdAt'];
            return AccountOrder(
                id: doc.id,
                status: '${json['status'] ?? ''}',
                total: (json['totalPkn'] as num?)?.toDouble() ?? 0,
                createdAt: createdAt is Timestamp ? createdAt.toDate() : null);
          }).toList()
            ..sort((a, b) => (b.createdAt ?? DateTime(1970))
                .compareTo(a.createdAt ?? DateTime(1970))));
  Stream<List<String>> watchFavorites(String uid) => _db
      .collection('user_card_watchlists')
      .doc(uid)
      .snapshots()
      .map((doc) => List.unmodifiable(
          (doc.data()?['cardIds'] as List? ?? []).whereType<String>().toSet()));

  Future<void> updateDisplayName(String uid, String name) =>
      _db.collection('users').doc(uid).set(
          {'displayName': name, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true));
}
