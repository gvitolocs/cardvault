import 'dart:async';
import '../model/cardex.dart';
import '../provider/collection_provider.dart';
import '../provider/inventory_provider.dart';
import '../model/inventory_listing.dart';
import 'inventory_reconciliation_service.dart';

/// Coordina sessione e collezione senza dipendere da Riverpod o widget legacy.
class CollectionService {
  CollectionService(
      {CollectionProvider? provider, InventoryProvider? inventory})
      : _provider = provider ?? CollectionProvider(),
        _inventory =
            inventory ?? (provider == null ? InventoryProvider() : null);
  final CollectionProvider _provider;
  final InventoryProvider? _inventory;

  Stream<CardCollection> watch() {
    late StreamController<CardCollection> output;
    StreamSubscription<String?>? session;
    StreamSubscription<List<OwnedCard>>? items;
    StreamSubscription<InventorySnapshot>? inventory;
    var version = 0;
    var cancelled = false;
    void emit(CardCollection collection) {
      if (!cancelled) output.add(collection);
    }

    void unavailable() =>
        emit(CardCollection(status: CollectionStatus.unavailable));
    Future<void> changeUser(String? uid) async {
      final request = ++version;
      final previous = items;
      items = null;
      unawaited(inventory?.cancel());
      inventory = null;
      emit(CardCollection(
          status:
              uid == null ? CollectionStatus.guest : CollectionStatus.loading));
      await previous?.cancel();
      if (cancelled || request != version || uid == null) return;
      List<OwnedCard>? holdings;
      List<InventoryListing>? listings = _inventory == null ? const [] : null;
      var inventoryComplete = _inventory == null;
      var failed = false;
      void fail() {
        if (request != version || cancelled) return;
        failed = true;
        unawaited(inventory?.cancel());
        unavailable();
      }

      void publish() {
        if (request != version || cancelled || failed || listings == null) {
          return;
        }
        if (inventoryComplete && holdings != null) {
          emit(CardCollection(
              status: CollectionStatus.ready,
              items: const InventoryReconciliationService()
                  .reconcile(holdings!, listings!)));
        } else {
          // Show proven listed cards early, never unmatched mirrored holdings.
          // Quantities/absence stay unknown until both complete sources reconcile.
          final preview = listings!
              .where((row) => row.isOwned)
              .map((row) => row.item)
              .toList();
          if (preview.isNotEmpty) {
            emit(CardCollection(
                status: CollectionStatus.loading, items: preview));
          }
        }
      }

      if (_inventory != null) {
        inventory = _inventory.watchItems(uid).listen((page) {
          listings = page.items;
          inventoryComplete = page.complete;
          publish();
        }, onError: (Object error, StackTrace stack) {
          fail();
        });
      }
      items = _provider.watchItems(uid).listen((rows) {
        holdings = rows;
        publish();
      }, onError: (Object error, StackTrace stack) {
        fail();
      });
    }

    output = StreamController<CardCollection>(onListen: () {
      emit(CardCollection(status: CollectionStatus.loading));
      session = _provider.watchUserId().listen((uid) {
        unawaited(changeUser(uid).catchError((Object error) {
          unavailable();
        }));
      }, onError: (Object error, StackTrace stack) {
        ++version;
        unawaited(items?.cancel());
        unawaited(inventory?.cancel());
        items = null;
        inventory = null;
        unavailable();
      });
    }, onCancel: () async {
      cancelled = true;
      ++version;
      await session?.cancel();
      await items?.cancel();
      await inventory?.cancel();
    });
    return output.stream;
  }
}
