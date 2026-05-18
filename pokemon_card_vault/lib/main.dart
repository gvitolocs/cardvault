import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:go_router/go_router.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'wallet/main.dart' show WalletScreen;
import 'screens/home_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/health_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/favorites_screen.dart';
import 'screens/card_detail_screen.dart';
import 'screens/marketplace_signal_screen.dart';
import 'screens/checkout_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/buy_pkn_screen.dart';
import 'screens/docs_screen.dart';
import 'screens/forum_screen.dart';
import 'constants/app_colors.dart';
import 'constants/project_links.dart';
import 'providers/marketplace_account_provider.dart';
import 'utils/card_url.dart';
import 'wallet/wallet_bridge_stub.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

  await _initializeFirebase();
  unawaited(_initializeLocalServices());

  runApp(
    const ProviderScope(
      child: PokoinApp(),
    ),
  );
}

Future<void> _initializeLocalServices() async {
  try {
    await Hive.initFlutter();
  } catch (error) {
    debugPrint('Hive initialization failed: $error');
  }
}

Future<void> _initializeFirebase() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error) {
    debugPrint('Firebase initialization failed: $error');
  }
}

class PokoinApp extends ConsumerStatefulWidget {
  const PokoinApp({super.key});

  @override
  ConsumerState<PokoinApp> createState() => _PokoinAppState();
}

class _PokoinAppState extends ConsumerState<PokoinApp> {
  late final WalletBridge _wallet = createWalletBridge();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  bool _walletListenerAttached = false;
  bool _switchingWalletAccount = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attachWalletAccountListener();
    });
  }

  void _attachWalletAccountListener() {
    if (_walletListenerAttached || !_wallet.hasProvider) {
      return;
    }
    _walletListenerAttached = true;
    _wallet.onAccountsChanged((address) {
      _handleWalletAccountChanged(address);
    });
  }

  Future<void> _handleWalletAccountChanged(String? address) async {
    final normalized = address?.trim().toLowerCase();
    if (_switchingWalletAccount || WalletSignInCoordinator.isSigning) {
      return;
    }

    final currentUser = ref.read(authServiceProvider).currentUser;
    if (currentUser == null) {
      return;
    }

    final currentProfile = ref.read(userProfileProvider).valueOrNull;
    final linkedWallet =
        currentProfile?.walletAddress?.trim().toLowerCase() ?? '';
    final hasLinkedWallet = linkedWallet.isNotEmpty;
    if (!hasLinkedWallet) {
      return;
    }

    if (normalized == null || normalized.isEmpty) {
      await ref.read(authServiceProvider).signOut();
      _refreshAccountProviders();
      if (mounted) {
        _showWalletMessage('MetaMask disconnected. You have been logged out.');
      }
      return;
    }

    if (linkedWallet == normalized) {
      ref.invalidate(linkedWalletBalanceProvider);
      return;
    }

    try {
      _switchingWalletAccount = true;
      await WalletSignInCoordinator.run(() async {
        final auth = ref.read(authServiceProvider);
        final nonce = await auth.requestWalletNonce(normalized);
        final message = nonce['message'] as String? ?? '';
        if (message.isEmpty) {
          throw StateError('Wallet sign-in nonce was empty.');
        }
        final signature = await _wallet.signMessage(
          address: normalized,
          message: message,
        );
        final result = await auth.verifyWalletSignature(
          address: normalized,
          signature: signature,
        );
        final token = result['customToken'] as String? ?? '';
        if (token.isEmpty) {
          throw StateError('Wallet sign-in token was empty.');
        }
        await auth.signInWithCustomToken(token);
      });
      _refreshAccountProviders();
      if (mounted) {
        _showWalletMessage('Switched to the selected MetaMask account.');
      }
    } catch (error) {
      if (mounted) {
        _showWalletMessage('Wallet account switch failed: $error',
            isError: true);
      }
    } finally {
      _switchingWalletAccount = false;
    }
  }

  void _refreshAccountProviders() {
    ref.invalidate(authStateProvider);
    ref.invalidate(userProfileProvider);
    ref.invalidate(pknBalanceProvider);
    ref.invalidate(linkedWalletBalanceProvider);
    ref.invalidate(userOrdersProvider);
    ref.invalidate(withdrawRequestsProvider);
  }

  void _showWalletMessage(String message, {bool isError = false}) {
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authBootstrapProvider);
    return MaterialApp.router(
      title: 'Pokoin',
      scaffoldMessengerKey: _scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _WebScrollBehavior(),
      theme: ThemeData(
        primarySwatch: Colors.green,
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.primary),
          ),
        ),
        useMaterial3: true,
      ),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

