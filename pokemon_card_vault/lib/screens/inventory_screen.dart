import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/card_listing.dart';
import '../providers/auth_provider.dart';
import '../providers/card_listing_provider.dart';
import '../providers/marketplace_account_provider.dart';
import '../utils/card_url.dart';
import '../utils/price_format.dart';

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    if (user == null) {
      return const _MarketAuthGate(message: 'Sign in to manage inventory.');
    }
    final listings = ref.watch(sellerListingsProvider(user.uid));
    final sellerOrders = ref.watch(sellerOrdersProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _InventoryHeader(
                    onBack: () => context.go('/profile'),
                    onSell: () => context.go('/marketplace'),
                  ),
                  const SizedBox(height: 18),
                  _SellerSummary(
                    listings: listings.valueOrNull ?? const [],
                    orders: sellerOrders.valueOrNull ?? const [],
                    loading: listings.isLoading || sellerOrders.isLoading,
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: listings.when(
                      data: (items) => items.isEmpty
                          ? const _EmptyInventory()
                          : ListView.separated(
                              itemCount: items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) => _ListingTile(
                                listing: items[index],
                                sellerUid: user.uid,
                              ),
                            ),
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, _) => _InlineError(message: '$error'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InventoryHeader extends StatelessWidget {
  const _InventoryHeader({required this.onBack, required this.onSell});

  final VoidCallback onBack;
  final VoidCallback onSell;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Market inventory',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'Manage listings, stock, and seller order flow.',
                style: TextStyle(color: Color(0xFF93A4C8)),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: onSell,
          icon: const Icon(Icons.add_business_outlined),
          label: const Text('List a card'),
        ),
      ],
    );
  }
}

class _SellerSummary extends StatelessWidget {
  const _SellerSummary({
    required this.listings,
    required this.orders,
    required this.loading,
  });

  final List<CardListing> listings;
  final List<Map<String, dynamic>> orders;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final active = listings.where((listing) => listing.isActive).length;
    final stock =
        listings.fold<int>(0, (sum, listing) => sum + listing.quantityAvailable);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _MetricCard(label: 'Active listings', value: loading ? '...' : '$active'),
        _MetricCard(label: 'Units in stock', value: loading ? '...' : '$stock'),
        _MetricCard(label: 'Seller orders', value: loading ? '...' : '${orders.length}'),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xDD0B1020),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF93A4C8))),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ListingTile extends ConsumerWidget {
  const _ListingTile({required this.listing, required this.sellerUid});

  final CardListing listing;
  final String sellerUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xDD0B1020),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              listing.cardImageUrl,
              width: 64,
              height: 88,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 64,
                height: 88,
                color: const Color(0xFF111936),
                child: const Icon(Icons.style, color: Color(0xFFFACC15)),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  listing.cardName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${listing.setName} #${listing.collectorNumber}',
                  style: const TextStyle(color: Color(0xFF93A4C8)),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Tag(text: listing.status),
                    _Tag(text: listing.condition),
                    _Tag(text: listing.language),
                    if (listing.graded) _Tag(text: '${listing.gradingCompany ?? 'Graded'} ${listing.grade ?? ''}'),
                    if (listing.reverse) const _Tag(text: 'Reverse'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatPkn(listing.pricePkn),
                style: const TextStyle(
                  color: Color(0xFFFACC15),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '${listing.quantityAvailable} available',
                style: const TextStyle(color: Color(0xFFB8C4E6)),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => context.go(cardDetailPathFromParts(
                      id: listing.cardId,
                      name: listing.cardName,
                      setName: listing.setName,
                      number: listing.collectorNumber,
                    )),
                    child: const Text('Open'),
                  ),
                  FilledButton(
                    onPressed: () => ref
                        .read(cardListingServiceProvider)
                        .updateListingStatus(
                          listingId: listing.id,
                          sellerUid: sellerUid,
                          status: listing.status == 'active' ? 'paused' : 'active',
                        ),
                    child: Text(listing.status == 'active' ? 'Pause' : 'Activate'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12),
      ),
    );
  }
}

class _EmptyInventory extends StatelessWidget {
  const _EmptyInventory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xDD0B1020),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, color: Color(0xFFFACC15), size: 44),
            SizedBox(height: 12),
            Text(
              'No seller inventory yet',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 6),
            Text(
              'Open a card page and use Sell this card to create your first listing.',
              style: TextStyle(color: Color(0xFF93A4C8)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(message, style: const TextStyle(color: Colors.redAccent)),
    );
  }
}

class _MarketAuthGate extends StatelessWidget {
  const _MarketAuthGate({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: Center(
        child: FilledButton.icon(
          onPressed: () => context.go('/auth?from=/inventory'),
          icon: const Icon(Icons.login),
          label: Text(message),
        ),
      ),
    );
  }
}
