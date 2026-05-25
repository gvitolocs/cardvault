import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/marketplace_account_provider.dart';
import '../utils/price_format.dart';
import '../widgets/listing_metadata_chips.dart';
import '../widgets/shop_chain_account_card.dart';

const _checkoutBg = Color(0xFF050816);
const _checkoutPanel = Color(0xF20B1024);
const _checkoutSurface = Color(0xFF111936);
const _checkoutGold = Color(0xFFFACC15);
const _checkoutCyan = Color(0xFF38BDF8);
const _checkoutMuted = Color(0xFF93A4C8);
const _checkoutBody = Color(0xFFB8C4E6);

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final TextEditingController _notesController = TextEditingController();
  bool _placingOrder = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartProvider);
    final user = ref.watch(authStateProvider).valueOrNull;

    return Scaffold(
      backgroundColor: _checkoutBg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xF20A1026),
            foregroundColor: Colors.white,
            title: const Text(
              'Pokoin Checkout',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => context.go('/cart'),
                icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                label: const Text('Cart'),
                style: TextButton.styleFrom(
                  foregroundColor: _checkoutGold,
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
          SliverToBoxAdapter(
            child: _CheckoutShell(
              child: cartState.items.isEmpty
                  ? const _EmptyCheckout()
                  : _CheckoutContent(
                      cartState: cartState,
                      signedIn: user != null,
                      email: user?.email ?? '',
                      notesController: _notesController,
                      placingOrder: _placingOrder,
                      onFulfillmentModeChanged: (mode) => ref
                          .read(cartProvider.notifier)
                          .setFulfillmentMode(mode),
                      onPlaceOrder: () => _confirmAndPlaceOrder(cartState),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndPlaceOrder(CartState cartState) async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) {
      context.go('/auth?from=/checkout');
      return;
    }
    if (_placingOrder) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _checkoutPanel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: _checkoutGold.withValues(alpha: 0.28),
          ),
        ),
        title: const Text(
          'Confirm Pokoin order',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        content: Text(
          cartState.isNftOnlyCheckout
              ? 'We will pay ${formatPkn(cartState.total)} from your Pokoin balance, create one paid NFT-only order with ${cartState.itemCount} item${cartState.itemCount == 1 ? '' : 's'}, and add the NFTs to your collection. No physical card ships now.'
              : 'We will pay ${formatPkn(cartState.total)} from your Pokoin balance, create one paid order with ${cartState.itemCount} item${cartState.itemCount == 1 ? '' : 's'}, and notify each seller once.',
          style: const TextStyle(color: _checkoutBody),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: _checkoutBody,
            ),
            child: const Text('Review again'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: _checkoutGold,
              foregroundColor: const Color(0xFF111827),
            ),
            child: const Text('Confirm order'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _placingOrder = true);
    try {
      final items = cartState.items.map(_orderSnapshotForItem).toList();
      await ref.read(marketplaceAccountServiceProvider).createPaidOrder(
            buyerEmail: user.email ?? '',
            items: items,
            subtotalPkn: cartState.subtotal,
            taxPkn: cartState.tax,
            shippingPkn: cartState.shipping,
            totalPkn: cartState.total,
            fulfillmentMode: cartState.effectiveFulfillmentMode.wireValue,
          );
      await ref.read(cartProvider.notifier).clearCart();
      if (mounted) context.go('/orders');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Checkout failed: $error'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    } finally {
      if (mounted) setState(() => _placingOrder = false);
    }
  }

  Map<String, dynamic> _orderSnapshotForItem(CartItem item) {
    return {
      'card': item.card.toJson(),
      'quantity': item.quantity,
      'listingId': item.listingId,
      'sellerUid': item.sellerUid,
      'sellerName': item.sellerName,
      'condition': item.condition,
      'language': item.language,
      'unitPricePkn': item.unitPrice,
      'totalPricePkn': item.totalPrice,
      'reverse': item.reverse,
      'sealed': item.sealed,
      'graded': item.graded,
      'gradingCompany': item.gradingCompany,
      'grade': item.grade,
      'certificationId': item.certificationId,
      'shippingAvailable': item.shippingAvailable,
      'reserveAvailable': item.reserveAvailable,
      'nftAvailable': item.nftAvailable,
      'fulfillmentMode':
          ref.read(cartProvider).effectiveFulfillmentMode.wireValue,
      'source': item.source,
      'sourceListingId': item.sourceListingId,
      'sourceMetadata': item.sourceMetadata,
      if (_notesController.text.trim().isNotEmpty)
        'buyerNotes': _notesController.text.trim(),
    };
  }
}

class _CheckoutShell extends StatelessWidget {
  const _CheckoutShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height),
      decoration: const BoxDecoration(
        color: _checkoutBg,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF050816),
            Color(0xFF071329),
            Color(0xFF050816),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -180,
            right: -140,
            child: _GlowOrb(color: _checkoutCyan.withValues(alpha: 0.20)),
          ),
          Positioned(
            bottom: 80,
            left: -160,
            child: _GlowOrb(color: _checkoutGold.withValues(alpha: 0.12)),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 34),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 360,
        height: 360,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color, blurRadius: 120, spreadRadius: 70),
          ],
        ),
      ),
    );
  }
}