class _WebScrollBehavior extends MaterialScrollBehavior {
  const _WebScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final authService = ref.watch(authServiceProvider);
  return GoRouter(
    refreshListenable: GoRouterRefreshStream(
      Firebase.apps.isEmpty ? Stream.value(null) : authService.authStateChanges,
    ),
    redirect: (context, state) {
      final authBootstrap = ref.read(authBootstrapProvider);
      if (authBootstrap.isLoading) {
        return null;
      }

      final user = Firebase.apps.isEmpty ? null : authService.currentUser;
      final isLoggedIn = user != null;
      final isAuthRoute = state.matchedLocation == '/auth';
      final isSignupVerification =
          state.uri.queryParameters['signupToken']?.isNotEmpty == true;
      final isProtectedRoute = {
        '/wallet',
        '/profile',
        '/checkout',
        '/orders',
      }.contains(state.matchedLocation);

      if (!isLoggedIn && isProtectedRoute) {
        final from = Uri.encodeComponent(state.uri.toString());
        return '/auth?from=$from';
      }
      if (isLoggedIn && isAuthRoute && !isSignupVerification) {
        return state.uri.queryParameters['from'] ?? '/profile';
      }
      return null;
    },
    errorBuilder: (context, state) => PokoinNotFoundScreen(
      location: state.uri.toString(),
    ),
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) {
          final host = Uri.base.host;
          if (host == 'explorer.pokoin.com') {
            return _appPage(state, const ScanScreen());
          }
          if (host == 'forum.pokoin.com') {
            return _appPage(state, const ForumScreen());
          }
          return _appPage(state, const LandingScreen());
        },
      ),
      GoRoute(
        path: '/health',
        pageBuilder: (context, state) => _appPage(state, const HealthScreen()),
      ),
      GoRoute(
        path: '/scan',
        pageBuilder: (context, state) => _appPage(state, const ScanScreen()),
      ),
      GoRoute(
        path: '/tx/:hash',
        pageBuilder: (context, state) => _appPage(
          state,
          ScanScreen(initialQuery: state.pathParameters['hash']),
        ),
      ),
      GoRoute(
        path: '/address/:address',
        pageBuilder: (context, state) => _appPage(
          state,
          ScanScreen(initialQuery: state.pathParameters['address']),
        ),
      ),
      GoRoute(
        path: '/block/:id',
        pageBuilder: (context, state) => _appPage(
          state,
          ScanScreen(initialQuery: state.pathParameters['id']),
        ),
      ),
      GoRoute(
        path: '/docs',
        pageBuilder: (context, state) => _appPage(state, const DocsScreen()),
      ),
      GoRoute(
        path: '/wallet',
        pageBuilder: (context, state) => _appPage(
          state,
          Theme(
            data: ThemeData(
              brightness: Brightness.dark,
              scaffoldBackgroundColor: const Color(0xFF050816),
              colorScheme: const ColorScheme.dark(
                primary: Color(0xFFFACC15),
                secondary: Color(0xFF38BDF8),
                surface: Color(0xFF0B1020),
              ),
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: const Color(0xFF111936),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              useMaterial3: true,
            ),
            child: const WalletScreen(),
          ),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return child;
        },
        routes: [
          GoRoute(
            path: '/marketplace',
            pageBuilder: (context, state) =>
                _appPage(state, const HomeScreen()),
          ),
          GoRoute(
            path: '/marketplace/search',
            pageBuilder: (context, state) => _appPage(
              state,
              MarketplaceSearchScreen(
                initialQuery: state.uri.queryParameters['q'] ?? '',
                expansion: state.uri.queryParameters['expansion'],
                productType: state.uri.queryParameters['productType'],
              ),
            ),
          ),
          GoRoute(
            path: '/marketplace/signal',
            pageBuilder: (context, state) =>
                _appPage(state, const MarketplaceSignalScreen()),
          ),
          GoRoute(
            path: '/cart',
            pageBuilder: (context, state) =>
                _appPage(state, const CartScreen()),
          ),
          GoRoute(
            path: '/favorites',
            pageBuilder: (context, state) =>
                _appPage(state, const FavoritesScreen()),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) =>
                _appPage(state, const ProfileScreen()),
          ),
          GoRoute(
            path: '/card/:id',
            pageBuilder: (context, state) {
              final cardId = cardIdFromSlug(state.pathParameters['id']!);
              return _appPage(state, CardDetailScreen(cardId: cardId));
            },
          ),
          GoRoute(
            path: '/:cardSlug',
            pageBuilder: (context, state) {
              final cardId = cardIdFromSlug(state.pathParameters['cardSlug']!);
              return _appPage(state, CardDetailScreen(cardId: cardId));
            },
          ),
          GoRoute(
            path: '/checkout',
            pageBuilder: (context, state) =>
                _appPage(state, const CheckoutScreen()),
          ),
          GoRoute(
            path: '/orders',
            pageBuilder: (context, state) =>
                _appPage(state, const OrdersScreen()),
          ),
          GoRoute(
            path: '/auth',
            pageBuilder: (context, state) =>
                _appPage(state, const AuthScreen()),
          ),
          GoRoute(
            path: '/buy',
            pageBuilder: (context, state) =>
                _appPage(state, const BuyPknScreen()),
          ),
          GoRoute(
            path: '/forum',
            pageBuilder: (context, state) =>
                _appPage(state, const ForumScreen()),
          ),
          GoRoute(
            path: '/forum/category/:id',
            pageBuilder: (context, state) => _appPage(
              state,
              ForumScreen(categoryId: state.pathParameters['id']),
            ),
          ),
          GoRoute(
            path: '/forum/topic/:id',
            pageBuilder: (context, state) => _appPage(
              state,
              ForumScreen(topicId: state.pathParameters['id']),
            ),
          ),
        ],
      ),
    ],
  );
});

