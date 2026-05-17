import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../models/app_user_profile.dart';

class AuthService {
  static const inactivityLogoutAfter = Duration(days: 30);

  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn? googleSignIn,
  })  : _providedAuth = auth,
        _providedFirestore = firestore,
        _providedGoogleSignIn = googleSignIn;

  final FirebaseAuth? _providedAuth;
  final FirebaseFirestore? _providedFirestore;
  final GoogleSignIn? _providedGoogleSignIn;

  GoogleSignIn get _googleSignIn => _providedGoogleSignIn ?? GoogleSignIn();

  FirebaseAuth get _auth {
    if (Firebase.apps.isEmpty) {
      throw StateError('Firebase is not initialized yet.');
    }
    return _providedAuth ?? FirebaseAuth.instance;
  }

  FirebaseFirestore get _firestore {
    if (Firebase.apps.isEmpty) {
      throw StateError('Firebase is not initialized yet.');
    }
    return _providedFirestore ?? FirebaseFirestore.instance;
  }

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Set<String> get currentProviderIds {
    final user = _auth.currentUser;
    if (user == null) {
      return const <String>{};
    }
    return user.providerData.map((info) => info.providerId).toSet();
  }

  Future<void> initializeSession() async {
    if (kIsWeb) {
      await _auth.setPersistence(Persistence.LOCAL);
    }

    final user = _auth.currentUser;
    if (user != null) {
      final shouldLogout = await _isInactivePastLimit(user.uid);
      if (shouldLogout) {
        await signOut();
        return;
      }
      await _touchUserSession(user);
    }
  }

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (kIsWeb) {
      await _auth.setPersistence(Persistence.LOCAL);
    }
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await ensureUserProfile(credential.user);
    await _markFreshLogin(credential.user);
    return credential;
  }

  Future<void> registerWithEmail({
    required String email,
    required String password,
    required String username,
    required String redirectPath,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanUsername = username.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9]{3,32}$').hasMatch(cleanUsername)) {
      throw ArgumentError(
        'Username must be 3-32 letters or numbers, with no spaces.',
      );
    }
    if (kIsWeb) {
      await _auth.setPersistence(Persistence.LOCAL);
    }
    final response = await http.post(
      Uri.parse('/api/register-email'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': cleanEmail,
        'password': password,
        'username': cleanUsername,
        'redirectPath': redirectPath,
      }),
    );
    final payload = _decodeJsonResponse(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(payload['error'] as String? ?? 'Registration failed.');
    }
  }

  Future<String> verifyEmailSignupToken(String signupToken) async {
    if (kIsWeb) {
      await _auth.setPersistence(Persistence.LOCAL);
    }
    final response = await http.post(
      Uri.parse('/api/verify-email-signup'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'token': signupToken.trim()}),
    );
    final payload = _decodeJsonResponse(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(payload['error'] as String? ?? 'Email verification failed.');
    }
    final token = payload['customToken'] as String? ?? '';
    if (token.isEmpty) {
      throw StateError('Email verification did not return a login token.');
    }
    final credential = await _auth.signInWithCustomToken(token);
    await credential.user?.reload();
    await ensureUserProfile(_auth.currentUser ?? credential.user);
    await _markFreshLogin(_auth.currentUser ?? credential.user);
    final redirectPath = payload['redirectPath'] as String? ?? '/';
    return redirectPath.startsWith('/') ? redirectPath : '/';
  }

  Future<UserCredential> signInWithGoogle() async {
    if (kIsWeb) {
      await _auth.setPersistence(Persistence.LOCAL);
      final provider = GoogleAuthProvider()
        ..setCustomParameters(<String, String>{
          'prompt': 'select_account',
        });
      final credential = await _auth.signInWithPopup(provider);
      await ensureUserProfile(credential.user);
      await _markFreshLogin(credential.user);
      if (credential.additionalUserInfo?.isNewUser == true) {
        await sendSignupNotification(provider: 'google');
      }
      return credential;
    }

    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw FirebaseAuthException(
        code: 'popup-closed-by-user',
        message: 'Google sign-in was cancelled.',
      );
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final userCredential = await _auth.signInWithCredential(credential);
    await ensureUserProfile(userCredential.user);
    await _markFreshLogin(userCredential.user);
    if (userCredential.additionalUserInfo?.isNewUser == true) {
      await sendSignupNotification(provider: 'google');
    }
    return userCredential;
  }

  Map<String, dynamic> _decodeJsonResponse(String body) {
    if (body.trim().isEmpty) {
      return <String, dynamic>{'error': 'Server returned an empty response.'};
    }
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{'error': 'Server returned an invalid response.'};
  }

  Future<void> sendSignupNotification({required String provider}) async {
    final user = _auth.currentUser;
    if (user == null) {
      return;
    }
    final token = await user.getIdToken();
    final response = await http.post(
      Uri.parse('/api/signup-notification'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'provider': provider}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint('Signup notification failed: ${response.body}');
    }
  }

  Future<UserCredential> linkGoogleToCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Log in before connecting Google.');
    }

    UserCredential credential;
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..setCustomParameters(<String, String>{
          'prompt': 'select_account',
        });
      credential = await user.linkWithPopup(provider);
    } else {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw FirebaseAuthException(
          code: 'popup-closed-by-user',
          message: 'Google sign-in was cancelled.',
        );
      }
      final googleAuth = await googleUser.authentication;
      final googleCredential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      credential = await user.linkWithCredential(googleCredential);
    }

    await credential.user?.reload();
    final refreshed = _auth.currentUser ?? credential.user;
    await ensureUserProfile(refreshed);
    await _markFreshLogin(refreshed);
    return credential;
  }

  Future<void> setEmailPassword({
    required String email,
    required String password,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Log in before updating email/password.');
    }
    final cleanEmail = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(cleanEmail)) {
      throw ArgumentError('Enter a valid email address.');
    }
    if (password.length < 6) {
      throw ArgumentError('Password must be at least 6 characters.');
    }

    final hasPasswordProvider =
        user.providerData.any((info) => info.providerId == 'password');
    final currentEmail = (user.email ?? '').trim().toLowerCase();
    if (currentEmail.isNotEmpty) {
      if (currentEmail != cleanEmail) {
        await user.verifyBeforeUpdateEmail(cleanEmail);
      }
      await user.updatePassword(password);
    } else if (!hasPasswordProvider) {
      final credential = EmailAuthProvider.credential(
        email: cleanEmail,
        password: password,
      );
      await user.linkWithCredential(credential);
    } else {
      await user.updatePassword(password);
    }

    await user.reload();
    final refreshed = _auth.currentUser ?? user;
    await ensureUserProfile(refreshed);
    await _markFreshLogin(refreshed);
  }

  Future<void> signOut() async {
    await Future.wait([
      _auth.signOut(),
      _googleSignIn.signOut(),
    ]);
  }

  Stream<AppUserProfile?> profileStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }
      return AppUserProfile.fromFirestore(snapshot);
    });
  }

  Stream<int> balanceStream(String uid) async* {
    final cached = await cachedBalance(uid);
    if (cached != null) {
      yield cached;
    }

    yield* _firestore.collection('balances').doc(uid).snapshots().map((doc) {
      final data = doc.data();
      final balance = (data?['availablePkn'] as num?)?.toInt() ?? 0;
      _cacheBalance(uid, balance);
      return balance;
    });
  }

  Future<int?> cachedBalance(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_balanceCacheKey(uid));
  }

  Future<void> _cacheBalance(String uid, int balance) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_balanceCacheKey(uid), balance);
  }

  String _balanceCacheKey(String uid) => 'pokoin_account_balance:$uid';

  Future<void> ensureUserProfile(User? user) async {
    if (user == null) {
      return;
    }

    final userRef = _firestore.collection('users').doc(user.uid);
    final balanceRef = _firestore.collection('balances').doc(user.uid);
    final now = FieldValue.serverTimestamp();

    await _firestore.runTransaction((transaction) async {
      final userDoc = await transaction.get(userRef);
      final balanceDoc = await transaction.get(balanceRef);

      final profileData = <String, dynamic>{
        'email': user.email ?? '',
        'displayName':
            user.displayName ?? user.email?.split('@').first ?? 'Pokoin user',
        'updatedAt': now,
      };

      if (userDoc.exists) {
        transaction.set(userRef, profileData, SetOptions(merge: true));
      } else {
        transaction.set(userRef, {
          ...profileData,
          'walletAddress': null,
          'createdAt': now,
        });
      }

      if (!balanceDoc.exists) {
        transaction.set(balanceRef, {
          'availablePkn': 0,
          'lockedPkn': 0,
          'updatedAt': now,
        });
      }
    });
    await ensureUsername();
  }

  Future<String?> ensureUsername() async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }
    final token = await user.getIdToken();
    final response = await http.post(
      Uri.parse('/api/ensure-username'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(payload['error'] as String? ?? 'Username setup failed.');
    }
    return payload['username'] as String?;
  }

  Future<Map<String, dynamic>> requestWithdraw({
    required String toAddress,
    required int amountPkn,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Log in before requesting a withdraw.');
    }
    final address = toAddress.trim();
    if (!RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(address)) {
      throw ArgumentError('Enter a valid 0x payout address.');
    }
    if (amountPkn <= 0) {
      throw ArgumentError('Withdraw amount must be greater than zero.');
    }

    final token = await user.getIdToken();
    final response = await http.post(
      Uri.parse('/api/request-pkn-withdraw'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'toAddress': address, 'amountPkn': amountPkn}),
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(payload['error'] as String? ?? 'Withdraw request failed.');
    }
    return payload;
  }

  Future<Map<String, dynamic>> requestWalletNonce(String address) async {
    final response = await http.post(
      Uri.parse('/api/wallet-auth/nonce'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'address': address.trim().toLowerCase()}),
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(payload['error'] as String? ?? 'Wallet nonce failed.');
    }
    return payload;
  }

  Future<Map<String, dynamic>> verifyWalletSignature({
    required String address,
    required String signature,
  }) async {
    final response = await http.post(
      Uri.parse('/api/wallet-auth/verify'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'address': address.trim().toLowerCase(),
        'signature': signature,
      }),
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        payload['error'] as String? ?? 'Wallet verification failed.',
      );
    }
    return payload;
  }

  Future<void> signInWithCustomToken(String customToken) async {
    if (kIsWeb) {
      await _auth.setPersistence(Persistence.LOCAL);
    }
    final credential = await _auth.signInWithCustomToken(customToken);
    await ensureUserProfile(credential.user);
    await _markFreshLogin(credential.user);
  }

  Future<Map<String, dynamic>> linkSignedWallet({
    required String address,
    required String signature,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Log in before connecting a wallet.');
    }
    final token = await user.getIdToken();
    final response = await http.post(
      Uri.parse('/api/wallet-link'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'address': address.trim().toLowerCase(),
        'signature': signature,
      }),
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(payload['error'] as String? ?? 'Wallet link failed.');
    }
    return payload;
  }

  Future<void> updateWalletAddress({
    required String uid,
    required String walletAddress,
  }) async {
    final address = walletAddress.trim();
    if (address.isNotEmpty &&
        !RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(address)) {
      throw ArgumentError('Enter a valid 0x wallet address.');
    }

    await _firestore.collection('users').doc(uid).set(
      {
        'walletAddress': address.isEmpty ? null : address,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    final user = _auth.currentUser;
    final email = (user?.email ?? '').trim().toLowerCase();
    if (email.isNotEmpty && address.isNotEmpty) {
      await _firestore.collection('email_wallets').doc(email).set(
        {
          'uid': uid,
          'email': email,
          'address': address.toLowerCase(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
  }

  Future<String> updateUsername({required String username}) async {
    final clean = username.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9]{3,32}$').hasMatch(clean)) {
      throw ArgumentError(
        'Username must be 3-32 letters or numbers, with no spaces.',
      );
    }
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Log in before updating your username.');
    }
    final token = await user.getIdToken();
    final response = await http.post(
      Uri.parse('/api/ensure-username'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'username': clean}),
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
          payload['error'] as String? ?? 'Username update failed.');
    }
    return payload['username'] as String? ?? clean;
  }

  Future<String> uploadProfilePicture({
    required Uint8List imageBytes,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign in before updating your profile picture.');
    }
    final token = await user.getIdToken();
    final response = await http.post(
      Uri.parse('/api/upload-profile-picture'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'imageBase64': base64Encode(imageBytes)}),
    );
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
          payload['error'] as String? ?? 'Profile picture upload failed.');
    }
    final photoUrl = payload['photoUrl'] as String? ?? '';
    return photoUrl;
  }

  Future<void> removeProfilePicture() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign in before updating your profile picture.');
    }
    final token = await user.getIdToken();
    final response = await http.post(
      Uri.parse('/api/remove-profile-picture'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      throw StateError(
          payload['error'] as String? ?? 'Profile picture removal failed.');
    }
  }

  Future<bool> _isInactivePastLimit(String uid) async {
    final snapshot = await _firestore.collection('users').doc(uid).get();
    final data = snapshot.data();
    final lastSeen = _readTimestamp(data?['lastSeenAt']) ??
        _readTimestamp(data?['lastLoginAt']) ??
        _readTimestamp(data?['updatedAt']);

    if (lastSeen == null) {
      return false;
    }
    return DateTime.now().difference(lastSeen) > inactivityLogoutAfter;
  }

  Future<void> _markFreshLogin(User? user) async {
    if (user == null) {
      return;
    }
    final now = FieldValue.serverTimestamp();
    await _firestore.collection('users').doc(user.uid).set(
      {
        'lastLoginAt': now,
        'lastSeenAt': now,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _touchUserSession(User user) async {
    await _firestore.collection('users').doc(user.uid).set(
      {
        'lastSeenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  DateTime? _readTimestamp(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
