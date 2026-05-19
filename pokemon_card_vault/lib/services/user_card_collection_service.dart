import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/user_card_collection_item.dart';

class UserCardCollectionService {
  UserCardCollectionService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const collectionName = 'user_card_collections';

  final FirebaseFirestore _firestore;

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
        if (set != 0) {
          return set;
        }
        return a.collectorNumber.compareTo(b.collectorNumber);
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

  Future<String> addItem(UserCardCollectionItem item) async {
    if (item.uid.trim().isEmpty || item.cardId.trim().isEmpty) {
      throw ArgumentError('Collection items require a user and card id.');
    }
    final doc = await _firestore.collection(collectionName).add({
      ...item.toFirestore(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> updateItem({
    required String itemId,
    required String uid,
    required Map<String, dynamic> fields,
  }) async {
    final ref = _firestore.collection(collectionName).doc(itemId);
    final snapshot = await ref.get();
    final item = UserCardCollectionItem.fromDocument(snapshot);
    if (!snapshot.exists || item.uid != uid) {
      throw StateError('Collection item not found for this user.');
    }
    await ref.set({
      ...fields,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeItem({
    required String itemId,
    required String uid,
  }) async {
    final ref = _firestore.collection(collectionName).doc(itemId);
    final snapshot = await ref.get();
    final item = UserCardCollectionItem.fromDocument(snapshot);
    if (!snapshot.exists || item.uid != uid) {
      throw StateError('Collection item not found for this user.');
    }
    await ref.delete();
  }
}
