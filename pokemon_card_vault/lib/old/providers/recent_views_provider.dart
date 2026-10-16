import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/pokemon_card.dart';

final recentViewsProvider =
    StateNotifierProvider<RecentViewsNotifier, RecentViewsState>((ref) {
  return RecentViewsNotifier();
});

class RecentCardView {
  const RecentCardView({
    required this.cardId,
    required this.name,
    required this.expansion,
    required this.number,
    required this.imageUrl,
    required this.previewImageUrl,
    required this.homepageImageUrl,
    required this.viewedAt,
    this.itemKind = 'single',
    this.productType = 'card',
    this.canonicalPath = '',
    this.publicNumber = '',
    this.pricePkn,
    this.available = false,
    this.listingCount = 0,
    this.listedQuantity = 0,
    this.priceSource = '',
    this.emoji = '',
    this.cardPalette = const {},
  });

  final String cardId;
  final String name;
  final String expansion;
  final String number;
  final String imageUrl;
  final String previewImageUrl;
  final String homepageImageUrl;
  final DateTime viewedAt;
  final String itemKind;
  final String productType;
  final String canonicalPath;
  final String publicNumber;
  final double? pricePkn;
  final bool available;
  final int listingCount;
  final int listedQuantity;
  final String priceSource;
  final String emoji;
  final Map<String, dynamic> cardPalette;

  factory RecentCardView.fromCard(PokemonCard card, DateTime viewedAt) {
    final cachesMarketPrice = card.productType == 'card' &&
        card.itemKind != 'product' &&
        card.isMarketAvailable &&
        card.price > 0;
    return RecentCardView(
      cardId: card.id,
      name: card.name,
      expansion: card.set,
      number: card.number,
      imageUrl: card.imageUrl,
      previewImageUrl: card.previewImageUrl,
      homepageImageUrl: card.homepageImageUrl,
      viewedAt: viewedAt,
      itemKind: card.itemKind,
      productType: card.productType,
      canonicalPath: card.canonicalPath,
      publicNumber: _publicNumberFromMarketplacePath(card.canonicalPath),
      pricePkn: cachesMarketPrice ? card.price : null,
      available: cachesMarketPrice,
      listingCount: cachesMarketPrice ? card.cardtraderEligibleListingCount : 0,
      listedQuantity: cachesMarketPrice ? card.stock : 0,
      priceSource: cachesMarketPrice
          ? (card.hasCardTraderListing ? 'cardtrader' : 'homepage')
          : '',
      emoji: card.emoji,
      cardPalette: card.cardPalette,
    );
  }

