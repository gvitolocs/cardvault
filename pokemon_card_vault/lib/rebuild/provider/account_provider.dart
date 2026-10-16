import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../firebase_options.dart';
import '../model/account.dart';

/// Firebase gestisce credenziali e rinnovo della sessione. Nei prefs solo
/// la scelta Ospite; nessuna password o copia dei token viene memorizzata qui.
class AccountProvider {
  AccountProvider({FirebaseAuth? auth, GoogleSignIn? googleSignIn})
      : _providedAuth = auth,
        _providedGoogle = googleSignIn;
  final FirebaseAuth? _providedAuth;
  final GoogleSignIn? _providedGoogle;
  // OAuth web client pubblico del progetto Pokoin. Corrisponde al client
  // type 3 dell'app Android in android/app/google-services.json, non al client
  // OAuth Android (type 1) né ai client di appinvite_service.
  static const googleServerClientId = String.fromEnvironment(
      'GOOGLE_SERVER_CLIENT_ID',
      defaultValue:
          '36941064114-t9tcju3rjaesd8q6nkttm36ver3qaktb.apps.googleusercontent.com');
  late final GoogleSignIn _google = _providedGoogle ??
      GoogleSignIn(
          serverClientId: googleServerClientId, scopes: const ['email']);
  FirebaseAuth get _auth => _providedAuth ?? FirebaseAuth.instance;
  Future<void>? _initializing;
  static const guestKey = 'pokoin_rebuild_guest_v1';

  Future<void> initialize() =>
      _initializing ??= _initialize().catchError((Object error) {
        _initializing = null;
        throw error;
      });

  Future<void> _initialize() async {
    if (_providedAuth == null && Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
              options: DefaultFirebaseOptions.currentPlatform)
          .timeout(const Duration(seconds: 12));
    }
    if (kIsWeb) await _auth.setPersistence(Persistence.LOCAL);
  }

  Stream<AccountUser?> watchUser() => _auth.userChanges().map((user) =>
      user == null
          ? null
          : AccountUser(
              id: user.uid,
              email: user.email ?? '',
              displayName: user.displayName ?? '',
              emailVerified: user.emailVerified));

  Future<bool> readGuestMode() async =>
      (await SharedPreferences.getInstance()).getBool(guestKey) ?? false;
  Future<void> saveGuestMode(bool enabled) async {
    await (await SharedPreferences.getInstance()).setBool(guestKey, enabled);
  }

  Future<void> signIn(String email, String password) => _translate(() async {
        await initialize();
        await _auth.signInWithEmailAndPassword(
            email: email, password: password);
      });
  Future<bool> signInWithGoogle() async {
    try {
      await initialize();
      if (kIsWeb) {
        await _auth.signInWithPopup(GoogleAuthProvider()
          ..setCustomParameters({'prompt': 'select_account'}));
      } else {
        final account = await _google.signIn();
        if (account == null) return false;
        final tokens = await account.authentication;
        if (tokens.idToken == null || tokens.idToken!.isEmpty) {
          throw const AccountFailure('google-configuration');
        }
        await _auth.signInWithCredential(GoogleAuthProvider.credential(
            idToken: tokens.idToken, accessToken: tokens.accessToken));
      }
      return true;
    } on FirebaseAuthException catch (error) {
      if (const [
        'popup-closed-by-user',
        'cancelled-popup-request',
        'web-context-cancelled'
      ].contains(error.code)) {
        return false;
      }
      throw AccountFailure(error.code);
    } on PlatformException catch (error) {
      if (const ['sign_in_canceled', 'sign_in_cancelled', 'canceled']
          .contains(error.code)) {
        return false;
      }
      final detail = error.message ?? '';
      if (RegExp(r'ApiException:\s*10(?:\D|$)').hasMatch(detail) ||
          detail.contains('DEVELOPER_ERROR')) {
        throw const AccountFailure('google-configuration');
      }
      if (error.code == 'network_error' ||
          detail.contains('ApiException: 7:')) {
        throw const AccountFailure('network-request-failed');
      }
      throw const AccountFailure('google-sign-in-failed');
    }
  }

  Future<void> signOut() => _translate(() async {
        await _auth.signOut();
        // Uscire da Firebase resta determinante anche se Google non è disponibile.
        if (!kIsWeb &&
            (_providedGoogle != null ||
                const [
                  TargetPlatform.android,
                  TargetPlatform.iOS,
                  TargetPlatform.macOS
                ].contains(defaultTargetPlatform))) {
          try {
            await _google.signOut();
          } catch (_) {/* Firebase è già disconnesso. */}
        }
      });
  Future<void> resetPassword(String email) => _translate(() async {
        await initialize();
        await _auth.sendPasswordResetEmail(email: email);
      });

  Future<void> _translate(Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseAuthException catch (error) {
      throw AccountFailure(error.code);
    }
  }
}
