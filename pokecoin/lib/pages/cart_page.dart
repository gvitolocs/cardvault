import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/cart.dart';
import 'orders_page.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key});

  Future<bool?> _showRemoveDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E3A8A),
        title: const Text('Rimuovi articolo',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Sei sicuro di voler rimuovere questo articolo dal carrello?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child:
                const Text('Annulla', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Rimuovi', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showClearDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E3A8A),
        title: const Text('Svuota carrello',
            style: TextStyle(color: Colors.white)),
        content: const Text('Vuoi svuotare completamente il carrello?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child:
                const Text('Annulla', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Svuota', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E3A8A),
      appBar: AppBar(
        backgroundColor: Colors.red,
        title: const Text('Carrello'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Svuota carrello',
            onPressed: () async {
              final shouldClear = await _showClearDialog(context);
              if (shouldClear ?? false) {
                Provider.of<Cart>(context, listen: false).clear();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Carrello svuotato.')),
                );
              }
            },
          ),
        ],
      ),
      body: Consumer<Cart>(
        builder: (context, cart, child) {
          if (cart.items.isEmpty) {
            return const Center(
              child: Text('Il carrello è vuoto.',
                  style: TextStyle(color: Colors.white70, fontSize: 18)),
            );
          }

          return ListView.builder(
            itemCount: cart.items.length,
            itemBuilder: (context, index) {
              final cartItem = cart.items[index];
              return Card(
                color: Colors.white.withOpacity(0.1),
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: cartItem.imageUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            cartItem.imageUrl,
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                          ),
                        )
                      : const Icon(Icons.image_not_supported,
                          color: Colors.white),
                  title: Text(
                    cartItem.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    'Condizione: ${cartItem.condition}\n'
                    'Espansione: ${cartItem.expansion}\n'
                    'Quantità: ${cartItem.quantity}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  trailing: Text(
                    '₽${cartItem.totalPrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  isThreeLine: true,
                  onLongPress: () async {
                    final shouldRemove = await _showRemoveDialog(context);
                    if (shouldRemove ?? false) {
                      cart.removeItem(cartItem);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                              Text('${cartItem.name} rimosso dal carrello.'),
                        ),
                      );
                    }
                  },
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: Consumer<Cart>(
        builder: (context, cart, child) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0F256E),
              boxShadow: [
                BoxShadow(
                  color: Colors.black54,
                  offset: Offset(0, -2),
                  blurRadius: 6,
                )
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Totale: ₽${cart.totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                ElevatedButton(
                  onPressed: cart.items.isEmpty
                      ? null
                      : () {
                          cart.placeOrder();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Ordine effettuato!')),
                          );
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const OrdersPage()),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Acquista',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
