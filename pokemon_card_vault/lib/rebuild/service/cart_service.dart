import 'dart:async';
import 'package:flutter/foundation.dart';

import '../model/card.dart';
import '../model/cart_item.dart';
import '../model/listing.dart';
import '../provider/cart_local_provider.dart';
import '../provider/cart_remote_provider.dart';

/// Regole del carrello e coordinamento della persistenza. Le classi DAO
/// gestiscono Hive/Firestore; gli articoli demo restano solo in memoria.
class CartService extends ChangeNotifier {
  CartService({CartLocalProvider? local, CartRemoteProvider? remote})
      : _local = local,
        _remote = remote;
  final CartLocalProvider? _local;
  final CartRemoteProvider? _remote;
  final _items = <String, CartItem>{};
  final _listingItems = <String, ListingCartItem>{};
  final _pending = <String, CartEdit>{};
  Future<void> _localWrites = Future.value();
  final _remoteWrites = <String, Future<void>>{};
  Future<void>? _sync;
  int _generation = 0, _writes = 0;
  bool _disposed = false, _loaded = false, _localWriteFailed = false;
  String? _uid;
  bool isLoading = false, isSyncing = false;
  bool get isSaving => _writes > 0;
  bool get canEdit => _local == null || _loaded;
  bool get isPersistent => _local != null;
  bool get isGuest => _uid == null;
  bool get hasPendingChanges => _pending.isNotEmpty;
  CartProblem? problem;

  bool _current(int generation) => !_disposed && generation == _generation;

  /// Invalida subito i dati precedenti; una risposta tardiva non può mostrare
  /// o salvare il carrello di un altro account nello stato corrente.
  Future<void> loadForUser(String? uid) async {
    if (_disposed || _local == null) return;
    final generation = ++_generation;
    _uid = uid;
    _loaded = false;
    _localWriteFailed = false;
    _sync = null;
    _writes = 0;
    _items.clear();
    _listingItems.clear();
    _pending.clear();
    problem = null;
    isLoading = true;
    isSyncing = false;
    notifyListeners();
    try {
      // Completa anche eventuali scritture dello stesso utente prima di rileggere.
      await _localWrites;
      if (!_current(generation)) return;
      final snapshot = await _local.read(uid);
      if (!_current(generation)) return;
      _listingItems
          .addAll({for (final item in snapshot.items) item.listing.id: item});
      _pending.addAll(snapshot.pending);
      _loaded = true;
      isLoading = false;
      notifyListeners();
      // Registra l'avvenuta importazione anche per un carrello vuoto: i vecchi
      // box non devono far riapparire articoli rimossi alla prossima apertura.
      if (await _saveLocal(generation)) await _synchronize(generation);
    } catch (_) {
      if (!_current(generation)) return;
      isLoading = false;
      problem = CartProblem.localRead;
      notifyListeners();
    }
  }

  Future<void> retry() async {
    if (_disposed || _local == null) return;
    if (!_loaded) return loadForUser(_uid);
    final generation = _generation;
    if (await _saveLocal(generation)) await _synchronize(generation);
  }

  Future<void> refresh() async {
    if (_loaded && !_disposed) await _synchronize(_generation);
  }

  Future<bool> _saveLocal(int generation) async {
    if (!_current(generation) || _local == null) return false;
    final uid = _uid;
    final snapshot =
        CartSnapshot(items: _listingItems.values, pending: _pending);
    ++_writes;
    final operation = _localWrites.then((_) => _local.write(uid, snapshot));
    // L'errore viene presentato alla UI, senza interrompere la coda delle scritture.
    _localWrites = operation.then<void>((_) {}, onError: (Object _) {});
    try {
      await operation;
      if (!_current(generation)) return false;
      _localWriteFailed = false;
      if (problem == CartProblem.localWrite) problem = null;
      return true;
    } catch (_) {
      if (_current(generation)) {
        _localWriteFailed = true;
        problem = CartProblem.localWrite;
      }
      return false;
    } finally {
      if (_current(generation)) {
        --_writes;
        notifyListeners();
      }
    }
  }

  Future<void> _synchronize(int generation) {
    if (!_current(generation) || _uid == null || _remote == null || !_loaded) {
      return Future.value();
    }
    return _sync ??= _syncRemote(generation).whenComplete(() {
      if (_current(generation)) _sync = null;
    });
  }

