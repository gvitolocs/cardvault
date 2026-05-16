import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/marketplace_account_provider.dart';
import '../constants/app_colors.dart';
import '../utils/price_format.dart';

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(userOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Orders'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              // TODO: Implement order filtering
            },
          ),
        ],
      ),
      body: orders.when(
        data: (items) =>
            items.isEmpty ? _buildEmptyOrders() : _buildOrdersList(items),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
      ),
    );
  }

  Widget _buildEmptyOrders() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shopping_bag_outlined,
            size: 100,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 24),
          Text(
            'No orders yet',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Your order history will appear here!',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersList(List<Map<String, dynamic>> orders) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        final total = order['totalPkn'] ?? order['total'] ?? 0;
        final status = order['status'] ?? 'pending';
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: Card(
            child: ListTile(
              leading: const Icon(Icons.shopping_bag),
              title: Text('Order #${order['id']}'),
              subtitle: Text('Status: $status'),
              trailing: Text(formatPkn(total is num ? total : 0)),
            ),
          ),
        );
      },
    );
  }
}
