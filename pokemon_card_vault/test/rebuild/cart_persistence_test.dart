import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/rebuild/controller/cart_controller.dart';
import 'package:pokoin/rebuild/model/cart_item.dart';
import 'package:pokoin/rebuild/model/demo_catalog.dart';
import 'package:pokoin/rebuild/provider/cart_codec.dart';
import 'package:pokoin/rebuild/service/cart_service.dart';
import 'fixtures/cart_fixtures.dart';

void main() {
  test(
      'guest persists real rows and removals, while demo rows remain in memory',
      () async {
    final local = MemoryCartLocal();
    final remote = MemoryCartRemote();
    var service = CartService(local: local, remote: remote);
    await service.loadForUser(null);
    final row = cartRow('a');
    service.addListing(row.card, row.listing);
    service.addListing(row.card, row.listing);
    service.addCard(demoCards.first);
    await settleCart(service);
    service.dispose();
    service = CartService(local: local, remote: remote);
    addTearDown(service.dispose);
    await service.loadForUser(null);
    expect(service.listingQuantity('a'), 2);
    expect(service.items, isEmpty);
    expect(service.totalPkn, 240);
    service.clear();
    await settleCart(service);
    expect(local.saved[null]!.items, isEmpty);
    expect(local.saved[null]!.pending, isEmpty);
    expect(remote.reads, isEmpty);
    expect(remote.writes, isEmpty);
  });

  test('restoring identical local and remote copies never adds quantities',
      () async {
    final row = cartRow('a', quantity: 2);
    final local = MemoryCartLocal()
      ..saved['alice'] = CartSnapshot(items: [row]);
    final remote = MemoryCartRemote()
      ..saved['alice'] = [CartCodec.encodeItem(row)];
    final service = CartService(local: local, remote: remote);
    addTearDown(service.dispose);
    for (var reload = 0; reload < 3; reload++) {
      await service.loadForUser('alice');
      expect(service.listingQuantity('a'), 2);
      expect(service.totalPkn, 240);
    }
    expect(remote.writes, isEmpty);
  });

  test(
      'offline absolute edits and tombstones survive restart and preserve other rows',
      () async {
    final a = cartRow('a', quantity: 2), b = cartRow('b');
    final local = MemoryCartLocal()
      ..saved['alice'] = CartSnapshot(items: [a, b]);
    final remote = MemoryCartRemote()
      ..offline = true
      ..saved['alice'] = [CartCodec.encodeItem(a), CartCodec.encodeItem(b)];
    var service = CartService(local: local, remote: remote);
    await service.loadForUser('alice');
    expect(service.problem, CartProblem.remoteSync);
    service.addListing(a.card, a.listing);
    service.removeListing('b');
    await settleCart(service);
    expect(local.saved['alice']!.pending['a']!.item!.quantity, 3);
    expect(local.saved['alice']!.pending['b']!.item, isNull);
    service.dispose();
    // Nel frattempo un altro dispositivo aggiunge un'offerta diversa.
    remote.saved['alice']!.add(CartCodec.encodeItem(cartRow('c')));
    remote.offline = false;
    service = CartService(local: local, remote: remote);
    addTearDown(service.dispose);
    await service.loadForUser('alice');
    expect(service.listingItems.map((item) => item.listing.id), ['a', 'c']);
    expect(service.listingQuantity('a'), 3);
    expect(service.hasPendingChanges, isFalse);
    expect(local.saved['alice']!.pending, isEmpty);
    await service.refresh();
    expect(service.listingQuantity('a'), 3);
  });

  test('edits during remote read remain visible and are sent after the read',
      () async {
    final local = MemoryCartLocal();
    final remote = MemoryCartRemote();
    final read = Completer<List<ListingCartItem>>();
    remote.heldReads['alice'] = read;
    final service = CartService(local: local, remote: remote);
    addTearDown(service.dispose);
    final loading = service.loadForUser('alice');
    await Future<void>.delayed(Duration.zero);
    expect(service.canEdit, isTrue);
    final row = cartRow('a');
    service.addListing(row.card, row.listing);
    service.addListing(row.card, row.listing);
    read.complete([cartRow('b')]);
    remote.saved['alice'] = [CartCodec.encodeItem(cartRow('b'))];
    await loading;
    await settleCart(service);
    expect(service.listingQuantity('a'), 2);
    expect(service.listingQuantity('b'), 1);
    expect(remote.writes.last.edits['a']!.item!.quantity, 2);
    expect(service.hasPendingChanges, isFalse);
  });

  test(
      'newer edit of the same row is not acknowledged by an older in-flight write',
      () async {
    final local = MemoryCartLocal();
    final remote = MemoryCartRemote();
    final service = CartService(local: local, remote: remote);
    addTearDown(service.dispose);
    await service.loadForUser('alice');
    final gate = Completer<void>();
    remote.applyGate = gate;
    final row = cartRow('a');
    service.addListing(row.card, row.listing);
    await Future<void>.delayed(Duration.zero);
    expect(remote.writes.single.edits['a']!.item!.quantity, 1);
    service.addListing(row.card, row.listing);
    remote.applyGate = null;
    gate.complete();
    await settleCart(service);
    expect(
        remote.writes.map((write) => write.edits['a']!.item!.quantity), [1, 2]);
    expect(service.listingQuantity('a'), 2);
    expect(local.saved['alice']!.pending, isEmpty);
  });

  test(
      'account change clears data immediately and ignores old local and remote replies',
      () async {
    final local = MemoryCartLocal();
    final remote = MemoryCartRemote();
    final stale = Completer<List<ListingCartItem>>();
    remote.heldReads['alice'] = stale;
    local.saved['alice'] = CartSnapshot(items: [cartRow('private')]);
    local.saved[null] = CartSnapshot(items: [cartRow('guest')]);
    remote.saved['bob'] = [CartCodec.encodeItem(cartRow('bob'))];
    final service = CartService(local: local, remote: remote);
    addTearDown(service.dispose);
    final oldLoad = service.loadForUser('alice');
    await Future<void>.delayed(Duration.zero);
    expect(service.listingQuantity('private'), 1);
    final newLoad = service.loadForUser('bob');
    expect(service.listingItems, isEmpty);
    expect(service.canEdit, isFalse);
    await newLoad;
    stale.complete([cartRow('private')]);
    await oldLoad;
    expect(service.listingItems.single.listing.id, 'bob');
    expect(local.saved['bob']!.items.single.listing.id, 'bob');
    await service.loadForUser(null);
    expect(service.listingItems.single.listing.id, 'guest');
    expect(remote.writes, isEmpty);
    // Un'altra lettura locale tardiva non ritarda il nuovo account.
    final heldLocal = Completer<CartSnapshot>();
    local.heldReads['alice'] = heldLocal;
    final pending = service.loadForUser('alice');
    await Future<void>.delayed(Duration.zero);
    await service.loadForUser('bob');
    heldLocal.complete(CartSnapshot(items: [cartRow('private')]));
    await pending;
    expect(service.listingItems.single.listing.id, 'bob');
  });

  test(
      'failed local read blocks edits, write failures retain state and support retry',
      () async {
    final local = MemoryCartLocal()..failRead = true;
    final remote = MemoryCartRemote();
    final service = CartService(local: local, remote: remote);
    addTearDown(service.dispose);
    await service.loadForUser('alice');
    final row = cartRow('a');
    expect(service.addListing(row.card, row.listing), isFalse);
    expect(service.problem, CartProblem.localRead);
    local.failRead = false;
    await service.retry();
    local.failWrite = true;
    expect(service.addListing(row.card, row.listing), isTrue);
    await settleCart(service);
    expect(service.problem, CartProblem.localWrite);
    expect(service.listingQuantity('a'), 1);
    expect(remote.writes, isEmpty);
    local.failWrite = false;
    await service.retry();
    expect(service.problem, isNull);
    expect(service.hasPendingChanges, isFalse);
    expect(local.saved['alice']!.items.single.quantity, 1);
  });

  test(
      'rapid edits persist in order and pending writes stay scoped after switching',
      () async {
    final local = MemoryCartLocal();
    final service = CartService(local: local);
    addTearDown(service.dispose);
    await service.loadForUser('alice');
    final gate = Completer<void>();
    local.writeGate = gate;
    final row = cartRow('a');
    service.addListing(row.card, row.listing);
    service.addListing(row.card, row.listing);
    service.decreaseListing('a');
    service.removeListing('a');
    final next = service.loadForUser('bob');
    expect(service.itemCount, 0);
    local.writeGate = null;
    gate.complete();
    await next;
    expect(local.saved['alice']!.items, isEmpty);
    expect(local.saved['alice']!.pending['a']!.item, isNull);
    expect(local.saved['bob']!.items, isEmpty);
  });

  test(
      'returning to an account orders commits without blocking another account',
      () async {
    final local = MemoryCartLocal();
    final remote = MemoryCartRemote();
    final service = CartService(local: local, remote: remote);
    addTearDown(service.dispose);
    await service.loadForUser('alice');
    final gate = Completer<void>();
    remote.applyGate = gate;
    final row = cartRow('a');
    service.addListing(row.card, row.listing);
    await Future<void>.delayed(Duration.zero);
    expect(remote.writes, hasLength(1));
    await service.loadForUser('bob');
    expect(service.listingItems, isEmpty);
    final back = service.loadForUser('alice');
    await Future<void>.delayed(Duration.zero);
    expect(service.listingQuantity('a'), 1);
    service.addListing(row.card, row.listing);
    remote.applyGate = null;
    gate.complete();
    await back;
    await settleCart(service);
    expect(CartCodec.decodeItems(remote.saved['alice']!).single.quantity, 2);
    expect(service.listingQuantity('a'), 2);
    expect(local.saved['bob']!.items, isEmpty);
  });

  test('controller follows one shared session and detaches on dispose',
      () async {
    final sessions = StreamController<String?>();
    final local = MemoryCartLocal()
      ..saved['alice'] = CartSnapshot(items: [cartRow('a')])
      ..saved['bob'] = CartSnapshot(items: [cartRow('b')]);
    final service = CartService(local: local);
    final controller = CartController(service: service);
    addTearDown(service.dispose);
    addTearDown(sessions.close);
    controller.start(userIds: sessions.stream);
    sessions.add('alice');
    await settleCart(service);
    expect(controller.quantityFor('a').value, 1);
    sessions.add('alice');
    sessions.add('bob');
    await settleCart(service);
    expect(controller.quantityFor('a').value, 0);
    expect(controller.quantityFor('b').value, 1);
    expect(local.reads, ['alice', 'bob']);
    controller.dispose();
    sessions.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(local.reads, ['alice', 'bob']);
  });
}
