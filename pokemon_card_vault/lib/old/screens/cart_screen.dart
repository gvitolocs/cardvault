import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/card_provider.dart';
import '../providers/cart_provider.dart';
import '../utils/card_navigation.dart';
import '../utils/price_format.dart';
import '../widgets/listing_metadata_chips.dart';
import 'home_screen.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool _searchFocused = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchTextChanged);
    _searchFocusNode.addListener(_handleSearchFocusChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchTextChanged);
    _searchFocusNode.removeListener(_handleSearchFocusChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleSearchTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleSearchFocusChanged() {
    final compactTopBar = MediaQuery.sizeOf(context).width < 760;
    if (!compactTopBar &&
        _searchFocusNode.hasFocus &&
        _searchController.text.trim().isEmpty) {
      showMarketplaceEmptyFocusSearchPreviews(ref);
    }
    if (mounted) {
      setState(() => _searchFocused = _searchFocusNode.hasFocus);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartProvider);
    final searchLanguage = ref.watch(
      cardProvider.select((state) => state.searchLanguage),
    );
    final cachedBalance = ref.watch(cachedPknBalanceProvider).valueOrNull;
    final balance =
        ref.watch(pknBalanceProvider).valueOrNull ?? cachedBalance ?? 0;
    final compactTopBar = MediaQuery.sizeOf(context).width < 760;
    final compactSearchExpanded =
        compactTopBar && (_searchFocused || _searchController.text.isNotEmpty);

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: marketplaceTopBarColor,
            foregroundColor: Colors.white,
            toolbarHeight: marketplaceTopBarHeight,
            elevation: 0,
            titleSpacing: 16,
            title: MarketplaceTopBar(
              compactExpanded: compactSearchExpanded,
              logo: MarketplaceLogoButton(
                onTap: compactTopBar
                    ? () => showMarketplaceSideMenu(context)
                    : () => context.go('/marketplace'),
              ),
              search: MarketplaceTopBarSearch(
                controller: _searchController,
                focusNode: _searchFocusNode,
                compactTopBar: compactTopBar,
                onSearchFocusedChanged: (hasFocus) {
                  if (mounted) {
                    setState(() => _searchFocused = hasFocus);
                  }
                },
                onSelected: (selection) {
                  final card = selection.card;
                  ref.read(cardProvider.notifier).recordCardInteraction(
                        card,
                        'click',
                        source: 'search_preview',
                      );
                  unawaited(navigateToCanonicalCardDetail(
                    context,
                    card,
                    source: 'cart_search_preview',
                    extra: selection.heroTag,
                  ));
                  Future<void>.delayed(marketplaceSearchPreviewHeroHoldDuration,
                      () {
                    if (mounted) {
                      _resetTransientSearch();
                    }
                  });
                },
              ),
              languageMenu: SearchLanguageMenu(
                value: searchLanguage,
                onChanged: (language) =>
                    ref.read(cardProvider.notifier).setSearchLanguage(language),
              ),
              actions: marketplaceTopBarActions(
                context: context,
                balance: balance,
                itemCount: cartState.itemCount,
                compactTopBar: compactTopBar,
                compactSearchExpanded: compactSearchExpanded,
                keyValue: 'cart-marketplace-actions',
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _CartShell(
              child: cartState.isLoading
                  ? const _LoadingCart()
                  : cartState.items.isEmpty
                      ? const _EmptyCart()
                      : _CartContent(cartState: cartState),
            ),
          ),
        ],
      ),
    );
  }

  void _resetTransientSearch() {
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
    }
    ref.read(cardProvider.notifier).clearSearchPreviews();
  }
}

class _CartShell extends StatelessWidget {
  const _CartShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height),
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topRight,
          radius: 1.2,
          colors: [Color(0x3338BDF8), Color(0x00050816)],
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 34),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _CartContent extends ConsumerWidget {
  const _CartContent({required this.cartState});

  final CartState cartState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 940;
    final itemsPanel = _CartItemsPanel(
      cartState: cartState,
      onQuantityChanged: (item, quantity) => ref
          .read(cartProvider.notifier)
          .updateQuantity(item.cartKey, quantity),
      onRemove: (item) =>
          ref.read(cartProvider.notifier).removeFromCart(item.cartKey),
      onClear: () => _showClearCartDialog(context, ref),
    );
    final summary = _CheckoutSummary(
      cartState: cartState,
      onFulfillmentModeChanged: (mode) =>
          ref.read(cartProvider.notifier).setFulfillmentMode(mode),
      onCheckout: () => context.go('/checkout'),
      onClear: () => _showClearCartDialog(context, ref),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CartHero(cartState: cartState),
        const SizedBox(height: 18),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: itemsPanel),
              const SizedBox(width: 18),
              SizedBox(width: 340, child: summary),
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              itemsPanel,
              const SizedBox(height: 18),
              summary,
            ],
          ),
      ],
    );
  }

  void _showClearCartDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0B1024),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: const Color(0xFFFACC15).withValues(alpha: 0.28),
          ),
        ),
        title: const Text(
          'Empty cart?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: const Text(
          'Remove every item from your Pokoin cart. This cannot be undone.',
          style: TextStyle(color: Color(0xFFB8C4E6)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFB8C4E6),
            ),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(cartProvider.notifier).clearCart();
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFACC15),
              foregroundColor: const Color(0xFF111827),
            ),
            child: const Text('Empty cart'),
          ),
        ],
      ),
    );
  }
}

