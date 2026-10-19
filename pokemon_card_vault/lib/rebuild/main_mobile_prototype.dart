import 'dart:async';

import 'package:flutter/material.dart';

import 'controller/marketplace_controller.dart';
import 'presentation/marketplace/marketplace_screen.dart';
import 'service/marketplace_home_service.dart';
import 'service/card_service.dart';
import 'service/marketplace_search_service.dart';
import 'service/marketplace_suggestion_service.dart';
import 'controller/account_controller.dart';
import 'service/account_service.dart';
import 'presentation/account/account_screen.dart';
import 'service/profile_service.dart';
import 'service/cart_service.dart';
import 'provider/cart_local_provider.dart';
import 'provider/cart_remote_provider.dart';

/// Avvio indipendente: flutter run -t lib/rebuild/main_mobile_prototype.dart
/// Marketplace, account e carrello persistente locale/remoto.
void main() => runApp(const MobileMarketplacePrototypeApp());

class MobileMarketplacePrototypeApp extends StatefulWidget {
  const MobileMarketplacePrototypeApp(
      {super.key,
      this.homeService,
      this.cardService,
      this.searchService,
      this.suggestionService,
      this.accountService,
      this.profileService,
      this.cartService,
      this.autoLoadDiscovery = true,
      this.showDiscovery = true});

  final MarketplaceHomeService? homeService;
  final CardService? cardService;
  final MarketplaceSearchService? searchService;
  final MarketplaceSuggestionService? suggestionService;
  final AccountService? accountService;
  final ProfileService? profileService;
  final CartService? cartService;
  final bool showDiscovery;
  final bool autoLoadDiscovery;

  @override
  State<MobileMarketplacePrototypeApp> createState() =>
      _MobileMarketplacePrototypeAppState();
}

/// Composition root: crea il controller e ne gestisce il ciclo di vita.
class _MobileMarketplacePrototypeAppState
    extends State<MobileMarketplacePrototypeApp> {
  late MarketplaceController _controller;
  late AccountController _account;
  late CartService _cartService;
  late bool _ownsCartService;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  void _createController() {
    _account = AccountController(service: widget.accountService)..initialize();
    _ownsCartService = widget.cartService == null;
    _cartService = widget.cartService ??
        CartService(local: HiveCartProvider(), remote: FirestoreCartProvider());
    _controller = MarketplaceController(
        cartService: _cartService,
        accountController: _account,
        profileService: widget.profileService,
        homeService: widget.homeService,
        cardService: widget.cardService,
        searchService: widget.searchService,
        suggestionService: widget.suggestionService);
    _controller.cart.start(userIds: _account.watchUserId());
    if (widget.showDiscovery && widget.autoLoadDiscovery) {
      unawaited(_controller.loadDiscovery());
    }
  }

  @override
  void didUpdateWidget(MobileMarketplacePrototypeApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.homeService != widget.homeService ||
        oldWidget.cardService != widget.cardService ||
        oldWidget.searchService != widget.searchService ||
        oldWidget.suggestionService != widget.suggestionService ||
        oldWidget.accountService != widget.accountService ||
        oldWidget.profileService != widget.profileService ||
        oldWidget.cartService != widget.cartService) {
      final previous = _controller;
      final previousAccount = _account;
      final previousCart = _cartService;
      final ownedCart = _ownsCartService;
      _createController();
      // I widget figli devono prima scollegarsi dai notifier precedenti.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previous.dispose();
        previousAccount.dispose();
        if (ownedCart) previousCart.dispose();
      });
    } else if (widget.showDiscovery &&
        widget.autoLoadDiscovery &&
        (!oldWidget.showDiscovery || !oldWidget.autoLoadDiscovery)) {
      unawaited(_controller.loadDiscovery());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _account.dispose();
    if (_ownsCartService) _cartService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pokoin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF11121A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE9FF72),
          brightness: Brightness.dark,
          primary: const Color(0xFFE9FF72),
          surface: const Color(0xFF1D1F2C),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1D1F2C),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: MarketplaceScreen(
          controller: _controller, showDiscovery: widget.showDiscovery),
      // Il gate avvolge il Navigator: logout rimuove anche eventuali route
      // private aperte, impedendo di riaprirle con il pulsante Indietro.
      builder: (context, navigator) => ListenableBuilder(
          listenable: _account,
          builder: (context, _) => _account.session.canBrowse
              ? navigator!
              : Navigator(
                  key: ValueKey(_account),
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => AccountScreen(controller: _account),
                  ),
                )),
    );
  }
}
