import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'marketplace_navigation_bar.dart';

/// Keeps scanner exits outside camera loading, errors and boot overlays.
class ScannerNavigationShell extends StatelessWidget {
  const ScannerNavigationShell({super.key, required this.body});

  final Widget body;

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.of(context);
    return PopScope<Object?>(
      canPop: router.canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) router.go('/marketplace');
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: const Color(0xFF0A1026),
          foregroundColor: Colors.white,
          leading: IconButton(
            tooltip: 'Torna al Marketplace',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => router.go('/marketplace'),
          ),
          title: const Text('Scanner'),
        ),
        body: body,
        bottomNavigationBar: const MarketplaceNavigationBar(selectedIndex: 1),
      ),
    );
  }
}
