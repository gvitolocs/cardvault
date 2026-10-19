import 'fixtures/cart_fixtures.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pokoin/rebuild/controller/account_controller.dart';
import 'package:pokoin/rebuild/controller/profile_controller.dart';
import 'package:pokoin/rebuild/main_mobile_prototype.dart';
import 'package:pokoin/rebuild/model/account.dart';
import 'package:pokoin/rebuild/presentation/account/account_screen.dart';
import 'package:pokoin/rebuild/presentation/marketplace/marketplace_screen.dart';
import 'package:pokoin/rebuild/presentation/profile/component/wallet_overview.dart';
import 'package:pokoin/rebuild/provider/account_provider.dart';
import 'package:pokoin/rebuild/provider/profile_provider.dart';
import 'package:pokoin/rebuild/service/account_service.dart';
import 'package:pokoin/rebuild/service/profile_service.dart';
import 'fixtures/account_fixtures.dart';

const alice =
    AccountUser(id: 'alice', email: 'alice@example.test', displayName: 'Alice');
const bob =
    AccountUser(id: 'bob', email: 'bob@example.test', displayName: 'Bob');
Future<void> flush() => Future<void>.delayed(Duration.zero);

class ProfileSource extends ProfileProvider {
  final profiles = <String, StreamController<AccountProfile>>{};
  final balances = <String, StreamController<AccountBalance>>{};
  final orders = <String, StreamController<List<AccountOrder>>>{};
  final favorites = <String, StreamController<List<String>>>{};
  String? savedUid, savedName;
  @override
  Stream<AccountProfile> watchProfile(String uid) => profiles
      .putIfAbsent(uid, () => StreamController<AccountProfile>.broadcast())
      .stream;
  @override
  Stream<AccountBalance> watchBalance(String uid) => balances
      .putIfAbsent(uid, () => StreamController<AccountBalance>.broadcast())
      .stream;
  @override
  Stream<List<AccountOrder>> watchOrders(String uid) => orders
      .putIfAbsent(uid, () => StreamController<List<AccountOrder>>.broadcast())
      .stream;
  @override
  Stream<List<String>> watchFavorites(String uid) => favorites
      .putIfAbsent(uid, () => StreamController<List<String>>.broadcast())
      .stream;
  @override
  Future<void> updateDisplayName(String uid, String name) async {
    savedUid = uid;
    savedName = name;
  }

  Future<void> close() async {
    for (final stream in [
      ...profiles.values,
      ...balances.values,
      ...orders.values,
      ...favorites.values
    ]) {
      await stream.close();
    }
  }
}

class FirebaseUser extends Fake implements User {
  @override
  String get uid => 'firebase-user';
  @override
  String? get email => 'firebase@example.test';
  @override
  String? get displayName => 'Firebase';
  @override
  bool get emailVerified => true;
}

class FirebaseCredential extends Fake implements UserCredential {}

class FirebaseAuthSource extends Fake implements FirebaseAuth {
  String? email, password;
  bool signedOut = false;
  Object? failure;
  @override
  Stream<User?> userChanges() => Stream.value(FirebaseUser());
  @override
  Future<UserCredential> signInWithEmailAndPassword(
      {required String email, required String password}) async {
    this.email = email;
    this.password = password;
    if (failure != null) throw failure!;
    return FirebaseCredential();
  }

  @override
  Future<void> signOut() async {
    signedOut = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Firebase DAO delegates authentication and translates Firebase errors',
      () async {
    final firebase = FirebaseAuthSource();
    final provider = AccountProvider(auth: firebase);
    await provider.initialize();
    await provider.signIn('firebase@example.test', ' not-trimmed ');
    expect(firebase.email, 'firebase@example.test');
    expect(firebase.password, ' not-trimmed ');
    final user = await provider.watchUser().first;
    expect(user!.id, 'firebase-user');
    expect(user.emailVerified, isTrue);
    firebase.failure = FirebaseAuthException(code: 'invalid-credential');
    await expectLater(
        provider.signIn('firebase@example.test', 'bad'),
        throwsA(isA<AccountFailure>()
            .having((failure) => failure.code, 'code', 'invalid-credential')));
    await provider.signOut();
    expect(firebase.signedOut, isTrue);
  });

