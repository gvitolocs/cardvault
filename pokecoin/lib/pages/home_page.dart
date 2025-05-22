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
  TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cardsFuture = ApiService.fetchCards();
  }

  // Funzione per filtrare le carte in base alla ricerca
  void _filterCards(String query) {
    setState(() {
      _filteredCards = _filteredCards
          .where(
              (card) => card.name.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<Cart>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pokecoin'),
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
            icon: const Icon(Icons.account_circle), // Icona profilo
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) =>
                        LoginPage()), // Navigazione alla pagina di login
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
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Cerca carta...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _filterCards,
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

                final cards = snapshot.data!;

                // Se la ricerca è attiva, filtra le carte
                if (_filteredCards.isEmpty &&
                    _searchController.text.isNotEmpty) {
                  _filteredCards = cards
                      .where((card) => card.name
                          .toLowerCase()
                          .contains(_searchController.text.toLowerCase()))
                      .toList();
                } else {
                  _filteredCards = cards;
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, // Più carte per riga
                    crossAxisSpacing: 8, // Distanza tra le carte
                    mainAxisSpacing: 8, // Distanza tra le righe
                    childAspectRatio: 0.7, // Cambia la proporzione delle carte
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
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            card.imageUrl,
                            fit: BoxFit.cover,
                          ),
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
