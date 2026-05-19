import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user_profile.dart';
import '../services/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

final authStateProvider = StreamProvider<User?>((ref) {
  if (Firebase.apps.isEmpty) {
    return Stream.value(null);
  }
  return ref.watch(authServiceProvider).authStateChanges;
});

final authBootstrapProvider = FutureProvider<void>((ref) async {
  if (Firebase.apps.isEmpty) {
    return;
  }
  await ref.watch(authServiceProvider).initializeSession();
});

final userProfileProvider = StreamProvider<AppUserProfile?>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || Firebase.apps.isEmpty) {
    return Stream.value(null);
  }
  return ref.watch(authServiceProvider).profileStream(user.uid);
});

final isAdminProvider = Provider<bool>((ref) {
  return ref.watch(userProfileProvider).valueOrNull?.hasAdminAccess ?? false;
});

final cachedPknBalanceProvider = FutureProvider<int?>((ref) async {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || Firebase.apps.isEmpty) {
    return null;
  }
  return ref.watch(authServiceProvider).cachedBalance(user.uid);
});

final pknBalanceProvider = StreamProvider<int>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null || Firebase.apps.isEmpty) {
    return Stream.value(0);
  }
  return ref.watch(authServiceProvider).balanceStream(user.uid);
});
