import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import 'home_screen.dart';

/// Public placeholder shown at `/marketplace/competitive` while the meta hub
/// is being rebuilt. The full competitive UI remains at
/// `/marketplace/competitive-wip`.
class MarketplaceCompetitiveRenovationScreen extends ConsumerWidget {
  const MarketplaceCompetitiveRenovationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compactTopBar = MediaQuery.sizeOf(context).width < 760;
    final cachedBalance = ref.watch(cachedPknBalanceProvider).valueOrNull;
    final balance =
        ref.watch(pknBalanceProvider).valueOrNull ?? cachedBalance ?? 0;
    final cartState = ref.watch(cartProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: AppBar(
        backgroundColor: marketplaceTopBarColor,
        toolbarHeight: marketplaceTopBarHeight,
        elevation: 0,
        titleSpacing: 16,
        title: MarketplaceTopBar(
          compactExpanded: false,
          logo: MarketplaceLogoButton(
            onTap: compactTopBar
                ? () => showMarketplaceSideMenu(context)
                : () => context.go('/marketplace'),
          ),
          search: const Row(
            children: [
              Icon(Icons.construction_rounded, color: Color(0xFFFACC15)),
              SizedBox(width: 10),
              Flexible(
                child: Text(
                  'Competitive',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          languageMenu: const SizedBox.shrink(),
          actions: marketplaceTopBarActions(
            context: context,
            balance: balance,
            itemCount: cartState.itemCount,
            compactTopBar: compactTopBar,
            compactSearchExpanded: false,
            keyValue: 'competitive-renovation-actions',
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF101B3E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0x33FACC15)),
                  ),
                  child: const Icon(
                    Icons.construction_rounded,
                    color: Color(0xFFFACC15),
                    size: 36,
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Page in renovation',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'This page is under construction. The competitive meta hub will return here soon.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFB8C4E6),
                    fontSize: 15,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () => context.go('/marketplace'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFACC15),
                    foregroundColor: const Color(0xFF111827),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 14,
                    ),
                  ),
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text(
                    'Back to marketplace',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
