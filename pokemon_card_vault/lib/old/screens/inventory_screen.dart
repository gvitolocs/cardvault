import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/card_listing.dart';
import '../models/pokemon_card.dart';
import '../providers/auth_provider.dart';
import '../providers/card_listing_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/marketplace_account_provider.dart';
import '../utils/card_navigation.dart';
import '../utils/price_format.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key, this.username});

  final String? username;

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  bool _pausingAll = false;
  bool _removingAll = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final requestedUsername = widget.username?.trim().toLowerCase();
    final isSelfShortcut = requestedUsername == null;
    if (isSelfShortcut && user == null) {
      return const _MarketAuthGate(message: 'Sign in to manage inventory.');
    }

    final profile = ref.watch(userProfileProvider);
    final currentUsername = profile.valueOrNull?.username.trim().toLowerCase();
    if (isSelfShortcut && currentUsername?.isNotEmpty == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && GoRouterState.of(context).uri.path == '/inventory') {
          context.go('/$currentUsername/inventory');
        }
      });
    }
    final isOwner = user != null &&
        (isSelfShortcut ||
            (requestedUsername.isNotEmpty &&
                requestedUsername == currentUsername));
    final ownerUid = isOwner ? user.uid : null;
    final listings = isOwner
        ? ref.watch(sellerListingsProvider(ownerUid!))
        : ref.watch(sellerUsernameListingsProvider(requestedUsername ?? ''));
    final sellerOrders = isOwner ? ref.watch(sellerOrdersProvider) : null;
    final listingItems = listings.valueOrNull ?? const <CardListing>[];
    final activeListings =
        listingItems.where((listing) => listing.isActive).toList();
    final isBusy = _pausingAll || _removingAll;

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
                    username: requestedUsername,
                    isOwner: isOwner,
                    hasActiveListings: activeListings.isNotEmpty,
                    busy: isBusy,
                    onBack: () =>
                        context.go(isOwner ? '/profile' : '/marketplace'),
                    onSell: isOwner ? () => context.go('/marketplace') : null,
                    onPauseAll: ownerUid != null
                        ? () => _pauseActiveListings(
                              context,
                              sellerUid: ownerUid,
                              listings: activeListings,
                              username: requestedUsername,
                            )
                        : null,
                    onRemoveAll: ownerUid != null
                        ? () => _removeActiveListings(
                              context,
                              sellerUid: ownerUid,
                              listings: activeListings,
                              username: requestedUsername,
                            )
                        : null,
                  ),
                  const SizedBox(height: 18),
                  _SellerSummary(
                    listings: listingItems,
                    orders: sellerOrders?.valueOrNull ?? const [],
                    loading: listings.isLoading ||
                        (sellerOrders?.isLoading ?? false),
                    showOrders: isOwner,
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
                                sellerUid: user?.uid,
                                isOwner: isOwner,
                                username: requestedUsername,
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

  Future<void> _pauseActiveListings(
    BuildContext context, {
    required String sellerUid,
    required List<CardListing> listings,
    required String? username,
  }) async {
    if (_pausingAll || listings.isEmpty) {
      return;
    }
    final confirmed = await _confirmInventoryAction(
      context,
      title: 'Pause active listings?',
      message:
          'This will pause ${listings.length} active listings. Already paused, inactive, or sold-out listings will be left unchanged.',
      confirmLabel: 'Pause all',
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    setState(() => _pausingAll = true);
    try {
      final service = ref.read(cardListingServiceProvider);
      await Future.wait(
        listings.map(
          (listing) => service.updateListingStatus(
            listingId: listing.id,
            sellerUid: sellerUid,
            status: 'paused',
          ),
        ),
      );
      _refreshListings(sellerUid, username);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${listings.length} listings paused.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pause all failed: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _pausingAll = false);
      }
    }
  }

  Future<void> _removeActiveListings(
    BuildContext context, {
    required String sellerUid,
    required List<CardListing> listings,
    required String? username,
  }) async {
    if (_removingAll || listings.isEmpty) {
      return;
    }
    final confirmed = await _confirmInventoryAction(
      context,
      title: 'Remove active listings?',
      message:
          'This will remove ${listings.length} active listings from the market. Paused, inactive, or sold-out listings will be left unchanged.',
      confirmLabel: 'Remove all',
      destructive: true,
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    setState(() => _removingAll = true);
    try {
      final service = ref.read(cardListingServiceProvider);
      await Future.wait(
        listings.map(
          (listing) => service.removeListing(
            listingId: listing.id,
            sellerUid: sellerUid,
          ),
        ),
      );
      _refreshListings(sellerUid, username);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${listings.length} listings removed.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Remove all failed: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _removingAll = false);
      }
    }
  }

  void _refreshListings(String sellerUid, String? username) {
    ref.invalidate(sellerListingsProvider(sellerUid));
    if (username?.isNotEmpty == true) {
      ref.invalidate(sellerUsernameListingsProvider(username!));
    }
  }
}

