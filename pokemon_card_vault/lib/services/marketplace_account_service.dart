import 'package:cloud_firestore/cloud_firestore.dart';

class MarketplaceAccountService {
  MarketplaceAccountService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<List<Map<String, dynamic>>> ordersForUser(String uid) {
    return _firestore
        .collection('orders')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map(
      (snapshot) {
        final items = snapshot.docs
            .map((doc) => {
                  'id': doc.id,
                  ...doc.data(),
                })
            .toList();
        items.sort((a, b) => _readTimestamp(b['createdAt'])
            .compareTo(_readTimestamp(a['createdAt'])));
        return items;
      },
    );
  }

  Stream<List<Map<String, dynamic>>> withdrawRequestsForUser(String uid) {
    return _firestore
        .collection('withdraw_requests')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map(
      (snapshot) {
        final items = snapshot.docs
            .map((doc) => {
                  'id': doc.id,
                  ...doc.data(),
                })
            .toList();
        items.sort((a, b) => _readTimestamp(b['createdAt'])
            .compareTo(_readTimestamp(a['createdAt'])));
        return items.take(10).toList();
      },
    );
  }

  DateTime _readTimestamp(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}
