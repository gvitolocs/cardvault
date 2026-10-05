import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
// ignore: avoid_relative_lib_imports
import '../lib/models/pokemon_card.dart';
// ignore: avoid_relative_lib_imports
import '../lib/services/marketplace_card_cache.dart';

PokemonCard _card(String id, {String? name}) =>
    PokemonCard.fromJson({'id': id, 'name': name ?? 'Card $id'});

void main() {
  late Directory directory;
  late Box<PokemonCard> box;
  var counter = 0;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('pokoin-cache-test-');
    Hive.init(directory.path);
    Hive.registerAdapter(PokemonCardAdapter());
  });
  setUp(() async {
    box = await Hive.openBox<PokemonCard>('cards_${counter++}');
  });
  tearDown(() async => box.close());
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('updates incoming cards without deleting or rekeying the catalog',
      () async {
    await box.putAll({7: _card('a'), 'saved': _card('b'), 99: _card('c')});
    await upsertMarketplaceCardCache(
        box, [_card('b', name: 'Updated B'), _card('d')]);
    expect(box.length, 4);
    expect(box.get(7)?.id, 'a');
    expect(box.get('saved')?.name, 'Updated B');
    expect(box.get(99)?.id, 'c');
    expect(box.values.map((card) => card.id).toSet(), {'a', 'b', 'c', 'd'});
  });

  test('blank IDs are ignored and the last incoming duplicate wins', () async {
    await upsertMarketplaceCardCache(box, [
      _card(''),
      _card('a', name: 'Earlier'),
      _card('a', name: 'Latest'),
    ]);
    expect(box.length, 1);
    expect(box.values.single.name, 'Latest');
  });

  test('overlapping writes retain every ID without duplicate additions',
      () async {
    await Future.wait([
      upsertMarketplaceCardCache(box, [_card('a'), _card('b')]),
      upsertMarketplaceCardCache(box, [
        _card('b', name: 'Second B'),
        _card('c'),
      ]),
    ]);
    expect(box.length, 3);
    expect(box.values.map((card) => card.id).toSet(), {'a', 'b', 'c'});
    expect(box.values.singleWhere((card) => card.id == 'b').name, 'Second B');
  });

  test('an empty snapshot leaves stored entries intact', () async {
    await box.put(50, _card('saved'));
    await upsertMarketplaceCardCache(box, const []);
    expect(box.length, 1);
    expect(box.get(50)?.id, 'saved');
  });

  test('bulk updates survive closing and reopening the box', () async {
    await box.addAll(List.generate(1000, (index) => _card('$index')));
    await upsertMarketplaceCardCache(
        box, List.generate(98, (index) => _card('$index', name: 'Updated')));
    final name = box.name;
    await box.close();
    box = await Hive.openBox<PokemonCard>(name);
    expect(box.length, 1000);
    expect(box.get(0)?.name, 'Updated');
    expect(box.get(97)?.name, 'Updated');
    expect(box.get(98)?.name, 'Card 98');
    expect(box.get(999)?.id, '999');
  });
}