class _CheckoutContent extends StatelessWidget {
  const _CheckoutContent({
    required this.cartState,
    required this.signedIn,
    required this.email,
    required this.notesController,
    required this.placingOrder,
    required this.onFulfillmentModeChanged,
    required this.onPlaceOrder,
  });

  final CartState cartState;
  final bool signedIn;
  final String email;
  final TextEditingController notesController;
  final bool placingOrder;
  final ValueChanged<CartFulfillmentMode> onFulfillmentModeChanged;
  final VoidCallback onPlaceOrder;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CheckoutHero(cartState: cartState, signedIn: signedIn),
        const SizedBox(height: 18),
        _CheckoutProgress(signedIn: signedIn),
        const SizedBox(height: 18),
        _CheckoutStepCard(
          step: '01',
          title: 'Account',
          icon: Icons.person_outline,
          child: _AccountStep(signedIn: signedIn, email: email),
        ),
        const SizedBox(height: 14),
        _CheckoutStepCard(
          step: '02',
          title: 'Items snapshot',
          icon: Icons.inventory_2_outlined,
          child: _CheckoutItems(
            items: cartState.items,
            showNftChip: cartState.isNftOnlyCheckout,
          ),
        ),
        const SizedBox(height: 14),
        _CheckoutStepCard(
          step: '03',
          title: 'Fulfillment mode',
          icon: Icons.hexagon_outlined,
          child: _FulfillmentModeStep(
            cartState: cartState,
            onChanged: onFulfillmentModeChanged,
          ),
        ),
        const SizedBox(height: 14),
        _CheckoutStepCard(
          step: '04',
          title: 'Fulfillment notes',
          icon: Icons.edit_note_outlined,
          child: _NotesStep(controller: notesController),
        ),
        const SizedBox(height: 14),
        const _CheckoutStepCard(
          step: '05',
          title: 'Wallet context',
          icon: Icons.account_balance_wallet_outlined,
          child: ShopChainAccountCard(compact: true),
        ),
      ],
    );
    final summary = _CheckoutSummary(
      cartState: cartState,
      signedIn: signedIn,
      placingOrder: placingOrder,
      onPlaceOrder: onPlaceOrder,
    );

    return wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: main),
              const SizedBox(width: 18),
              SizedBox(width: 350, child: summary),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              main,
              const SizedBox(height: 18),
              summary,
            ],
          );
  }
}

class _CheckoutProgress extends StatelessWidget {
  const _CheckoutProgress({required this.signedIn});

  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      compact: true,
      child: Row(
        children: [
          const _ProgressNode(
            label: 'Cart',
            icon: Icons.shopping_cart_outlined,
            active: true,
          ),
          const _ProgressLine(active: true),
          _ProgressNode(
            label: 'Account',
            icon: signedIn ? Icons.verified_user_outlined : Icons.login,
            active: signedIn,
          ),
          _ProgressLine(active: signedIn),
          const _ProgressNode(
            label: 'Pending order',
            icon: Icons.receipt_long_outlined,
            active: false,
          ),
        ],
      ),
    );
  }
}

