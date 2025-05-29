import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/card_model.dart';
import '../services/api_service.dart';
import '../pages/card_detail_page.dart';
import '../pages/cart_page.dart';
import '../models/cart.dart';
import '../pages/login_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<CardModel>> _cardsFuture;
  List<CardModel> _filteredCards = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cardsFuture = ApiService.fetchCards();
  }

  // Funzione per filtrare le carte in base alla ricerca
  void _filterCards(String query, List<CardModel> allCards) {
    setState(() {
      if (query.isEmpty) {
        _filteredCards = allCards;
      } else {
        _filteredCards = allCards
            .where(
                (card) => card.name.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<Cart>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
            'Pokecoin (${cart.items.length})'), // Mostra quante carte ci sono nel carrello
        actions: [
          // Icona carrello
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => CartPage()),
              );
            },
          ),
          // Icona profilo
          IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const LoginPage()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Barra di ricerca
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: FutureBuilder<List<CardModel>>(
              future: _cardsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(child: Text('Errore: ${snapshot.error}'));
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('Nessuna carta trovata.'));
                }

                final allCards = snapshot.data!;

                // Applica filtro quando cambia il testo di ricerca
                return TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Cerca carta...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => _filterCards(value, allCards),
                );
              },
            ),
          ),
          // Corpo della pagina con le carte
          Expanded(
            child: FutureBuilder<List<CardModel>>(
              future: _cardsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(child: Text('Errore: ${snapshot.error}'));
                } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('Nessuna carta trovata.'));
                }

                if (_filteredCards.isEmpty && _searchController.text.isEmpty) {
                  _filteredCards = snapshot.data!;
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.7,
                  ),
                  itemCount: _filteredCards.length,
                  itemBuilder: (context, index) {
                    final card = _filteredCards[index];
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CardDetailPage(card: card),
                          ),
                        );
                      },
                      child: Card(
                        elevation: 4.0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                card.imageUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                              ),
                            ),
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: IconButton(
                                icon: const Icon(Icons.add_shopping_cart,
                                    color: Colors.white),
                                onPressed: () {
                                  cart.addItem(card);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          '${card.name} aggiunta al carrello'),
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                },
                              ),
                            )
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
