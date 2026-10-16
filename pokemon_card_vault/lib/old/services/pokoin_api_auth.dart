import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PokoinAuthToken {
  const PokoinAuthToken({
    required this.accessToken,
    required this.tokenType,
    required this.uid,
    this.email,
  });

  final String accessToken;
  final String tokenType;
  final String uid;
  final String? email;

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'tokenType': tokenType,
        'uid': uid,
        if (email != null && email!.isNotEmpty) 'email': email,
      };
}

class PokoinApiAuthService {
  PokoinApiAuthService({FirebaseAuth? auth}) : _providedAuth = auth;

  static const bearerTokenCacheKey = 'pokoin_api_bearer_token';
  static const bearerUidCacheKey = 'pokoin_api_bearer_uid';
  static final Map<FirebaseAuth, PokoinApiAuthService> _instances = {};

  factory PokoinApiAuthService.instance({FirebaseAuth? auth}) {
    if (auth != null) {
      return _instances.putIfAbsent(
          auth, () => PokoinApiAuthService(auth: auth));
    }
    if (Firebase.apps.isEmpty) {
      return PokoinApiAuthService();
    }
    final defaultAuth = FirebaseAuth.instance;
    return _instances.putIfAbsent(
      defaultAuth,
      () => PokoinApiAuthService(auth: defaultAuth),
    );
  }

  final FirebaseAuth? _providedAuth;
  StreamSubscription<User?>? _idTokenSubscription;

  FirebaseAuth get _auth {
    if (Firebase.apps.isEmpty) {
      throw StateError('Firebase is not initialized yet.');
    }
    return _providedAuth ?? FirebaseAuth.instance;
  }

  Future<void> initialize() async {
    if (Firebase.apps.isEmpty || _idTokenSubscription != null) {
      return;
    }
    _idTokenSubscription = _auth.idTokenChanges().listen((user) {
      if (user == null) {
        unawaited(clearCachedToken());
      } else {
        unawaited(_cacheCurrentUserToken(user));
      }
    });
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      await clearCachedToken();
    } else {
      await _cacheCurrentUserToken(currentUser);
    }
  }

  Future<PokoinAuthToken?> currentToken({bool forceRefresh = false}) async {
    if (Firebase.apps.isEmpty) {
      return null;
    }
    final user = _auth.currentUser;
    if (user == null) {
      await clearCachedToken();
      return null;
    }
    final token = await user.getIdToken(forceRefresh);
    if (token == null || token.isEmpty) {
      await clearCachedToken();
      return null;
    }
    await _cacheToken(user.uid, token);
    return PokoinAuthToken(
      accessToken: token,
      tokenType: 'Bearer',
      uid: user.uid,
      email: user.email,
    );
  }

  Future<String?> bearerToken({bool forceRefresh = false}) async {
    final token = await currentToken(forceRefresh: forceRefresh);
    return token?.accessToken;
  }

  Future<Map<String, String>> authorizationHeaders({
    bool forceRefresh = false,
    bool requireSignedIn = true,
  }) async {
    final token = await bearerToken(forceRefresh: forceRefresh);
    if (token == null || token.isEmpty) {
      if (requireSignedIn) {
        throw StateError('Sign in before calling the Pokoin API.');
      }
      return const {};
    }
    return {'Authorization': 'Bearer $token'};
  }

  Future<void> clearCachedToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(bearerTokenCacheKey);
    await prefs.remove(bearerUidCacheKey);
  }

  Future<void> dispose() async {
    await _idTokenSubscription?.cancel();
    _idTokenSubscription = null;
  }

  Future<void> _cacheCurrentUserToken(User user) async {
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      await clearCachedToken();
      return;
    }
    await _cacheToken(user.uid, token);
  }

  Future<void> _cacheToken(String uid, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(bearerTokenCacheKey, token);
    await prefs.setString(bearerUidCacheKey, uid);
  }
}