class _ProgressNode extends StatelessWidget {
  const _ProgressNode({
    required this.label,
    required this.icon,
    required this.active,
  });

  final String label;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? _checkoutGold : _checkoutMuted;
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? _checkoutGold.withValues(alpha: 0.14)
                  : _checkoutSurface,
              border: Border.all(
                color: active
                    ? _checkoutGold.withValues(alpha: 0.60)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 22),
        color: active
            ? _checkoutGold.withValues(alpha: 0.50)
            : Colors.white.withValues(alpha: 0.08),
      ),
    );
  }
}

class _CheckoutHero extends StatelessWidget {
  const _CheckoutHero({required this.cartState, required this.signedIn});

  final CartState cartState;
  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.all(24),
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 18,
            runSpacing: 18,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Eyebrow(text: 'Pokoin secure checkout'),
                    SizedBox(height: 8),
                    Text(
                      'Confirm and reserve real seller inventory',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        height: 1.02,
                        letterSpacing: -0.8,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Every checkout is built from live cart entries: exact listing IDs, seller metadata, conditions, language, grading, NFT and shipping flags are preserved in the order snapshot.',
                      style: TextStyle(
                        color: _checkoutBody,
                        fontSize: 15,
                        height: 1.48,
                      ),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _CheckoutMetric(
                    label: 'Items',
                    value: '${cartState.itemCount}',
                    icon: Icons.shopping_cart_outlined,
                  ),
                  _CheckoutMetric(
                    label: 'Total',
                    value: formatPkn(cartState.total),
                    icon: Icons.token_outlined,
                  ),
                  _CheckoutMetric(
                    label: 'Mode',
                    value:
                        cartState.isNftOnlyCheckout ? 'NFT only' : 'Physical',
                    icon: cartState.isNftOnlyCheckout
                        ? Icons.hexagon_outlined
                        : Icons.local_shipping_outlined,
                  ),
                  _CheckoutMetric(
                    label: 'Account',
                    value: signedIn ? 'Ready' : 'Sign in',
                    icon: signedIn ? Icons.verified_user_outlined : Icons.login,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _TrustPill(icon: Icons.fingerprint, text: 'Listing snapshots'),
              _TrustPill(icon: Icons.security, text: 'Firebase order store'),
              _TrustPill(icon: Icons.currency_bitcoin, text: 'PKN-first total'),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountStep extends StatelessWidget {
  const _AccountStep({required this.signedIn, required this.email});

  final bool signedIn;
  final String email;

  @override
  Widget build(BuildContext context) {
    if (!signedIn) {
      return _InlineNotice(
        icon: Icons.login,
        title: 'Sign in to bind this checkout to your Pokoin account',
        body:
            'You can build carts anonymously, but pending orders require an account so listings, seller snapshots and order history stay attached to you.',
        action: TextButton(
          onPressed: () => context.go('/auth?from=/checkout'),
          child: const Text('Sign in'),
        ),
      );
    }
    return _InlineNotice(
      icon: Icons.verified_user_outlined,
      title: 'Pokoin account verified',
      body: email.isEmpty
          ? 'Your authenticated account is ready to receive this pending order.'
          : 'This pending order will be saved to $email.',
    );
  }
}

class _CheckoutItems extends StatelessWidget {
  const _CheckoutItems({
    required this.items,
    required this.showNftChip,
  });

  final List<CartItem> items;
  final bool showNftChip;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          _CheckoutItemRow(
            item: items[index],
            showNftChip: showNftChip,
          ),
          if (index != items.length - 1)
            const Divider(height: 18, color: Color(0x14FFFFFF)),
        ],
      ],
    );
  }
}

class _CheckoutItemRow extends StatelessWidget {
  const _CheckoutItemRow({
    required this.item,
    required this.showNftChip,
  });

