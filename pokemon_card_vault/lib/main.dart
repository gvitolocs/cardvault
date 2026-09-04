import 'dart:async';
import 'dart:ui' as ui;

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
import 'screens/inventory_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/health_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/card_scan_screen.dart';
import 'screens/live_card_scan_screen.dart';
import 'screens/cart_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/favorites_screen.dart';
import 'screens/card_detail_screen.dart';
import 'screens/card_versions_screen.dart';
import 'screens/artist_collection_screen.dart';
import 'screens/marketplace_signal_screen.dart';
import 'screens/marketplace_competitive_renovation_screen.dart';
import 'screens/marketplace_competitive_screen.dart';
import 'screens/cardtrader_connect_screen.dart';
import 'screens/marketplace_admin_edit_screen.dart';
import 'screens/marketplace_debug_screen.dart';
import 'screens/checkout_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/buy_pkn_screen.dart';
import 'screens/earn_pkn_screen.dart';
import 'screens/docs_screen.dart';
import 'screens/privacy_screen.dart';
import 'screens/about_screen.dart';
import 'screens/contact_screen.dart';
import 'screens/whitepaper_screen.dart';
import 'screens/forum_screen.dart';
import 'screens/nft_screen.dart';
import 'screens/collection_screen.dart';
import 'screens/not_found_screen.dart';
import 'screens/product_landing_screen.dart';
import 'screens/extension_auth_bridge_screen.dart';
import 'constants/app_colors.dart';
import 'models/app_user_profile.dart';
import 'providers/marketplace_account_provider.dart';
import 'services/card_service.dart';
import 'services/flutter_debug_log.dart';
import 'utils/browser_location.dart';
import 'utils/card_url.dart';
import 'wallet/wallet_bridge_stub.dart';
import 'widgets/pokoin_assistant.dart';

const double _assistantDesktopBreakpoint = 960;

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    _installFlutterDebugErrorHooks();
    usePathUrlStrategy();

    await _initializeFirebase();
    await _initializeLocalServices();

    runApp(
      const ProviderScope(
        child: PokoinApp(),
      ),
    );
  }, (error, stackTrace) {
    FlutterDebugLog.instance.recordError(
      'flutter.zone_error',
      error,
      stackTrace: stackTrace,
    );
  });
}