class _InventoryHeader extends StatelessWidget {
  const _InventoryHeader({
    required this.onBack,
    required this.onSell,
    required this.onPauseAll,
    required this.onRemoveAll,
    required this.isOwner,
    required this.hasActiveListings,
    required this.busy,
    this.username,
  });

  final VoidCallback onBack;
  final VoidCallback? onSell;
  final VoidCallback? onPauseAll;
  final VoidCallback? onRemoveAll;
  final bool isOwner;
  final bool hasActiveListings;
  final bool busy;
  final String? username;

  @override
  Widget build(BuildContext context) {
    final title =
        username == null ? 'Market inventory' : '@$username inventory';
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                isOwner
                    ? 'Manage listings, stock, and seller order flow.'
                    : 'Browse this seller inventory and add active listings to cart.',
                style: const TextStyle(color: Color(0xFF93A4C8)),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (isOwner) ...[
              OutlinedButton.icon(
                onPressed: hasActiveListings && !busy ? onPauseAll : null,
                icon: const Icon(Icons.pause_circle_outline),
                label: const Text('Pause all'),
              ),
              OutlinedButton.icon(
                onPressed: hasActiveListings && !busy ? onRemoveAll : null,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove all'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFCA5A5),
                  side: BorderSide(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
            if (onSell != null)
              FilledButton.icon(
                onPressed: busy ? null : onSell,
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('List a card'),
              ),
          ],
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
    required this.showOrders,
  });

  final List<CardListing> listings;
  final List<Map<String, dynamic>> orders;
  final bool loading;
  final bool showOrders;

  @override
  Widget build(BuildContext context) {
    final active = listings.where((listing) => listing.isActive).length;
    final stock = listings.fold<int>(
        0, (sum, listing) => sum + listing.quantityAvailable);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _MetricCard(
            label: 'Active listings', value: loading ? '...' : '$active'),
        _MetricCard(label: 'Units in stock', value: loading ? '...' : '$stock'),
        if (showOrders)
          _MetricCard(
              label: 'Seller orders',
              value: loading ? '...' : '${orders.length}'),
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
  const _ListingTile({
    required this.listing,
    required this.sellerUid,
    required this.isOwner,
    required this.username,
  });

  final CardListing listing;
  final String? sellerUid;
  final bool isOwner;
  final String? username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inCart = ref.watch(cartProvider).isListingInCart(listing.id);
    final navigationCard = _listingCardForNavigation(listing);

    void openListingCard() {
      navigateToCanonicalCardDetail(
        context,
        navigationCard,
        source: 'inventory_listing',
      );
    }

    return Semantics(
      button: true,
      label: 'Open ${listing.cardName}',
      child: Material(
        color: const Color(0xDD0B1020),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: openListingCard,
          mouseCursor: SystemMouseCursors.click,
          child: Padding(
            padding: const EdgeInsets.all(14),
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
                        '${listing.setName} ${listing.collectorNumber}',
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
                          if (listing.graded)
                            _Tag(
                                text:
                                    '${listing.gradingCompany ?? 'Graded'} ${listing.grade ?? ''}'),
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
                          onPressed: openListingCard,
                          child: const Text('Open'),
                        ),
                        if (isOwner && sellerUid != null) ...[
                          FilledButton(
                            onPressed: () async {
                              await ref
                                  .read(cardListingServiceProvider)
                                  .updateListingStatus(
                                    listingId: listing.id,
                                    sellerUid: sellerUid!,
                                    status: listing.status == 'active'
                                        ? 'paused'
                                        : 'active',
                                  );
                              ref.invalidate(
                                  sellerListingsProvider(sellerUid!));
                              if (username?.isNotEmpty == true) {
                                ref.invalidate(
                                    sellerUsernameListingsProvider(username!));
                              }
                            },
                            child: Text(listing.status == 'active'
                                ? 'Pause'
                                : 'Activate'),
                          ),
                          OutlinedButton(
                            onPressed: () => _removeListing(
                              context,
                              ref,
                              sellerUid: sellerUid!,
                              listing: listing,
                              username: username,
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFFCA5A5),
                              side: BorderSide(
                                color: const Color(0xFFEF4444)
                                    .withValues(alpha: 0.55),
                              ),
                            ),
                            child: const Text('Remove'),
                          ),
                        ] else if (listing.isActive)
                          FilledButton.icon(
                            onPressed: () async {
                              final cart = ref.read(cartProvider.notifier);
                              if (inCart) {
                                await cart.removeFromCart(listing.id);
                              } else {
                                await cart.addListingToCart(
                                  _cardFromListing(listing),
                                  listing,
                                );
                              }
                            },
                            icon: Icon(inCart
                                ? Icons.remove_shopping_cart
                                : Icons.shopping_cart_outlined),
                            label: Text(
                                inCart ? 'Remove from cart' : 'Add to cart'),
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

PokemonCard _cardFromListing(CardListing listing) {
  return PokemonCard(
    id: listing.cardId,
    name: listing.cardName,
    imageUrl: listing.cardImageUrl,
    rarity: 'Card',
    type: 'Pokemon',
    hp: 0,
    attacks: const [],
    price: listing.pricePkn,
    description: '',
    set: listing.setName,
    number: listing.collectorNumber,
    artist: '',
    stock: listing.quantityAvailable,
    rating: 0,
    reviewCount: 0,
    isFoil: listing.reverse,
    isHolo: listing.reverse,
    releaseDate: DateTime.now(),
    tags: const [],
    condition: listing.condition,
    isGraded: listing.graded,
    grade: listing.grade,
    gradingCompany: listing.gradingCompany,
    canonicalPath: listing.canonicalPath,
  );
}

Future<void> _removeListing(
  BuildContext context,
  WidgetRef ref, {
  required String sellerUid,
  required CardListing listing,
  required String? username,
}) async {
  final confirmed = await _confirmInventoryAction(
    context,
    title: 'Remove listing?',
    message: 'This removes ${listing.cardName} from the market.',
    confirmLabel: 'Remove',
    destructive: true,
  );
  if (!confirmed || !context.mounted) {
    return;
  }
  try {
    await ref.read(cardListingServiceProvider).removeListing(
          listingId: listing.id,
          sellerUid: sellerUid,
        );
    ref.invalidate(sellerListingsProvider(sellerUid));
    if (username?.isNotEmpty == true) {
      ref.invalidate(sellerUsernameListingsProvider(username!));
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listing removed.')),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Remove failed: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

Future<bool> _confirmInventoryAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: const Color(0xFF0B1024),
      surfaceTintColor: Colors.transparent,
      title: Text(title, style: const TextStyle(color: Colors.white)),
      content: Text(
        message,
        style: const TextStyle(color: Color(0xFFCBD5E1)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
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
            Icon(Icons.inventory_2_outlined,
                color: Color(0xFFFACC15), size: 44),
            SizedBox(height: 12),
            Text(
              'No seller inventory yet',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
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

PokemonCard _listingCardForNavigation(CardListing listing) {
  return PokemonCard(
    id: listing.cardId,
    name: listing.cardName.isEmpty ? 'Pokemon card' : listing.cardName,
    imageUrl: listing.cardImageUrl,
    previewImageUrl: listing.cardImageUrl,
    rarity: 'Card',
    type: 'Trading card',
    hp: 0,
    attacks: const [],
    price: listing.pricePkn,
    description: 'Seller listing card.',
    set: listing.setName,
    number: listing.collectorNumber,
    artist: '',
    stock: listing.quantityAvailable,
    rating: 0,
    reviewCount: 0,
    isFoil: false,
    isHolo: false,
    releaseDate: DateTime.now(),
    tags: const [],
    condition: listing.condition,
    isGraded: listing.graded,
    grade: listing.grade,
    gradingCompany: listing.gradingCompany,
    canonicalPath: listing.canonicalPath,
  );
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