  final CartItem item;
  final bool showNftChip;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 58,
          height: 78,
          decoration: BoxDecoration(
            color: const Color(0xFF111936),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          clipBehavior: Clip.antiAlias,
          child: CachedNetworkImage(
            imageUrl: item.card.previewImageUrl.isNotEmpty
                ? item.card.previewImageUrl
                : item.card.imageUrl,
            fit: BoxFit.contain,
            errorWidget: (_, __, ___) => const Icon(
              Icons.style,
              color: Color(0xFF38BDF8),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.card.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ListingMetaChip(text: 'Qty ${item.quantity}'),
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
                  ListingConditionChip(
                    condition: item.condition ?? item.card.condition,
                  ),
                  if ((item.language ?? '').isNotEmpty)
                    ListingMetaChip(text: listingLanguageLabel(item.language!)),
                  if (item.reverse) const ListingMetaChip(text: 'Reverse'),
                  if (item.reserveAvailable)
                    const ListingMetaChip(text: 'Reserve'),
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
          ),
        ),
        const SizedBox(width: 10),
        Text(
          formatPkn(item.totalPrice),
          style: const TextStyle(
            color: Color(0xFFFACC15),
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _FulfillmentModeStep extends StatelessWidget {
  const _FulfillmentModeStep({
    required this.cartState,
    required this.onChanged,
  });

  final CartState cartState;
  final ValueChanged<CartFulfillmentMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final mode = cartState.effectiveFulfillmentMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FulfillmentOption(
          selected: mode == CartFulfillmentMode.physical,
          icon: Icons.local_shipping_outlined,
          title: 'Physical card checkout',
          body:
              'Use the current ${formatPkn(temporaryFixedCheckoutShippingPkn, decimals: 0)} shipping amount and keep the seller shipment workflow.',
          onTap: () => onChanged(CartFulfillmentMode.physical),
        ),
        const SizedBox(height: 10),
        _FulfillmentOption(
          selected: mode == CartFulfillmentMode.nftOnly,
          enabled: cartState.canCheckoutNftOnly,
          icon: Icons.hexagon_outlined,
          title: 'NFT express',
          body: cartState.canCheckoutNftOnly
              ? 'Purchase the nft now. trade it, sell it, expand your collection. Physical version ships when you request it from your NFT page'
              : 'Every cart item must show the NFT tag before NFT-only checkout is available.',
          onTap: () => onChanged(CartFulfillmentMode.nftOnly),
        ),
        const SizedBox(height: 12),
        _InlineNotice(
          icon: mode == CartFulfillmentMode.nftOnly
              ? Icons.inventory_2_outlined
              : Icons.local_shipping_outlined,
          title: mode == CartFulfillmentMode.nftOnly
              ? 'No shipping is charged now'
              : 'Physical shipping applies now',
          body: mode == CartFulfillmentMode.nftOnly
              ? 'The paid order stores NFT ownership in your collection. Shipping a physical card is a separate request and is not charged automatically.'
              : 'This checkout keeps the current physical fulfillment behavior and temporary shipping amount.',
        ),
      ],
    );
  }
}

class _FulfillmentOption extends StatelessWidget {
  const _FulfillmentOption({
    required this.selected,
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
    this.enabled = true,
  });

  final bool selected;
  final bool enabled;
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = selected ? _checkoutGold : _checkoutCyan;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? _checkoutGold.withValues(alpha: 0.12)
              : _checkoutSurface,
          borderRadius: BorderRadius.circular(18),
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
              size: 20,
            ),
            const SizedBox(width: 10),
            Icon(icon, color: enabled ? accent : const Color(0xFF64748B)),
            const SizedBox(width: 12),
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
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: TextStyle(
                      color: enabled ? _checkoutBody : const Color(0xFF64748B),
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

class _NotesStep extends StatelessWidget {
  const _NotesStep({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: 4,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Optional notes for the seller or fulfillment team...',
        hintStyle: const TextStyle(color: Color(0xFF64748B)),
        filled: true,
        fillColor: const Color(0xFF111936),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF38BDF8)),
        ),
      ),
    );
  }
}

class _CheckoutSummary extends StatelessWidget {
  const _CheckoutSummary({
    required this.cartState,
    required this.signedIn,
    required this.placingOrder,
    required this.onPlaceOrder,
  });

