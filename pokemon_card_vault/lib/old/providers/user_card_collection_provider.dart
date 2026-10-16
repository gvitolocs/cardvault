import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_card_collection_item.dart';
import '../services/user_card_collection_service.dart';
import 'auth_provider.dart';

final userCardCollectionServiceProvider =
    Provider<UserCardCollectionService>((ref) {
  return UserCardCollectionService();
});

final userCardCollectionProvider =
    StreamProvider<List<UserCardCollectionItem>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) {
    return Stream.value(const []);
  }
  return ref.watch(userCardCollectionServiceProvider).itemsForUser(user.uid);
});

final userOwnedBlueprintIdsProvider = Provider<Set<String>>((ref) {
  final items = ref.watch(userCardCollectionProvider).valueOrNull ?? const [];
  return {
    for (final item in items)
      if (item.cardId.isNotEmpty) item.cardId,
  };
});

final userCardCollectionForCardProvider =
    StreamProvider.family<List<UserCardCollectionItem>, String>((ref, cardId) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) {
    return Stream.value(const []);
  }
  return ref.watch(userCardCollectionServiceProvider).itemsForUserCard(
        uid: user.uid,
        cardId: cardId,
      );
});
