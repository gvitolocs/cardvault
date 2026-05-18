import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/card_listing.dart';
import '../services/card_listing_service.dart';

final cardListingServiceProvider = Provider<CardListingService>((ref) {
  return CardListingService();
});

final activeCardListingsProvider = StreamProvider<List<CardListing>>((ref) {
  return ref.watch(cardListingServiceProvider).activeListings();
});

final cardListingsProvider =
    StreamProvider.family<List<CardListing>, String>((ref, cardId) {
  return ref.watch(cardListingServiceProvider).activeListingsForCard(cardId);
});
