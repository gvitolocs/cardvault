import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/cart.dart';

class CartPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<Cart>(context);

    return Scaffold(
      appBar: AppBar(title: Text('Il tuo Carrello')),
      body: cart.items.isEmpty
          ? Center(child: Text('Il carrello è vuoto.'))
          : ListView.builder(
              itemCount: cart.items.length,
              itemBuilder: (context, index) {
                return Dismissible(
                  key: ValueKey(cart.items[index].id),
                  onDismissed: (_) {
                    cart.removeItem(cart.items[index]);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text("${cart.items[index].name} rimosso")));
                  },
                  background: Container(color: Colors.red),
                  child: ListTile(
                    leading: Image.network(cart.items[index].imageUrl),
                    title: Text(cart.items[index].name),
                    subtitle:
                        Text('Prezzo: \$${cart.items[index].price.toString()}'),
                    trailing: IconButton(
                      icon: Icon(Icons.remove),
                      onPressed: () {
                        cart.removeItem(cart.items[index]);
                      },
                    ),
                  ),
                );
              },
            ),
      bottomSheet: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          'Totale: \$${cart.totalAmount.toStringAsFixed(2)}',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
