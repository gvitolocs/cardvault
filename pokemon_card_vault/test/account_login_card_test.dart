import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Test the real components in the Flutter-only Windows test harness as well.
// ignore: avoid_relative_lib_imports
import '../lib/widgets/account_login_card.dart';
// ignore: avoid_relative_lib_imports
import '../lib/widgets/marketplace_cart_navigation.dart';

class _LoginFixture {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  final confirm = TextEditingController();
  final username = TextEditingController();
  int submitted = 0;
  int toggled = 0;
  int google = 0;
  int wallet = 0;

  void dispose() {
    email.dispose();
    password.dispose();
    confirm.dispose();
    username.dispose();
  }

  Widget screen({
    bool isLogin = true,
    bool loading = false,
    bool googleLoading = false,
    bool walletLoading = false,
    bool connectedWallet = false,
    double textScale = 1,
  }) =>
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: AccountLoginCard(
                    formKey: formKey,
                    emailController: email,
                    passwordController: password,
                    confirmPasswordController: confirm,
                    usernameController: username,
                    isLogin: isLogin,
                    isLoading: loading,
                    isGoogleLoading: googleLoading,
                    isWalletLoading: walletLoading,
                    hasConnectedMetaMask: connectedWallet,
                    onSubmit: () {
                      if (formKey.currentState!.validate()) submitted++;
                    },
                    onGoogle: () => google++,
                    onCryptoWallet: () => wallet++,
                    onToggleMode: () => toggled++,
                  ),
                ),
              ),
            ),
          ),
          bottomNavigationBar: MarketplaceUtilityBar(
            selectedIndex: 4,
            onSearch: () {},
            onScanner: () {},
            onWallet: () {},
            onListings: () {},
            onProfile: () {},
          ),
        ),
      );
}

void main() {
  for (final width in [320.0, 390.0, 600.0, 1200.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('login fits width $width at text scale $scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = _LoginFixture();
        addTearDown(fixture.dispose);
        await tester.pumpWidget(fixture.screen(textScale: scale));
        expect(find.text('Access your account'), findsOneWidget);
        expect(find.byType(AccountLoginCard), findsOneWidget);
        expect(find.byType(TextFormField), findsNWidgets(2));
        expect(find.byType(Image), findsNothing);
        expect(find.text('Sign in once.'), findsNothing);
        expect(
            tester
                .widget<NavigationBar>(find.byType(NavigationBar))
                .selectedIndex,
            4);
        final before = tester.getRect(find.byType(NavigationBar));
        await tester.drag(
            find.byType(SingleChildScrollView), const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byType(NavigationBar)), before);
        expect(find.text('Profilo').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('email login retains validation before submission',
      (tester) async {
    final fixture = _LoginFixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.screen());
    expect(fixture.formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Please enter your email'), findsOneWidget);
    fixture.email.text = 'collector@example.test';
    fixture.password.text = 'test-only-password';
    expect(fixture.formKey.currentState!.validate(), isTrue);
    await tester.pump();
    final submit = find.widgetWithText(FilledButton, 'Sign in');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    expect(fixture.submitted, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signup retains username and password confirmation',
      (tester) async {
    final fixture = _LoginFixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.screen(isLogin: false));
    expect(find.byType(TextFormField), findsNWidgets(4));
    fixture.username.text = 'collector1';
    fixture.email.text = 'collector@example.test';
    fixture.password.text = 'test-only-password';
    fixture.confirm.text = 'different';
    expect(fixture.formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Passwords do not match'), findsOneWidget);
    fixture.confirm.text = fixture.password.text;
    expect(fixture.formKey.currentState!.validate(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('busy states disable the corresponding auth actions',
      (tester) async {
    final fixture = _LoginFixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.screen(
        loading: true, googleLoading: true, walletLoading: true));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Opening Google...'))
            .onPressed,
        isNull);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    expect(
        tester
            .widgetList<FilledButton>(find.byType(FilledButton))
            .every((button) => button.onPressed == null),
        isTrue);
    await tester.pumpWidget(fixture.screen(connectedWallet: true));
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(
                FilledButton, 'Google disabled while MetaMask is connected'))
            .onPressed,
        isNull);
  });

  testWidgets('auth actions delegate to callbacks without owning session state',
      (tester) async {
    final fixture = _LoginFixture();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(fixture.screen());
    await tester.tap(find.text('Continue with Google'));
    await tester.tap(find.text('Continue with MetaMask or EVM wallet'));
    final toggle = find.widgetWithText(TextButton, 'Sign up');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    expect([fixture.google, fixture.wallet, fixture.toggled], [1, 1, 1]);
    expect(tester.takeException(), isNull);
  });
}
