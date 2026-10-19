import 'dart:async';
import 'package:flutter/foundation.dart';

import '../model/card.dart';
import '../model/cart_item.dart';
import '../model/listing.dart';
import '../service/cart_service.dart';
import '../service/card_service.dart';
import '../model/cart_add_result.dart';

/// Coordina CartService ed espone stato e azioni alla presentazione.
/// Snapshot e totali vengono ricalcolati solo dopo una modifica del carrello.
class CartController extends ChangeNotifier {
  CartController({CartService? service, CardService? cards})
      : _service = service ?? CartService(),
        _cards = cards,
        _ownsCards = cards == null,
        _ownsService = service == null {
    _editable.value = _service.canEdit;
    _service.addListener(_onCartChanged);
  }

  final CartService _service;
  final bool _ownsService;
  CardService? _cards;
  final bool _ownsCards;
  bool _disposed = false;
  int _sessionVersion = 0;
  final _quickAdds = <String, Future<CartAddResult>>{};
  final _adding = <String, ValueNotifier<bool>>{};
  ValueListenable<bool> adding(String cardId) =>
      _adding.putIfAbsent(cardId, () => ValueNotifier(false));

  Future<CartAddResult> addCheapestOffer(String cardId) {
    if (_disposed || !canEdit) {
      return Future.value(const CartAddResult(CartAddStatus.notReady));
    }
    final version = _sessionVersion;
    return _quickAdds.putIfAbsent(
        cardId,
        () => _addCheapest(cardId).whenComplete(() {
              if (version == _sessionVersion) _quickAdds.remove(cardId);
            }));
  }

  Future<CartAddResult> _addCheapest(String cardId) async {
    final version = _sessionVersion;
    final busy = _adding.putIfAbsent(cardId, () => ValueNotifier(false));
    busy.value = true;
    try {
      final cards = _cards ??= CardService();
      final results =
          await (cards.fetchCard(cardId), cards.fetchListings(cardId)).wait;
      if (_disposed || version != _sessionVersion) {
        return const CartAddResult(CartAddStatus.sessionChanged);
      }
      final (card, offers) = results;
      if (!canEdit) return const CartAddResult(CartAddStatus.notReady);
      if (offers.isEmpty) return const CartAddResult(CartAddStatus.unavailable);
      final offer = offers.first;
      return CartAddResult(
          _service.addListing(card, offer)
              ? CartAddStatus.added
              : CartAddStatus.full,
          listing: offer);
    } catch (_) {
      return CartAddResult(_disposed || version != _sessionVersion
          ? CartAddStatus.sessionChanged
          : CartAddStatus.failed);
    } finally {
      if (!_disposed && version == _sessionVersion) busy.value = false;
    }
  }

  final _editable = ValueNotifier(true);
  ValueListenable<bool> get editable => _editable;
  StreamSubscription<String?>? _session;

  void start({required Stream<String?> userIds}) {
    if (_session != null) return;
    _session = userIds.distinct().listen((uid) {
      ++_sessionVersion;
      _quickAdds.clear();
      for (final notifier in _adding.values) {
        notifier.value = false;
      }
      unawaited(_service.loadForUser(uid));
    });
  }

  bool get isLoading => _service.isLoading;
  bool get isSaving => _service.isSaving;
  bool get isSyncing => _service.isSyncing;
  bool get canEdit => _service.canEdit;
  bool get isPersistent => _service.isPersistent;
  bool get isGuest => _service.isGuest;
  bool get hasPendingChanges => _service.hasPendingChanges;
  String? get error => switch (_service.problem) {
        CartProblem.localRead =>
          'Impossibile recuperare il carrello salvato. Riprova prima di modificarlo.',
        CartProblem.localWrite =>
          'Le ultime modifiche non sono salvate sul dispositivo. Riprova.',
        CartProblem.remoteSync =>
          'Sincronizzazione non riuscita. Il carrello è salvato sul dispositivo; riprova quando sei online.',
        CartProblem.limit =>
          'Il carrello può contenere al massimo 100 offerte diverse.',
        null => null,
      };
  Future<void> retry() => _service.retry();
  Future<void> refresh() => _service.refresh();
  void clear() => _service.clear();
  List<CartItem>? _items;
  int? _itemCount;
  double? _totalPrice;
  List<ListingCartItem>? _listingItems;
  double? _totalPkn;
  final _quantities = <String, ValueNotifier<int>>{};

  List<CartItem> get items => _items ??= _service.items;
  int get itemCount => _itemCount ??= _service.itemCount;
  double get totalPrice => _totalPrice ??= _service.totalPrice;
  List<ListingCartItem> get listingItems =>
      _listingItems ??= _service.listingItems;
  double get totalPkn => _totalPkn ??= _service.totalPkn;
  ValueListenable<int> quantityFor(String id) => _quantities.putIfAbsent(
      id, () => ValueNotifier(_service.listingQuantity(id)));
  bool addListing(MarketplaceCard card, MarketplaceListing listing) =>
      _service.addListing(card, listing);
  void decreaseListing(String id) => _service.decreaseListing(id);
  void removeListing(String id) => _service.removeListing(id);

  void addCard(DemoCard card) => _service.addCard(card);
  void removeCard(String cardId) => _service.removeCard(cardId);

  void _onCartChanged() {
    _editable.value = _service.canEdit;
    _items = null;
    _itemCount = null;
    _totalPrice = null;
    _listingItems = null;
    _totalPkn = null;
    for (final entry in _quantities.entries) {
      entry.value.value = _service.listingQuantity(entry.key);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_session?.cancel());
    _editable.dispose();
    for (final notifier in _adding.values) {
      notifier.dispose();
    }
    if (_ownsCards) _cards?.dispose();
    _service.removeListener(_onCartChanged);
    for (final notifier in _quantities.values) {
      notifier.dispose();
    }
    if (_ownsService) _service.dispose();
    super.dispose();
  }
}