  test('only guest preference is stored and survives a new provider', () async {
    SharedPreferences.setMockInitialValues({});
    await AccountProvider().saveGuestMode(true);
    expect(await AccountProvider().readGuestMode(), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {AccountProvider.guestKey});
    await AccountProvider().saveGuestMode(false);
    expect(await AccountProvider().readGuestMode(), isFalse);
  });

  test(
      'restores Firebase user before showing login, even with saved guest preference',
      () async {
    final provider = FakeAccountProvider(guest: true, user: alice);
    final account =
        AccountController(service: AccountService(provider: provider));
    account.initialize();
    expect(account.session.status, AccountStatus.restoring);
    await flush();
    expect(account.session.user!.id, 'alice');
    expect(account.session.status, AccountStatus.authenticated);
    account.dispose();
    await provider.close();
  });

  test('validates login, preserves password, handles failure and signout',
      () async {
    final provider = FakeAccountProvider();
    final account =
        AccountController(service: AccountService(provider: provider))
          ..initialize();
    await flush();
    expect(await account.signIn('broken', 'password'), isFalse);
    expect(provider.loginCalls, 0);
    provider.loginError = const AccountFailure('invalid-credential');
    expect(await account.signIn(' alice@example.test ', ' wrong '), isFalse);
    expect(account.error, 'Email o password non corrette.');
    provider.loginError = null;
    expect(await account.signIn(' alice@example.test ', ' correct '), isTrue);
    await flush();
    expect(provider.submittedEmail, 'alice@example.test');
    expect(provider.submittedPassword, ' correct ');
    expect(account.session.user!.id, 'alice');
    expect(provider.guest, isFalse);
    await account.signOut();
    await flush();
    expect(account.session.status, AccountStatus.signedOut);
    expect(account.session.user, isNull);
    account.dispose();
    await provider.close();
  });

  test(
      'guest works while restore is pending and after Firebase initialization fails',
      () async {
    final provider = FakeAccountProvider()..bootstrap = Completer<void>();
    final account =
        AccountController(service: AccountService(provider: provider))
          ..initialize();
    expect(await account.continueAsGuest(), isTrue);
    expect(account.session.status, AccountStatus.guest);
    provider.initializationError = StateError('Firebase unavailable');
    provider.bootstrap!.complete();
    await flush();
    expect(account.session.status, AccountStatus.guest);
    // A later login must reopen the auth listener after bootstrap terminated.
    provider.initializationError = null;
    expect(await account.signIn('alice@example.test', 'password'), isTrue);
    await flush();
    expect(account.session.user!.id, 'alice');
    account.dispose();
    await provider.close();
  });

  test('profile cancels old-user streams and clears balances on signout',
      () async {
    final source = FakeAccountProvider(user: alice);
    final account = AccountController(service: AccountService(provider: source))
      ..initialize();
    await flush();
    final data = ProfileSource();
    final profile = ProfileController(
        account: account, service: ProfileService(provider: data))
      ..start();
    data.profiles['alice']!.add(const AccountProfile(
        displayName: 'Alice', walletAddress: 'wallet-alice'));
    data.balances['alice']!
        .add(const AccountBalance(available: 100, locked: 5));
    await flush();
    expect(profile.balance!.available, 100);
    source.emit(bob);
    await flush();
    expect(profile.balance, isNull);
    expect(profile.profile, isNull);
    expect(data.balances['alice']!.hasListener, isFalse);
    data.balances['alice']!
        .add(const AccountBalance(available: 999, locked: 0));
    data.balances['bob']!.addError(StateError('offline'));
    await flush();
    expect(profile.balance, isNull);
    expect(profile.errors, contains('balance'));
    expect(await profile.saveName('  Bob Collector  '), isTrue);
    expect(data.savedUid, 'bob');
    expect(data.savedName, 'Bob Collector');
    await account.signOut();
    await flush();
    expect(profile.errors, isEmpty);
    expect(profile.balance, isNull);
    expect(profile.orders, isNull);
    expect(data.balances['bob']!.hasListener, isFalse);
    profile.dispose();
    account.dispose();
    await source.close();
    await data.close();
  });

