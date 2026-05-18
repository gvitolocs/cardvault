import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/card_listing.dart';

class CardListingService {
  CardListingService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Stream<List<CardListing>> activeListings({int limit = 500}) {
    if (Firebase.apps.isEmpty) {
      return Stream.value(const []);
    }
    return _firestore
        .collection('card_listings')
        .where('status', isEqualTo: 'active')
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      final listings = snapshot.docs
          .map(CardListing.fromDocument)
          .where((listing) => listing.isActive)
          .toList();
      listings.sort((a, b) => a.pricePkn.compareTo(b.pricePkn));
      return listings;
    });
  }

  Stream<List<CardListing>> activeListingsForCard(String cardId) {
    if (Firebase.apps.isEmpty) {
      return Stream.value(const []);
    }
    return _firestore
        .collection('card_listings')
        .where('cardId', isEqualTo: cardId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) {
      final listings = snapshot.docs
          .map(CardListing.fromDocument)
          .where((listing) => listing.isActive)
          .toList();
      listings.sort((a, b) => a.pricePkn.compareTo(b.pricePkn));
      return listings;
    });
  }

  Future<String> createListing(CardListing listing) async {
    final doc = await _firestore.collection('card_listings').add({
      ...listing.toFirestore(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }
}
