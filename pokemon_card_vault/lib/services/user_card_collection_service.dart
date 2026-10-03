import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/user_card_collection_item.dart';

/// Read-only compatibility for collection providers still used by the app.
/// Collection mutations belong to server-owned marketplace/order workflows.
class UserCardCollectionService {
  UserCardCollectionService({FirebaseFirestore? firestore})
      : _injectedFirestore = firestore;

  static const collectionName = 'user_card_collections';
  final FirebaseFirestore? _injectedFirestore;
  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  Stream<List<UserCardCollectionItem>> itemsForUser(String uid) {
    if (Firebase.apps.isEmpty || uid.trim().isEmpty) {
      return Stream.value(const []);
    }
    return _firestore
        .collection(collectionName)
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
      final items =
          snapshot.docs.map(UserCardCollectionItem.fromDocument).toList();
      items.sort((a, b) {
        final set = a.setName.compareTo(b.setName);
        return set != 0 ? set : a.collectorNumber.compareTo(b.collectorNumber);
      });
      return items;
    });
  }

  Stream<List<UserCardCollectionItem>> itemsForUserCard({
    required String uid,
    required String cardId,
  }) {
    if (Firebase.apps.isEmpty || uid.trim().isEmpty || cardId.trim().isEmpty) {
      return Stream.value(const []);
    }
    return _firestore
        .collection(collectionName)
        .where('uid', isEqualTo: uid)
        .where('cardId', isEqualTo: cardId)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map(UserCardCollectionItem.fromDocument).toList());
  }
}
