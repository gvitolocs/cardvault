import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

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
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await ensureUserProfile(credential.user);
    await _markFreshLogin(credential.user);
    return credential;
  }

  Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    if (displayName.trim().isNotEmpty) {
      await credential.user?.updateDisplayName(displayName.trim());
      await credential.user?.reload();
    }
    await ensureUserProfile(_auth.currentUser ?? credential.user);
    await _markFreshLogin(_auth.currentUser ?? credential.user);
    return credential;
  }

  Future<UserCredential> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..setCustomParameters(<String, String>{
          'prompt': 'select_account',
        });
      final credential = await _auth.signInWithPopup(provider);
      await ensureUserProfile(credential.user);
      await _markFreshLogin(credential.user);
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
    return userCredential;
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

  Stream<int> balanceStream(String uid) {
    return _firestore.collection('balances').doc(uid).snapshots().map((doc) {
      final data = doc.data();
      return data?['availablePkn'] as int? ?? 0;
    });
  }

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
        'photoUrl': user.photoURL,
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
  }

  Future<void> requestWithdraw({
    required String uid,
    required String toAddress,
    required int amountPkn,
  }) async {
    final address = toAddress.trim();
    if (!RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(address)) {
      throw ArgumentError('Enter a valid 0x payout address.');
    }
    if (amountPkn <= 0) {
      throw ArgumentError('Withdraw amount must be greater than zero.');
    }

    await _firestore.collection('withdraw_requests').add({
      'uid': uid,
      'toAddress': address,
      'amountPkn': amountPkn,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
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

  Future<void> updateDisplayName({
    required String uid,
    required String displayName,
  }) async {
    final name = displayName.trim();
    if (name.length < 2) {
      throw ArgumentError('Display name must be at least 2 characters.');
    }

    await _auth.currentUser?.updateDisplayName(name);
    await _firestore.collection('users').doc(uid).set(
      {
        'displayName': name,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> updatePhotoUrl({
    required String uid,
    required String photoUrl,
  }) async {
    final url = photoUrl.trim();
    if (url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasAbsolutePath || !uri.isScheme('https')) {
        throw ArgumentError('Enter a valid https image URL.');
      }
    }

    await _auth.currentUser?.updatePhotoURL(url.isEmpty ? null : url);
    await _firestore.collection('users').doc(uid).set(
      {
        'photoUrl': url.isEmpty ? null : url,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
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
