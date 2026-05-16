import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pokoin_wallet/main.dart' show WalletScreen;
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'screens/home_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/health_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/favorites_screen.dart';
import 'screens/card_detail_screen.dart';
import 'screens/checkout_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/buy_pkn_screen.dart';
import 'screens/docs_screen.dart';
import 'screens/forum_screen.dart';
import 'constants/app_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

  await _initializeFirebase();
  unawaited(_initializeLocalServices());

  runApp(
    const ProviderScope(
      child: PokemonCardVaultApp(),
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

class PokemonCardVaultApp extends ConsumerWidget {
  const PokemonCardVaultApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authBootstrapProvider);
    return MaterialApp.router(
      title: 'CardVault',
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
      if (isLoggedIn && isAuthRoute) {
        return state.uri.queryParameters['from'] ?? '/profile';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) {
          final host = Uri.base.host;
          if (host == 'explorer.pokoin.com') {
            return const ScanScreen();
          }
          if (host == 'forum.pokoin.com') {
            return const ForumScreen();
          }
          return const LandingScreen();
        },
      ),
      GoRoute(
        path: '/health',
        builder: (context, state) => const HealthScreen(),
      ),
      GoRoute(
        path: '/scan',
        builder: (context, state) => const ScanScreen(),
      ),
      GoRoute(
        path: '/docs',
        builder: (context, state) => const DocsScreen(),
      ),
      GoRoute(
        path: '/wallet',
        builder: (context, state) => Theme(
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
      ShellRoute(
        builder: (context, state, child) {
          return child;
        },
        routes: [
          GoRoute(
            path: '/marketplace',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/cart',
            builder: (context, state) => const CartScreen(),
          ),
          GoRoute(
            path: '/favorites',
            builder: (context, state) => const FavoritesScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
          GoRoute(
            path: '/card/:id',
            builder: (context, state) {
              final cardId = state.pathParameters['id']!;
              return CardDetailScreen(cardId: cardId);
            },
          ),
          GoRoute(
            path: '/checkout',
            builder: (context, state) => const CheckoutScreen(),
          ),
          GoRoute(
            path: '/orders',
            builder: (context, state) => const OrdersScreen(),
          ),
          GoRoute(
            path: '/auth',
            builder: (context, state) => const AuthScreen(),
          ),
          GoRoute(
            path: '/buy',
            builder: (context, state) => const BuyPknScreen(),
          ),
          GoRoute(
            path: '/forum',
            builder: (context, state) => const ForumScreen(),
          ),
          GoRoute(
            path: '/forum/category/:id',
            builder: (context, state) => ForumScreen(
              categoryId: state.pathParameters['id'],
            ),
          ),
          GoRoute(
            path: '/forum/topic/:id',
            builder: (context, state) => ForumScreen(
              topicId: state.pathParameters['id'],
            ),
          ),
        ],
      ),
    ],
  );
});

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
