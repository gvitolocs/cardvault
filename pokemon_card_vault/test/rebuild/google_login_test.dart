import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pokoin/rebuild/controller/account_controller.dart';
import 'package:pokoin/rebuild/main_mobile_prototype.dart';
import 'package:pokoin/rebuild/model/account.dart';
import 'package:pokoin/rebuild/presentation/account/account_screen.dart';
import 'package:pokoin/rebuild/presentation/marketplace/marketplace_screen.dart';
import 'package:pokoin/rebuild/provider/account_provider.dart';
import 'package:pokoin/rebuild/service/account_service.dart';
import 'account_test.dart' show FirebaseAuthSource, FirebaseCredential;
import 'fixtures/account_fixtures.dart';

class GoogleTokens extends Fake implements GoogleSignInAuthentication {
  GoogleTokens({this.token = 'test-id-token'});
  final String? token;
  @override
  String? get idToken => token;
  @override
  String? get accessToken => 'test-access-token';
}

class GoogleAccount extends Fake implements GoogleSignInAccount {
  GoogleAccount({this.token = 'test-id-token'});
  final String? token;
  @override
  Future<GoogleSignInAuthentication> get authentication async =>
      GoogleTokens(token: token);
}

class GoogleClient extends Fake implements GoogleSignIn {
  GoogleSignInAccount? selected = GoogleAccount();
  Object? failure;
  int selections = 0, signOuts = 0;
  @override
  Future<GoogleSignInAccount?> signIn() async {
    ++selections;
    if (failure != null) throw failure!;
    return selected;
  }

  @override
  Future<GoogleSignInAccount?> signOut() async {
    ++signOuts;
    return null;
  }
}

class CredentialAuth extends FirebaseAuthSource {
  AuthCredential? credential;
  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    if (failure != null) throw failure!;
    this.credential = credential;
    return FirebaseCredential();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'native Google token becomes a Firebase credential and both sessions sign out',
      () async {
    final google = GoogleClient();
    final firebase = CredentialAuth();
    final provider = AccountProvider(auth: firebase, googleSignIn: google);
    expect(AccountProvider.googleServerClientId,
        endsWith('.apps.googleusercontent.com'));
    expect(await provider.signInWithGoogle(), isTrue);
    expect(google.selections, 1);
    expect(firebase.credential!.providerId, 'google.com');
    expect((firebase.credential! as OAuthCredential).idToken, 'test-id-token');
    await provider.signOut();
    expect(firebase.signedOut, isTrue);
    expect(google.signOuts, 1);
  });

  test('cancelled chooser does not authenticate Firebase', () async {
    final firebase = CredentialAuth();
    final google = GoogleClient()..selected = null;
    final provider = AccountProvider(auth: firebase, googleSignIn: google);
    expect(await provider.signInWithGoogle(), isFalse);
    expect(firebase.credential, isNull);
    google.failure = PlatformException(code: 'sign_in_canceled');
    expect(await provider.signInWithGoogle(), isFalse);
    expect(firebase.credential, isNull);
  });

  test('missing token and Android developer errors give configuration feedback',
      () async {
    final firebase = CredentialAuth();
    final google = GoogleClient()..selected = GoogleAccount(token: null);
    final provider = AccountProvider(auth: firebase, googleSignIn: google);
    final configurationError = isA<AccountFailure>()
        .having((failure) => failure.code, 'code', 'google-configuration');
    await expectLater(provider.signInWithGoogle(), throwsA(configurationError));
    google.failure = PlatformException(
        code: 'sign_in_failed',
        message: 'com.google.android.gms.common.api.ApiException: 10:');
    await expectLater(provider.signInWithGoogle(), throwsA(configurationError));
    expect(firebase.credential, isNull);
  });

  test('Google network and Firebase failures are typed without exposing tokens',
      () async {
    final google = GoogleClient()
      ..failure = PlatformException(code: 'network_error');
    final firebase = CredentialAuth();
    final provider = AccountProvider(auth: firebase, googleSignIn: google);
    await expectLater(
        provider.signInWithGoogle(),
        throwsA(isA<AccountFailure>().having(
            (failure) => failure.code, 'code', 'network-request-failed')));
    google.failure = null;
    firebase.failure =
        FirebaseAuthException(code: 'account-exists-with-different-credential');
    await expectLater(
        provider.signInWithGoogle(),
        throwsA(isA<AccountFailure>().having((failure) => failure.code, 'code',
            'account-exists-with-different-credential')));
  });

  test('Google success replaces guest; cancellation keeps guest choice',
      () async {
    final provider = FakeAccountProvider(guest: true)..googleCancelled = true;
    final account =
        AccountController(service: AccountService(provider: provider))
          ..initialize();
    await Future<void>.delayed(Duration.zero);
    expect(await account.signInWithGoogle(), isFalse);
    expect(account.error, isNull);
    expect(account.session.status, AccountStatus.guest);
    expect(provider.guest, isTrue);
    provider.googleCancelled = false;
    expect(await account.signInWithGoogle(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(account.session.user!.id, 'alice');
    expect(provider.guest, isFalse);
    expect(provider.loginCalls, 0);
    account.dispose();
    await provider.close();
  });

  testWidgets(
      'Google button signs in without email or password and prevents duplicate requests',
      (tester) async {
    final provider = FakeAccountProvider()..googlePending = Completer<void>();
    await tester.pumpWidget(MobileMarketplacePrototypeApp(
        showDiscovery: false,
        accountService: AccountService(provider: provider)));
    await tester.pumpAndSettle();
    expect(find.byType(AccountScreen), findsOneWidget);
    await tester.tap(find.text('Continua con Google'));
    await tester.pump();
    expect(provider.googleCalls, 1);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Continua con Google'))
            .onPressed,
        isNull);
    provider.googlePending!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AccountScreen), findsNothing);
    expect(find.byType(MarketplaceScreen), findsOneWidget);
    expect(provider.submittedPassword, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await provider.close();
  });
}
