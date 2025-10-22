import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/card_provider.dart';
import '../constants/app_colors.dart';

class CategorySection extends ConsumerWidget {
  const CategorySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = [
      CategoryItem(
        name: 'Fire',
        icon: Icons.local_fire_department,
        color: AppColors.fire,
        type: 'Fire',
      ),
      CategoryItem(
        name: 'Water',
        icon: Icons.water_drop,
        color: AppColors.water,
        type: 'Water',
      ),
      CategoryItem(
        name: 'Lightning',
        icon: Icons.flash_on,
        color: AppColors.lightning,
        type: 'Lightning',
      ),
      CategoryItem(
        name: 'Grass',
        icon: Icons.eco,
        color: AppColors.grass,
        type: 'Grass',
      ),
      CategoryItem(
        name: 'Psychic',
        icon: Icons.psychology,
        color: AppColors.psychic,
        type: 'Psychic',
      ),
      CategoryItem(
        name: 'Fighting',
        icon: Icons.sports_mma,
        color: AppColors.fighting,
        type: 'Fighting',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Categories',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            itemBuilder: (context, index) {
              return Container(
                width: 80,
                margin: const EdgeInsets.only(right: 16),
                child: _CategoryItem(
                  category: categories[index],
                  onTap: () {
                    ref.read(cardProvider.notifier).filterByType(categories[index].type);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class CategoryItem {
  final String name;
  final IconData icon;
  final Color color;
  final String type;

  CategoryItem({
    required this.name,
    required this.icon,
    required this.color,
    required this.type,
  });
}

class _CategoryItem extends StatelessWidget {
  final CategoryItem category;
  final VoidCallback onTap;

  const _CategoryItem({
    required this.category,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: category.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                category.icon,
                color: category.color,
                size: 24,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              category.name,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