  Future<void> _syncRemote(int generation) async {
    final uid = _uid!;
    isSyncing = true;
    notifyListeners();
    try {
      do {
        await _localWrites;
        if (!_current(generation) || _localWriteFailed) return;
        final sent = Map.of(_pending);
        // Un ritorno rapido allo stesso account attende un suo vecchio commit;
        // gli altri account possono invece partire senza aspettarlo.
        await _remoteWrites[uid];
        if (!_current(generation)) return;
        final operation =
            sent.isEmpty ? _remote!.read(uid) : _remote!.apply(uid, sent);
        if (sent.isNotEmpty) {
          _remoteWrites[uid] =
              operation.then<void>((_) {}, onError: (Object _) {});
        }
        final remoteItems = await operation;
        if (!_current(generation)) return;
        for (final entry in sent.entries) {
          // Una modifica arrivata durante la richiesta non è già confermata.
          if (identical(_pending[entry.key], entry.value)) {
            _pending.remove(entry.key);
          }
        }
        _listingItems
          ..clear()
          ..addAll({for (final item in remoteItems) item.listing.id: item});
        for (final entry in _pending.entries) {
          final item = entry.value.item;
          if (item == null) {
            _listingItems.remove(entry.key);
          } else {
            _listingItems[entry.key] = item;
          }
        }
        if (problem == CartProblem.remoteSync) problem = null;
        notifyListeners();
        if (!await _saveLocal(generation)) return;
      } while (_current(generation) && _pending.isNotEmpty);
    } catch (_) {
      if (_current(generation) && !_localWriteFailed) {
        problem = CartProblem.remoteSync;
      }
    } finally {
      if (_current(generation)) {
        isSyncing = false;
        notifyListeners();
      }
    }
  }

  void _changed(String id, ListingCartItem? item) {
    if (_local != null && _uid != null) _pending[id] = CartEdit(item);
    if (problem == CartProblem.limit) problem = null;
    notifyListeners();
    if (_local != null) unawaited(_persistChanges(_generation));
  }

  Future<void> _persistChanges(int generation) async {
    if (await _saveLocal(generation)) await _synchronize(generation);
  }

  List<ListingCartItem> get listingItems =>
      List.unmodifiable(_listingItems.values);
  double get totalPkn =>
      _listingItems.values.fold(0, (sum, item) => sum + item.totalPkn);
  int listingQuantity(String id) => _listingItems[id]?.quantity ?? 0;

  /// Snapshot non modificabile: lo stato cambia solo attraverso il servizio.
  List<CartItem> get items => List.unmodifiable(_items.values);

  /// Numero di articoli, incluse le quantità della stessa carta.
  int get itemCount =>
      _items.values.fold(0, (sum, item) => sum + item.quantity) +
      _listingItems.values.fold(0, (sum, item) => sum + item.quantity);

  bool addListing(MarketplaceCard card, MarketplaceListing listing) {
    if (!canEdit ||
        _disposed ||
        listing.cardId != card.id ||
        !listing.isAvailable) {
      return false;
    }
    final quantity = listingQuantity(listing.id);
    if (quantity >= listing.stock) return false;
    if (quantity == 0 && _listingItems.length >= 100) {
      problem = CartProblem.limit;
      notifyListeners();
      return false;
    }
    _listingItems[listing.id] = ListingCartItem(
        card: card,
        listing: listing,
        quantity: quantity + 1,
        storedData: _listingItems[listing.id]?.storedData ?? const {});
    _changed(listing.id, _listingItems[listing.id]);
    return true;
  }

  void decreaseListing(String id) {
    if (!canEdit || _disposed) return;
    final item = _listingItems[id];
    if (item == null) return;
    if (item.quantity == 1) {
      _listingItems.remove(id);
    } else {
      _listingItems[id] = item.withQuantity(item.quantity - 1);
    }
    _changed(id, _listingItems[id]);
  }

  void removeListing(String id) {
    if (!canEdit || _disposed) return;
    if (_listingItems.remove(id) != null) _changed(id, null);
  }

  void clear() {
    if (!canEdit || _disposed || itemCount == 0) return;
    if (_local != null && _uid != null) {
      for (final id in _listingItems.keys) {
        _pending[id] = const CartEdit(null);
      }
    }
    _items.clear();
    _listingItems.clear();
    notifyListeners();
    if (_local != null) unawaited(_persistChanges(_generation));
  }

  double get totalPrice =>
      _items.values.fold(0, (sum, item) => sum + item.totalPrice);

  void addCard(DemoCard card) {
    if (!canEdit || _disposed) return;
    // Solo demo: gli articoli reali entrano tramite addListing, mai dal prezzo
    // indicativo del catalogo. I due totali non mescolano EUR e PKN.
    _items[card.id] = CartItem(
      card: card,
      quantity: (_items[card.id]?.quantity ?? 0) + 1,
    );
    notifyListeners();
  }

  /// Rimuove l'intera riga, mantenendo il comportamento del prototipo.
  void removeCard(String cardId) {
    if (!canEdit || _disposed) return;
    if (_items.remove(cardId) != null) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
