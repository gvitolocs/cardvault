import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../providers/card_provider.dart';
import '../constants/app_colors.dart';
import '../utils/price_format.dart';

class FeaturedCards extends ConsumerWidget {
  const FeaturedCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardState = ref.watch(cardProvider);

    if (cardState.isLoading) {
      return _buildShimmerList();
    }

    // Get featured cards (high-rated or rare cards)
    final featuredCards = cardState.cards
        .where((card) => card.rating >= 4.0 || card.rarity == 'Rare Holo')
        .take(5)
        .toList();

    if (featuredCards.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Featured Cards',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: featuredCards.length,
            itemBuilder: (context, index) {
              return Container(
                width: 150,
                margin: const EdgeInsets.only(right: 16),
                child: _FeaturedCardItem(card: featuredCards[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildShimmerList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Featured Cards',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: 3,
            itemBuilder: (context, index) {
              return Container(
                width: 150,
                margin: const EdgeInsets.only(right: 16),
                child: Shimmer.fromColors(
                  baseColor: Colors.grey[300]!,
                  highlightColor: Colors.grey[100]!,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FeaturedCardItem extends StatelessWidget {
  final dynamic card;

  const _FeaturedCardItem({required this.card});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Image
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _getTypeColors(card.type),
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: CachedNetworkImage(
                  imageUrl: card.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Shimmer.fromColors(
                    baseColor: Colors.grey[300]!,
                    highlightColor: Colors.grey[100]!,
                    child: Container(
                      color: Colors.white,
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey[200],
                    child: const Icon(
                      Icons.image,
                      size: 30,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Card Info
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.name,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getTypeColor(card.type),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          card.type,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        formatPkn(card.price, decimals: 0),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Color> _getTypeColors(String type) {
    switch (type.toLowerCase()) {
      case 'fire':
        return [Colors.red[300]!, Colors.orange[300]!];
      case 'water':
        return [Colors.blue[300]!, Colors.cyan[300]!];
      case 'lightning':
        return [Colors.yellow[300]!, Colors.amber[300]!];
      case 'grass':
        return [Colors.green[300]!, Colors.lightGreen[300]!];
      case 'psychic':
        return [Colors.purple[300]!, Colors.pink[300]!];
      case 'fighting':
        return [Colors.brown[300]!, Colors.orange[300]!];
      case 'darkness':
        return [Colors.grey[600]!, Colors.black54];
      case 'metal':
        return [Colors.grey[400]!, Colors.blueGrey[300]!];
      case 'fairy':
        return [Colors.pink[200]!, Colors.purple[200]!];
      case 'dragon':
        return [Colors.indigo[300]!, Colors.purple[300]!];
      default:
        return [Colors.grey[300]!, Colors.grey[200]!];
    }
  }

  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'fire':
        return Colors.red;
      case 'water':
        return Colors.blue;
      case 'lightning':
        return Colors.yellow[700]!;
      case 'grass':
        return Colors.green;
      case 'psychic':
        return Colors.purple;
      case 'fighting':
        return Colors.brown;
      case 'darkness':
        return Colors.grey[800]!;
      case 'metal':
        return Colors.grey;
      case 'fairy':
        return Colors.pink;
      case 'dragon':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }
}
