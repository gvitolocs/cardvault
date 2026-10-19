import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/rebuild/model/card.dart';
import 'package:pokoin/rebuild/model/cart_item.dart';
import 'package:pokoin/rebuild/model/listing.dart';
import 'package:pokoin/rebuild/provider/cart_codec.dart';
import 'package:pokoin/rebuild/provider/cart_local_provider.dart';
import 'package:pokoin/rebuild/provider/cart_remote_provider.dart';
import 'package:pokoin/rebuild/service/cart_service.dart';

ListingCartItem cartRow(String id, {int quantity = 1, int stock = 10}) =>
    ListingCartItem(
      card: const MarketplaceCard(
          id: '24',
          name: 'Carta vera',
          expansion: 'Set',
          number: '12',
          imageUrl: ''),
      listing: MarketplaceListing(
          id: id,
          cardId: '24',
          sellerName: 'Venditore',
          country: 'IT',
          condition: 'NM',
          language: 'IT',
          pricePkn: 120,
          stock: stock),
      quantity: quantity,
    );

class MemoryCartLocal implements CartLocalProvider {
  final saved = <String?, CartSnapshot>{};
  final writes = <({String? uid, CartSnapshot snapshot})>[];
  final reads = <String?>[];
  final heldReads = <String?, Completer<CartSnapshot>>{};
  bool failRead = false, failWrite = false;
  Completer<void>? writeGate;
  @override
  Future<CartSnapshot> read(String? uid) async {
    reads.add(uid);
    if (failRead) throw StateError('Local read failed');
    return heldReads[uid]?.future ?? saved[uid] ?? CartSnapshot();
  }

  @override
  Future<void> write(String? uid, CartSnapshot snapshot) async {
    if (writeGate != null) await writeGate!.future;
    if (failWrite) throw StateError('Local write failed');
    // Simula il round trip del DAO, senza condividere identità con il service.
    saved[uid] = CartCodec.decodeSnapshot(CartCodec.encodeSnapshot(snapshot));
    writes.add((uid: uid, snapshot: saved[uid]!));
  }
}

class MemoryCartRemote implements CartRemoteProvider {
  final saved = <String, List<Object?>>{};
  final reads = <String>[];
  final writes = <({String uid, Map<String, CartEdit> edits})>[];
  final heldReads = <String, Completer<List<ListingCartItem>>>{};
  Completer<void>? applyGate;
  bool offline = false;
  @override
  Future<List<ListingCartItem>> read(String uid) async {
    reads.add(uid);
    if (offline) throw StateError('Offline');
    return heldReads[uid]?.future ?? CartCodec.decodeItems(saved[uid] ?? []);
  }

  @override
  Future<List<ListingCartItem>> apply(
      String uid, Map<String, CartEdit> edits) async {
    writes.add((uid: uid, edits: Map.of(edits)));
    if (offline) throw StateError('Offline');
    if (applyGate != null) await applyGate!.future;
    saved[uid] = CartCodec.applyEdits(saved[uid] ?? [], edits);
    return CartCodec.decodeItems(saved[uid]!);
  }
}

Future<void> settleCart(CartService service) async {
  for (var turn = 0; turn < 100; turn++) {
    await Future<void>.delayed(Duration.zero);
    if (!service.isLoading && !service.isSaving && !service.isSyncing) return;
  }
  throw StateError('Cart did not settle');
}

CartService memoryCartService() {
  final service = CartService();
  addTearDown(service.dispose);
  return service;
}