  factory RecentCardView.fromJson(Map<String, dynamic> json) {
    return RecentCardView(
      cardId: '${json['cardId'] ?? json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      expansion: '${json['expansion'] ?? json['set'] ?? ''}',
      number: '${json['number'] ?? ''}',
      imageUrl: '${json['imageUrl'] ?? ''}',
      previewImageUrl: '${json['previewImageUrl'] ?? json['imageUrl'] ?? ''}',
      homepageImageUrl:
          '${json['homepageImageUrl'] ?? json['previewImageUrl'] ?? json['imageUrl'] ?? ''}',
      viewedAt: _parseDate(json['viewedAt']),
      itemKind: '${json['itemKind'] ?? 'single'}',
      productType: '${json['productType'] ?? json['product_type'] ?? 'card'}',
      canonicalPath:
          '${json['canonicalPath'] ?? json['canonical_path'] ?? ''}'.trim(),
      publicNumber:
          '${json['publicNumber'] ?? json['public_number'] ?? ''}'.trim(),
      pricePkn: _readDouble(json, const [
        'pricePkn',
        'marketPricePkn',
        'market_price_pkn',
        'lowestPricePkn',
        'lowest_price_pkn',
      ]),
      available: _readBool(json, const [
        'available',
        'inStock',
        'in_stock',
        'hasCardTraderListing',
        'has_cardtrader_listing',
      ]),
      listingCount: _readInt(json, const [
        'listingCount',
        'listing_count',
        'cardtraderEligibleListingCount',
        'cardtrader_eligible_listing_count',
      ]),
      listedQuantity: _readInt(json, const [
        'listedQuantity',
        'listed_quantity',
        'stock',
        'quantity',
      ]),
      priceSource:
          '${json['priceSource'] ?? json['price_source'] ?? json['source'] ?? ''}'
              .trim(),
      emoji: '${json['emoji'] ?? ''}',
      cardPalette: _readMap(json['cardPalette'] ?? json['card_palette']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cardId': cardId,
      'name': name,
      'expansion': expansion,
      'number': number,
      'imageUrl': imageUrl,
      'previewImageUrl': previewImageUrl,
      'homepageImageUrl': homepageImageUrl,
      'viewedAt': viewedAt.toIso8601String(),
      'itemKind': itemKind,
      'productType': productType,
      'canonicalPath': canonicalPath,
      'publicNumber': publicNumber,
      if (pricePkn != null) 'pricePkn': pricePkn,
      'available': available,
      'inStock': available,
      'listingCount': listingCount,
      'listedQuantity': listedQuantity,
      if (priceSource.isNotEmpty) 'priceSource': priceSource,
      'emoji': emoji,
      'cardPalette': cardPalette,
    };
  }

  Map<String, dynamic> toFirestore() {
    return {
      'cardId': cardId,
      'name': name,
      'expansion': expansion,
      'number': number,
      'imageUrl': imageUrl,
      'previewImageUrl': previewImageUrl,
      'homepageImageUrl': homepageImageUrl,
      'viewedAt': Timestamp.fromDate(viewedAt),
      'itemKind': itemKind,
      'productType': productType,
      'canonicalPath': canonicalPath,
      'publicNumber': publicNumber,
      if (pricePkn != null) 'pricePkn': pricePkn,
      'available': available,
      'inStock': available,
      'listingCount': listingCount,
      'listedQuantity': listedQuantity,
      if (priceSource.isNotEmpty) 'priceSource': priceSource,
      'emoji': emoji,
      'cardPalette': cardPalette,
    };
  }

  static const Object _unset = Object();

  RecentCardView copyWith({
    String? cardId,
    String? name,
    String? expansion,
    String? number,
    String? imageUrl,
    String? previewImageUrl,
    String? homepageImageUrl,
    DateTime? viewedAt,
    String? itemKind,
    String? productType,
    String? canonicalPath,
    String? publicNumber,
    Object? pricePkn = _unset,
    bool? available,
    int? listingCount,
    int? listedQuantity,
    String? priceSource,
    String? emoji,
    Map<String, dynamic>? cardPalette,
  }) {
    return RecentCardView(
      cardId: cardId ?? this.cardId,
      name: name ?? this.name,
      expansion: expansion ?? this.expansion,
      number: number ?? this.number,
      imageUrl: imageUrl ?? this.imageUrl,
      previewImageUrl: previewImageUrl ?? this.previewImageUrl,
      homepageImageUrl: homepageImageUrl ?? this.homepageImageUrl,
      viewedAt: viewedAt ?? this.viewedAt,
      itemKind: itemKind ?? this.itemKind,
      productType: productType ?? this.productType,
      canonicalPath: canonicalPath ?? this.canonicalPath,
      publicNumber: publicNumber ?? this.publicNumber,
      pricePkn:
          identical(pricePkn, _unset) ? this.pricePkn : pricePkn as double?,
      available: available ?? this.available,
      listingCount: listingCount ?? this.listingCount,
      listedQuantity: listedQuantity ?? this.listedQuantity,
      priceSource: priceSource ?? this.priceSource,
      emoji: emoji ?? this.emoji,
      cardPalette: cardPalette ?? this.cardPalette,
    );
  }

  static DateTime _parseDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    return DateTime.tryParse('${value ?? ''}') ?? DateTime.now();
  }

  static Map<String, dynamic> _readMap(Object? value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const {};
  }

  static double? _readDouble(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is num && value > 0) {
        return value.toDouble();
      }
      final parsed = double.tryParse('${value ?? ''}'.trim());
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
    return null;
  }

  static int _readInt(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is num) {
        return value.toInt();
      }
      final parsed = int.tryParse('${value ?? ''}'.trim());
      if (parsed != null) {
        return parsed;
      }
    }
    return 0;
  }

  static bool _readBool(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is bool) {
        return value;
      }
      if (value is num) {
        return value > 0;
      }
      final text = '${value ?? ''}'.trim().toLowerCase();
      if (const {'true', '1', 'yes', 'y'}.contains(text)) {
        return true;
      }
      if (const {'false', '0', 'no', 'n'}.contains(text)) {
        return false;
      }
    }
    return false;
  }

  static String _publicNumberFromMarketplacePath(String canonicalPath) {
    final match = RegExp(r'/cards/([0-9]+)(?:/|$)').firstMatch(canonicalPath);
    return match?.group(1) ?? '';
  }
}

