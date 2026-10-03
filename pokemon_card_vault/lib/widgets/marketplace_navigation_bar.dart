import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'marketplace_cart_navigation.dart';

/// Shared marketplace destinations, also available from login and profile.
class MarketplaceNavigationBar extends StatelessWidget {
  const MarketplaceNavigationBar({super.key, this.selectedIndex = 0});

  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    return MarketplaceUtilityBar(
      selectedIndex: selectedIndex,
      onSearch: () => context.go('/marketplace/search'),
      onScanner: () => context.go('/cardscan'),
      onListings: () => unawaited(_openDashboard(context)),
      // The router preserves /profile as the return path for signed-out users.
      onProfile: () => context.go('/profile'),
    );
  }

  Future<void> _openDashboard(BuildContext context) async {
    try {
      final opened = await launchUrl(
        Uri.parse('https://pokoin.com/dashboard'),
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_self',
      );
      if (opened) return;
    } catch (_) {
      // Keep the same recoverable message for platform launch failures.
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile aprire Elenco. Riprova.')),
      );
    }
  }
}
