import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

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
  FavoritesNotifier() : super(FavoritesState()) {
    _authSubscription = Firebase.apps.isEmpty
        ? null
        : FirebaseAuth.instance.authStateChanges().listen((_) {
            _loadFavorites();
          });
    _loadFavorites();
  }

  static const String _favoritesBoxName = 'favorites';
  dynamic _authSubscription;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  User? get _user =>
      Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser;

  @override
  void dispose() {
    _authSubscription?.cancel();
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
      final remoteIds = _idsFromDoc(doc.data());
      final localIds = await _localFavoriteIds();
      final merged = {...remoteIds, ...localIds}.toList()..sort();
      if (merged.length != remoteIds.length || !_sameIds(merged, remoteIds)) {
        await _favoriteDoc(user.uid).set({
          'cardIds': merged,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
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
    ids.contains(cardId) ? ids.remove(cardId) : ids.add(cardId);
    await _persist(ids.toList()..sort());
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
    await _persist(const []);
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
}
