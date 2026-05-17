import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/cart_provider.dart';
import '../utils/price_format.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cartState = ref.watch(cartProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xFF0B1B3A),
            foregroundColor: Colors.white,
            title: const Text('Your shopping cart'),
            actions: [
              TextButton(
                onPressed: () => context.go('/marketplace'),
                child: const Text('Marketplace'),
              ),
              const SizedBox(width: 8),
            ],
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: cartState.isLoading
                      ? const _LoadingCart()
                      : cartState.items.isEmpty
                          ? const _EmptyCart()
                          : _CartContent(cartState: cartState),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartContent extends ConsumerWidget {
  const _CartContent({required this.cartState});

  final CartState cartState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width > 900;
    final package = _ReservePackage(
      items: cartState.items,
      onQuantityChanged: (item, quantity) => ref
          .read(cartProvider.notifier)
          .updateQuantity(item.card.id, quantity),
      onRemove: (item) =>
          ref.read(cartProvider.notifier).removeFromCart(item.card.id),
    );
    final summary = _CartSummary(
      cartState: cartState,
      onCheckout: () => context.go('/checkout'),
      onPayNow: () => context.go('/checkout'),
      onClear: () => _showClearCartDialog(context, ref),
    );

    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          package,
          const SizedBox(height: 18),
          summary,
          const SizedBox(height: 18),
          const _OptimizerCard(),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: package),
        const SizedBox(width: 18),
        SizedBox(
          width: 300,
          child: Column(
            children: [
              summary,
              const SizedBox(height: 14),
              const _OptimizerCard(),
            ],
          ),
        ),
      ],
    );
  }

  void _showClearCartDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Empty all carts'),
        content:
            const Text('Remove all cards from your Pokoin Card Reserve cart?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(cartProvider.notifier).clearCart();
              Navigator.pop(context);
            },
            child: const Text('Empty cart'),
          ),
        ],
      ),
    );
  }
}

class _ReservePackage extends StatelessWidget {
  const _ReservePackage({
    required this.items,
    required this.onQuantityChanged,
    required this.onRemove,
  });

  final List<CartItem> items;
  final void Function(CartItem item, int quantity) onQuantityChanged;
  final void Function(CartItem item) onRemove;

