import 'package:flutter_test/flutter_test.dart';
import 'package:pokoin/rebuild/controller/cart_controller.dart';
import 'package:pokoin/rebuild/model/cart_item.dart';
import 'package:pokoin/rebuild/model/demo_catalog.dart';
import 'package:pokoin/rebuild/service/cart_service.dart';

class _CountingCartService extends CartService {
  int itemsReads = 0;
  int countReads = 0;
  int totalReads = 0;
  bool disposed = false;

  @override
  List<CartItem> get items {
    itemsReads++;
    return super.items;
  }

  @override
  int get itemCount {
    countReads++;
    return super.itemCount;
  }

  @override
  double get totalPrice {
    totalReads++;
    return super.totalPrice;
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  test('reuses service snapshots and totals until cart changes', () {
    final service = _CountingCartService()..addCard(demoCards.first);
    final controller = CartController(service: service);
    addTearDown(service.dispose);
    addTearDown(controller.dispose);
    final snapshot = controller.items;
    for (var rebuild = 0; rebuild < 10; rebuild++) {
      expect(controller.items, same(snapshot));
      expect(controller.itemCount, 1);
      expect(controller.totalPrice, 24.9);
    }
    expect(service.itemsReads, 1);
    expect(service.countReads, 1);
    expect(service.totalReads, 1);
    service.addCard(demoCards.first);
    expect(controller.items.single.quantity, 2);
    expect(snapshot.single.quantity, 1);
    expect(controller.itemCount, 2);
    expect(controller.totalPrice, closeTo(49.8, 0.001));
    expect(service.itemsReads, 2);
    expect(service.countReads, 2);
    expect(service.totalReads, 2);
    expect(() => controller.items.clear(), throwsUnsupportedError);
  });

  test('delegates commands and notifies only for effective cart changes', () {
    final controller = CartController();
    addTearDown(controller.dispose);
    var changes = 0;
    controller.addListener(() => changes++);
    controller.addCard(demoCards.first);
    controller.addCard(demoCards.first);
    controller.addCard(demoCards[1]);
    expect(controller.itemCount, 3);
    expect(controller.totalPrice, closeTo(89.3, 0.001));
    controller.removeCard('unknown');
    expect(changes, 3);
    controller.removeCard(demoCards.first.id);
    expect(controller.itemCount, 1);
    expect(controller.totalPrice, 39.5);
    controller.removeCard(demoCards[1].id);
    expect(controller.items, isEmpty);
    expect(controller.itemCount, 0);
    expect(controller.totalPrice, 0);
    expect(changes, 5);
  });

  test('detaches on disposal and leaves an injected service usable', () {
    final service = _CountingCartService();
    addTearDown(service.dispose);
    final controller = CartController(service: service);
    controller.dispose();
    expect(service.disposed, isFalse);
    // A dangling subscription would notify an already disposed controller.
    service.addCard(demoCards.first);
    expect(service.itemCount, 1);
  });
}
