import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/cardtrader_integration_service.dart';
import 'auth_provider.dart';

final cardTraderIntegrationServiceProvider =
    Provider<CardTraderIntegrationService>((ref) {
  return CardTraderIntegrationService();
});

final cardTraderConnectionStatusProvider =
    FutureProvider.autoDispose<CardTraderConnectionStatus>((ref) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) {
    return const CardTraderConnectionStatus(
      connected: false,
      provider: 'cardtrader',
      metadata: null,
    );
  }
  return ref.watch(cardTraderIntegrationServiceProvider).status();
});
