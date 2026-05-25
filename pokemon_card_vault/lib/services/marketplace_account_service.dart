import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

import 'pokoin_api_client.dart';

class MarketplaceAccountService {
  MarketplaceAccountService({
    FirebaseFirestore? firestore,
    PokoinApiClient? apiClient,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _apiClient = apiClient ?? PokoinApiClient();

  final FirebaseFirestore _firestore;
  final PokoinApiClient _apiClient;

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

  Future<String> createPaidOrder({
    required String buyerEmail,
    required List<Map<String, dynamic>> items,
    required double subtotalPkn,
    required double taxPkn,
    required double shippingPkn,
    required double totalPkn,
    required String fulfillmentMode,
  }) async {
    final response = await _apiClient.postJson(
      Uri.base.resolve('/api/marketplace-orders'),
      body: {
        'buyerEmail': buyerEmail,
        'items': items,
        'subtotalPkn': subtotalPkn,
        'taxPkn': taxPkn,
        'shippingPkn': shippingPkn,
        'totalPkn': totalPkn,
        'fulfillmentMode': fulfillmentMode,
      },
    );
    final decoded = _decode(response);
    final order = Map<String, dynamic>.from(decoded['order'] as Map? ?? {});
    final orderId = '${order['id'] ?? ''}'.trim();
    if (orderId.isEmpty) {
      throw StateError(
          'Marketplace order was paid but no order id was returned.');
    }
    return orderId;
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

  Future<String> requestNftPhysicalShipping({
    required String collectionItemId,
    required Map<String, dynamic> shippingAddress,
    String notes = '',
  }) async {
    final response = await _apiClient.postJson(
      Uri.base.resolve('/api/marketplace-orders?action=nft-shipping-request'),
      body: {
        'collectionItemId': collectionItemId,
        'shippingAddress': shippingAddress,
        if (notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    );
    final decoded = _decode(response);
    final request = Map<String, dynamic>.from(decoded['request'] as Map? ?? {});
    final requestId = '${request['id'] ?? ''}'.trim();
    if (requestId.isEmpty) {
      throw StateError('NFT shipping request was saved without an id.');
    }
    return requestId;
  }

  Future<int> requestAllNftPhysicalShipping({
    required List<String> collectionItemIds,
    required Map<String, dynamic> shippingAddress,
    String notes = '',
  }) async {
    final response = await _apiClient.postJson(
      Uri.base.resolve('/api/marketplace-orders?action=nft-shipping-request'),
      body: {
        'collectionItemIds': collectionItemIds,
        'shippingAddress': shippingAddress,
        if (notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    );
    final decoded = _decode(response);
    final requests = decoded['requests'];
    return requests is List ? requests.length : 0;
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

Map<String, dynamic> _decode(http.Response response) {
  final decoded = response.body.isEmpty
      ? <String, dynamic>{}
      : jsonDecode(response.body) as Map<String, dynamic>;
  if (response.statusCode >= 400) {
    throw StateError(
      decoded['error'] as String? ?? 'Marketplace order request failed.',
    );
  }
  return decoded;
}