class RecentViewsState {
  const RecentViewsState({
    this.views = const [],
    this.isLoading = false,
    this.error,
  });

  final List<RecentCardView> views;
  final bool isLoading;
  final String? error;

  RecentViewsState copyWith({
    List<RecentCardView>? views,
    bool? isLoading,
    String? error,
  }) {
    return RecentViewsState(
      views: views ?? this.views,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class RecentViewsNotifier extends StateNotifier<RecentViewsState> {
  RecentViewsNotifier() : super(const RecentViewsState()) {
    _authSubscription = Firebase.apps.isEmpty
        ? null
        : FirebaseAuth.instance.authStateChanges().listen((user) {
            if (_lastUid != null && user?.uid != _lastUid) {
              unawaited(_saveLocal(const []));
              state = state.copyWith(
                views: const [],
                isLoading: true,
                error: null,
              );
            }
            _lastUid = user?.uid;
            _startLoadRecentViews();
          });
    _lastUid = _user?.uid;
    _startLoadRecentViews();
  }

  static const String _recentViewsBoxName = 'recent_card_views';
  static const int _limit = 60;
  static const Duration _retentionWindow = Duration(days: 30);
  dynamic _authSubscription;
  Future<void>? _loadFuture;
  String? _lastUid;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  User? get _user =>
      Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser;

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> remember(PokemonCard card, {bool updateState = true}) async {
    await _loadFuture;
    final view = RecentCardView.fromCard(card, DateTime.now());
    final updated = _dedupeAndLimit([view, ...state.views]);
    if (updateState) {
      state = state.copyWith(views: updated, isLoading: false, error: null);
    }
    await _persist(updated, updateState: updateState);
  }

  void rememberNow(PokemonCard card) {
    final view = RecentCardView.fromCard(card, DateTime.now());
    final updated = _dedupeAndLimit([view, ...state.views]);
    state = state.copyWith(views: updated, isLoading: false, error: null);
    unawaited(_persist(updated));
    final loadFuture = _loadFuture;
    if (loadFuture != null) {
      unawaited(loadFuture.whenComplete(() {
        final refreshed = _dedupeAndLimit([view, ...state.views]);
        state = state.copyWith(
          views: refreshed,
          isLoading: false,
          error: null,
        );
        unawaited(_persist(refreshed));
      }));
    }
  }

  Future<void> _persist(
    List<RecentCardView> updated, {
    bool updateState = true,
  }) async {
    try {
      await _saveLocal(updated);
      final user = _user;
      if (user != null) {
        await _recentViewsDoc(user.uid).set({
          'cardIds': updated.map((item) => item.cardId).toList(),
          'cards': updated.map((item) => item.toFirestore()).toList(),
          'updatedAt': FieldValue.serverTimestamp(),
          'expiresAt': _expiresAt(),
        }, SetOptions(merge: true));
      }
    } catch (error) {
      if (updateState) {
        state = state.copyWith(error: error.toString());
      }
    }
  }

  Future<void> clear() async {
    state = state.copyWith(views: const [], isLoading: false, error: null);
    try {
      await _saveLocal(const []);
      final user = _user;
      if (user != null) {
        await _recentViewsDoc(user.uid).set({
          'cardIds': const <String>[],
          'cards': const <Map<String, dynamic>>[],
          'updatedAt': FieldValue.serverTimestamp(),
          'expiresAt': _expiresAt(),
        }, SetOptions(merge: true));
      }
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  void replaceHydratedViews(List<RecentCardView> views) {
    final updated = _dedupeAndLimit(views);
    if (_sameViewsWithIdentity(updated, state.views)) {
      return;
    }
    state = state.copyWith(views: updated, isLoading: false, error: null);
    unawaited(_persist(updated));
  }

  void _startLoadRecentViews() {
    final future = _loadRecentViews();
    _loadFuture = future;
    unawaited(future.whenComplete(() {
      if (identical(_loadFuture, future)) {
        _loadFuture = null;
      }
    }));
  }

  Future<void> _loadRecentViews() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final local = await _localRecentViews();
      state = state.copyWith(views: local, isLoading: true, error: null);
      final user = _user;
      if (user == null) {
        state = state.copyWith(views: local, isLoading: false, error: null);
        return;
      }

      final doc = await _recentViewsDoc(user.uid).get();
      final data = doc.data();
      if (_isExpired(data)) {
        if (local.isNotEmpty) {
          await _recentViewsDoc(user.uid).set({
            'cardIds': local.map((item) => item.cardId).toList(),
            'cards': local.map((item) => item.toFirestore()).toList(),
            'updatedAt': FieldValue.serverTimestamp(),
            'expiresAt': _expiresAt(),
          }, SetOptions(merge: true));
          await _saveLocal(local);
          state = state.copyWith(
            views: local,
            isLoading: false,
            error: null,
          );
          return;
        }
        await _recentViewsDoc(user.uid).set({
          'cardIds': const <String>[],
          'cards': const <Map<String, dynamic>>[],
          'updatedAt': FieldValue.serverTimestamp(),
          'expiresAt': _expiresAt(),
        }, SetOptions(merge: true));
        await _saveLocal(const []);
        state = state.copyWith(
          views: const [],
          isLoading: false,
          error: null,
        );
        return;
      }
      final remote = _viewsFromDoc(data);
      final merged = _dedupeAndLimit([...remote, ...local]);
      if (merged.length != remote.length || !_sameViews(merged, remote)) {
        await _recentViewsDoc(user.uid).set({
          'cardIds': merged.map((item) => item.cardId).toList(),
          'cards': merged.map((item) => item.toFirestore()).toList(),
          'updatedAt': FieldValue.serverTimestamp(),
          'expiresAt': _expiresAt(),
        }, SetOptions(merge: true));
      } else if (merged.isNotEmpty) {
        await _touchRemote(user.uid);
      }
      await _saveLocal(merged);
      state = state.copyWith(views: merged, isLoading: false, error: null);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  DocumentReference<Map<String, dynamic>> _recentViewsDoc(String uid) {
    return _firestore.collection('user_card_recent_views').doc(uid);
  }

  Future<List<RecentCardView>> _localRecentViews() async {
    final box = await Hive.openBox<Map>(_recentViewsBoxName);
    return _dedupeAndLimit(
      box.values
          .whereType<Map>()
          .map((item) =>
              RecentCardView.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.cardId.isNotEmpty)
          .toList(),
    );
  }

  Future<void> _saveLocal(List<RecentCardView> views) async {
    final box = await Hive.openBox<Map>(_recentViewsBoxName);
    await box.clear();
    for (final view in views.take(_limit)) {
      await box.add(view.toJson());
    }
  }

  List<RecentCardView> _viewsFromDoc(Map<String, dynamic>? data) {
    return _dedupeAndLimit(
      (data?['cards'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) =>
              RecentCardView.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.cardId.isNotEmpty)
          .toList(),
    );
  }

  List<RecentCardView> _dedupeAndLimit(List<RecentCardView> views) {
    final seen = <String>{};
    final unique = <RecentCardView>[];
    final ordered = [...views]
      ..sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    for (final view in ordered) {
      if (seen.add(view.cardId)) {
        unique.add(view);
      }
      if (unique.length >= _limit) {
        break;
      }
    }
    return unique;
  }

  bool _sameViews(List<RecentCardView> a, List<RecentCardView> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (a[index].cardId != b[index].cardId ||
          a[index].viewedAt.millisecondsSinceEpoch !=
              b[index].viewedAt.millisecondsSinceEpoch) {
        return false;
      }
    }
    return true;
  }

  bool _sameViewsWithIdentity(List<RecentCardView> a, List<RecentCardView> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      final left = a[index];
      final right = b[index];
      if (left.cardId != right.cardId ||
          left.viewedAt.millisecondsSinceEpoch !=
              right.viewedAt.millisecondsSinceEpoch ||
          left.canonicalPath != right.canonicalPath ||
          left.publicNumber != right.publicNumber ||
          left.pricePkn != right.pricePkn ||
          left.available != right.available ||
          left.listingCount != right.listingCount ||
          left.listedQuantity != right.listedQuantity ||
          left.priceSource != right.priceSource) {
        return false;
      }
    }
    return true;
  }

  Future<void> _touchRemote(String uid) {
    return _recentViewsDoc(uid).set({
      'updatedAt': FieldValue.serverTimestamp(),
      'expiresAt': _expiresAt(),
    }, SetOptions(merge: true));
  }

  Timestamp _expiresAt() {
    return Timestamp.fromDate(DateTime.now().add(_retentionWindow));
  }

  bool _isExpired(Map<String, dynamic>? data) {
    final value = data?['expiresAt'];
    if (value is Timestamp) {
      return value.toDate().isBefore(DateTime.now());
    }
    return false;
  }
}
