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
    required this.viewedAt,
  });

  final String cardId;
  final String name;
  final String expansion;
  final String number;
  final String imageUrl;
  final String previewImageUrl;
  final DateTime viewedAt;

  factory RecentCardView.fromCard(PokemonCard card, DateTime viewedAt) {
    return RecentCardView(
      cardId: card.id,
      name: card.name,
      expansion: card.set,
      number: card.number,
      imageUrl: card.imageUrl,
      previewImageUrl: card.previewImageUrl,
      viewedAt: viewedAt,
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
      viewedAt: _parseDate(json['viewedAt']),
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
      'viewedAt': viewedAt.toIso8601String(),
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
      'viewedAt': Timestamp.fromDate(viewedAt),
    };
  }

  static DateTime _parseDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    return DateTime.tryParse('${value ?? ''}') ?? DateTime.now();
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
        : FirebaseAuth.instance.authStateChanges().listen((_) {
            _loadRecentViews();
          });
    _loadRecentViews();
  }

  static const String _recentViewsBoxName = 'recent_card_views';
  static const int _limit = 60;
  static const Duration _retentionWindow = Duration(days: 30);
  dynamic _authSubscription;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  User? get _user =>
      Firebase.apps.isEmpty ? null : FirebaseAuth.instance.currentUser;

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> remember(PokemonCard card) async {
    final view = RecentCardView.fromCard(card, DateTime.now());
    final updated = _dedupeAndLimit([view, ...state.views]);
    state = state.copyWith(views: updated, isLoading: false, error: null);

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
      state = state.copyWith(error: error.toString());
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