  test('password reset validates email and exposes generic confirmation',
      () async {
    final provider = FakeAccountProvider();
    final account =
        AccountController(service: AccountService(provider: provider))
          ..initialize();
    await flush();
    expect(await account.resetPassword('invalid'), isFalse);
    expect(provider.resetEmail, isNull);
    expect(await account.resetPassword(' alice@example.test '), isTrue);
    expect(provider.resetEmail, 'alice@example.test');
    expect(
        account.message, contains('Se l’indirizzo è associato a un account'));
    account.dispose();
    await provider.close();
  });

  testWidgets('restored user enters the app without showing the login form',
      (tester) async {
    final provider = FakeAccountProvider(user: alice);
    await tester.pumpWidget(MobileMarketplacePrototypeApp(
        cartService: memoryCartService(),
        showDiscovery: false,
        accountService: AccountService(provider: provider)));
    await tester.pumpAndSettle();
    expect(find.byType(AccountScreen), findsNothing);
    expect(find.byType(MarketplaceScreen), findsOneWidget);
    final market =
        tester.widget<MarketplaceScreen>(find.byType(MarketplaceScreen));
    expect(market.controller.account.session.user!.id, 'alice');
    await tester.pumpWidget(const SizedBox.shrink());
    await provider.close();
  });

  for (final width in [320.0, 390.0]) {
    testWidgets(
        'initial login and guest entry fit ${width}px with enlarged text',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = FakeAccountProvider();
      final account =
          AccountController(service: AccountService(provider: provider))
            ..initialize();
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 844),
                  textScaler: const TextScaler.linear(2)),
              child: AccountScreen(controller: account))));
      await tester.pumpAndSettle();
      expect(find.text('Accedi a Pokoin'), findsOneWidget);
      final guest = find.text('Continua come ospite');
      await tester.ensureVisible(guest);
      await tester.tap(guest);
      await tester.pumpAndSettle();
      expect(account.session.status, AccountStatus.guest);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      account.dispose();
      await provider.close();
    });
  }

  testWidgets(
      'app shows first login, guest profile, then login and removes private routes on logout',
      (tester) async {
    final provider = FakeAccountProvider();
    final profileData = ProfileSource();
    await tester.pumpWidget(MobileMarketplacePrototypeApp(
        cartService: memoryCartService(),
        showDiscovery: false,
        accountService: AccountService(provider: provider),
        profileService: ProfileService(provider: profileData)));
    await tester.pumpAndSettle();
    expect(find.byType(AccountScreen), findsOneWidget);
    expect(find.byType(MarketplaceScreen), findsNothing);
    await tester.ensureVisible(find.text('Continua come ospite'));
    await tester.tap(find.text('Continua come ospite'));
    await tester.pumpAndSettle();
    expect(find.byType(MarketplaceScreen), findsOneWidget);
    final market =
        tester.widget<MarketplaceScreen>(find.byType(MarketplaceScreen));
    await tester.tap(find.text('Profilo'));
    await tester.pumpAndSettle();
    expect(find.text('Modalità Ospite'), findsOneWidget);
    await tester.tap(find.text('Wallet'));
    await tester.pumpAndSettle();
    expect(find.byType(WalletOverview), findsOneWidget);
    expect(find.text('0,00 PKN'), findsNothing);
    await tester.tap(find.text('Accedi al tuo account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'alice@example.test');
    await tester.enterText(find.byType(TextField).at(1), 'password');
    await tester.tap(find.text('Accedi'));
    await tester.pump();
    profileData.profiles['alice']!
        .add(const AccountProfile(displayName: 'Alice'));
    profileData.balances['alice']!
        .add(const AccountBalance(available: 123, locked: 5));
    profileData.orders['alice']!.add([]);
    profileData.favorites['alice']!.add([]);
    await tester.pumpAndSettle();
    expect(find.byType(AccountScreen), findsNothing);
    await market.controller.account.signOut();
    await tester.pumpAndSettle();
    expect(find.byType(AccountScreen), findsOneWidget);
    expect(find.byType(WalletOverview), findsNothing);
    expect(find.byType(MarketplaceScreen), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await provider.close();
    await profileData.close();
  });
}