void _installFlutterDebugErrorHooks() {
  final previousFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    previousFlutterError?.call(details);
    FlutterDebugLog.instance.recordError(
      'flutter.framework_error',
      details.exception,
      stackTrace: details.stack,
      payload: {
        'library': details.library,
        'context': details.context?.toDescription(),
      },
    );
  };
  ui.PlatformDispatcher.instance.onError = (error, stackTrace) {
    FlutterDebugLog.instance.recordError(
      'flutter.platform_error',
      error,
      stackTrace: stackTrace,
    );
    return false;
  };
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
  GoRouter? _debugObservedRouter;
  VoidCallback? _debugRouterListener;
  String _lastDebugRoute = '';
  String _lastDebugRouterSnapshotKey = '';
  String _lastCardDetailRoute = '';

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

  void _attachRouterDebugListener(GoRouter router) {
    if (identical(_debugObservedRouter, router)) {
      return;
    }
    final previousListener = _debugRouterListener;
    if (previousListener != null) {
      _debugObservedRouter?.routeInformationProvider
          .removeListener(previousListener);
    }
    _debugObservedRouter = router;
    _lastDebugRoute = router.routeInformationProvider.value.uri.toString();
    if (isMarketplaceCardDetailRoutePath(
      router.routeInformationProvider.value.uri.path,
    )) {
      _lastCardDetailRoute = _lastDebugRoute;
      CardDetailRouteGuard.instance.updateCardDetailRoute(_lastDebugRoute);
    }
    _debugRouterListener = () {
      final routeInformation = router.routeInformationProvider.value;
      final route = routeInformation.uri.toString();
      if (route == _lastDebugRoute) {
        return;
      }
      final previousRoute = _lastDebugRoute;
      final previousCardRoute = _lastCardDetailRoute;
      _lastDebugRoute = route;
      final browserPath = (currentBrowserUri() ?? Uri.base).path;
      final explicitNavigation =
          CardDetailRouteGuard.instance.consumeExplicitNavigation(route);
      if (isMarketplaceCardDetailRoutePath(routeInformation.uri.path)) {
        _lastCardDetailRoute = route;
        CardDetailRouteGuard.instance.updateCardDetailRoute(route);
      } else if (shouldRepairCardDetailRootDrift(
        previousPath: Uri.tryParse(previousRoute)?.path ?? previousRoute,
        nextPath: routeInformation.uri.path,
        lastCardDetailRoute: previousCardRoute.isNotEmpty
            ? previousCardRoute
            : _lastCardDetailRoute,
        cardDetailMounted: CardDetailRouteGuard.instance.hasMountedCardDetail,
        hasExplicitNavigationIntent: explicitNavigation,
        browserPath: browserPath,
      )) {
        final repairedRoute = previousCardRoute.isNotEmpty
            ? previousCardRoute
            : _lastCardDetailRoute;
        FlutterDebugLog.instance.record(
          'router.root_drift.repaired',
          category: 'navigation',
          routePath: routeInformation.uri.path,
          payload: {
            'previousRoute': previousRoute,
            'nextRoute': route,
            'repairedRoute': repairedRoute,
            'cardDetailMounted':
                CardDetailRouteGuard.instance.hasMountedCardDetail,
            'browserUrl': (currentBrowserUri() ?? Uri.base).toString(),
          },
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          final currentPath = router.routeInformationProvider.value.uri.path;
          if (isProtectedCardDetailDriftTargetPath(currentPath) &&
              !isMarketplaceCardDetailRoutePath(currentPath)) {
            router.replace(repairedRoute);
          }
        });
      }
      FlutterDebugLog.instance.record(
        'router.route_changed',
        category: 'navigation',
        routePath: routeInformation.uri.path,
        payload: {
          'previousRoute': previousRoute,
          'route': route,
          if (explicitNavigation) 'explicitNavigation': true,
          'browserUrl': (currentBrowserUri() ?? Uri.base).toString(),
        },
      );
    };
    router.routeInformationProvider.addListener(_debugRouterListener!);
    _recordCurrentRouterDebugSnapshot(router, reason: 'listener_attached');
  }

  void _recordCurrentRouterDebugSnapshot(
    GoRouter router, {
    required String reason,
  }) {
    if (!FlutterDebugLog.instance.enabled) {
      return;
    }
    final routeInformation = router.routeInformationProvider.value;
    final browserUrl = (currentBrowserUri() ?? Uri.base).toString();
    final snapshotKey = '$reason|${routeInformation.uri}|$browserUrl';
    if (snapshotKey == _lastDebugRouterSnapshotKey) {
      return;
    }
    _lastDebugRouterSnapshotKey = snapshotKey;
    FlutterDebugLog.instance.record(
      'router.current_state',
      category: 'navigation',
      routePath: routeInformation.uri.path,
      payload: {
        'reason': reason,
        'route': routeInformation.uri.toString(),
        'browserUrl': browserUrl,
      },
    );
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
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final router = ref.watch(routerProvider);
    syncFlutterDebugAuthorization(profile);
    FlutterDebugLog.instance.configureFromUri(currentBrowserUri() ?? Uri.base);
    _attachRouterDebugListener(router);
    _recordCurrentRouterDebugSnapshot(router, reason: 'build');
    return MaterialApp.router(
      title: 'Pokoin Official - PKN Card Reserve Marketplace, Wallet and Scan',
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
      builder: (context, child) {
        final routePath = router.routeInformationProvider.value.uri.path;
        final showAssistant =
            MediaQuery.sizeOf(context).width >= _assistantDesktopBreakpoint &&
                routePath != '/pokontact';
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            if (showAssistant) PokoinAssistant(router: router),
          ],
        );
      },
      routerConfig: router,
    );
  }

  @override
  void dispose() {
    final listener = _debugRouterListener;
    if (listener != null) {
      _debugObservedRouter?.routeInformationProvider.removeListener(listener);
    }
    super.dispose();
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
  final browserUri = currentBrowserUri() ?? Uri.base;
  final initialLocation = browserInitialLocationForRouter(browserUri);
  final initialDebugPath = initialLocation == null
      ? browserUri.path
      : (Uri.tryParse(initialLocation)?.path ?? initialLocation);
  FlutterDebugLog.instance.record(
    'router.initialized',
    category: 'navigation',
    routePath: initialDebugPath,
    payload: {
      'initialLocation': initialLocation,
      'browserUrl': browserUri.toString(),
    },
  );
  return GoRouter(
    initialLocation: initialLocation,
    overridePlatformDefaultLocation: initialLocation != null,
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
      final isCloseOnAuth = _isCloseOnAuthRequest(state.uri.queryParameters);
      final isSignupVerification =
          state.uri.queryParameters['signupToken']?.isNotEmpty == true;
      final isProtectedRoute = {
        '/wallet',
        '/swap',
        '/profile',
        '/inventory',
        '/collection',
        '/nft',
        '/checkout',
        '/orders',
        '/marketplace/connect',
      }.contains(state.matchedLocation);

      if (!isLoggedIn && isProtectedRoute) {
        final from = Uri.encodeComponent(state.uri.toString());
        return '/auth?from=$from';
      }
      if (isLoggedIn &&
          isAuthRoute &&
          !isSignupVerification &&
          !isCloseOnAuth) {
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
        path: '/cardscan',
        pageBuilder: (context, state) =>
            _appPage(state, const LiveCardScanScreen()),
      ),
      GoRoute(
        path: '/scancard',
        redirect: (context, state) => '/cardscan',
      ),
      GoRoute(
        path: '/livescan',
        redirect: (context, state) => '/cardscan',
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
        path: '/privacy',
        pageBuilder: (context, state) => _appPage(state, const PrivacyScreen()),
      ),
      GoRoute(
        path: '/about',
        pageBuilder: (context, state) => _appPage(state, const AboutScreen()),
      ),
      GoRoute(
        path: '/contact',
        pageBuilder: (context, state) => _appPage(state, const ContactScreen()),
      ),
      GoRoute(
        path: '/pokontact',
        pageBuilder: (context, state) =>
            _appPage(state, const PokontactChatScreen()),
      ),
      GoRoute(
        path: '/whitepaper',
        pageBuilder: (context, state) =>
            _appPage(state, const WhitepaperScreen()),
      ),
      GoRoute(
        path: '/extension/auth-bridge',
        pageBuilder: (context, state) =>
            _instantAppPage(state, const ExtensionAuthBridgeScreen()),
      ),
      GoRoute(
        path: '/wallet',
        pageBuilder: (context, state) => _appPage(state, _walletRoute()),
      ),
      GoRoute(
        path: '/swap',
        pageBuilder: (context, state) => _appPage(
          state,
          _walletRoute(initialSwapOpen: true),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return child;
        },
        routes: [
          GoRoute(
            path: '/marketplace',
            pageBuilder: (context, state) {
              final extra = state.extra;
              return _appPage(
                state,
                HomeScreen(
                  returnToRecentTop: extra is MarketplaceHomeRouteIntent &&
                      extra.shouldReturnToRecentTop,
                ),
              );
            },
          ),
          GoRoute(
            path: '/marketplace/search',
            pageBuilder: (context, state) => _appPage(
              state,
              MarketplaceSearchScreen(
                initialQuery: state.uri.queryParameters['q'] ?? '',
                expansion: state.uri.queryParameters['expansion'],
                productType: state.uri.queryParameters['productType'],
                searchLanguage: state.uri.queryParameters['lang'],
              ),
            ),
          ),
          GoRoute(
            path: '/marketplace/:lang/cards/:cardPage/:cardSlug/versions',
            pageBuilder: (context, state) {
              final cardPage = state.pathParameters['cardPage']!;
              final cardSlug = state.pathParameters['cardSlug']!;
              final routeParts = parseMarketplaceCardRoute(
                firstSegment: cardPage,
                slugSegment: cardSlug,
              );
              return _appPage(
                state,
                CardVersionsScreen(
                  cardId: routeParts.cardId,
                  cardSlug: routeParts.cardSlug,
                  language: state.pathParameters['lang'] ?? 'en',
                ),
              );
            },
          ),
          GoRoute(
            path: '/marketplace/:lang/cards/:cardPage/versions',
            pageBuilder: (context, state) {
              final cardPage = state.pathParameters['cardPage']!;
              final routeParts = parseMarketplaceCardRoute(
                firstSegment: cardPage,
              );
              return _appPage(
                state,
                CardVersionsScreen(
                  cardId: routeParts.cardId,
                  cardSlug: routeParts.cardSlug,
                  language: state.pathParameters['lang'] ?? 'en',
                ),
              );
            },
          ),
          GoRoute(
            path: '/marketplace/:lang/artists/:artistSlug',
            pageBuilder: (context, state) => _appPage(
              state,
              ArtistCollectionScreen(
                artistSlug: state.pathParameters['artistSlug']!,
                language: state.pathParameters['lang'] ?? 'en',
              ),
            ),
          ),
          GoRoute(
            path: '/marketplace/:lang/artists/:artistSlug/illustration',
            pageBuilder: (context, state) => _appPage(
              state,
              ArtistCollectionScreen(
                artistSlug: state.pathParameters['artistSlug']!,
                language: state.pathParameters['lang'] ?? 'en',
                initialFilter: ArtistCardFilter.illustrations,
              ),
            ),
          ),
          GoRoute(
            path: '/marketplace/:lang/artists/:artistSlug/full-arts',
            pageBuilder: (context, state) => _appPage(
              state,
              ArtistCollectionScreen(
                artistSlug: state.pathParameters['artistSlug']!,
                language: state.pathParameters['lang'] ?? 'en',
                initialFilter: ArtistCardFilter.fullArts,
              ),
            ),
          ),
          GoRoute(
            path: '/marketplace/:lang/artists/:artistSlug/normal-cards',
            pageBuilder: (context, state) => _appPage(
              state,
              ArtistCollectionScreen(
                artistSlug: state.pathParameters['artistSlug']!,
                language: state.pathParameters['lang'] ?? 'en',
                initialFilter: ArtistCardFilter.normalCards,
              ),
            ),
          ),
          GoRoute(
            path: '/marketplace/:lang/artists/:artistSlug/profile',
            pageBuilder: (context, state) {
              final extra = state.extra is ArtistProfileRouteExtra
                  ? state.extra! as ArtistProfileRouteExtra
                  : null;
              return _appPage(
                state,
                ArtistCollectionScreen(
                  artistSlug: state.pathParameters['artistSlug']!,
                  language: state.pathParameters['lang'] ?? 'en',
                  initialView: ArtistPageView.profile,
                  initialSnapshot: extra?.snapshot,
                  heroSourceSlug: extra?.heroSourceSlug,
                ),
              );
            },
          ),
          GoRoute(
            path: '/marketplace/:lang/cards/:cardPage/:cardSlug',
            pageBuilder: (context, state) {
              final cardPage = state.pathParameters['cardPage']!;
              final cardSlug = state.pathParameters['cardSlug']!;
              final routeParts = parseMarketplaceCardRoute(
                firstSegment: cardPage,
                slugSegment: cardSlug,
              );
              return _appPage(
                state,
                CardDetailScreen(
                  cardId: routeParts.cardId,
                  cardSlug: routeParts.cardSlug,
                  language: state.pathParameters['lang'] ?? 'en',
                  heroTag:
                      state.extra is String ? state.extra! as String : null,
                ),
              );
            },
          ),
          GoRoute(
            path: '/marketplace/:lang/cards/:cardPage',
            redirect: (context, state) {
              final cardPage = state.pathParameters['cardPage'] ?? '';
              if (isRootCardShortLink(cardPage)) {
                return marketplaceCardShortLinkRedirectPath(cardPage);
              }
              return null;
            },
            pageBuilder: (context, state) {
              final cardPage = state.pathParameters['cardPage']!;
              final routeParts = parseMarketplaceCardRoute(
                firstSegment: cardPage,
              );
              return _appPage(
                state,
                CardDetailScreen(
                  cardId: routeParts.cardId,
                  cardSlug: routeParts.cardSlug,
                  language: state.pathParameters['lang'] ?? 'en',
                  heroTag:
                      state.extra is String ? state.extra! as String : null,
                ),
              );
            },
          ),
          GoRoute(
            path: '/marketplace/signal',
            pageBuilder: (context, state) =>
                _appPage(state, const MarketplaceSignalScreen()),
          ),
          GoRoute(
            path: '/marketplace/competitive',
            pageBuilder: (context, state) => _appPage(
              state,
              const MarketplaceCompetitiveRenovationScreen(),
            ),
          ),
          GoRoute(
            path: '/marketplace/competitive/decks/:deckId',
            pageBuilder: (context, state) => _appPage(
              state,
              const MarketplaceCompetitiveRenovationScreen(),
            ),
          ),
          GoRoute(
            path: '/marketplace/competitive/decklists/:decklistId',
            pageBuilder: (context, state) => _appPage(
              state,
              const MarketplaceCompetitiveRenovationScreen(),
            ),
          ),
          // Placeholder name for the existing meta hub / top decks UI while
          // the public competitive URL shows the renovation page.
          GoRoute(
            path: '/marketplace/competitive-wip',
            pageBuilder: (context, state) =>
                _appPage(state, const MarketplaceCompetitiveScreen()),
          ),
          GoRoute(
            path: '/marketplace/competitive-wip/decks/:deckId',
            pageBuilder: (context, state) => _appPage(
              state,
              MarketplaceCompetitiveScreen(
                initialDeckId: state.pathParameters['deckId'] ?? '',
              ),
            ),
          ),
          GoRoute(
            path: '/marketplace/competitive-wip/decklists/:decklistId',
            pageBuilder: (context, state) => _appPage(
              state,
              MarketplaceCompetitiveScreen(
                initialDecklistId: state.pathParameters['decklistId'] ?? '',
              ),
            ),
          ),
          GoRoute(
            path: '/marketplace/connect',
            pageBuilder: (context, state) =>
                _appPage(state, const CardTraderConnectScreen()),
          ),
          GoRoute(
            path: '/marketplace/admin/edit',
            pageBuilder: (context, state) =>
                _appPage(state, const MarketplaceAdminEditScreen()),
          ),
          GoRoute(
            path: '/marketplace/debug',
            pageBuilder: (context, state) =>
                _appPage(state, const MarketplaceDebugScreen()),
          ),
          GoRoute(
            path: '/marketplace/debug/refinement',
            pageBuilder: (context, state) =>
                _appPage(state, const MarketplaceDebugRefinementScreen()),
          ),
          GoRoute(
            path: '/marketplace/debug/artists',
            pageBuilder: (context, state) =>
                _appPage(state, const MarketplaceDebugArtistScreen()),
          ),
          GoRoute(
            path: '/marketplace/debug/events',
            pageBuilder: (context, state) =>
                _appPage(state, const MarketplaceDebugEventsScreen()),
          ),
          GoRoute(
            path: '/marketplace/debug/cardmarket-guesses',
            pageBuilder: (context, state) =>
                _appPage(state, const MarketplaceCardmarketGuessReviewScreen()),
          ),
          GoRoute(
            path: '/marketplace/:publicNumber',
            redirect: (context, state) {
              final publicNumber = state.pathParameters['publicNumber'] ?? '';
              if (!isRootCardShortLink(publicNumber)) {
                return '/marketplace';
              }
              return null;
            },
            pageBuilder: (context, state) {
              final publicNumber = state.pathParameters['publicNumber']!;
              return _appPage(
                state,
                CardDetailScreen(
                  cardId: publicNumber,
                ),
              );
            },
          ),
          GoRoute(
            path: '/admin',
            pageBuilder: (context, state) =>
                _appPage(state, const MarketplaceDebugScreen()),
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
            path: '/inventory',
            pageBuilder: (context, state) =>
                _appPage(state, const InventoryScreen()),
          ),
          GoRoute(
            path: '/:username/inventory',
            pageBuilder: (context, state) => _appPage(
              state,
              InventoryScreen(username: state.pathParameters['username']),
            ),
          ),
          GoRoute(
            path: '/collection',
            pageBuilder: (context, state) =>
                _appPage(state, const CollectionScreen()),
          ),
          GoRoute(
            path: '/collection/artists/:artistSlug',
            pageBuilder: (context, state) => _appPage(
              state,
              CollectionArtistScreen(
                artistSlug: state.pathParameters['artistSlug']!,
              ),
            ),
          ),
          GoRoute(
            path: '/collection/:expansionSlug',
            pageBuilder: (context, state) => _appPage(
              state,
              CollectionExpansionScreen(
                expansionSlug: state.pathParameters['expansionSlug']!,
              ),
            ),
          ),
          GoRoute(
            path: '/nft',
            pageBuilder: (context, state) => _appPage(
              state,
              NftScreen(cardId: state.uri.queryParameters['card']),
            ),
          ),
          GoRoute(
            path: '/product/:kind',
            pageBuilder: (context, state) => _appPage(
              state,
              ProductLandingScreen(
                kind: state.pathParameters['kind'] ?? '',
              ),
            ),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) =>
                _appPage(state, const ProfileScreen()),
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
            path: '/earn',
            pageBuilder: (context, state) =>
                _appPage(state, const EarnPknScreen()),
          ),
          GoRoute(
            path: '/shard-review',
            pageBuilder: (context, state) =>
                _appPage(state, const ShardReviewScreen()),
          ),
          GoRoute(
            path: '/reserve',
            pageBuilder: (context, state) =>
                _appPage(state, const ReserveScreen()),
          ),
          GoRoute(
            path: '/forum',
            pageBuilder: (context, state) =>
                _instantAppPage(state, const ForumScreen()),
          ),
          GoRoute(
            path: '/forum/category/:id',
            pageBuilder: (context, state) => _instantAppPage(
              state,
              ForumScreen(categoryId: state.pathParameters['id']),
            ),
          ),
          GoRoute(
            path: '/forum/topic/:id',
            pageBuilder: (context, state) => _instantAppPage(
              state,
              ForumScreen(topicId: state.pathParameters['id']),
            ),
          ),
          GoRoute(
            path: '/card/:id',
            pageBuilder: (context, state) {
              final cardId = cardIdFromSlug(state.pathParameters['id']!);
              return _appPage(
                state,
                CardDetailScreen(
                  cardId: cardId,
                  heroTag:
                      state.extra is String ? state.extra! as String : null,
                ),
              );
            },
          ),
          GoRoute(
            path: '/:cardId/:cardSlug',
            pageBuilder: (context, state) {
              final routeParts = parseMarketplaceCardRoute(
                firstSegment: state.pathParameters['cardId']!,
                slugSegment: state.pathParameters['cardSlug'],
              );
              return _appPage(
                state,
                CardDetailScreen(
                  cardId: routeParts.cardId,
                  cardSlug: routeParts.cardSlug,
                  heroTag:
                      state.extra is String ? state.extra! as String : null,
                ),
              );
            },
          ),
          GoRoute(
            path: '/:cardSlug',
            redirect: (context, state) {
              final slug = state.pathParameters['cardSlug'] ?? '';
              if (isRootCardShortLink(slug)) {
                return marketplaceCardShortLinkRedirectPath(slug);
              }
              return null;
            },
            pageBuilder: (context, state) {
              final slug = state.pathParameters['cardSlug']!;
              return _appPage(
                state,
                ExpansionOrCardSlugScreen(slug: slug),
              );
            },
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
  final keepPageChromeFixed = _keepsPageChromeFixed(path);

  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: ColoredBox(
      color: const Color(0xFF050816),
      child: child,
    ),
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (keepPageChromeFixed) {
        return child;
      }
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

bool _keepsPageChromeFixed(String path) {
  return path == '/marketplace' ||
      path.startsWith('/marketplace/') ||
      path.startsWith('/card/') ||
      _isRootCardRoutePath(path) ||
      path.startsWith('/wallet') ||
      path.startsWith('/swap') ||
      path.startsWith('/orders') ||
      path.startsWith('/auth') ||
      path.startsWith('/buy') ||
      path.startsWith('/earn') ||
      path.startsWith('/shard-review') ||
      path.startsWith('/reserve') ||
      path.startsWith('/admin') ||
      path.startsWith('/cart') ||
      path.startsWith('/checkout') ||
      path.startsWith('/favorites') ||
      path.startsWith('/inventory') ||
      RegExp(r'^/[a-z0-9]{3,32}/inventory$').hasMatch(path.trim()) ||
      path.startsWith('/collection') ||
      path.startsWith('/product/') ||
      path.startsWith('/profile');
}

bool _isCloseOnAuthRequest(Map<String, String> queryParameters) {
  final closeOnAuth = queryParameters['closeOnAuth']?.toLowerCase();
  final extension = queryParameters['extension']?.toLowerCase();
  final from = queryParameters['from']?.toLowerCase();
  return closeOnAuth == '1' ||
      closeOnAuth == 'true' ||
      extension == '1' ||
      extension == 'true' ||
      from == 'extension';
}

void syncFlutterDebugAuthorization(AppUserProfile? profile) {
  final username = profile?.username.trim().toLowerCase() ?? '';
  final email = profile?.email.trim().toLowerCase() ?? '';
  final debugEnabled = username == 'vitologiuseppe17' ||
      email == 'vitologiuseppe17@gmail.com' ||
      email == 'pokoinpos@gmail.com' ||
      (profile?.hasAdminAccess ?? false);
  FlutterDebugLog.instance.setAuthorized(
    debugEnabled,
    userId: profile?.uid ?? '',
  );
}

NoTransitionPage<void> _instantAppPage(GoRouterState state, Widget child) {
  final path = state.uri.path;
  _lastRouteDepth = _routeDepth(path);
  _lastRouteOrder = _routeOrder(path);
  return NoTransitionPage<void>(
    key: state.pageKey,
    child: child,
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
  if (path.startsWith('/card/') || _isRootCardRoutePath(path)) {
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
  if (path.startsWith('/swap')) {
    return 60;
  }
  return 100;
}

Widget _walletRoute({bool initialSwapOpen = false}) {
  return Theme(
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
    child: WalletScreen(initialSwapOpen: initialSwapOpen),
  );
}

bool _isRootCardRoutePath(String path) {
  return RegExp(r'^/\d+(?:/[^/]+)?$').hasMatch(path.trim());
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

class ExpansionOrCardSlugScreen extends ConsumerWidget {
  const ExpansionOrCardSlugScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expansion = ref.watch(_expansionBySlugProvider(slug));
    return expansion.when(
      data: (value) {
        if (value != null && value.name.isNotEmpty) {
          return CollectionExpansionScreen(expansionSlug: value.slug);
        }
        return CardDetailScreen(cardId: cardIdFromSlug(slug));
      },
      loading: () => const Scaffold(
        backgroundColor: Color(0xFF050816),
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => CardDetailScreen(cardId: cardIdFromSlug(slug)),
    );
  }
}

final _expansionBySlugProvider =
    FutureProvider.family<MarketplaceExpansion?, String>((ref, slug) {
  return CardService().getMarketplaceExpansionBySlug(slug);
});
