import 'package:flutter/material.dart';
import 'card_detail_page.dart';
import 'cart_page.dart';
import 'login_page.dart';
import 'wallet_page.dart';
import 'orders_page.dart'; // ✅ aggiornato
import '../models/card_model.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<CardModel> trendingCards = [];
  List<CardModel> newReleases = [];
  List<CardModel> allCards = [];

  List<CardModel> searchSuggestions = [];

  bool isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool showSuggestions = false;

  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadDummyData();

    _searchController.addListener(() {
      _onSearchChanged(_searchController.text);
    });

    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        setState(() {
          showSuggestions = false;
        });
      } else if (_searchController.text.isNotEmpty) {
        setState(() {
          showSuggestions = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _loadDummyData() {
    trendingCards = [
      CardModel(
        id: '1',
        name: 'Charizard',
        imageUrl: 'https://images.pokemontcg.io/base1/4.png',
        price: 200.0,
        set: 'Base Set',
      ),
      CardModel(
        id: '2',
        name: 'Pikachu',
        imageUrl: 'https://images.pokemontcg.io/base1/58.png',
        price: 50.0,
        set: 'Base Set',
      ),
    ];

    newReleases = [
      CardModel(
        id: '3',
        name: 'Mewtwo',
        imageUrl: 'https://images.pokemontcg.io/swsh35/2.png',
        price: 120.0,
        set: 'Sword & Shield',
      ),
      CardModel(
        id: '4',
        name: 'Eevee',
        imageUrl: 'https://images.pokemontcg.io/swsh35/10.png',
        price: 30.0,
        set: 'Sword & Shield',
      ),
    ];

    allCards = [...trendingCards, ...newReleases];

    setState(() {
      isLoading = false;
    });
  }

  void _onSearchChanged(String query) {
    final lowerQuery = query.toLowerCase();

    if (lowerQuery.isNotEmpty) {
      searchSuggestions = allCards
          .where((card) => card.name.toLowerCase().contains(lowerQuery))
          .toList();
      showSuggestions = true;
    } else {
      searchSuggestions = [];
      showSuggestions = false;
    }
    setState(() {});
  }

  void _onBottomNavTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    switch (index) {
      case 0:
        break;
      case 1:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
        break;
      case 2:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CartPage()),
        );
        break;
      case 3:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WalletPage()),
        );
        break;
      case 4:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const OrdersPage()), // ✅ aggiornato
        );
        break;
    }
  }

  Widget _buildCardItem(CardModel card) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CardDetailPage(card: card)),
        );
      },
      child: SizedBox(
        width: 140,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                child: Image.network(card.imageUrl,
                    height: 100, fit: BoxFit.cover),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    Text(
                      card.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '\$${card.price.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<CardModel> cards) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: cards.length,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _buildCardItem(cards[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSuggestions() {
    return Positioned(
      left: 16,
      right: 16,
      top: 110,
      child: Material(
        elevation: 10,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 250),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: searchSuggestions.length,
            itemBuilder: (context, index) {
              final card = searchSuggestions[index];
              return ListTile(
                leading: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(card.imageUrl,
                        width: 40, height: 40, fit: BoxFit.cover)),
                title: Text(card.name),
                subtitle: Text('\$${card.price.toStringAsFixed(2)}'),
                onTap: () {
                  setState(() {
                    showSuggestions = false;
                    _searchController.text = card.name;
                  });
                  FocusScope.of(context).unfocus();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => CardDetailPage(card: card)),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchController,
        focusNode: _focusNode,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.red.shade700,
          hintText: 'Cerca carte...',
          hintStyle: const TextStyle(color: Colors.white70),
          prefixIcon: const Icon(Icons.search, color: Colors.white70),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D47A1),
        body: Center(child: CircularProgressIndicator(color: Colors.red)),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1),
        elevation: 0,
        centerTitle: true,
        title: const Text('Pokecoin'),
      ),
      body: Stack(
        children: [
          ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              _buildSearchBar(),
              _buildSection('Tendenze', trendingCards),
              _buildSection('Nuove uscite', newReleases),
              const SizedBox(height: 32),
            ],
          ),
          if (showSuggestions) _buildSuggestions(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.red.shade700,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white70,
        currentIndex: _selectedIndex,
        onTap: _onBottomNavTapped,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profilo'),
          BottomNavigationBarItem(
              icon: Icon(Icons.shopping_cart), label: 'Carrello'),
          BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet), label: 'Wallet'),
          BottomNavigationBarItem(
              icon: Icon(Icons.local_shipping), label: 'Ordini'),
        ],
      ),
    );
  }
}
