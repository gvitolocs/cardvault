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

  Future<String> createPendingOrder({
    required String uid,
    required String buyerEmail,
    required List<Map<String, dynamic>> items,
    required double subtotalPkn,
    required double totalPkn,
  }) async {
    final doc = await _firestore.collection('orders').add({
      'uid': uid,
      'buyerUid': uid,
      'buyerEmail': buyerEmail,
      'items': items,
      'subtotalPkn': subtotalPkn,
      'totalPkn': totalPkn,
      'status': 'pending',
      'fulfillmentStatus': 'awaiting_seller_confirmation',
      'paymentStatus': 'reserved',
      'sellerUids': items
          .map((item) => '${item['sellerUid'] ?? ''}')
          .where((sellerUid) => sellerUid.isNotEmpty)
          .toSet()
          .toList(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Stream<List<Map<String, dynamic>>> ordersForSeller(String sellerUid) {
    if (sellerUid.trim().isEmpty) {
      return Stream.value(const []);
    }
    return _firestore
        .collection('orders')
        .where('sellerUids', arrayContains: sellerUid)
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

  Future<void> updateOrderStatus({
    required String orderId,
    required String status,
  }) async {
    await _firestore.collection('orders').doc(orderId).set({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
