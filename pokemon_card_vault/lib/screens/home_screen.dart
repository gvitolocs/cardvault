import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:carousel_slider/carousel_slider.dart';  // Temporarily disabled
import 'package:shimmer/shimmer.dart';
import '../providers/card_provider.dart';
import '../widgets/card_grid.dart';
import '../widgets/search_bar.dart';
import '../widgets/filter_chips.dart';
// import '../widgets/featured_cards.dart';  // Temporarily disabled
import '../widgets/category_section.dart';
import '../constants/app_colors.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<String> _featuredImages = [
    'https://images.pokemontcg.io/base1/4_hires.png',
    'https://images.pokemontcg.io/base1/58_hires.png',
    'https://images.pokemontcg.io/base1/25_hires.png',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cardProvider.notifier).refreshCards();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cardState = ref.watch(cardProvider);
    
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // App Bar
          SliverAppBar(
            expandedHeight: 120.0,
            floating: false,
            pinned: true,
            backgroundColor: AppColors.primary,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                'Pokemon Card Vault',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.secondary],
                  ),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.search, color: Colors.white),
                onPressed: () => _showSearchDialog(),
              ),
              IconButton(
                icon: const Icon(Icons.filter_list, color: Colors.white),
                onPressed: () => _showFilterDialog(),
              ),
            ],
          ),
          
          // Featured Cards Carousel
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Featured Cards',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _featuredImages.length,
                      itemBuilder: (context, index) {
                        return Container(
                          width: 300,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.network(
                              _featuredImages[index],
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: AppColors.primary.withOpacity(0.1),
                                  child: const Icon(
                                    Icons.image,
                                    size: 50,
                                    color: AppColors.primary,
                                  ),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Categories
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: const CategorySection(),
            ),
          ),
          
          // Search Bar
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(16),
              child: const PokemonSearchBar(),
            ),
          ),
          
          // Filter Chips
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: const FilterChips(),
            ),
          ),
          
          // Cards Grid
          if (cardState.isLoading)
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(16),
                child: _buildShimmerGrid(),
              ),
            )
          else if (cardState.error != null)
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red[300],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading cards',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.red[300],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        cardState.error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          ref.read(cardProvider.notifier).refreshCards();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'All Cards (${cardState.filteredCards.length})',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            ref.read(cardProvider.notifier).sortCards(value);
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'name',
                              child: Text('Sort by Name'),
                            ),
                            const PopupMenuItem(
                              value: 'price',
                              child: Text('Sort by Price'),
                            ),
                            const PopupMenuItem(
                              value: 'rating',
                              child: Text('Sort by Rating'),
                            ),
                            const PopupMenuItem(
                              value: 'rarity',
                              child: Text('Sort by Rarity'),
                            ),
                          ],
                          child: const Icon(Icons.sort),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    CardGrid(cards: cardState.filteredCards),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildShimmerGrid() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.7,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: 6,
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          );
        },
      ),
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search Cards'),
        content: TextField(
          decoration: const InputDecoration(
            hintText: 'Enter card name or description...',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            ref.read(cardProvider.notifier).searchCards(value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter Cards'),
        content: const FilterDialog(),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(cardProvider.notifier).clearFilters();
              Navigator.pop(context);
            },
            child: const Text('Clear All'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }
}

class FilterDialog extends ConsumerWidget {
  const FilterDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardState = ref.watch(cardProvider);
    
    return SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Rarity Filter
          DropdownButtonFormField<String>(
            value: cardState.selectedRarity.isEmpty ? null : cardState.selectedRarity,
            decoration: const InputDecoration(
              labelText: 'Rarity',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: '', child: Text('All Rarities')),
              DropdownMenuItem(value: 'Common', child: Text('Common')),
              DropdownMenuItem(value: 'Uncommon', child: Text('Uncommon')),
              DropdownMenuItem(value: 'Rare', child: Text('Rare')),
              DropdownMenuItem(value: 'Rare Holo', child: Text('Rare Holo')),
            ],
            onChanged: (value) {
              ref.read(cardProvider.notifier).filterByRarity(value ?? '');
            },
          ),
          const SizedBox(height: 16),
          
          // Type Filter
          DropdownButtonFormField<String>(
            value: cardState.selectedType.isEmpty ? null : cardState.selectedType,
            decoration: const InputDecoration(
              labelText: 'Type',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: '', child: Text('All Types')),
              DropdownMenuItem(value: 'Fire', child: Text('Fire')),
              DropdownMenuItem(value: 'Water', child: Text('Water')),
              DropdownMenuItem(value: 'Lightning', child: Text('Lightning')),
              DropdownMenuItem(value: 'Grass', child: Text('Grass')),
              DropdownMenuItem(value: 'Psychic', child: Text('Psychic')),
              DropdownMenuItem(value: 'Fighting', child: Text('Fighting')),
              DropdownMenuItem(value: 'Darkness', child: Text('Darkness')),
              DropdownMenuItem(value: 'Metal', child: Text('Metal')),
              DropdownMenuItem(value: 'Fairy', child: Text('Fairy')),
              DropdownMenuItem(value: 'Dragon', child: Text('Dragon')),
              DropdownMenuItem(value: 'Colorless', child: Text('Colorless')),
            ],
            onChanged: (value) {
              ref.read(cardProvider.notifier).filterByType(value ?? '');
            },
          ),
          const SizedBox(height: 16),
          
          // Price Range
          RangeSlider(
            values: RangeValues(cardState.minPrice, cardState.maxPrice),
            min: 0,
            max: 1000,
            divisions: 100,
            labels: RangeLabels(
              '\$${cardState.minPrice.toStringAsFixed(0)}',
              '\$${cardState.maxPrice.toStringAsFixed(0)}',
            ),
            onChanged: (values) {
              ref.read(cardProvider.notifier).filterByPriceRange(
                values.start,
                values.end,
              );
            },
          ),
          const SizedBox(height: 16),
          
          // In Stock Only
          CheckboxListTile(
            title: const Text('In Stock Only'),
            value: cardState.showOnlyInStock,
            onChanged: (value) {
              ref.read(cardProvider.notifier).toggleInStockFilter();
            },
          ),
        ],
      ),
    );
  }
}