CustomTransitionPage<void> _appPage(GoRouterState state, Widget child) {
  final path = state.uri.path;
  final depth = _routeDepth(path);
  final isReverse = depth < _lastRouteDepth ||
      (depth == _lastRouteDepth && _routeOrder(path) < _lastRouteOrder);
  _lastRouteDepth = depth;
  _lastRouteOrder = _routeOrder(path);

  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final begin = Offset(isReverse ? -0.08 : 0.08, 0);
      return FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position:
              Tween<Offset>(begin: begin, end: Offset.zero).animate(curve),
          child: child,
        ),
      );
    },
  );
}

int _lastRouteDepth = 0;
int _lastRouteOrder = 0;

int _routeDepth(String path) {
  if (path == '/' || path.isEmpty) {
    return 0;
  }
  return path.split('/').where((segment) => segment.isNotEmpty).length;
}

int _routeOrder(String path) {
  if (path == '/') {
    return 0;
  }
  if (path.startsWith('/marketplace')) {
    return 10;
  }
  if (path.startsWith('/card/') || RegExp(r'^/\d+').hasMatch(path)) {
    return 20;
  }
  if (path.startsWith('/cart')) {
    return 30;
  }
  if (path.startsWith('/checkout')) {
    return 40;
  }
  if (path.startsWith('/orders')) {
    return 50;
  }
  if (path.startsWith('/wallet')) {
    return 60;
  }
  return 100;
}

class PokoinNotFoundScreen extends StatelessWidget {
  const PokoinNotFoundScreen({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final isExplorer = Uri.base.host == 'explorer.pokoin.com';
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF0B1020),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0x33FACC15)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 40,
                    offset: Offset(0, 24),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.network(
                        ProjectLinks.logo,
                        width: 72,
                        height: 72,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.none,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.toll,
                          size: 56,
                          color: Color(0xFFFACC15),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Page not found',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      location.isEmpty
                          ? 'This Pokoin page does not exist.'
                          : 'No Pokoin route exists for $location.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 16,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 26),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton(
                          onPressed: () => context.go(isExplorer ? '/' : '/'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFACC15),
                            foregroundColor: const Color(0xFF111827),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 16,
                            ),
                          ),
                          child:
                              Text(isExplorer ? 'Open PokoinScan' : 'Go home'),
                        ),
                        OutlinedButton(
                          onPressed: () => context.go('/health'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF38BDF8)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 16,
                            ),
                          ),
                          child: const Text('Network health'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((dynamic _) {
      notifyListeners();
    });
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
