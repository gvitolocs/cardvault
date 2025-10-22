import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/card_provider.dart';
import '../constants/app_colors.dart';

class FilterChips extends ConsumerWidget {
  const FilterChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardState = ref.watch(cardProvider);
    
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Rarity Filter
          _buildFilterChip(
            label: 'All Rarities',
            isSelected: cardState.selectedRarity.isEmpty,
            onTap: () => ref.read(cardProvider.notifier).filterByRarity(''),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'Common',
            isSelected: cardState.selectedRarity == 'Common',
            onTap: () => ref.read(cardProvider.notifier).filterByRarity('Common'),
            color: AppColors.common,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'Uncommon',
            isSelected: cardState.selectedRarity == 'Uncommon',
            onTap: () => ref.read(cardProvider.notifier).filterByRarity('Uncommon'),
            color: AppColors.uncommon,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'Rare',
            isSelected: cardState.selectedRarity == 'Rare',
            onTap: () => ref.read(cardProvider.notifier).filterByRarity('Rare'),
            color: AppColors.rare,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'Rare Holo',
            isSelected: cardState.selectedRarity == 'Rare Holo',
            onTap: () => ref.read(cardProvider.notifier).filterByRarity('Rare Holo'),
            color: AppColors.rareHolo,
          ),
          const SizedBox(width: 16),
          
          // Type Filter
          _buildFilterChip(
            label: 'All Types',
            isSelected: cardState.selectedType.isEmpty,
            onTap: () => ref.read(cardProvider.notifier).filterByType(''),
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'Fire',
            isSelected: cardState.selectedType == 'Fire',
            onTap: () => ref.read(cardProvider.notifier).filterByType('Fire'),
            color: AppColors.fire,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'Water',
            isSelected: cardState.selectedType == 'Water',
            onTap: () => ref.read(cardProvider.notifier).filterByType('Water'),
            color: AppColors.water,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'Lightning',
            isSelected: cardState.selectedType == 'Lightning',
            onTap: () => ref.read(cardProvider.notifier).filterByType('Lightning'),
            color: AppColors.lightning,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'Grass',
            isSelected: cardState.selectedType == 'Grass',
            onTap: () => ref.read(cardProvider.notifier).filterByType('Grass'),
            color: AppColors.grass,
          ),
          const SizedBox(width: 16),
          
          // Special Filters
          _buildFilterChip(
            label: 'In Stock',
            isSelected: cardState.showOnlyInStock,
            onTap: () => ref.read(cardProvider.notifier).toggleInStockFilter(),
            color: AppColors.success,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'Holo',
            isSelected: false,
            onTap: () {
              // TODO: Implement holo filter
            },
            color: AppColors.rareHolo,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            label: 'Graded',
            isSelected: false,
            onTap: () {
              // TODO: Implement graded filter
            },
            color: AppColors.accent,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected 
              ? (color ?? AppColors.primary)
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected 
                ? (color ?? AppColors.primary)
                : Colors.grey[300]!,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: (color ?? AppColors.primary).withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
