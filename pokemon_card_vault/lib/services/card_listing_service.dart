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

  Stream<List<CardListing>> listingsForSeller(String sellerUid) {
    if (Firebase.apps.isEmpty || sellerUid.trim().isEmpty) {
      return Stream.value(const []);
    }
    return _firestore
        .collection('card_listings')
        .where('sellerUid', isEqualTo: sellerUid)
        .snapshots()
        .map((snapshot) {
      final listings = snapshot.docs.map(CardListing.fromDocument).toList();
      listings.sort((a, b) {
        final aDate = a.updatedAt ?? a.createdAt ?? DateTime(1970);
        final bDate = b.updatedAt ?? b.createdAt ?? DateTime(1970);
        return bDate.compareTo(aDate);
      });
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

  Future<void> updateListingStatus({
    required String listingId,
    required String sellerUid,
    required String status,
  }) async {
    final ref = _firestore.collection('card_listings').doc(listingId);
    final snapshot = await ref.get();
    final listing = CardListing.fromDocument(snapshot);
    if (!snapshot.exists || listing.sellerUid != sellerUid) {
      throw StateError('Listing not found for this seller.');
    }
    await ref.set({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateListingQuantity({
    required String listingId,
    required String sellerUid,
    required int quantityAvailable,
  }) async {
    if (quantityAvailable < 0) {
      throw ArgumentError('Quantity cannot be negative.');
    }
    final ref = _firestore.collection('card_listings').doc(listingId);
    final snapshot = await ref.get();
    final listing = CardListing.fromDocument(snapshot);
    if (!snapshot.exists || listing.sellerUid != sellerUid) {
      throw StateError('Listing not found for this seller.');
    }
    await ref.set({
      'quantityAvailable': quantityAvailable,
      'status': quantityAvailable == 0 ? 'paused' : listing.status,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> decrementListingQuantity({
    required String listingId,
    required int quantity,
  }) async {
    if (listingId.isEmpty || quantity <= 0) {
      return;
    }
    final ref = _firestore.collection('card_listings').doc(listingId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) {
        return;
      }
      final listing = CardListing.fromDocument(snapshot);
      final nextQuantity = (listing.quantityAvailable - quantity).clamp(0, 999999);
      transaction.set(ref, {
        'quantityAvailable': nextQuantity,
        'status': nextQuantity == 0 ? 'sold_out' : listing.status,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }
}