class _CartHero extends StatelessWidget {
  const _CartHero({required this.cartState});

  final CartState cartState;

  @override
  Widget build(BuildContext context) {
    final sellers = cartState.items
        .map((item) => item.sellerName?.trim())
        .where((name) => name != null && name.isNotEmpty)
        .toSet()
        .length;
    return _GlassPanel(
      padding: const EdgeInsets.all(22),
      child: Wrap(
        spacing: 18,
        runSpacing: 18,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Eyebrow(text: 'Pokoin marketplace checkout'),
                SizedBox(height: 8),
                Text(
                  'Review your cards before checkout',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'Your cart keeps the exact seller listing, condition, language, quantity and fulfillment options selected on the card page.',
                  style: TextStyle(
                    color: Color(0xFFB8C4E6),
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _CartMetric(
                label: 'Items',
                value: '${cartState.itemCount}',
                icon: Icons.shopping_cart_outlined,
              ),
              _CartMetric(
                label: 'Listings',
                value: '${cartState.items.length}',
                icon: Icons.style_outlined,
              ),
              _CartMetric(
                label: 'Sellers',
                value: sellers == 0 ? '—' : '$sellers',
                icon: Icons.storefront_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CartItemsPanel extends StatelessWidget {
  const _CartItemsPanel({
    required this.cartState,
    required this.onQuantityChanged,
    required this.onRemove,
    required this.onClear,
  });

  final CartState cartState;
  final void Function(CartItem item, int quantity) onQuantityChanged;
  final void Function(CartItem item) onRemove;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Selected listings',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Exact seller inventory is preserved through checkout.',
                        style: TextStyle(color: Color(0xFF93A4C8)),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Clear'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFF87171),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0x18FFFFFF)),
          for (var index = 0; index < cartState.items.length; index++) ...[
            _CartItemCard(
              item: cartState.items[index],
              showNftChip: cartState.isNftOnlyCheckout,
              onQuantityChanged: (quantity) =>
                  onQuantityChanged(cartState.items[index], quantity),
              onRemove: () => onRemove(cartState.items[index]),
            ),
            if (index != cartState.items.length - 1)
              const Divider(height: 1, color: Color(0x12FFFFFF)),
          ],
        ],
      ),
    );
  }
}

class _CartItemCard extends StatelessWidget {
  const _CartItemCard({
    required this.item,
    required this.showNftChip,
    required this.onQuantityChanged,
    required this.onRemove,
  });

  final CartItem item;
  final bool showNftChip;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 700;
    final image = _CartImage(card: item.card);
    final details = _CartItemDetails(
      item: item,
      showNftChip: showNftChip,
    );
    final controls = _CartItemControls(
      item: item,
      onQuantityChanged: onQuantityChanged,
      onRemove: onRemove,
    );

    return InkWell(
      onTap: () => navigateToCanonicalCardDetail(
        context,
        item.card,
        source: 'cart_item',
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      image,
                      const SizedBox(width: 14),
                      Expanded(child: details),
                    ],
                  ),
                  const SizedBox(height: 14),
                  controls,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  image,
                  const SizedBox(width: 16),
                  Expanded(child: details),
                  const SizedBox(width: 16),
                  SizedBox(width: 190, child: controls),
                ],
              ),
      ),
    );
  }
}

class _CartImage extends StatelessWidget {
  const _CartImage({required this.card});

  final dynamic card;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 78,
      height: 104,
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      clipBehavior: Clip.antiAlias,
      child: CachedNetworkImage(
        imageUrl: card.previewImageUrl.isNotEmpty
            ? card.previewImageUrl
            : card.imageUrl,
        fit: BoxFit.contain,
        errorWidget: (_, __, ___) => const Icon(
          Icons.style,
          color: Color(0xFF38BDF8),
        ),
      ),
    );
  }
}

