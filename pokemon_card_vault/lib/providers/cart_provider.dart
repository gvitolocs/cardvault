import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/card_listing.dart';
import '../models/pokemon_card.dart';
import '../services/card_listing_service.dart';
import '../services/pokoin_api_auth.dart';

final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  return CartNotifier();
});

const double temporaryFixedCheckoutShippingPkn = 2000;

enum CartFulfillmentMode {
  physical,
  nftOnly;

  String get wireValue {
    switch (this) {
      case CartFulfillmentMode.physical:
        return 'physical';
      case CartFulfillmentMode.nftOnly:
        return 'nft_only';
    }
  }

  static CartFulfillmentMode fromWireValue(Object? value) {
    return '${value ?? ''}' == 'nft_only'
        ? CartFulfillmentMode.nftOnly
        : CartFulfillmentMode.physical;
  }
}

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
  final bool sealed;
  final bool graded;
  final String? gradingCompany;
  final String? grade;
  final String? certificationId;
  final bool shippingAvailable;
  final bool reserveAvailable;
  final bool nftAvailable;
  final String source;
  final String sourceListingId;
  final Map<String, dynamic> sourceMetadata;

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
    this.sealed = false,
    this.graded = false,
    this.gradingCompany,
    this.grade,
    this.certificationId,
    this.shippingAvailable = false,
    this.reserveAvailable = false,
    this.nftAvailable = false,
    this.source = 'pokoin_user_listing',
    this.sourceListingId = '',
    this.sourceMetadata = const <String, dynamic>{},
  });

  String get cartKey =>
      listingId == null || listingId!.isEmpty ? card.id : listingId!;

  double get unitPrice => unitPricePkn ?? card.price;

  int get maxQuantity => quantityAvailable ?? card.stock;

  double get totalPrice => unitPrice * quantity;

  bool get isNftEligible => nftAvailable;

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
    bool? sealed,
    bool? graded,
    String? gradingCompany,
    String? grade,
    String? certificationId,
    bool? shippingAvailable,
    bool? reserveAvailable,
    bool? nftAvailable,
    String? source,
    String? sourceListingId,
    Map<String, dynamic>? sourceMetadata,
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
      sealed: sealed ?? this.sealed,
      graded: graded ?? this.graded,
      gradingCompany: gradingCompany ?? this.gradingCompany,
      grade: grade ?? this.grade,
      certificationId: certificationId ?? this.certificationId,
      shippingAvailable: shippingAvailable ?? this.shippingAvailable,
      reserveAvailable: reserveAvailable ?? this.reserveAvailable,
      nftAvailable: nftAvailable ?? this.nftAvailable,
      source: source ?? this.source,
      sourceListingId: sourceListingId ?? this.sourceListingId,
      sourceMetadata: sourceMetadata ?? this.sourceMetadata,
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
      'sealed': sealed,
      'graded': graded,
      'gradingCompany': gradingCompany,
      'grade': grade,
      'certificationId': certificationId,
      'shippingAvailable': shippingAvailable,
      'reserveAvailable': reserveAvailable,
      'nftAvailable': nftAvailable,
      'source': source,
      'sourceListingId': sourceListingId,
      'sourceMetadata': sourceMetadata,
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
      sealed: json['sealed'] == true,
      graded: json['graded'] == true,
      gradingCompany: json['gradingCompany'] as String?,
      grade: json['grade'] as String?,
      certificationId: json['certificationId'] as String?,
      shippingAvailable: json['shippingAvailable'] == true,
      reserveAvailable: json['reserveAvailable'] == true,
      nftAvailable: json['nftAvailable'] == true,
      source: '${json['source'] ?? 'pokoin_user_listing'}',
      sourceListingId: '${json['sourceListingId'] ?? ''}',
      sourceMetadata:
          Map<String, dynamic>.from(json['sourceMetadata'] as Map? ?? const {}),
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
      sealed: listing.sealed,
      graded: listing.graded,
      gradingCompany: listing.gradingCompany,
      grade: listing.grade,
      certificationId: listing.certificationId,
      shippingAvailable: listing.shippingAvailable,
      reserveAvailable: listing.reserveAvailable,
      nftAvailable: listing.isNftEligible,
      source: listing.source,
      sourceListingId: listing.sourceListingId,
      sourceMetadata: listing.sourceMetadata,
    );
  }
}

class CartState {
  final List<CartItem> items;
  final bool isLoading;
  final String? error;
  final bool hasHydratedLocalCache;
  final CartFulfillmentMode fulfillmentMode;

  CartState({
    this.items = const [],
    this.isLoading = false,
    this.error,
    this.hasHydratedLocalCache = false,
    this.fulfillmentMode = CartFulfillmentMode.physical,
  });

