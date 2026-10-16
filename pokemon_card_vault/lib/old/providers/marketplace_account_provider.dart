import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'auth_provider.dart';
import '../constants/project_links.dart';
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

final sellerOrdersProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) {
    return Stream.value(const []);
  }
  return ref.watch(marketplaceAccountServiceProvider).ordersForSeller(user.uid);
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

final linkedWalletBalanceProvider =
    FutureProvider.autoDispose<String?>((ref) async {
  final profile = await ref.watch(userProfileProvider.future);
  final address = profile?.walletAddress?.trim();
  if (address == null || address.isEmpty) {
    return null;
  }

  final response = await http
      .post(
        Uri.parse(ProjectLinks.rpc),
        headers: const <String, String>{'content-type': 'application/json'},
        body: jsonEncode(<String, Object>{
          'jsonrpc': '2.0',
          'id': DateTime.now().microsecondsSinceEpoch,
          'method': 'eth_getBalance',
          'params': <Object>[address, 'latest'],
        }),
      )
      .timeout(const Duration(seconds: 10));
  final payload = jsonDecode(response.body) as Map<String, dynamic>;
  if (response.statusCode >= 400 || payload['error'] != null) {
    throw Exception(payload['error'] ?? 'RPC HTTP ${response.statusCode}');
  }
  return _formatWei(_hexToBigInt(payload['result'] as String));
});

BigInt _hexToBigInt(String hex) {
  final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
  if (clean.isEmpty) {
    return BigInt.zero;
  }
  return BigInt.parse(clean, radix: 16);
}

String _formatWei(BigInt wei) {
  final base = BigInt.from(10).pow(18);
  final whole = wei ~/ base;
  final fraction = wei.remainder(base).toString().padLeft(18, '0');
  final compact = fraction.substring(0, 2);
  return '$whole.${compact.padRight(2, '0')}';
}