  final CartState cartState;
  final bool signedIn;
  final bool placingOrder;
  final VoidCallback onPlaceOrder;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.all(18),
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _checkoutGold.withValues(alpha: 0.14),
                  border: Border.all(
                    color: _checkoutGold.withValues(alpha: 0.42),
                  ),
                ),
                child: const Icon(
                  Icons.receipt_long_outlined,
                  color: _checkoutGold,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Eyebrow(text: 'Final review'),
                    SizedBox(height: 2),
                    Text(
                      'Order total',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SummaryLine(label: 'Subtotal', value: formatPkn(cartState.subtotal)),
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
            onPressed: placingOrder ? null : onPlaceOrder,
            icon: placingOrder
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(signedIn ? Icons.lock_outline : Icons.login),
            label: Text(signedIn ? 'Pay with PKN' : 'Sign in to checkout'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFACC15),
              foregroundColor: const Color(0xFF111827),
              minimumSize: const Size.fromHeight(52),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => context.go('/cart'),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back to cart'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF38BDF8),
              side: const BorderSide(color: Color(0x6638BDF8)),
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 16),
          const _InlineNotice(
            icon: Icons.info_outline,
            title: 'Inventory-aware order',
            body:
                'The backend verifies inventory, pays sellers from your PKN balance, saves the paid order, and sends each seller one sale notification.',
          ),
        ],
      ),
    );
  }
}

class _EmptyCheckout extends StatelessWidget {
  const _EmptyCheckout();

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.all(28),
      accent: true,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _checkoutCyan.withValues(alpha: 0.14),
                  border:
                      Border.all(color: _checkoutCyan.withValues(alpha: 0.34)),
                ),
                child: const Icon(
                  Icons.shopping_cart_checkout,
                  color: _checkoutGold,
                  size: 44,
                ),
              ),
              const SizedBox(height: 20),
              const _Eyebrow(text: 'Checkout is waiting'),
              const SizedBox(height: 8),
              const Text(
                'Your cart is empty',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Add a real seller listing first, then return here to create a pending Pokoin order.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _checkoutBody,
                  fontSize: 15,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: () => context.go('/marketplace'),
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('Browse marketplace'),
                style: FilledButton.styleFrom(
                  backgroundColor: _checkoutGold,
                  foregroundColor: const Color(0xFF111827),
                  minimumSize: const Size(200, 50),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckoutStepCard extends StatelessWidget {
  const _CheckoutStepCard({
    required this.step,
    required this.title,
    required this.icon,
    required this.child,
  });

  final String step;
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _GlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _StepNumberBadge(step: step, icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'STEP $step',
                      style: const TextStyle(
                        color: Color(0xFF38BDF8),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.accent = false,
    this.compact = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _checkoutPanel,
            accent ? const Color(0xF2131B38) : const Color(0xF20B1024),
          ],
        ),
        borderRadius: BorderRadius.circular(compact ? 20 : 26),
        border: Border.all(
          color: accent
              ? _checkoutGold.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.34),
            blurRadius: compact ? 18 : 30,
            offset: Offset(0, compact ? 10 : 18),
          ),
          if (accent)
            BoxShadow(
              color: _checkoutGold.withValues(alpha: 0.08),
              blurRadius: 26,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Stack(
        children: [
          if (accent)
            Positioned(
              top: -50,
              right: -50,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _checkoutGold.withValues(alpha: 0.05),
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

class _TrustPill extends StatelessWidget {
  const _TrustPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _checkoutSurface.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _checkoutGold, size: 15),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFFE2E8F0),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepNumberBadge extends StatelessWidget {
  const _StepNumberBadge({required this.step, required this.icon});

  final String step;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _checkoutCyan.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _checkoutCyan.withValues(alpha: 0.28)),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(icon, color: _checkoutGold, size: 20),
          Positioned(
            right: -13,
            top: -12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: _checkoutGold,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                step,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutMetric extends StatelessWidget {
  const _CheckoutMetric({
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
      constraints: const BoxConstraints(minWidth: 112),
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
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(label, style: const TextStyle(color: Color(0xFF93A4C8))),
        ],
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFFACC15), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    color: Color(0xFFB8C4E6),
                    height: 1.35,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: 8),
                  action!,
                ],
              ],
            ),
          ),
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
            ? _checkoutGold.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: large
              ? _checkoutGold.withValues(alpha: 0.28)
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
