import 'package:flutter/material.dart';
import '../models/card_model.dart';
import '../services/api_service.dart';
import 'card_detail_page.dart';
import 'package:provider/provider.dart';
import '../models/cart.dart';

class CardsListPage extends StatefulWidget {
  const CardsListPage({super.key});

  @override
  _CardsListPageState createState() => _CardsListPageState();
}

class _CardsListPageState extends State<CardsListPage> {
  late Future<List<CardModel>> futureCards;

  @override
  void initState() {
    super.initState();
    futureCards = ApiService.fetchCards();
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<Cart>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Carte Pokémon'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            onPressed: () {
              Navigator.pushNamed(context,
                  '/cart'); // Assicurati che la rotta /cart sia definita
            },
          ),
        ],
      ),
      body: FutureBuilder<List<CardModel>>(
        future: futureCards,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Errore: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Nessuna carta trovata.'));
          }

          final cards = snapshot.data!;
          return ListView.builder(
            itemCount: cards.length,
            itemBuilder: (context, index) {
              final card = cards[index];
              return Card(
                child: ListTile(
                  leading: Image.network(card.imageUrl),
                  title: Text(card.name),
                  subtitle: Text('Prezzo: \$${card.price.toStringAsFixed(2)}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.add_shopping_cart),
                    onPressed: () {
                      // Qui devi passare anche condition ed expansion, qui per esempio valori fissi
                      cart.addItem(card, 'Near Mint', 'Base Set');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text('${card.name} aggiunta al carrello')),
                      );
                    },
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CardDetailPage(card: card),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