  double get subtotal =>
      items.fold(0.0, (total, item) => total + item.totalPrice);

  double get tax => subtotal * 0.08;

  bool get canCheckoutNftOnly =>
      items.isNotEmpty && items.every((item) => item.isNftEligible);

  CartFulfillmentMode get effectiveFulfillmentMode =>
      fulfillmentMode == CartFulfillmentMode.nftOnly && canCheckoutNftOnly
          ? CartFulfillmentMode.nftOnly
          : CartFulfillmentMode.physical;

  bool get isNftOnlyCheckout =>
      effectiveFulfillmentMode == CartFulfillmentMode.nftOnly;

  double get shipping =>
      isNftOnlyCheckout ? 0 : temporaryFixedCheckoutShippingPkn;

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
    bool? hasHydratedLocalCache,
    CartFulfillmentMode? fulfillmentMode,
  }) {
    return CartState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      hasHydratedLocalCache:
          hasHydratedLocalCache ?? this.hasHydratedLocalCache,
      fulfillmentMode: fulfillmentMode ?? this.fulfillmentMode,
    );
  }
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier({
    http.Client? httpClient,
    PokoinApiAuthService? apiAuth,
    CardListingService? listingService,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _apiAuth = apiAuth ?? PokoinApiAuthService.instance(),
        _listingService = listingService ?? CardListingService(),
        super(CartState()) {
    _lastUid = _user?.uid;
    if (Firebase.apps.isEmpty) {
      _authSubscription = null;
    } else {
      _authSubscription =
          FirebaseAuth.instance.authStateChanges().listen((user) {
        final nextUid = user?.uid;
        final previousUid = _lastUid;
        if (nextUid == previousUid &&
            (_loadOperation != null || state.hasHydratedLocalCache)) {
          return;
        }
        if (previousUid != null && nextUid != previousUid) {
          state = state.copyWith(
            items: const [],
            isLoading: true,
            error: null,
            hasHydratedLocalCache: false,
            fulfillmentMode: CartFulfillmentMode.physical,
          );
        }
        _lastUid = nextUid;
        unawaited(_loadCartForUid(nextUid, clearPreviousUser: previousUid));
      });
    }
    unawaited(_loadCartForUid(_lastUid));
  }

  static const String _cartBoxName = 'cart_items';
  static const String _cartAnalyticsHolderKey = 'cart_analytics_holder_id';
  dynamic _authSubscription;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final PokoinApiAuthService _apiAuth;
  final CardListingService _listingService;
  String? _lastUid;
  Future<void>? _loadOperation;
  int _loadGeneration = 0;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  User? get _user =>
      Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser;

  @override
  void dispose() {
    _authSubscription?.cancel();
    if (_ownsHttpClient) {
      _httpClient.close();
    }
    super.dispose();
  }

  Future<void> _loadCartForUid(
    String? uid, {
    String? clearPreviousUser,
  }) {
    final generation = ++_loadGeneration;
    final previous = _loadOperation ?? Future<void>.value();
    final operation = previous.catchError((_) {}).then((_) async {
      await _loadCartSnapshot(
        uid,
        generation,
        clearPreviousUser: clearPreviousUser,
      );
    });
    _loadOperation = operation;
    return operation;
  }

  Future<void> _loadCartSnapshot(
    String? uid,
    int generation, {
    String? clearPreviousUser,
  }) async {
    if (clearPreviousUser != null && clearPreviousUser != uid) {
      await _saveLocalItemsForUid(clearPreviousUser, const []);
      await _saveLegacyLocalItems(const []);
    }
    state = state.copyWith(isLoading: true, error: null);
    try {
      final localItems = await _loadLocalItemsForUid(uid);
      if (!_isCurrentLoad(uid, generation)) {
        return;
      }
      state = state.copyWith(
        items: localItems,
        isLoading: uid != null,
        error: null,
        hasHydratedLocalCache: true,
      );
      if (uid == null) {
        final refreshed = await _refreshListingSnapshots(localItems);
        if (!_sameItems(refreshed, localItems)) {
          await _saveLocalItemsForUid(null, refreshed);
          if (!_isCurrentLoad(uid, generation)) {
            return;
          }
          state = state.copyWith(
            items: refreshed,
            isLoading: false,
            error: null,
          );
        }
        return;
      }

      final doc = await _cartDoc(uid).get();
      if (!_isCurrentLoad(uid, generation)) {
        return;
      }
      final remoteItems = _itemsFromData(doc.data());
      final merged = _mergeItems(remoteItems, localItems);
      final refreshed = await _refreshListingSnapshots(merged);
      if (!_sameItems(refreshed, remoteItems)) {
        await _saveRemote(uid, refreshed);
      }
      await _saveLocalItemsForUid(uid, refreshed);
      if (!_isCurrentLoad(uid, generation)) {
        return;
      }
      state = state.copyWith(items: refreshed, isLoading: false, error: null);
    } catch (error) {
      if (_isCurrentLoad(uid, generation)) {
        state = state.copyWith(isLoading: false, error: error.toString());
      }
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
    CartFulfillmentMode? fulfillmentMode,
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
        reserveAvailable: listing.reserveAvailable,
        nftAvailable: listing.isNftEligible,
        source: listing.source,
        sourceListingId: listing.sourceListingId,
        sourceMetadata: listing.sourceMetadata,
      );
    }
    await _persist(items, fulfillmentMode: fulfillmentMode);
  }

  Future<void> removeFromCart(String cardId) async {
    await _persist(state.items
        .where((item) => item.card.id != cardId && item.cartKey != cardId)
        .toList());
  }

  Future<void> updateQuantity(String cartKey, int quantity) async {
    if (quantity <= 0) {
      await removeFromCart(cartKey);
      return;
    }
    final items = state.items.map((item) {
      if (item.card.id != cartKey && item.cartKey != cartKey) {
        return item;
      }
      return item.copyWith(quantity: quantity.clamp(1, item.maxQuantity));
    }).toList();
    await _persist(items);
  }

  Future<void> clearCart() async {
    await _persist(const []);
  }

  void setFulfillmentMode(CartFulfillmentMode mode) {
    final nextMode =
        mode == CartFulfillmentMode.nftOnly && !state.canCheckoutNftOnly
            ? CartFulfillmentMode.physical
            : mode;
    state = state.copyWith(fulfillmentMode: nextMode, error: null);
  }

  bool isInCart(String cardId) => state.isInCart(cardId);

  int getQuantity(String cardId) => state.getQuantity(cardId);

  Future<void> _persist(
    List<CartItem> items, {
    CartFulfillmentMode? fulfillmentMode,
  }) async {
    final previousItems = state.items;
    final requestedMode = fulfillmentMode ?? state.fulfillmentMode;
    final mode = requestedMode == CartFulfillmentMode.nftOnly &&
            (items.isEmpty || items.any((item) => !item.isNftEligible))
        ? CartFulfillmentMode.physical
        : requestedMode;
    state = state.copyWith(
      items: items,
      isLoading: true,
      error: null,
      fulfillmentMode: mode,
    );
    try {
      final user = _user;
      await _saveLocalItemsForUid(user?.uid, items);
      if (user != null) {
        await _saveRemote(user.uid, items);
      }
      state = state.copyWith(
        items: items,
        isLoading: false,
        error: null,
        hasHydratedLocalCache: true,
        fulfillmentMode: mode,
      );
      _recordCartAnalyticsDiff(previousItems, items);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  void _recordCartAnalyticsDiff(
    List<CartItem> previousItems,
    List<CartItem> nextItems,
  ) {
    final previousIds = _cartCardIds(previousItems);
    final nextIds = _cartCardIds(nextItems);
    for (final cardId in nextIds.difference(previousIds)) {
      _recordCartAnalytics(cardId, 'add');
    }
    for (final cardId in previousIds.difference(nextIds)) {
      _recordCartAnalytics(cardId, 'remove');
    }
  }

  Set<String> _cartCardIds(List<CartItem> items) {
    final ids = <String>{};
    for (final item in items) {
      final id = item.card.id.trim();
      final numericId = int.tryParse(id);
      if (numericId != null && numericId > 0) {
        ids.add(id);
      }
    }
    return ids;
  }

  void _recordCartAnalytics(String cardId, String action) {
    final numericId = int.tryParse(cardId.trim());
    if (numericId == null || numericId <= 0) {
      return;
    }
    unawaited(Future<void>(() async {
      try {
        final authHeaders = await _apiAuth.authorizationHeaders(
          requireSignedIn: false,
        );
        final anonymousId = await _cartAnalyticsHolderId();
        await _httpClient
            .post(
              Uri.base.resolve('/api/marketplace-cart'),
              headers: {
                'content-type': 'application/json',
                ...authHeaders,
              },
              body: jsonEncode({
                'cardId': numericId,
                'action': action,
                'anonymousId': anonymousId,
                'source': 'flutter',
              }),
            )
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        // Cart analytics should not affect local cart state.
      }
    }));
  }

  Future<String> _cartAnalyticsHolderId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_cartAnalyticsHolderKey);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing;
    }
    final generated =
        'cart-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
    await prefs.setString(_cartAnalyticsHolderKey, generated);
    return generated;
  }

  DocumentReference<Map<String, dynamic>> _cartDoc(String uid) {
    return _firestore.collection('user_carts').doc(uid);
  }

  Future<List<CartItem>> _loadLocalItemsForUid(String? uid) async {
    final box = await _openLocalBox(uid);
    final items = box.values
        .map((value) => CartItem.fromJson(Map<String, dynamic>.from(value)))
        .where((item) => item.card.id.isNotEmpty)
        .toList();
    if (items.isNotEmpty) {
      return items;
    }
    if (uid != null && uid.isNotEmpty) {
      return const [];
    }
    return _loadLegacyLocalItems();
  }

  Future<void> _saveLocalItemsForUid(String? uid, List<CartItem> items) async {
    final box = await _openLocalBox(uid);
    await box.clear();
    for (final item in items) {
      await box.put(item.cartKey, item.toJson());
    }
    await _saveLegacyLocalItems(const []);
  }

  Future<Box<Map>> _openLocalBox(String? uid) {
    final suffix =
        uid == null || uid.isEmpty ? 'guest' : uid.replaceAll(':', '_');
    return Hive.openBox<Map>('${_cartBoxName}_$suffix');
  }

  Future<List<CartItem>> _loadLegacyLocalItems() async {
    final box = await Hive.openBox<Map>(_cartBoxName);
    return box.values
        .map((value) => CartItem.fromJson(Map<String, dynamic>.from(value)))
        .where((item) => item.card.id.isNotEmpty)
        .toList();
  }

  Future<void> _saveLegacyLocalItems(List<CartItem> items) async {
    final box = await Hive.openBox<Map>(_cartBoxName);
    await box.clear();
    for (final item in items) {
      await box.put(item.cartKey, item.toJson());
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

  Future<List<CartItem>> _refreshListingSnapshots(List<CartItem> items) async {
    final listingIds = items
        .map((item) => item.listingId?.trim() ?? '')
        .where((id) => _isNativeListingId(id))
        .toSet();
    if (listingIds.isEmpty) {
      return items;
    }
    try {
      final listings = await _listingService.listingsByIds(listingIds);
      if (listings.isEmpty) {
        return items;
      }
      final byId = {
        for (final listing in listings)
          if (listing.id.trim().isNotEmpty) listing.id: listing,
      };
      return items.map((item) {
        final listing = byId[item.listingId?.trim()];
        if (listing == null) {
          return item;
        }
        final quantity = item.quantity.clamp(1, listing.quantityAvailable);
        return item.copyWith(
          card: item.card.copyWith(
            price: listing.pricePkn,
            stock: listing.quantityAvailable,
            condition: listing.condition,
          ),
          quantity: quantity,
          sellerUid: listing.sellerUid,
          sellerName: listing.sellerName,
          condition: listing.condition,
          language: listing.language,
          unitPricePkn: listing.pricePkn,
          quantityAvailable: listing.quantityAvailable,
          reverse: listing.reverse,
          sealed: listing.sealed,
          graded: listing.graded,
          gradingCompany: listing.gradingCompany,
          grade: listing.grade,
          certificationId: listing.certificationId,
          shippingAvailable: listing.shippingAvailable,
          reserveAvailable: listing.reserveAvailable,
          nftAvailable: listing.isNftEligible,
          source: listing.source,
          sourceListingId: listing.sourceListingId,
          sourceMetadata: listing.sourceMetadata,
        );
      }).toList(growable: false);
    } catch (_) {
      return items;
    }
  }

  bool _isNativeListingId(String id) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(id);
  }

  bool _sameItems(List<CartItem> a, List<CartItem> b) {
    if (a.length != b.length) {
      return false;
    }
    final aSorted = [...a]..sort((x, y) => x.cartKey.compareTo(y.cartKey));
    final bSorted = [...b]..sort((x, y) => x.cartKey.compareTo(y.cartKey));
    for (var index = 0; index < aSorted.length; index++) {
      if (aSorted[index].cartKey != bSorted[index].cartKey ||
          aSorted[index].quantity != bSorted[index].quantity ||
          aSorted[index].sellerName != bSorted[index].sellerName ||
          aSorted[index].unitPricePkn != bSorted[index].unitPricePkn ||
          aSorted[index].quantityAvailable !=
              bSorted[index].quantityAvailable ||
          aSorted[index].condition != bSorted[index].condition ||
          aSorted[index].language != bSorted[index].language ||
          aSorted[index].reserveAvailable != bSorted[index].reserveAvailable ||
          aSorted[index].nftAvailable != bSorted[index].nftAvailable) {
        return false;
      }
    }
    return true;
  }

  bool _isCurrentLoad(String? uid, int generation) {
    return mounted && generation == _loadGeneration && uid == _lastUid;
  }
}
