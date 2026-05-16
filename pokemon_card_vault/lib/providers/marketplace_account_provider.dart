import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import '../services/marketplace_account_service.dart';

final marketplaceAccountServiceProvider =
    Provider<MarketplaceAccountService>((ref) {
  return MarketplaceAccountService();
});

final userOrdersProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) {
    return Stream.value(const []);
  }
  return ref.watch(marketplaceAccountServiceProvider).ordersForUser(user.uid);
});

final withdrawRequestsProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) {
    return Stream.value(const []);
  }
  return ref
      .watch(marketplaceAccountServiceProvider)
      .withdrawRequestsForUser(user.uid);
});
