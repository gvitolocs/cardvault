import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/marketplace_account_provider.dart';
import '../utils/price_format.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(userOrdersProvider);

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
                  _OrdersHeader(onBack: () => context.go('/profile')),
                  const SizedBox(height: 18),
                  Expanded(
                    child: orders.when(
                      data: (items) => items.isEmpty
                          ? _EmptyOrders(onBrowse: () => context.go('/marketplace'))
                          : ListView.separated(
                              itemCount: items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 14),
                              itemBuilder: (context, index) =>
                                  _OrderCard(order: items[index]),
                            ),
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, _) => Center(
                        child: Text(
                          '$error',
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
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

class _OrdersHeader extends StatelessWidget {
  const _OrdersHeader({required this.onBack});

  final VoidCallback onBack;

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
                'Orders',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'Buyer history, reserved seller listings, and fulfillment state.',
                style: TextStyle(color: Color(0xFF93A4C8)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders({required this.onBrowse});

  final VoidCallback onBrowse;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.shopping_bag_outlined,
              color: Color(0xFFFACC15),
              size: 48,
            ),
            const SizedBox(height: 12),
            const Text(
              'No marketplace orders yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Orders created from seller listings will appear here.',
              style: TextStyle(color: Color(0xFF93A4C8)),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onBrowse,
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('Back to marketplace'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final items = (order['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final total = order['totalPkn'] ?? order['total'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xDD0B1020),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Order #${order['id']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                formatPkn(total is num ? total : 0),
                style: const TextStyle(
                  color: Color(0xFFFACC15),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusChip(text: '${order['status'] ?? 'pending'}'),
              _StatusChip(text: '${order['paymentStatus'] ?? 'reserved'}'),
              _StatusChip(
                text:
                    '${order['fulfillmentStatus'] ?? 'awaiting_seller_confirmation'}'
                        .replaceAll('_', ' '),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final item in items.take(8)) _OrderItemRow(item: item),
        ],
      ),
    );
  }
}

class _OrderItemRow extends StatelessWidget {
  const _OrderItemRow({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final card = Map<String, dynamic>.from(item['card'] as Map? ?? {});
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              '${card['previewImageUrl'] ?? card['imageUrl'] ?? ''}',
              width: 44,
              height: 58,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 44,
                height: 58,
                color: const Color(0xFF111936),
                child: const Icon(Icons.style, color: Color(0xFFFACC15)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              [
                '${card['name'] ?? 'Card'}',
                'Qty ${item['quantity'] ?? 1}',
                if ((item['sellerName'] ?? '').toString().isNotEmpty)
                  '${item['sellerName']}',
                if ((item['condition'] ?? '').toString().isNotEmpty)
                  '${item['condition']}',
                if ((item['language'] ?? '').toString().isNotEmpty)
                  '${item['language']}',
              ].join(' · '),
              style: const TextStyle(color: Color(0xFFE2E8F0)),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
