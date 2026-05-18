import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/card_listing.dart';
import '../models/pokemon_card.dart';

final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  return CartNotifier();
});

class CartItem {
  final PokemonCard card;
  final int quantity;
  final String? listingId;
  final String? sellerUid;
  final String? sellerName;
  final String? condition;
  final String? language;
  final double? unitPricePkn;
  final int? quantityAvailable;
  final bool reverse;
  final bool graded;
  final String? gradingCompany;
  final String? grade;
  final String? certificationId;
  final bool shippingAvailable;
  final bool nftAvailable;

  CartItem({
    required this.card,
    required this.quantity,
    this.listingId,
    this.sellerUid,
    this.sellerName,
    this.condition,
    this.language,
    this.unitPricePkn,
    this.quantityAvailable,
    this.reverse = false,
    this.graded = false,
    this.gradingCompany,
    this.grade,
    this.certificationId,
    this.shippingAvailable = false,
    this.nftAvailable = false,
  });

  String get cartKey =>
      listingId == null || listingId!.isEmpty ? card.id : listingId!;

  double get unitPrice => unitPricePkn ?? card.price;

  int get maxQuantity => quantityAvailable ?? card.stock;

  double get totalPrice => unitPrice * quantity;

  CartItem copyWith({
    PokemonCard? card,
    int? quantity,
    String? listingId,
    String? sellerUid,
    String? sellerName,
    String? condition,
    String? language,
    double? unitPricePkn,
    int? quantityAvailable,
    bool? reverse,
    bool? graded,
    String? gradingCompany,
    String? grade,
    String? certificationId,
    bool? shippingAvailable,
    bool? nftAvailable,
  }) {
    return CartItem(
      card: card ?? this.card,
      quantity: quantity ?? this.quantity,
      listingId: listingId ?? this.listingId,
      sellerUid: sellerUid ?? this.sellerUid,
      sellerName: sellerName ?? this.sellerName,
      condition: condition ?? this.condition,
      language: language ?? this.language,
      unitPricePkn: unitPricePkn ?? this.unitPricePkn,
      quantityAvailable: quantityAvailable ?? this.quantityAvailable,
      reverse: reverse ?? this.reverse,
      graded: graded ?? this.graded,
      gradingCompany: gradingCompany ?? this.gradingCompany,
      grade: grade ?? this.grade,
      certificationId: certificationId ?? this.certificationId,
      shippingAvailable: shippingAvailable ?? this.shippingAvailable,
      nftAvailable: nftAvailable ?? this.nftAvailable,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'card': card.toJson(),
      'quantity': quantity,
      'listingId': listingId,
      'sellerUid': sellerUid,
      'sellerName': sellerName,
      'condition': condition,
      'language': language,
      'unitPricePkn': unitPricePkn,
      'quantityAvailable': quantityAvailable,
      'reverse': reverse,
      'graded': graded,
      'gradingCompany': gradingCompany,
      'grade': grade,
      'certificationId': certificationId,
      'shippingAvailable': shippingAvailable,
      'nftAvailable': nftAvailable,
    };
  }

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      card: PokemonCard.fromJson(
          Map<String, dynamic>.from(json['card'] as Map? ?? {})),
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      listingId: json['listingId'] as String?,
      sellerUid: json['sellerUid'] as String?,
      sellerName: json['sellerName'] as String?,
      condition: json['condition'] as String?,
      language: json['language'] as String?,
      unitPricePkn: (json['unitPricePkn'] as num?)?.toDouble(),
      quantityAvailable: (json['quantityAvailable'] as num?)?.toInt(),
      reverse: json['reverse'] == true,
      graded: json['graded'] == true,
      gradingCompany: json['gradingCompany'] as String?,
      grade: json['grade'] as String?,
      certificationId: json['certificationId'] as String?,
      shippingAvailable: json['shippingAvailable'] == true,
      nftAvailable: json['nftAvailable'] == true,
    );
  }

  factory CartItem.fromListing({
    required PokemonCard card,
    required CardListing listing,
    int quantity = 1,
  }) {
    return CartItem(
      card: card.copyWith(
        price: listing.pricePkn,
        stock: listing.quantityAvailable,
        condition: listing.condition,
      ),
      quantity: quantity.clamp(1, listing.quantityAvailable),
      listingId: listing.id,
      sellerUid: listing.sellerUid,
      sellerName: listing.sellerName,
      condition: listing.condition,
      language: listing.language,
      unitPricePkn: listing.pricePkn,
      quantityAvailable: listing.quantityAvailable,
      reverse: listing.reverse,
      graded: listing.graded,
      gradingCompany: listing.gradingCompany,
      grade: listing.grade,
      certificationId: listing.certificationId,
      shippingAvailable: listing.shippingAvailable,
      nftAvailable: listing.nftAvailable,
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

  bool isListingInCart(String listingId) =>
      items.any((item) => item.listingId == listingId);

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

  Future<void> addListingToCart(
    PokemonCard card,
    CardListing listing, {
    int quantity = 1,
  }) async {
    if (!listing.isActive) {
      state = state.copyWith(error: '${card.name} is currently unavailable');
      return;
    }
    final items = [...state.items];
    final index = items.indexWhere((item) => item.cartKey == listing.id);
    if (index == -1) {
      items.add(CartItem.fromListing(
        card: card,
        listing: listing,
        quantity: quantity,
      ));
    } else {
      final existing = items[index];
      items[index] = existing.copyWith(
        card: card.copyWith(
          price: listing.pricePkn,
          stock: listing.quantityAvailable,
          condition: listing.condition,
        ),
        quantity:
            (existing.quantity + quantity).clamp(1, listing.quantityAvailable),
        listingId: listing.id,
        sellerUid: listing.sellerUid,
        sellerName: listing.sellerName,
        condition: listing.condition,
        language: listing.language,
        unitPricePkn: listing.pricePkn,
        quantityAvailable: listing.quantityAvailable,
        reverse: listing.reverse,
        graded: listing.graded,
        gradingCompany: listing.gradingCompany,
        grade: listing.grade,
        certificationId: listing.certificationId,
        shippingAvailable: listing.shippingAvailable,
        nftAvailable: listing.nftAvailable,
      );
    }
    await _persist(items);
  }

  Future<void> removeFromCart(String cardId) async {
    await _persist(state.items
        .where((item) => item.card.id != cardId && item.cartKey != cardId)
        .toList());
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
      return item.copyWith(quantity: quantity.clamp(1, item.maxQuantity));
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
      for (final item in remote) item.cartKey: item,
    };
    for (final item in local) {
      final existing = byId[item.cartKey];
      if (existing == null) {
        byId[item.cartKey] = item;
      } else {
        byId[item.cartKey] = existing.copyWith(
          quantity: (existing.quantity + item.quantity)
              .clamp(1, existing.maxQuantity),
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
    final aSorted = [...a]..sort((x, y) => x.cartKey.compareTo(y.cartKey));
    final bSorted = [...b]..sort((x, y) => x.cartKey.compareTo(y.cartKey));
    for (var index = 0; index < aSorted.length; index++) {
      if (aSorted[index].cartKey != bSorted[index].cartKey ||
          aSorted[index].quantity != bSorted[index].quantity) {
        return false;
      }
    }
    return true;
  }
}
