import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/cart.dart';
import '../models/order.dart';

class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});

  Color _getStatusColor(ShippingStatus status) {
    switch (status) {
      case ShippingStatus.ordered:
        return Colors.orangeAccent;
      case ShippingStatus.shipped:
        return Colors.lightBlueAccent;
      case ShippingStatus.delivered:
        return Colors.greenAccent;
      case ShippingStatus.cancelled:
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(ShippingStatus status) {
    switch (status) {
      case ShippingStatus.ordered:
        return Icons.shopping_bag;
      case ShippingStatus.shipped:
        return Icons.local_shipping;
      case ShippingStatus.delivered:
        return Icons.check_circle;
      case ShippingStatus.cancelled:
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }

  String _getStatusText(ShippingStatus status) {
    switch (status) {
      case ShippingStatus.ordered:
        return 'Acquistato';
      case ShippingStatus.shipped:
        return 'Spedito';
      case ShippingStatus.delivered:
        return 'Arrivato';
      case ShippingStatus.cancelled:
        return 'Annullato';
      default:
        return 'Sconosciuto';
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<Cart>().orders;

    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1),
      appBar: AppBar(
        title: const Text('I tuoi ordini'),
        backgroundColor: const Color(0xFF0D47A1),
        elevation: 0,
      ),
      body: orders.isEmpty
          ? const Center(
              child: Text(
                'Nessun ordine effettuato',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            )
          : ListView.builder(
              itemCount: orders.length,
              padding: const EdgeInsets.all(12),
              itemBuilder: (context, index) {
                final order = orders[index];
                return Card(
                  color: Colors.white.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ordine #${order.id}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...order.items.map((item) => Text(
                              '${item.name} - ${item.condition} - ${item.expansion} - \$${item.price.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                              ),
                            )),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _getStatusIcon(order.status),
                                  color: _getStatusColor(order.status),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _getStatusText(order.status),
                                  style: TextStyle(
                                    color: _getStatusColor(order.status),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            PopupMenuButton<String>(
                              onSelected: (choice) {
                                if (choice == 'cancel') {
                                  context.read<Cart>().updateOrderStatus(
                                      order.id, ShippingStatus.cancelled);
                                } else {
                                  final newStatus = ShippingStatus.values
                                      .firstWhere(
                                          (s) => _getStatusText(s) == choice);
                                  context
                                      .read<Cart>()
                                      .updateOrderStatus(order.id, newStatus);
                                }
                              },
                              icon: const Icon(Icons.more_vert,
                                  color: Colors.white70),
                              color: Colors.white,
                              itemBuilder: (context) {
                                final statusItems = ShippingStatus.values
                                    .where((status) =>
                                        status != ShippingStatus.cancelled)
                                    .map((status) => PopupMenuItem<String>(
                                          value: _getStatusText(status),
                                          child: Text(_getStatusText(status)),
                                        ))
                                    .toList();

                                if (order.status == ShippingStatus.ordered) {
                                  statusItems.add(const PopupMenuItem<String>(
                                    value: 'cancel',
                                    child: Text(
                                      'Annulla ordine',
                                      style: TextStyle(color: Colors.redAccent),
                                    ),
                                  ));
                                }

                                return statusItems;
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