  @override
  Widget build(BuildContext context) {
    final subtotal =
        items.fold<double>(0, (sum, item) => sum + item.totalPrice);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFB800), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFFFFB800),
              borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
            ),
            child: Row(
              children: [
                const _ReserveLogo(),
                const Spacer(),
                TextButton(
                  onPressed: () {},
                  child: const Text(
                    'More info',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F8EF),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF74C69D)),
            ),
            child: const Row(
              children: [
                Icon(Icons.hub_outlined, color: Color(0xFF15803D), size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Add as many items as you want, send all to our Hub without paying repeated shipments.',
                    style: TextStyle(
                      color: Color(0xFF15803D),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final item in items)
            _ReserveCartRow(
              item: item,
              onQuantityChanged: (quantity) =>
                  onQuantityChanged(item, quantity),
              onRemove: () => onRemove(item),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Row(
              children: [
                Text(
                  '${items.length} ${items.length == 1 ? 'item' : 'items'}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                const Text('Subtotal',
                    style: TextStyle(color: Color(0xFF64748B))),
                const SizedBox(width: 10),
                Text(
                  formatPkn(subtotal),
                  style: const TextStyle(
                    color: Color(0xFF0B1B3A),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReserveCartRow extends StatelessWidget {
  const _ReserveCartRow({
    required this.item,
    required this.onQuantityChanged,
    required this.onRemove,
  });

  final CartItem item;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              width: 56,
              height: 72,
              color: const Color(0xFFF1F5F9),
              child: CachedNetworkImage(
                imageUrl: item.card.imageUrl,
                fit: BoxFit.contain,
                errorWidget: (_, __, ___) =>
                    const Icon(Icons.style, color: Color(0xFF0EA5E9)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => context.go('/card/${item.card.id}'),
                  child: Text(
                    item.card.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF0284C7),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${item.card.rarity} | ${item.card.number}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const _ConditionChip('NM'),
                    const _LanguageDot(),
                    Text(
                      'Ready about ${_readyDate(item.card.id)}',
                      style: const TextStyle(
                        color: Color(0xFF334155),
                        fontSize: 12,
                      ),
                    ),
                    if (item.quantity > 1) const _DelayBadge(text: '3+ weeks'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            formatPkn(item.card.price),
            style: const TextStyle(
              color: Color(0xFF0B1B3A),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 12),
          _QuantityStepper(
            quantity: item.quantity,
            maxQuantity: mathMax(1, item.card.stock),
            onChanged: onQuantityChanged,
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 88,
            child: Text(
              formatPkn(item.totalPrice),
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF0B1B3A),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: onRemove,
            icon: const Icon(Icons.delete, size: 16),
            label: const Text('Remove'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF0B1B3A),
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  static String _readyDate(String id) {
    final seed = id.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
    const months = ['May', 'Jun'];
    return '${months[seed % months.length]} ${20 + seed % 10}';
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
      height: 34,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed: quantity > 1 ? () => onChanged(quantity - 1) : null,
            icon: const Icon(Icons.remove, size: 15),
          ),
          Text(
            '$quantity',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text('of', style: TextStyle(color: Color(0xFF64748B))),
          ),
          Text(
            '$maxQuantity',
            style: const TextStyle(color: Color(0xFF64748B)),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            onPressed:
                quantity < maxQuantity ? () => onChanged(quantity + 1) : null,
            icon: const Icon(Icons.add, size: 15),
          ),
        ],
      ),
    );
  }
}

class _CartSummary extends StatelessWidget {
  const _CartSummary({
    required this.cartState,
    required this.onCheckout,
    required this.onPayNow,
    required this.onClear,
  });

  final CartState cartState;
  final VoidCallback onCheckout;
  final VoidCallback onPayNow;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final fees = cartState.subtotal * 0.015;
    final total = cartState.subtotal + fees;

    return _SidePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Cart summary',
            style: TextStyle(
              color: Color(0xFF0B1B3A),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          const _SummaryLine(label: 'Packages count', value: '1'),
          _SummaryLine(label: 'Items count', value: '${cartState.itemCount}'),
          const Divider(height: 26),
          _SummaryLine(label: 'Items', value: formatPkn(cartState.subtotal)),
          const _SummaryLine(label: 'Shipping to our Hub', value: 'Free'),
          _SummaryLine(label: 'Fees', value: formatPkn(fees)),
          const _SummaryLine(
            label: 'Total Safeguard',
            value: 'Free',
            positive: true,
          ),
          const SizedBox(height: 18),
          TextButton(
            onPressed: () {},
            child: const Align(
              alignment: Alignment.centerLeft,
              child: Text('Have a coupon code?'),
            ),
          ),
          const Divider(height: 22),
          _SummaryLine(
            label: 'Total',
            value: formatPkn(total),
            large: true,
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onCheckout,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF38BDF8),
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Go to checkout'),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: onPayNow,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFFB800),
              foregroundColor: const Color(0xFF0B1B3A),
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('Pay Now'),
          ),
          const SizedBox(height: 18),
          TextButton(
            onPressed: onClear,
            style:
                TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            child: const Text('Empty all carts'),
          ),
        ],
      ),
    );
  }
}

class _OptimizerCard extends StatelessWidget {
  const _OptimizerCard();

  @override
  Widget build(BuildContext context) {
    return _SidePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Optimize your shopping cart and save money now!',
            style: TextStyle(
              color: Color(0xFF0B1B3A),
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: 0.68,
            minHeight: 8,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: const Color(0xFFE2E8F0),
            valueColor: const AlwaysStoppedAnimation(Color(0xFF22C55E)),
          ),
          const SizedBox(height: 10),
          const Text(
            'Pokoin Card Reserve groups sellers before checkout.',
            style: TextStyle(color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shopping_cart_outlined,
              color: Color(0xFF38BDF8), size: 62),
          const SizedBox(height: 16),
          const Text(
            'Your cart is empty',
            style: TextStyle(
              color: Color(0xFF0B1B3A),
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add listings from the marketplace to build a Pokoin Card Reserve shipment.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: () => context.go('/marketplace'),
            icon: const Icon(Icons.storefront_outlined),
            label: const Text('Browse marketplace'),
          ),
        ],
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

class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.label,
    required this.value,
    this.positive = false,
    this.large = false,
  });

  final String label;
  final String value;
  final bool positive;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: const Color(0xFF334155),
                fontSize: large ? 16 : 14,
                fontWeight: large ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color:
                  positive ? const Color(0xFF16A34A) : const Color(0xFF0B1B3A),
              fontSize: large ? 22 : 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReserveLogo extends StatelessWidget {
  const _ReserveLogo();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'POKOIN',
          style: TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        Text(
          'RESERVE',
          style: TextStyle(
            color: Colors.white,
            fontSize: 27,
            fontWeight: FontWeight.w900,
            height: 0.82,
          ),
        ),
      ],
    );
  }
}

class _ConditionChip extends StatelessWidget {
  const _ConditionChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF84CC16),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _LanguageDot extends StatelessWidget {
  const _LanguageDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        color: Color(0xFFDC2626),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _DelayBadge extends StatelessWidget {
  const _DelayBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFFB800),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

int mathMax(int a, int b) => a > b ? a : b;
