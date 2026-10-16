import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pokoin/rebuild/model/card.dart';
import 'package:pokoin/rebuild/service/cart_service.dart';

const _firstCard = DemoCard(
    'demo-1', 'Carta A', 'Set', '1/10', 12.50, Colors.amber, Icons.bolt);
const _secondCard =
    DemoCard('demo-2', 'Carta B', 'Set', '2/10', 5, Colors.red, Icons.star);

void main() {
  late CartService cart;

  setUp(() => cart = CartService());
  tearDown(() => cart.dispose());

  test('Repeated additions aggregate quantities and the overall total', () {
    cart.addCard(_firstCard);
    cart.addCard(_firstCard);
    cart.addCard(_secondCard);

    expect(cart.items, hasLength(2));
    expect(cart.items.first.quantity, 2);
    expect(cart.items.first.totalPrice, 25);
    expect(cart.itemCount, 3);
    expect(cart.totalPrice, 30);
  });

  test('Removing a card removes all its units and updates remaining totals',
      () {
    cart.addCard(_firstCard);
    cart.addCard(_firstCard);
    cart.addCard(_secondCard);
    cart.removeCard(_firstCard.id);

    expect(cart.items.single.card.id, _secondCard.id);
    expect(cart.itemCount, 1);
    expect(cart.totalPrice, 5);

    cart.removeCard(_secondCard.id);
    expect(cart.items, isEmpty);
    expect(cart.itemCount, 0);
    expect(cart.totalPrice, 0);
  });

  test('Readers cannot mutate cart state and snapshots remain stable', () {
    cart.addCard(_firstCard);
    final snapshot = cart.items;
    expect(() => snapshot.clear(), throwsUnsupportedError);

    cart.addCard(_firstCard);
    expect(snapshot.single.quantity, 1);
    expect(cart.items.single.quantity, 2);
  });
}