class _CartItemDetails extends StatelessWidget {
  const _CartItemDetails({
    required this.item,
    required this.showNftChip,
  });

  final CartItem item;
  final bool showNftChip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.card.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          [
            item.card.set,
            item.card.number,
            item.card.rarity,
          ].where((value) => value.trim().isNotEmpty).join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF93A4C8), height: 1.35),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            ListingConditionChip(
                condition: item.condition ?? item.card.condition),
            if ((item.language ?? '').isNotEmpty)
              ListingMetaChip(text: listingLanguageLabel(item.language!)),
            ListingMetaChip(
              color: const Color(0xFFFACC15),
              text: listingDisplaySellerName(
                sellerName: item.sellerName,
                reserveAvailable: item.reserveAvailable,
                isCardTraderLinked: listingIsCardTraderLinked(
                  source: item.source,
                  sourceListingId: item.sourceListingId,
                ),
              ),
            ),
            if (item.reverse) const ListingMetaChip(text: 'Reverse'),
            if (item.reserveAvailable) const ListingMetaChip(text: 'Reserve'),
            if (item.graded)
              ListingMetaChip(
                text: [
                  item.gradingCompany ?? 'Graded',
                  if ((item.grade ?? '').isNotEmpty) item.grade!,
                  if ((item.certificationId ?? '').isNotEmpty)
                    '#${item.certificationId!}',
                ].join(' '),
              ),
            if (showNftChip && item.nftAvailable)
              const ListingMetaChip(text: 'NFT'),
          ],
        ),
      ],
    );
  }
}

class _CartItemControls extends StatelessWidget {
  const _CartItemControls({
    required this.item,
    required this.onQuantityChanged,
    required this.onRemove,
  });

  final CartItem item;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          formatPkn(item.totalPrice),
          textAlign: TextAlign.right,
          style: const TextStyle(
            color: Color(0xFFFACC15),
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${formatPkn(item.unitPrice)} each',
          textAlign: TextAlign.right,
          style: const TextStyle(color: Color(0xFF93A4C8), fontSize: 12),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: _QuantityStepper(
            quantity: item.quantity,
            maxQuantity: mathMax(1, item.maxQuantity),
            onChanged: onQuantityChanged,
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: onRemove,
          icon: const Icon(Icons.close, size: 16),
          label: const Text('Remove'),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFCBD5E1),
            alignment: Alignment.centerRight,
          ),
        ),
      ],
    );
  }
}

class _CheckoutSummary extends StatelessWidget {
  const _CheckoutSummary({
    required this.cartState,
    required this.onFulfillmentModeChanged,
    required this.onCheckout,
    required this.onClear,
  });

  final CartState cartState;
  final ValueChanged<CartFulfillmentMode> onFulfillmentModeChanged;
  final VoidCallback onCheckout;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Eyebrow(text: 'Secure checkout'),
          const SizedBox(height: 8),
          const Text(
            'Order summary',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          _FulfillmentModePicker(
            mode: cartState.effectiveFulfillmentMode,
            canCheckoutNftOnly: cartState.canCheckoutNftOnly,
            onChanged: onFulfillmentModeChanged,
          ),
          const SizedBox(height: 12),
          _SummaryLine(label: 'Items', value: formatPkn(cartState.subtotal)),
          _SummaryLine(label: 'Tax estimate', value: formatPkn(cartState.tax)),
          _SummaryLine(
            label: 'Shipping',
            value: cartState.isNftOnlyCheckout
                ? 'No shipping'
                : formatPkn(cartState.shipping, decimals: 0),
          ),
          const Divider(height: 28, color: Color(0x18FFFFFF)),
          _SummaryLine(
            label: 'Total',
            value: formatPkn(cartState.total),
            large: true,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onCheckout,
            icon: const Icon(Icons.lock_outline),
            label: const Text('Continue to checkout'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFACC15),
              foregroundColor: const Color(0xFF111827),
              minimumSize: const Size.fromHeight(52),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => context.go('/marketplace'),
            icon: const Icon(Icons.add_shopping_cart_outlined),
            label: const Text('Add more cards'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF38BDF8),
              side: const BorderSide(color: Color(0x6638BDF8)),
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: onClear,
            style:
                TextButton.styleFrom(foregroundColor: const Color(0xFFF87171)),
            child: const Text('Empty cart'),
          ),
        ],
      ),
    );
  }
}

