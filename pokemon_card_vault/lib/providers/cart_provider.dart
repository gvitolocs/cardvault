import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/pokemon_card.dart';

final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  return CartNotifier();
});

class CartItem {
  final PokemonCard card;
  final int quantity;

  CartItem({
    required this.card,
    required this.quantity,
  });

  double get totalPrice => card.price * quantity;

  CartItem copyWith({
    PokemonCard? card,
    int? quantity,
  }) {
    return CartItem(
      card: card ?? this.card,
      quantity: quantity ?? this.quantity,
    );
  }
}

class CartState {
  final List<CartItem> items;
  final bool isLoading;
  final String? error;

  CartState({
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  double get subtotal => items.fold(0.0, (sum, item) => sum + item.totalPrice);
  
  double get tax => subtotal * 0.08; // 8% tax
  
  double get shipping => subtotal > 50 ? 0 : 5.99; // Free shipping over $50
  
  double get total => subtotal + tax + shipping;
  
  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);
  
  bool isInCart(String cardId) {
    return items.any((item) => item.card.id == cardId);
  }

  int getQuantity(String cardId) {
    final item = items.firstWhere(
      (item) => item.card.id == cardId,
      orElse: () => CartItem(
        card: PokemonCard(
          id: '',
          name: '',
          imageUrl: '',
          rarity: '',
          type: '',
          hp: 0,
          attacks: [],
          price: 0,
          description: '',
          set: '',
          number: '',
          artist: '',
          stock: 0,
          rating: 0,
          reviewCount: 0,
          isFoil: false,
          isHolo: false,
          releaseDate: DateTime.now(),
          tags: [],
          condition: '',
          isGraded: false,
        ),
        quantity: 0,
      ),
    );
    return item.quantity;
  }

  CartState copyWith({
    List<CartItem>? items,
    bool? isLoading,
    String? error,
  }) {
    return CartState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier() : super(CartState()) {
    _loadCart();
  }

  Future<void> _loadCart() async {
    try {
      final box = await Hive.openBox<CartItem>('cart');
      final items = box.values.toList();
      state = state.copyWith(items: items);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> _saveCart() async {
    try {
      final box = await Hive.openBox<CartItem>('cart');
      await box.clear();
      for (int i = 0; i < state.items.length; i++) {
        await box.put(i, state.items[i]);
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  Future<void> addToCart(PokemonCard card, {int quantity = 1}) async {
    try {
      state = state.copyWith(isLoading: true);
      
      final existingItemIndex = state.items.indexWhere(
        (item) => item.card.id == card.id,
      );

      List<CartItem> newItems = List.from(state.items);

      if (existingItemIndex != -1) {
        // Update existing item
        final existingItem = newItems[existingItemIndex];
        newItems[existingItemIndex] = existingItem.copyWith(
          quantity: existingItem.quantity + quantity,
        );
      } else {
        // Add new item
        newItems.add(CartItem(card: card, quantity: quantity));
      }

      state = state.copyWith(
        items: newItems,
        isLoading: false,
      );
      
      await _saveCart();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> removeFromCart(String cardId) async {
    try {
      state = state.copyWith(isLoading: true);
      
      final newItems = state.items.where(
        (item) => item.card.id != cardId,
      ).toList();

      state = state.copyWith(
        items: newItems,
        isLoading: false,
      );
      
      await _saveCart();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> updateQuantity(String cardId, int quantity) async {
    try {
      if (quantity <= 0) {
        await removeFromCart(cardId);
        return;
      }

      state = state.copyWith(isLoading: true);
      
      final itemIndex = state.items.indexWhere(
        (item) => item.card.id == cardId,
      );

      if (itemIndex != -1) {
        List<CartItem> newItems = List.from(state.items);
        newItems[itemIndex] = newItems[itemIndex].copyWith(quantity: quantity);
        
        state = state.copyWith(
          items: newItems,
          isLoading: false,
        );
        
        await _saveCart();
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  Future<void> clearCart() async {
    try {
      state = state.copyWith(isLoading: true);
      
      final box = await Hive.openBox<CartItem>('cart');
      await box.clear();
      
      state = state.copyWith(
        items: [],
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  bool isInCart(String cardId) {
    return state.items.any((item) => item.card.id == cardId);
  }

  int getQuantity(String cardId) {
    final item = state.items.firstWhere(
      (item) => item.card.id == cardId,
      orElse: () => CartItem(card: PokemonCard(
        id: '',
        name: '',
        imageUrl: '',
        rarity: '',
        type: '',
        hp: 0,
        attacks: [],
        price: 0,
        description: '',
        set: '',
        number: '',
        artist: '',
        stock: 0,
        rating: 0,
        reviewCount: 0,
        isFoil: false,
        isHolo: false,
        releaseDate: DateTime.now(),
        tags: [],
        condition: '',
        isGraded: false,
      ), quantity: 0),
    );
    return item.quantity;
  }
}
