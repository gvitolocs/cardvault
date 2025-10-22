import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/pokemon_card.dart';

class FavoritesState {
  final List<String> favoriteCardIds;
  final bool isLoading;
  final String? error;

  FavoritesState({
    this.favoriteCardIds = const [],
    this.isLoading = false,
    this.error,
  });

  FavoritesState copyWith({
    List<String>? favoriteCardIds,
    bool? isLoading,
    String? error,
  }) {
    return FavoritesState(
      favoriteCardIds: favoriteCardIds ?? this.favoriteCardIds,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }

  bool isFavorite(String cardId) {
    return favoriteCardIds.contains(cardId);
  }
}

class FavoritesNotifier extends StateNotifier<FavoritesState> {
  static const String _favoritesBoxName = 'favorites';

  FavoritesNotifier() : super(FavoritesState()) {
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    try {
      state = state.copyWith(isLoading: true);
      
      final box = await Hive.openBox<String>(_favoritesBoxName);
      final favoriteIds = box.values.toList();
      
      state = state.copyWith(
        favoriteCardIds: favoriteIds,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> toggleFavorite(String cardId) async {
    try {
      final box = await Hive.openBox<String>(_favoritesBoxName);
      
      if (state.isFavorite(cardId)) {
        // Remove from favorites
        final key = box.keys.firstWhere(
          (key) => box.get(key) == cardId,
          orElse: () => -1,
        );
        if (key != -1) {
          await box.delete(key);
        }
      } else {
        // Add to favorites
        await box.add(cardId);
      }
      
      // Reload favorites
      await _loadFavorites();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> addToFavorites(String cardId) async {
    if (!state.isFavorite(cardId)) {
      await toggleFavorite(cardId);
    }
  }

  Future<void> removeFromFavorites(String cardId) async {
    if (state.isFavorite(cardId)) {
      await toggleFavorite(cardId);
    }
  }

  Future<void> clearFavorites() async {
    try {
      final box = await Hive.openBox<String>(_favoritesBoxName);
      await box.clear();
      await _loadFavorites();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }
}

final favoritesProvider = StateNotifierProvider<FavoritesNotifier, FavoritesState>((ref) {
  return FavoritesNotifier();
});