class _FulfillmentModePicker extends StatelessWidget {
  const _FulfillmentModePicker({
    required this.mode,
    required this.canCheckoutNftOnly,
    required this.onChanged,
  });

  final CartFulfillmentMode mode;
  final bool canCheckoutNftOnly;
  final ValueChanged<CartFulfillmentMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FulfillmentChoice(
          selected: mode == CartFulfillmentMode.physical,
          icon: Icons.local_shipping_outlined,
          title: 'Physical cards',
          subtitle: 'Ship the real cards now with the current checkout fee.',
          onTap: () => onChanged(CartFulfillmentMode.physical),
        ),
        const SizedBox(height: 8),
        _FulfillmentChoice(
          selected: mode == CartFulfillmentMode.nftOnly,
          enabled: canCheckoutNftOnly,
          icon: Icons.hexagon_outlined,
          title: 'NFT express',
          subtitle: canCheckoutNftOnly
              ? 'Purchase the nft now. trade it, sell it, expand your collection. Physical version ships when you request it from your NFT page'
              : 'Available when every cart item has the NFT tag.',
          onTap: () => onChanged(CartFulfillmentMode.nftOnly),
        ),
      ],
    );
  }
}

class _FulfillmentChoice extends StatelessWidget {
  const _FulfillmentChoice({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  final bool selected;
  final bool enabled;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = selected ? const Color(0xFFFACC15) : const Color(0xFF38BDF8);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFACC15).withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.045),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: enabled
                ? accent.withValues(alpha: selected ? 0.45 : 0.22)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: enabled ? accent : const Color(0xFF64748B),
              size: 18,
            ),
            const SizedBox(width: 10),
            Icon(icon,
                color: enabled ? accent : const Color(0xFF64748B), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: enabled ? Colors.white : const Color(0xFF64748B),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: enabled
                          ? const Color(0xFFB8C4E6)
                          : const Color(0xFF64748B),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.all(26),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x2238BDF8),
                  border: Border.all(color: const Color(0x6638BDF8)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.16),
                      blurRadius: 34,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.shopping_cart_outlined,
                  color: Color(0xFFFACC15),
                  size: 46,
                ),
              ),
              const SizedBox(height: 20),
              const _Eyebrow(text: 'Your cart is empty'),
              const SizedBox(height: 8),
              const Text(
                'Nothing here yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'This space is ready for real cards and NFTs you add from the marketplace to expand your collection.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFB8C4E6),
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => context.go('/marketplace'),
                    icon: const Icon(Icons.storefront_outlined),
                    label: const Text('Browse marketplace'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFACC15),
                      foregroundColor: const Color(0xFF111827),
                      minimumSize: const Size(190, 50),
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/marketplace/search'),
                    icon: const Icon(Icons.search),
                    label: const Text('Search cards'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF38BDF8),
                      side: const BorderSide(color: Color(0x6638BDF8)),
                      minimumSize: const Size(170, 50),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingCart extends StatelessWidget {
  const _LoadingCart();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(48),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xF20B1024),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.34),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantity,
    required this.maxQuantity,
    required this.onChanged,
  });

  final int quantity;
  final int maxQuantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed: quantity > 1 ? () => onChanged(quantity - 1) : null,
            icon: const Icon(Icons.remove, size: 16),
          ),
          Text(
            '$quantity',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            ' / $maxQuantity',
            style: const TextStyle(color: Color(0xFF93A4C8), fontSize: 12),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed:
                quantity < maxQuantity ? () => onChanged(quantity + 1) : null,
            icon: const Icon(Icons.add, size: 16),
          ),
        ],
      ),
    );
  }
}

class _CartMetric extends StatelessWidget {
  const _CartMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF38BDF8), size: 20),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFFACC15),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(label, style: const TextStyle(color: Color(0xFF93A4C8))),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.label,
    required this.value,
    this.large = false,
  });

  final String label;
  final String value;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final valueColor = large ? Colors.white : const Color(0xFFFDE68A);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: large ? 12 : 10,
      ),
      decoration: BoxDecoration(
        color: large
            ? const Color(0xFFFACC15).withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: large
              ? const Color(0xFFFACC15).withValues(alpha: 0.28)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: large ? Colors.white : const Color(0xFFD8E2FF),
                fontSize: large ? 16 : 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: valueColor,
              fontSize: large ? 24 : 16,
              fontWeight: FontWeight.w900,
              letterSpacing: large ? -0.4 : 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF38BDF8),
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.4,
      ),
    );
  }
}

int mathMax(int a, int b) => a > b ? a : b;
