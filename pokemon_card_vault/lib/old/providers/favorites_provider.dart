import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import '../services/pokoin_api_auth.dart';

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, FavoritesState>((ref) {
  return FavoritesNotifier();
});

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
      error: error,
    );
  }

  bool isFavorite(String cardId) => favoriteCardIds.contains(cardId);
}

class FavoritesNotifier extends StateNotifier<FavoritesState> {
  FavoritesNotifier({
    http.Client? httpClient,
    PokoinApiAuthService? apiAuth,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _apiAuth = apiAuth ?? PokoinApiAuthService.instance(),
        super(FavoritesState()) {
    _authSubscription = Firebase.apps.isEmpty
        ? null
        : FirebaseAuth.instance.authStateChanges().listen((_) {
            _loadFavorites();
          });
    _loadFavorites();
  }

  static const String _favoritesBoxName = 'favorites';
  static const Duration _retentionWindow = Duration(days: 30);
  dynamic _authSubscription;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  final PokoinApiAuthService _apiAuth;

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

  Future<void> _loadFavorites() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final user = _user;
      if (user == null) {
        final box = await Hive.openBox<String>(_favoritesBoxName);
        state = state.copyWith(
          favoriteCardIds: box.values.toSet().toList(),
          isLoading: false,
          error: null,
        );
        return;
      }

      final doc = await _favoriteDoc(user.uid).get();
      final data = doc.data();
      if (_isExpired(data)) {
        await _favoriteDoc(user.uid).set({
          'cardIds': const <String>[],
          'updatedAt': FieldValue.serverTimestamp(),
          'expiresAt': _expiresAt(),
        }, SetOptions(merge: true));
        await _saveLocal(const []);
        state = state.copyWith(
          favoriteCardIds: const [],
          isLoading: false,
          error: null,
        );
        return;
      }
      final remoteIds = _idsFromDoc(data);
      final localIds = await _localFavoriteIds();
      final merged = {...remoteIds, ...localIds}.toList()..sort();
      if (merged.length != remoteIds.length || !_sameIds(merged, remoteIds)) {
        await _favoriteDoc(user.uid).set({
          'cardIds': merged,
          'updatedAt': FieldValue.serverTimestamp(),
          'expiresAt': _expiresAt(),
        }, SetOptions(merge: true));
      } else if (merged.isNotEmpty) {
        await _touchRemote(user.uid);
      }
      await _saveLocal(merged);
      state = state.copyWith(
        favoriteCardIds: merged,
        isLoading: false,
        error: null,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<void> toggleFavorite(String cardId) async {
    final ids = state.favoriteCardIds.toSet();
    final action = ids.contains(cardId) ? 'remove' : 'add';
    if (action == 'remove') {
      ids.remove(cardId);
    } else {
      ids.add(cardId);
    }
    await _persist(ids.toList()..sort());
    _recordWatchlistAnalytics(cardId, action);
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
    final removedIds = [...state.favoriteCardIds];
    await _persist(const []);
    for (final cardId in removedIds) {
      _recordWatchlistAnalytics(cardId, 'remove');
    }
  }

  Future<void> _persist(List<String> ids) async {
    state = state.copyWith(favoriteCardIds: ids, isLoading: true, error: null);
    try {
      await _saveLocal(ids);
      final user = _user;
      if (user != null) {
        await _favoriteDoc(user.uid).set({
          'cardIds': ids,
          'updatedAt': FieldValue.serverTimestamp(),
          'expiresAt': _expiresAt(),
        }, SetOptions(merge: true));
      }
      state = state.copyWith(
        favoriteCardIds: ids,
        isLoading: false,
        error: null,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  DocumentReference<Map<String, dynamic>> _favoriteDoc(String uid) {
    return _firestore.collection('user_card_watchlists').doc(uid);
  }

  Future<List<String>> _localFavoriteIds() async {
    final box = await Hive.openBox<String>(_favoritesBoxName);
    return box.values.toSet().toList();
  }

  Future<void> _saveLocal(List<String> ids) async {
    final box = await Hive.openBox<String>(_favoritesBoxName);
    await box.clear();
    for (final id in ids) {
      await box.add(id);
    }
  }

  List<String> _idsFromDoc(Map<String, dynamic>? data) {
    return (data?['cardIds'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
  }

  Future<void> _touchRemote(String uid) {
    return _favoriteDoc(uid).set({
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

  bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) {
        return false;
      }
    }
    return true;
  }

  void _recordWatchlistAnalytics(String cardId, String action) {
    final numericId = int.tryParse(cardId.trim());
    if (numericId == null || numericId <= 0) {
      return;
    }
    unawaited(Future<void>(() async {
      try {
        final authHeaders = await _apiAuth.authorizationHeaders(
          requireSignedIn: false,
        );
        await _httpClient
            .post(
              Uri.base.resolve('/api/marketplace-watchlist'),
              headers: {
                'content-type': 'application/json',
                ...authHeaders,
              },
              body: jsonEncode({
                'cardId': numericId,
                'action': action,
                'source': 'flutter',
              }),
            )
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        // Watchlist analytics should not affect local watchlist state.
      }
    }));
  }
}
