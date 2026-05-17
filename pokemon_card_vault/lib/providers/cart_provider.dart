import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
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

  Map<String, dynamic> toJson() {
    return {
      'card': card.toJson(),
      'quantity': quantity,
    };
  }

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      card: PokemonCard.fromJson(
          Map<String, dynamic>.from(json['card'] as Map? ?? {})),
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
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

  double get subtotal =>
      items.fold(0.0, (total, item) => total + item.totalPrice);

  double get tax => subtotal * 0.08;

  double get shipping => subtotal > 50 ? 0 : 5.99;

  double get total => subtotal + tax + shipping;

  int get itemCount => items.fold(0, (total, item) => total + item.quantity);

  bool isInCart(String cardId) => items.any((item) => item.card.id == cardId);

  int getQuantity(String cardId) {
    for (final item in items) {
      if (item.card.id == cardId) {
        return item.quantity;
      }
    }
    return 0;
  }

  CartState copyWith({
    List<CartItem>? items,
    bool? isLoading,
    String? error,
  }) {
    return CartState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier() : super(CartState()) {
    _authSubscription = Firebase.apps.isEmpty
        ? null
        : FirebaseAuth.instance.authStateChanges().listen((_) {
            _loadCart();
          });
    _loadCart();
  }

  static const String _cartBoxName = 'cart_items';
  dynamic _authSubscription;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  User? get _user =>
      Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser;

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadCart() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final localItems = await _loadLocalItems();
      final user = _user;
      if (user == null) {
        state =
            state.copyWith(items: localItems, isLoading: false, error: null);
        return;
      }

      final doc = await _cartDoc(user.uid).get();
      final remoteItems = _itemsFromData(doc.data());
      final merged = _mergeItems(remoteItems, localItems);
      if (!_sameItems(merged, remoteItems)) {
        await _saveRemote(user.uid, merged);
      }
      await _saveLocalItems(merged);
      state = state.copyWith(items: merged, isLoading: false, error: null);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<void> addToCart(PokemonCard card, {int quantity = 1}) async {
    if (card.stock <= 0) {
      state = state.copyWith(error: '${card.name} is currently unavailable');
      return;
    }
    final items = [...state.items];
    final index = items.indexWhere((item) => item.card.id == card.id);
    if (index == -1) {
      items.add(CartItem(card: card, quantity: quantity.clamp(1, card.stock)));
    } else {
      final existing = items[index];
      items[index] = existing.copyWith(
        card: card,
        quantity: (existing.quantity + quantity).clamp(1, card.stock),
      );
    }
    await _persist(items);
  }

  Future<void> removeFromCart(String cardId) async {
    await _persist(
        state.items.where((item) => item.card.id != cardId).toList());
  }

  Future<void> updateQuantity(String cardId, int quantity) async {
    if (quantity <= 0) {
      await removeFromCart(cardId);
      return;
    }
    final items = state.items.map((item) {
      if (item.card.id != cardId) {
        return item;
      }
      return item.copyWith(quantity: quantity.clamp(1, item.card.stock));
    }).toList();
    await _persist(items);
  }

  Future<void> clearCart() async {
    await _persist(const []);
  }

  bool isInCart(String cardId) => state.isInCart(cardId);

  int getQuantity(String cardId) => state.getQuantity(cardId);

  Future<void> _persist(List<CartItem> items) async {
    state = state.copyWith(items: items, isLoading: true, error: null);
    try {
      await _saveLocalItems(items);
      final user = _user;
      if (user != null) {
        await _saveRemote(user.uid, items);
      }
      state = state.copyWith(items: items, isLoading: false, error: null);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  DocumentReference<Map<String, dynamic>> _cartDoc(String uid) {
    return _firestore.collection('user_carts').doc(uid);
  }

  Future<List<CartItem>> _loadLocalItems() async {
    final box = await Hive.openBox<Map>(_cartBoxName);
    return box.values
        .map((value) => CartItem.fromJson(Map<String, dynamic>.from(value)))
        .where((item) => item.card.id.isNotEmpty)
        .toList();
  }

  Future<void> _saveLocalItems(List<CartItem> items) async {
    final box = await Hive.openBox<Map>(_cartBoxName);
    await box.clear();
    for (final item in items) {
      await box.put(item.card.id, item.toJson());
    }
  }

  Future<void> _saveRemote(String uid, List<CartItem> items) async {
    await _cartDoc(uid).set({
      'items': items.map((item) => item.toJson()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  List<CartItem> _itemsFromData(Map<String, dynamic>? data) {
    return (data?['items'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((value) => CartItem.fromJson(Map<String, dynamic>.from(value)))
        .where((item) => item.card.id.isNotEmpty)
        .toList();
  }

  List<CartItem> _mergeItems(List<CartItem> remote, List<CartItem> local) {
    final byId = <String, CartItem>{
      for (final item in remote) item.card.id: item,
    };
    for (final item in local) {
      final existing = byId[item.card.id];
      if (existing == null) {
        byId[item.card.id] = item;
      } else {
        byId[item.card.id] = existing.copyWith(
          quantity:
              (existing.quantity + item.quantity).clamp(1, existing.card.stock),
        );
      }
    }
    return byId.values.toList()
      ..sort((a, b) => a.card.name.compareTo(b.card.name));
  }

  bool _sameItems(List<CartItem> a, List<CartItem> b) {
    if (a.length != b.length) {
      return false;
    }
    final aSorted = [...a]..sort((x, y) => x.card.id.compareTo(y.card.id));
    final bSorted = [...b]..sort((x, y) => x.card.id.compareTo(y.card.id));
    for (var index = 0; index < aSorted.length; index++) {
      if (aSorted[index].card.id != bSorted[index].card.id ||
          aSorted[index].quantity != bSorted[index].quantity) {
        return false;
      }
    }
    return true;
  }
}
